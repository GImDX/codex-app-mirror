#!/usr/bin/env python3
import importlib.util
import json
import sys
import zipfile
from pathlib import Path
import struct


def die(message):
    print(message, file=sys.stderr)
    raise SystemExit(1)


def read_exact(handle, size):
    data = handle.read(size)
    if len(data) != size:
        die(f"Unexpected end of file while reading {size} bytes.")
    return data


def parse_asar_header(handle):
    prefix = read_exact(handle, 16)
    fields = struct.unpack("<IIII", prefix)

    candidates = []
    # Electron ASAR archives commonly begin with:
    #   uint32 4, uint32 header_size, uint32 pickle_payload_size, uint32 json_size
    # followed by the JSON header at offset 16. The payload starts at
    # 8 + header_size.
    if fields[0] == 4 and fields[1] >= 8 and fields[3] > 0:
        candidates.append((16, fields[3], 8 + fields[1]))

    # Older/custom writers sometimes expose the JSON size directly after the
    # first uint32. Keep this fallback small and structural so corrupt files do
    # not accidentally parse as a huge header.
    if fields[0] > 0 and fields[1] > 0:
        candidates.append((8, fields[1], 8 + fields[0]))

    max_needed = max((offset + size for offset, size, _ in candidates), default=0)
    if max_needed > len(prefix):
        prefix += read_exact(handle, max_needed - len(prefix))

    for json_offset, json_size, data_offset in candidates:
        raw = prefix[json_offset : json_offset + json_size]
        if not raw.startswith(b"{"):
            continue
        try:
            header = json.loads(raw.decode("utf-8"))
        except json.JSONDecodeError:
            continue
        if isinstance(header, dict) and isinstance(header.get("files"), dict):
            return header, data_offset

    die("Could not parse app.asar header.")


def find_file_entry(node, path_parts):
    current = node.get("files", {})
    for part in path_parts:
        entry = current.get(part)
        if not isinstance(entry, dict):
            return None
        if part == path_parts[-1]:
            return entry
        current = entry.get("files", {})
    return None


def find_file_by_basename(node, basename):
    files = node.get("files", {})
    for name, entry in files.items():
        if name == basename and isinstance(entry, dict) and "offset" in entry and "size" in entry:
            return entry
        if isinstance(entry, dict):
            found = find_file_by_basename(entry, basename)
            if found:
                return found
    return None


def read_asar_file_from_zip(zip_file, asar_name, offset, size):
    with zip_file.open(asar_name) as handle:
        remaining = offset
        while remaining:
            chunk = handle.read(min(1024 * 1024, remaining))
            if not chunk:
                die("Unexpected end of app.asar while seeking to package.json.")
            remaining -= len(chunk)
        return read_exact(handle, size)


def app_asar_names(zip_file):
    names = [
        info.filename
        for info in zip_file.infolist()
        if info.filename.replace("\\", "/").lower().endswith("app.asar")
    ]
    names.sort(key=lambda name: ("/resources/app.asar" not in name.replace("\\", "/").lower(), len(name)))
    return names


def direct_package_json_names(zip_file):
    names = [
        info.filename
        for info in zip_file.infolist()
        if info.filename.replace("\\", "/").lower().endswith("/package.json")
    ]
    names.sort(key=lambda name: ("resources/app" not in name.replace("\\", "/").lower(), len(name)))
    return names


def package_version_from_asar(zip_file, asar_name):
    with zip_file.open(asar_name) as handle:
        header, data_offset = parse_asar_header(handle)

    entry = find_file_entry(header, ["package.json"]) or find_file_by_basename(header, "package.json")
    if not entry:
        return ""

    try:
        offset = data_offset + int(str(entry["offset"]))
        size = int(entry["size"])
    except (KeyError, TypeError, ValueError):
        return ""

    package_json = json.loads(read_asar_file_from_zip(zip_file, asar_name, offset, size).decode("utf-8"))
    return str(package_json.get("version") or "")


def package_version_direct(zip_file, name):
    try:
        with zip_file.open(name) as handle:
            package_json = json.loads(handle.read().decode("utf-8"))
        return str(package_json.get("version") or "")
    except (KeyError, json.JSONDecodeError, UnicodeDecodeError):
        return ""


def read_app_version(zip_file):
    for name in app_asar_names(zip_file):
        version = package_version_from_asar(zip_file, name)
        if version:
            return version

    for name in direct_package_json_names(zip_file):
        version = package_version_direct(zip_file, name)
        if version:
            return version

    return ""


def read_backend_version(msix_path):
    helper_path = Path(__file__).with_name("read-codex-backend-version.py")
    spec = importlib.util.spec_from_file_location("read_codex_backend_version", helper_path)
    if spec is None or spec.loader is None:
        return ""
    module = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(module)
    return module.read_backend_version(msix_path)


def main(argv):
    if len(argv) not in (2, 3):
        die("Usage: read-windows-msix-version.py [--app-version|--backend-version] <OpenAI.Codex_...Msix>")

    mode = "--app-version"
    msix_path = argv[1]
    if len(argv) == 3:
        mode = argv[1]
        msix_path = argv[2]

    if mode not in ("--app-version", "--backend-version"):
        die(f"Unknown mode: {mode}")

    if mode == "--backend-version":
        version = read_backend_version(msix_path)
        if version:
            print(version)
            return
        die("Could not read Codex backend version from MSIX by running the packaged backend binary.")

    with zipfile.ZipFile(msix_path) as zip_file:
        version = read_app_version(zip_file)
        if version:
            print(version)
            return
        die("Could not find Codex package.json version in MSIX.")


if __name__ == "__main__":
    main(sys.argv)
