#!/usr/bin/env bash
set -euo pipefail

ROOT="$(git rev-parse --show-toplevel 2>/dev/null || pwd)"
cd "$ROOT"

: "${CHECKOV_VERSION:=3.2.301}"
: "${PLAN_JSON:=artifacts-terraform-plan.json}"

command -v terraform >/dev/null || { echo "terraform is required" >&2; exit 1; }
command -v conftest >/dev/null || { echo "conftest is required" >&2; exit 1; }
command -v checkov >/dev/null || { echo "checkov is required" >&2; exit 1; }

mkdir -p artifacts-local

echo "[1/5] Terraform format, init, validate, plan"
terraform -chdir=terraform fmt -check -recursive
terraform -chdir=terraform init -backend=false -input=false
terraform -chdir=terraform validate -no-color
terraform -chdir=terraform plan -out=tfplan -input=false -no-color
terraform -chdir=terraform show -json tfplan > "$PLAN_JSON"

echo "[2/5] Conftest"
conftest test \
  --policy ci-policy-samples/conftest \
  --all-namespaces \
  "$PLAN_JSON"

echo "[3/5] Checkov"
checkov -d terraform \
  --framework terraform \
  --external-checks-dir ci-policy-samples/checkov \
  --check CKV_GCP_CUSTOM_001,CKV_GCP_CUSTOM_002,CKV_GCP_CUSTOM_003 \
  --soft-fail false \
  --output cli

echo "[4/5] SQL static checks"
bash ci-policy-samples/scripts/sql-static-check.sh

echo "[5/5] Evidence"
sha256sum "$PLAN_JSON" | tee artifacts-local/plan.sha256
{
  echo "commit=$(git rev-parse HEAD 2>/dev/null || echo unknown)"
  echo "terraform=$(terraform version -json 2>/dev/null | jq -r '.terraform_version' || true)"
  echo "conftest=$(conftest --version 2>/dev/null || true)"
  echo "checkov=$(checkov --version 2>/dev/null || true)"
  date -u +"run_at=%Y-%m-%dT%H:%M:%SZ"
} | tee artifacts-local/tool-versions.txt

echo "Local policy checks passed"
