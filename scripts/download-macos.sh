#!/usr/bin/env bash
set -euo pipefail

out_dir="${1:-dist}"
mkdir -p "$out_dir"

arm_url="https://persistent.oaistatic.com/codex-app-prod/Codex.dmg"
x64_url="https://persistent.oaistatic.com/codex-app-prod/Codex-latest-x64.dmg"

curl -fL --retry 3 --retry-delay 2 \
  -o "$out_dir/Codex-mac-arm64.dmg" \
  "$arm_url"

curl -fL --retry 3 --retry-delay 2 \
  -o "$out_dir/Codex-mac-x64.dmg" \
  "$x64_url"

shasum -a 256 "$out_dir/Codex-mac-arm64.dmg" "$out_dir/Codex-mac-x64.dmg" \
  > "$out_dir/SHA256SUMS-macos.txt"
