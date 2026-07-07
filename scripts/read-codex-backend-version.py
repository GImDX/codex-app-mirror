#!/usr/bin/env python3
import argparse
import json
import os
import re
import shutil
import stat
import subprocess
import sys
import tempfile
import zipfile
from pathlib import Path


VERSION_RE = re.compile(r"(?<![0-9A-Za-z])([0-9]+(?:\.[0-9A-Za-z][0-9A-Za-z._+-]*)+)(?![0-9A-Za-z])")


def die(message):
    print(message, file=sys.stderr)
    raise SystemExit(1)


def parse_version(output):
    match = VERSION_RE.search(output)
    return match.group(1) if match else ""


def isolated_env(tmp_dir):
    env = os.environ.copy()
    home = os.path.join(tmp_dir, "home")
    os.makedirs(home, exist_ok=True)
    paths = {
        "HOME": home,
        "USERPROFILE": home,
        "APPDATA": os.path.join(tmp_dir, "appdata"),
        "LOCALAPPDATA": os.path.join(tmp_dir, "localappdata"),
        "XDG_CONFIG_HOME": os.path.join(tmp_dir, "xdg-config"),
        "XDG_CACHE_HOME": os.path.join(tmp_dir, "xdg-cache"),
        "CODEX_HOME": os.path.join(tmp_dir, "codex-home"),
    }
    for key, value in paths.items():
        os.makedirs(value, exist_ok=True)
        env[key] = value
    return env


def run_backend(binary_path):
    with tempfile.TemporaryDirectory(prefix="codex-backend-version-") as tmp_dir:
        env = isolated_env(tmp_dir)
        try:
            completed = subprocess.run(
                [binary_path, "--version"],
                cwd=tmp_dir,
                env=env,
                stdout=subprocess.PIPE,
                stderr=subprocess.PIPE,
                text=True,
                timeout=20,
                check=False,
            )
        except (OSError, subprocess.TimeoutExpired):
            return ""

    return parse_version((completed.stdout or "") + "\n" + (completed.stderr or ""))


def candidate_score(path):
    normalized = path.replace("\\", "/").lower()
    basename = os.path.basename(normalized)
    score = 0
    if normalized.endswith("/contents/resources/codex") or normalized.endswith("/resources/codex.exe"):
        score -= 50
    if basename in ("codex", "codex.exe"):
        score -= 25
    score += normalized.count("/")
    score += len(normalized) // 100
    return score


def iter_backend_paths(root):
    root = os.path.abspath(root)
    if os.path.isfile(root):
        yield root
        return

    candidates = []
    for dirpath, dirnames, filenames in os.walk(root):
        dirnames.sort()
        for filename in sorted(filenames):
            if filename.lower() in ("codex", "codex.exe"):
                candidates.append(os.path.join(dirpath, filename))

    for path in sorted(candidates, key=candidate_score):
        yield path


def ensure_executable(path):
    if os.name == "nt":
        return
    try:
        current = os.stat(path).st_mode
        os.chmod(path, current | stat.S_IXUSR)
    except OSError:
        pass


def zip_backend_entries(zip_file):
    entries = [
        info
        for info in zip_file.infolist()
        if os.path.basename(info.filename.replace("\\", "/")).lower() in ("codex", "codex.exe")
    ]
    entries.sort(key=lambda info: candidate_score(info.filename))
    return entries


def read_backend_version_from_zip(path):
    with zipfile.ZipFile(path) as zip_file:
        for entry in zip_backend_entries(zip_file):
            with tempfile.TemporaryDirectory(prefix="codex-backend-msix-") as tmp_dir:
                target = os.path.join(tmp_dir, os.path.basename(entry.filename))
                with zip_file.open(entry) as source, open(target, "wb") as output:
                    shutil.copyfileobj(source, output)
                ensure_executable(target)
                version = run_backend(target)
                if version:
                    return version
    return ""


def read_backend_version(path):
    if os.path.isfile(path) and zipfile.is_zipfile(path):
        return read_backend_version_from_zip(path)

    for candidate in iter_backend_paths(path):
        ensure_executable(candidate)
        version = run_backend(candidate)
        if version:
            return version
    return ""


def main(argv):
    parser = argparse.ArgumentParser(description="Read the bundled Codex backend version by running the packaged backend binary.")
    parser.add_argument("path", help="MSIX/ZIP, backend executable, or mounted Codex.app path")
    parser.add_argument("--json", action="store_true", help="Always emit a JSON metadata object and exit 0")
    parser.add_argument("--platform", default="", help="Platform label for --json output")
    parser.add_argument("--architecture", default="", help="Architecture label for --json output")
    args = parser.parse_args(argv[1:])

    version = read_backend_version(args.path)
    if args.json:
        payload = {
            "status": "found" if version else "unavailable",
        }
        if args.platform:
            payload["platform"] = args.platform
        if args.architecture:
            payload["architecture"] = args.architecture
        if version:
            payload["backendVersion"] = version
        json.dump(payload, sys.stdout, indent=2, sort_keys=True)
        sys.stdout.write("\n")
        return

    if version:
        print(version)
        return
    die("Could not read Codex backend version by running the packaged backend binary.")


if __name__ == "__main__":
    main(sys.argv)
