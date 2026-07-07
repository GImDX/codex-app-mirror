#!/usr/bin/env bash
set -euo pipefail

tmp_dir="$(mktemp -d)"
repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cleanup() {
  rm -rf "$tmp_dir"
}
trap cleanup EXIT

mkdir -p "$tmp_dir/Codex.app/Contents/Resources" "$tmp_dir/msix/app/resources"

cat > "$tmp_dir/Codex.app/Contents/Resources/codex" <<'SH'
#!/usr/bin/env bash
printf 'codex-cli 0.142.5\n'
SH
chmod +x "$tmp_dir/Codex.app/Contents/Resources/codex"

test "$(python3 "$repo_root/scripts/read-codex-backend-version.py" "$tmp_dir/Codex.app")" = "0.142.5"

cat > "$tmp_dir/msix/app/resources/codex.exe" <<'SH'
#!/usr/bin/env bash
printf 'codex-cli 0.143.0\n'
SH
chmod +x "$tmp_dir/msix/app/resources/codex.exe"
(
  cd "$tmp_dir/msix"
  zip -q -r "$tmp_dir/backend.Msix" app
)

test "$(python3 "$repo_root/scripts/read-codex-backend-version.py" "$tmp_dir/backend.Msix")" = "0.143.0"
python3 "$repo_root/scripts/read-codex-backend-version.py" \
  --json \
  --platform windows \
  --architecture x64 \
  "$tmp_dir/backend.Msix" > "$tmp_dir/backend.json"
test "$(jq -r '.backendVersion' "$tmp_dir/backend.json")" = "0.143.0"
test "$(jq -r '.status' "$tmp_dir/backend.json")" = "found"

printf 'not executable' > "$tmp_dir/missing"
if python3 "$repo_root/scripts/read-codex-backend-version.py" "$tmp_dir/missing" >/dev/null 2>&1; then
  echo "Expected missing backend version to fail." >&2
  exit 1
fi
python3 "$repo_root/scripts/read-codex-backend-version.py" --json "$tmp_dir/missing" > "$tmp_dir/missing.json"
test "$(jq -r '.status' "$tmp_dir/missing.json")" = "unavailable"
test "$(jq -r '.backendVersion // empty' "$tmp_dir/missing.json")" = ""

echo "read-codex-backend-version fixture PASS"