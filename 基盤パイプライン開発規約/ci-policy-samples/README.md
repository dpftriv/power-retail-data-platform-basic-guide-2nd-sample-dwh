# Terraform統制ポリシー・CI/CDサンプル

## 実行環境

ツールの推奨バージョン、必須度、用途は、[ローカル開発環境標準](../design-guides/ローカル開発環境標準.md)を参照する。CI WorkflowのTerraformは`1.16.2`を標準とし、Conftest、Checkov、Google Cloud SDKのバージョンもローカルとCIで一致させる。

## 構成

| パス | 内容 |
|---|---|
| `conftest/terraform_security_cost.rego` | IAM、公開設定、SAキー、保持、ラベル、CMEK、Cloud Runを検査するRego |
| `conftest/bigquery_schema.rego` | BigQueryのパーティション、`require_partition_filter`、ラベル、説明を検査するRego |
| `checkov/custom_policies.py` | BigQuery Dataset / Table、公開IAMを検査するCheckovカスタムチェック |
| `github-workflows/terraform-controls.yml` | Pull Request、main push、Stagingゲートを実行するGitHub Actions |
| `scripts/sql-static-check.sh` | PII・鍵・マスク列JOINの補助検査 |
| `scripts/bq-dry-run.sh` | `totalBytesProcessed`によるBigQueryコストゲート |
| `scripts/staging-access-test.sh` | Stagingの権限・テーブル設定・証跡収集 |

## Conftestの実行

```bash
terraform plan -out=tfplan
terraform show -json tfplan > artifacts-terraform-plan.json
conftest verify \
  --policy ci-policy-samples/conftest \
  --namespace terraform.security_cost \
  --namespace terraform.bigquery_schema \
  artifacts-terraform-plan.json
```

Regoは`terraform show -json`のplan JSONを前提とする。利用するTerraform Providerのバージョンによって属性の構造が異なる場合があるため、CIで実際のplan JSONをfixtureとして保存し、ポリシー単体テストを行う。

## Checkovの実行

```bash
python -m pip install 'checkov==3.2.301'
checkov -d terraform \
  --framework terraform \
  --external-checks-dir ci-policy-samples/checkov \
  --check CKV_GCP_CUSTOM_001,CKV_GCP_CUSTOM_002,CKV_GCP_CUSTOM_003 \
  --soft-fail false
```

カスタムチェックは例示用である。Checkovのマイナーバージョンを固定し、CIで import と実行を検証する。組織共通チェックへ昇格する場合は、ID、重大度、例外方式、テストfixtureを正式管理する。

## GitHub Actionsの必須設定

次のRepository Variablesを設定する。

| Variable | 内容 |
|---|---|
| `GCP_WORKLOAD_IDENTITY_PROVIDER` | GitHub Actions用Workload Identity Federation Provider |
| `GCP_CI_SERVICE_ACCOUNT` | Terraform plan・BQ dry run専用サービスアカウント |
| `CI_GCP_PROJECT` | CI用GCPプロジェクト |
| `STAGING_GCP_PROJECT` | Stagingプロジェクト |
| `MAX_BYTES_BILLED` | CI代表クエリの最大スキャンバイト数 |

長期サービスアカウントキーをGitHub Secretsへ保存しない。GitHub ActionsからGoogle Cloudへは、Workload Identity Federationを使用する。

## ポリシー単体テスト

最低限、次のfixtureを用意する。

- `allUsers`を含むIAMが拒否される
- `roles/editor`が拒否される
- production Silver / Gold / Servingでパーティションなしが拒否される
- `require_partition_filter = false`が拒否される
- restrictedデータセットでCMEKなしが拒否される
- 必須コストラベル欠落が拒否される
- 適切なサービスアカウント、CMEK、TTL、ラベルが合格する

CIの初期導入では、Non-Criticalルールを警告から開始し、Criticalルールは初日から失敗させる。例外はTerraformの属性へ自由記述せず、対象、理由、承認者、有効期限を別の例外台帳で管理し、CIで期限切れを拒否する。
