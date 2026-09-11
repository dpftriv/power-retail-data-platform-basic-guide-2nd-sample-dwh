#!/usr/bin/env bash
set -euo pipefail

# 補助的な検査。最終判定はSQL parser、Dataform compile、BigQuery dry runで行う。
mapfile -d '' files < <(find sql models -type f \( -name '*.sql' -o -name '*.sqlx' \) -print0 2>/dev/null || true)
for file in "${files[@]}"; do
  if grep -Eiq 'JOIN[[:space:]]+[^;]*(masked_|sha256_|hash_)' "$file"; then
    echo "FAIL: masked/hash column used as JOIN key: $file" >&2
    exit 1
  fi
  if grep -Eiq '(plaintext_keyset|kms_key|secret_value|customer_name|email|phone|address)' "$file" \
      && [[ "$file" =~ (gold|serving) ]]; then
    echo "FAIL: possible PII/key reference in Gold/Serving SQL: $file" >&2
    exit 1
  fi
done
echo "SQL static checks passed"
