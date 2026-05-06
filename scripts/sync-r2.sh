#!/usr/bin/env bash
set -euo pipefail

if [[ $# -lt 3 ]]; then
  echo "Usage: sync-r2.sh <bucket> <prefix> <file> [file ...]" >&2
  exit 2
fi

bucket="$1"
prefix="${2#/}"
prefix="${prefix%/}"
shift 2

if [[ -z "$bucket" || -z "$prefix" ]]; then
  echo "Bucket and prefix are required." >&2
  exit 2
fi

: "${R2_S3_ENDPOINT:?R2_S3_ENDPOINT must be set, for example https://<account-id>.r2.cloudflarestorage.com}"
: "${AWS_ACCESS_KEY_ID:?AWS_ACCESS_KEY_ID must be set}"
: "${AWS_SECRET_ACCESS_KEY:?AWS_SECRET_ACCESS_KEY must be set}"

if ! command -v aws >/dev/null 2>&1; then
  echo "aws CLI is required for multipart-capable R2 uploads." >&2
  exit 1
fi

content_type_for() {
  case "$1" in
    *.dmg) printf '%s' 'application/x-apple-diskimage' ;;
    *.Msix|*.msix) printf '%s' 'application/vnd.ms-appx' ;;
    *.json) printf '%s' 'application/json' ;;
    *.txt) printf '%s' 'text/plain; charset=utf-8' ;;
    *) printf '%s' 'application/octet-stream' ;;
  esac
}

for file in "$@"; do
  if [[ ! -f "$file" ]]; then
    echo "Not a file: $file" >&2
    exit 1
  fi

  name="$(basename "$file")"
  object_path="$prefix/$name"
  content_type="$(content_type_for "$name")"

  echo "Uploading $file to r2://$bucket/$object_path"
  aws s3 cp "$file" "s3://$bucket/$object_path" \
    --endpoint-url "$R2_S3_ENDPOINT" \
    --region "${AWS_DEFAULT_REGION:-auto}" \
    --content-type "$content_type" \
    --content-disposition "attachment; filename=\"$name\"" \
    --no-progress
done
