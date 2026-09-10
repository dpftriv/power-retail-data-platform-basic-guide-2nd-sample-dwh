#!/usr/bin/env bash
set -euo pipefail
# B-13：境界日（今日 − 2年）の1パーティションを Active → Cold へメタデータコピー（Cloud Composer / Cloud Scheduler から実行）
D=$(TZ=Asia/Tokyo date -d "2 years ago" +%Y%m%d)
ACTIVE="`${GCP_PROJECT_ID}.${BQ_DATASET_GOLD}.agg_slot_summary_active`\$${D}"
COLD="`${GCP_PROJECT_ID}.${BQ_DATASET_GOLD}.agg_slot_summary_cold`\$${D}"

n_active=$(bq query --use_legacy_sql=false --format=csv \
  "SELECT COUNT(*) FROM `${GCP_PROJECT_ID}.${BQ_DATASET_GOLD}.agg_slot_summary_active` WHERE target_date = PARSE_DATE('%Y%m%d', '${D}')" | tail -1)
n_cold=$(bq query --use_legacy_sql=false --format=csv \
  "SELECT COUNT(*) FROM `${GCP_PROJECT_ID}.${BQ_DATASET_GOLD}.agg_slot_summary_cold`   WHERE target_date = PARSE_DATE('%Y%m%d', '${D}')" | tail -1)

if [ "${n_active}" = "0" ]; then echo "no source partition ${D}"; exit 0; fi
if [ "${n_cold}" = "${n_active}" ]; then echo "already archived ${D}"; exit 0; fi
if [ "${n_cold}" != "0" ]; then bq rm -f --table "${COLD}"; fi        # 部分退避の残骸をパーティション単位で捨てる
bq cp --append_table "${ACTIVE}" "${COLD}"                            # メタデータ操作。Active 側は触らない
# 退避結果の検証（件数一致）は 15.4「Cold 未退避」監視ジョブが翌日再確認する
