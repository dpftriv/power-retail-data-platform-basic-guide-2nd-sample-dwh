# Conftest / Checkov ローカル実行手順書

**版**：1.1

**対象**：Terraform統制ポリシー、BigQueryスキーマポリシー、GitHub Actions投入前の手元検証

**関連成果物**：[Terraform統制ポリシー・CI/CDサンプル](../ci-policy-samples/README.md)、[ローカル開発環境標準](ローカル開発環境標準.md)

## 1. ローカル検証の目的

GitHub Actionsへ投入する前に、Terraform plan、Conftest / OPA、Checkov、SQL静的検査、BigQuery dry runを手元で実行する。ローカル検証はPull Requestの早期フィードバックを目的とし、最終的な認証、Stagingアクセス、費用上限はCI環境でも再検証する。

ローカルでGCPへ接続する場合も、個人の恒久的な高権限資格情報を使わない。`gcloud auth application-default login`、サービスアカウント偽装、または組織が承認した短期認証を利用する。

## 2. 必要ツール

| ツール | 推奨バージョン | 必須度 | 用途 | 推奨固定方法 |
|---|---:|---|---|---|
| Terraform | **1.16.2** | 必須 | GCP IaC / plan JSON生成 | `.terraform-version` |
| Python | **3.13.x** | 必須 | Cloud Functions / スクリプト | `.python-version` / venv |
| Google Cloud SDK | **583.0.0** | 必須 | `gcloud` / `gsutil` / `bq` | SDK固定 |
| Git | **2.4x～2.5x** | 必須 | 差分とCommit SHA | OS / tool manager |
| Conftest | 0.56.0 | 必須 | Regoポリシー評価 | `CONFTEST_VERSION` |
| OPA | プロジェクト固定 | 推奨 | Rego単体評価の補助 | `OPA_VERSION` |
| Checkov | 3.2.301 | 必須 | Terraform標準・カスタム検査 | `CHECKOV_VERSION` |
| jq | **1.7.x** | 推奨 | JSON結果処理 | OS package manager |
| yq | **4.x** | 推奨 | YAML処理 | OS package manager |
| GitHub CLI | **2.x** | 推奨 | GitHub操作 | `gh` |
| curl / unzip / bash / OpenSSL | Ubuntu標準 | 必須 | 通信 / 展開 / スクリプト / TLS | OS標準 |
| wget / make / Docker / Compose | 指定表に準拠 | 推奨 | ダウンロード / 自動化 / コンテナ | OS / tool manager |
| Node.js | **22 LTS** | 条件付き | Node.js系Cloud Functions | `.nvmrc` / package manager |

## 3. セットアップ

### 3.1 リポジトリ構成

次の構成を前提とする。

```text
.
├── terraform/
├── sql/ または models/
├── ci-policy-samples/
│   ├── conftest/
│   ├── checkov/
│   └── scripts/
└── .github/workflows/
```

### 3.2 バージョン確認

```bash
terraform version       # 1.16.2
python3 --version       # 3.13.x
gcloud version          # Google Cloud SDK 583.0.0
bq version
git --version
gh --version           # 推奨
jq --version            # 1.7.x
yq --version            # 4.x
curl --version
wget --version
unzip -v | head -1
make --version
docker --version
docker compose version
node --version           # 条件付き
openssl version
bash --version
conftest --version
checkov --version
```

CheckovをPython環境へ入れる場合は、プロジェクトごとの仮想環境を使用する。

```bash
python3.13 -m venv .venv-policy
source .venv-policy/bin/activate
python -m pip install --upgrade pip
python -m pip install 'checkov==3.2.301'
```

Conftestは公式リリースバイナリを取得し、Checksumを検証してからPATHへ配置する。バージョン値はCIと一致させる。

```bash
export CONFTEST_VERSION="0.56.0"
curl -fsSL "https://github.com/open-policy-agent/conftest/releases/download/v${CONFTEST_VERSION}/conftest_${CONFTEST_VERSION}_Linux_x86_64.tar.gz" -o /tmp/conftest.tgz
# 組織で管理するSHA256SUMSの値を設定して検証する
# echo "EXPECTED_SHA256  /tmp/conftest.tgz" | sha256sum -c -
tar -xzf /tmp/conftest.tgz -C /tmp
install -m 0755 /tmp/conftest "$HOME/.local/bin/conftest"
```

