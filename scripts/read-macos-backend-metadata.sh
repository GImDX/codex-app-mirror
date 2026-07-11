#!/usr/bin/env bash
set -euo pipefail

output_path="${1:?output path is required}"
arch="${2:?architecture is required}"
input_manifest="${3:?prepared backend input manifest is required}"
script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
tmp_output="$(mktemp)"

cleanup() {
  rm -f "$tmp_output"
}
trap cleanup EXIT

mkdir -p "$(dirname "$output_path")"
if python3 "$script_dir/read-codex-backend-version.py" \
  --prepared-input \
  --json \
  --platform macos \
  --architecture "$arch" \
  "$input_manifest" > "$tmp_output" &&
  python3 -m json.tool "$tmp_output" >/dev/null; then
  mv "$tmp_output" "$output_path"
else
  echo "Could not read macOS $arch backend metadata; leaving it unavailable." >&2
  printf '%s\n' \
    "{\"architecture\":\"$arch\",\"platform\":\"macos\",\"status\":\"unavailable\"}" \
    > "$output_path"
fi

cat "$output_path"
