#!/usr/bin/env bash
set -euo pipefail

output_path="${1:?output path is required}"
arch="${2:?architecture is required}"
dmg="${3:?DMG path is required}"
script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

require() {
  if ! command -v "$1" >/dev/null 2>&1; then
    echo "Missing required command: $1" >&2
    exit 1
  fi
}

require hdiutil
require python3

tmp_dir="$(mktemp -d)"
volume=""
cleanup() {
  if [[ -n "$volume" ]]; then
    hdiutil detach "$volume" -quiet >/dev/null 2>&1 || true
  fi
  rm -rf "$tmp_dir"
}
trap cleanup EXIT

if [[ ! -f "$dmg" ]]; then
  echo "Missing DMG: $dmg" >&2
  exit 1
fi

attach_plist="$(hdiutil attach -plist -nobrowse -readonly "$dmg")"
volume="$(python3 -c '
import plistlib
import sys

data = plistlib.loads(sys.stdin.buffer.read())
mounts = [
    item.get("mount-point", "")
    for item in data.get("system-entities", [])
    if item.get("mount-point", "").startswith("/Volumes/")
]
print(mounts[-1] if mounts else "")
' <<<"$attach_plist")"

if [[ -z "$volume" ]]; then
  echo "Could not find mounted volume for $dmg" >&2
  exit 1
fi

app_path="$volume/Codex.app"
if [[ ! -d "$app_path" ]]; then
  echo "Missing Codex.app in $dmg" >&2
  exit 1
fi

mkdir -p "$(dirname "$output_path")"
python3 "$script_dir/read-codex-backend-version.py" \
  --json \
  --platform macos \
  --architecture "$arch" \
  "$app_path" > "$output_path"
cat "$output_path"