## 4. Terraform planの作成

```bash
cd terraform
terraform fmt -check -recursive
terraform init -backend=false -input=false
terraform validate -no-color
terraform plan -out=tfplan -input=false -no-color
terraform show -json tfplan > ../artifacts-terraform-plan.json
cd ..
```

ローカルでProduction backendへ接続してplanを実行しない。CI・Staging用の変数とProvider設定を分離する。

## 5. Conftestの実行

```bash
conftest test \
  --policy ci-policy-samples/conftest \
  --all-namespaces \
  artifacts-terraform-plan.json
```

正常時は全テストがpassする。違反がある場合は、Resource address、ルール、理由を確認する。

Namespaceを限定して確認する場合は、Conftestの利用バージョンのCLI仕様に合わせる。サンプルは複数Namespaceを一括評価するため、`--all-namespaces`を標準とする。

### 5.1 Rego単体テスト

ポリシーの評価ロジックを変更した場合は、正常・違反fixtureを追加する。

```bash
conftest verify --policy ci-policy-samples/conftest
```

### 5.2 期待する拒否ケース

| Fixture | 期待結果 |
|---|---|
| `allUsers` IAM | Failure |
| `roles/editor` | Failure |
| サービスアカウントキー | Failure |
| 本番DatasetのCMEKなし | Failure |
| 必須ラベル欠落 | Failure |
| 本番Goldテーブルのpartitionなし | Failure |
| `require_partition_filter = false` | Failure |
| 適切なSA、CMEK、TTL、ラベル | Pass |

## 6. Checkovの実行

```bash
checkov \
  -d terraform \
  --framework terraform \
  --external-checks-dir ci-policy-samples/checkov \
  --check CKV_GCP_CUSTOM_001,CKV_GCP_CUSTOM_002,CKV_GCP_CUSTOM_003 \
  --soft-fail false \
  --output cli
```

JSON結果を保存する場合は、次のようにする。

```bash
mkdir -p artifacts-local
checkov \
  -d terraform \
  --framework terraform \
  --external-checks-dir ci-policy-samples/checkov \
  --check CKV_GCP_CUSTOM_001,CKV_GCP_CUSTOM_002,CKV_GCP_CUSTOM_003 \
  --soft-fail false \
  --output json > artifacts-local/checkov.json
```

カスタムCheck IDが表示されない場合は、Python import、Checkov version、`--external-checks-dir`のパスを確認する。

## 7. SQL静的検査

```bash
bash ci-policy-samples/scripts/sql-static-check.sh
```

この検査は補助検査である。SQL parser、Dataform compile、BigQuery dry run、実データのDQテストを代替しない。

## 8. BigQuery dry run

### 8.1 認証

```bash
gcloud auth application-default login
gcloud config set project "$CI_GCP_PROJECT"
bq ls --project_id="$CI_GCP_PROJECT"
```

組織の規約でユーザー認証が禁止されている場合は、承認済みのサービスアカウント偽装を使用する。認証情報をファイルへ保存・コミットしない。

### 8.2 単一SQLのコスト検査

```bash
export CI_GCP_PROJECT="prj-data-ci"
export MAX_BYTES_BILLED="10737418240"
bash ci-policy-samples/scripts/bq-dry-run.sh \
  "$CI_GCP_PROJECT" \
  "$MAX_BYTES_BILLED" \
  sql/daily_power_usage.sql
```

### 8.3 全SQLの検査

```bash
find sql models -type f \( -name '*.sql' -o -name '*.sqlx' \) -print0 2>/dev/null \
  | xargs -0 -r -n1 bash ci-policy-samples/scripts/bq-dry-run.sh \
      "$CI_GCP_PROJECT" "$MAX_BYTES_BILLED"
```

