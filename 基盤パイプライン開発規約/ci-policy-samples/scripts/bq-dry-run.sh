#!/usr/bin/env bash
set -euo pipefail

project_id="${1:?project id is required}"
max_bytes="${2:?maximum bytes is required}"
sql_file="${3:?SQL file is required}"

[[ -s "$sql_file" ]] || { echo "FAIL: empty SQL file: $sql_file" >&2; exit 1; }

result=$(bq query \
  --project_id="$project_id" \
  --use_legacy_sql=false \
  --dry_run \
  --format=json < "$sql_file")
bytes=$(jq -r '.[0].totalBytesProcessed // .totalBytesProcessed // empty' <<< "$result")
[[ "$bytes" =~ ^[0-9]+$ ]] || { echo "FAIL: cannot read totalBytesProcessed: $sql_file" >&2; exit 1; }

if (( bytes > max_bytes )); then
  echo "FAIL: $sql_file scans $bytes bytes; limit is $max_bytes" >&2
  exit 1
fi

echo "PASS: $sql_file scans $bytes bytes"
