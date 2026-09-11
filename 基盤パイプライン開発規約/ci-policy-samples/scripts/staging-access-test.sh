#!/usr/bin/env bash
set -euo pipefail

project_id="${1:?staging project is required}"
out="artifacts-staging"
mkdir -p "$out"

bq ls --project_id="$project_id" --format=json > "$out/datasets.json"
bq query --project_id="$project_id" --use_legacy_sql=false --format=json \
  'SELECT table_schema, table_name, option_name, option_value
   FROM `region-asia-northeast1`.INFORMATION_SCHEMA.TABLE_OPTIONS
   WHERE option_name IN ("require_partition_filter", "expiration_timestamp")' \
  > "$out/table-options.json"

# 実際の業務プロジェクトでは、ここへ代表ロールごとのクエリを追加する。
# 例: 需給運用、経理・精算、営業、BI利用者が許可/拒否どおりに動くかを確認する。
if command -v jq >/dev/null 2>&1; then
  jq empty "$out/datasets.json"
  jq empty "$out/table-options.json"
fi

echo "Staging access/DQ evidence collected for $project_id"