`require_partition_filter`を設定したテーブルでは、日付、対象エリア、地点範囲を明示する。月次精算や長期バックフィルは、通常のCI上限ではなく、承認済みの別ジョブ・別上限で実行する。

## 9. Stagingアクセス・DQ検証

```bash
export STAGING_GCP_PROJECT="prj-data-stg"
bash ci-policy-samples/scripts/staging-access-test.sh "$STAGING_GCP_PROJECT"
```

実プロジェクトでは、次の代表ロールごとのテストを追加する。

- 需給運用：速報・確報・インバランスは読めるが原PIIは読めない
- 経理・精算：確定値・制度マスタ・精算Goldは読めるが速報の直接更新はできない
- 営業・CS：担当顧客だけ読める
- 経営：地点・原PIIではなく集計Servingだけ読める
- BI利用者：Gold / Servingだけ読める
- データエンジニア：一時権限なしではRestricted PIIを読めない

## 10. まとめて実行するローカルランナー

次のスクリプトをリポジトリルートで実行する。

```bash
#!/usr/bin/env bash
set -euo pipefail

terraform -chdir=terraform fmt -check -recursive
terraform -chdir=terraform init -backend=false -input=false
terraform -chdir=terraform validate -no-color
terraform -chdir=terraform plan -out=tfplan -input=false -no-color
terraform -chdir=terraform show -json tfplan > artifacts-terraform-plan.json

conftest test --policy ci-policy-samples/conftest --all-namespaces artifacts-terraform-plan.json
checkov -d terraform --framework terraform \
  --external-checks-dir ci-policy-samples/checkov \
  --check CKV_GCP_CUSTOM_001,CKV_GCP_CUSTOM_002,CKV_GCP_CUSTOM_003 \
  --soft-fail false

bash ci-policy-samples/scripts/sql-static-check.sh
```

本内容は`ci-policy-samples/scripts/local-policy-check.sh`としても提供する。

## 11. 失敗時の切り分け

| 症状 | 確認事項 |
|---|---|
| ConftestがRegoを読み込めない | Conftest version、package、Rego構文、`--policy`パス |
| `allUsers`が検出されない | Terraform plan JSONのresource type、`change.after`、Policy namespace |
| CheckovのカスタムIDが出ない | Python import、Checkov version、external checks path、registry登録 |
| dry runが失敗する | 認証、Project、Job User、Dataset metadata、region |
| `require_partition_filter`で失敗する | SQLのパーティション列条件、ビュー展開、BI生成SQL |
| Stagingアクセスが期待と違う | IAM、Policy Tag、Row Access Policy、テストユーザー、キャッシュ |
| CIだけ失敗する | GitHub Variables、WIF条件、Environment、RunnerのPATH |

## 12. 証跡管理

ローカル検証では、次を保存してPull Requestへ添付またはCIへ引き渡す。

- Commit SHA
- Terraform version、Provider version
- `artifacts-terraform-plan.json`のハッシュ
- Conftest versionと結果
- Checkov versionとJSON結果
- BigQuery dry runのJob IDと`totalBytesProcessed`
- Dataform compile / DQ結果
- 実行日時、実行者、対象Project、リージョン

Secret、OIDCトークン、生成資格情報ファイル、PIIサンプルを証跡へ含めない。

## References

[1]: /home/ubuntu/output/design-guides/ci-policy-samples/README.md "Terraform統制ポリシー・CI/CDサンプル"
[2]: /home/ubuntu/output/design-guides/implementation-control-checklist-and-electricity-antipatterns.md "CI/CD・Terraform自動検証チェックリストと電力小売りアンチパターン集"
[3]: https://www.conftest.dev/ "Conftest documentation"
[4]: https://www.checkov.io/ "Checkov documentation"
[5]: https://developer.hashicorp.com/terraform/cli/commands/show "Terraform show command"
[6]: https://cloud.google.com/bigquery/docs/dry-run-quotas "Estimate query costs"

---

**注意**：本書のサンプルは組織のProject、Dataset、Repository、Branch、Environment、費用上限、例外台帳に合わせて設定する。サンプルを無変更で本番へ適用しない。
