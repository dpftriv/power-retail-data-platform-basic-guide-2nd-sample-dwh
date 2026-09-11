# GitHub Actions × Google Cloud Workload Identity Federation 設定ガイド

**版**：1.1

**対象**：Terraform統制、Conftest、Checkov、BigQuery dry run、Staging検証を実行するGitHub Actions

**前提**：本ガイドは、長期有効なサービスアカウントキーをGitHub Secretsへ保存せず、GitHub ActionsのOIDCトークンをGoogle Cloud Workload Identity Federation（WIF）で短期認証へ交換する構成を標準とする。[1] [2]

## 0. ローカル開発環境

ローカル開発環境の標準は、[ローカル開発環境標準](ローカル開発環境標準.md)に定義する。WIF設定を実行する端末では、少なくともTerraform `1.16.2`、Python `3.13.x`、Google Cloud SDK `583.0.0`、Git、curl、bash、OpenSSLを確認する。GitHub CLI、jq、yq、Dockerは必要な作業で使用する。

```bash
terraform version
python3 --version
gcloud version
openssl version
```

## 1. 推奨構成

```text
GitHub Actions job
  │ OIDC token（id-token: write）
  ▼
Workload Identity Pool
  └─ GitHub OIDC Provider
       ├─ issuer: https://token.actions.githubusercontent.com/
       ├─ attribute mapping: repository_id / repository_owner_id / ref / workflow
       └─ attribute condition: 組織・リポジトリ・ブランチ・環境を制限
  ▼
専用CIサービスアカウント
  ├─ roles/iam.workloadIdentityUser（WIF主体に限定）
  ├─ Terraform plan用の最小権限
  ├─ BigQuery dry run用のジョブ実行権限
  └─ Staging検証用の限定権限
```

GitHub、GitHub Organization、Repositoryの**名称だけ**で信頼を構成せず、再利用されない数値ID（`repository_id`、`repository_owner_id`）を条件へ含める。Google Cloud公式資料も、名称変更・削除後のなりすまし対策として数値IDの利用を推奨している。[1]

## 2. 事前に決める値

以下は例であり、実環境の値へ置き換える。

| 変数 | 例 | 説明 |
|---|---|---|
| `GCP_PROJECT_ID` | `prj-data-ci` | WIFとCIサービスアカウントを管理するプロジェクト |
| `GCP_PROJECT_NUMBER` | `123456789012` | `gcloud projects describe`で取得する数値ID |
| `POOL_ID` | `github-actions` | Workload Identity Pool ID |
| `PROVIDER_ID` | `github-oidc` | OIDC Provider ID |
| `GITHUB_OWNER` | `example-org` | GitHub Organization名。補助条件に使用 |
| `GITHUB_OWNER_ID` | `12345678` | GitHub Organizationの数値ID |
| `GITHUB_REPOSITORY_ID` | `87654321` | 対象Repositoryの数値ID |
| `GITHUB_REPO` | `example-org/data-platform` | `repository` claim。ログ確認用 |
| `CI_SERVICE_ACCOUNT` | `sa-ci-controls@prj-data-ci.iam.gserviceaccount.com` | Terraform plan / dry run主体 |
| `STAGING_PROJECT_ID` | `prj-data-stg` | Staging検証先 |
| `PROD_PROJECT_ID` | `prj-data-prod` | 原則、Pull Requestジョブから直接操作しない |

## 3. Google Cloud APIの有効化

WIF、IAM、STS、Cloud Resource Manager、BigQuery、Cloud Billingの利用を有効化する。既存組織の標準に従い、CI管理プロジェクトとデータプロジェクトを分離する。

```bash
export GCP_PROJECT_ID="prj-data-ci"
gcloud config set project "$GCP_PROJECT_ID"

gcloud services enable \
  iam.googleapis.com \
  iamcredentials.googleapis.com \
  sts.googleapis.com \
  cloudresourcemanager.googleapis.com \
  bigquery.googleapis.com \
  billingbudgets.googleapis.com
```

WIFの作成権限は、日常のCI実行サービスアカウントへ付与しない。初期設定は基盤またはセキュリティ管理者が実施する。

## 4. Workload Identity Poolの作成

```bash
export POOL_ID="github-actions"

gcloud iam workload-identity-pools create "$POOL_ID" \
  --project="$GCP_PROJECT_ID" \
  --location="global" \
  --display-name="GitHub Actions Pool" \
  --description="OIDC identities for approved GitHub Actions workflows"

export PROJECT_NUMBER="$(gcloud projects describe "$GCP_PROJECT_ID" --format='value(projectNumber)')"
export POOL_NAME="projects/${PROJECT_NUMBER}/locations/global/workloadIdentityPools/${POOL_ID}"

gcloud iam workload-identity-pools describe "$POOL_ID" \
  --project="$GCP_PROJECT_ID" \
  --location="global" \
  --format='value(name)'
```

## 5. GitHub OIDC Providerの作成

### 5.1 Attribute Mapping

最低限、次をマッピングする。

```text
google.subject=assertion.sub
attribute.repository_id=assertion.repository_id
attribute.repository_owner_id=assertion.repository_owner_id
attribute.repository=assertion.repository
attribute.ref=assertion.ref
attribute.workflow=assertion.workflow
attribute.environment=assertion.environment
```

`repository_id`と`repository_owner_id`は数値IDによる固定条件に使用する。`repository`、`ref`、`workflow`、`environment`は補助的な絞り込みと監査表示に使用する。

### 5.2 Attribute Condition

Pull Requestとmainブランチの権限を分ける。例として、Staging用ProviderはRepository ID、Organization ID、mainブランチへ限定する。

```text
assertion.repository_owner_id == '12345678' &&
assertion.repository_id == '87654321' &&
assertion.ref == 'refs/heads/main'
```

GitHub公式ドキュメントは、OIDC連携で少なくとも1つの条件を定義し、信頼しないRepositoryがトークンを要求できないようにすることを求めている。[2]

### 5.3 Provider作成コマンド

```bash
export PROVIDER_ID="github-oidc"
export GITHUB_OWNER_ID="12345678"
export GITHUB_REPOSITORY_ID="87654321"

MAPPINGS="google.subject=assertion.sub,attribute.repository_id=assertion.repository_id,attribute.repository_owner_id=assertion.repository_owner_id,attribute.repository=assertion.repository,attribute.ref=assertion.ref,attribute.workflow=assertion.workflow,attribute.environment=assertion.environment"
CONDITION="assertion.repository_owner_id == '${GITHUB_OWNER_ID}' && assertion.repository_id == '${GITHUB_REPOSITORY_ID}'"

gcloud iam workload-identity-pools providers create-oidc "$PROVIDER_ID" \
  --project="$GCP_PROJECT_ID" \
  --location="global" \
  --workload-identity-pool="$POOL_ID" \
  --issuer-uri="https://token.actions.githubusercontent.com/" \
  --attribute-mapping="$MAPPINGS" \
  --attribute-condition="$CONDITION"

export WIF_PROVIDER="projects/${PROJECT_NUMBER}/locations/global/workloadIdentityPools/${POOL_ID}/providers/${PROVIDER_ID}"
echo "$WIF_PROVIDER"
```

Provider IDは後から変更しにくいため、命名規則、用途、環境、Repository範囲を先に決める。GitHub ActionsのIssuer URLは `https://token.actions.githubusercontent.com/` を使用する。[1] [2]

## 6. CIサービスアカウントの作成と権限

```bash
export CI_SA_ID="sa-ci-controls"
export CI_SERVICE_ACCOUNT="${CI_SA_ID}@${GCP_PROJECT_ID}.iam.gserviceaccount.com"

gcloud iam service-accounts create "$CI_SA_ID" \
  --project="$GCP_PROJECT_ID" \
  --display-name="CI Terraform and BigQuery controls"
```

WIF主体へサービスアカウントの偽装権限を付与する。属性を利用したPrincipal指定により、対象Repository以外からの偽装を防ぐ。

```bash
gcloud iam service-accounts add-iam-policy-binding "$CI_SERVICE_ACCOUNT" \
  --project="$GCP_PROJECT_ID" \
  --role="roles/iam.workloadIdentityUser" \
  --member="principalSet://iam.googleapis.com/${POOL_NAME}/attribute.repository_id/${GITHUB_REPOSITORY_ID}"
```

CIサービスアカウントへ付与する権限は、次のようにジョブ目的ごとに限定する。

| ジョブ | 例示権限 | 付与先 |
|---|---|---|
| Terraform plan | Resource読み取り、plan対象APIの読み取り | CIプロジェクトまたは対象Stagingプロジェクト |
| BigQuery dry run | BigQuery Job User、対象Dataset metadata閲覧 | CI / Stagingプロジェクト |
| Staging DQ | 対象Staging Datasetの読取・必要な一時書込 | Staging Datasetのみ |
| 本番apply | 原則別サービスアカウント、承認付きEnvironmentのみ | 本番プロジェクト |

`roles/owner`、`roles/editor`、プロジェクト全体の`roles/bigquery.admin`をCIサービスアカウントへ付与しない。Pull Requestでは、本番書込み権限を付与しない。

## 7. GitHub ActionsのVariablesとSecrets

### 7.1 Repository Variables（機密ではない設定値）

| Variable | 必須 | 例 | 用途 |
|---|---:|---|---|
| `GCP_WORKLOAD_IDENTITY_PROVIDER` | Yes | `projects/123.../providers/github-oidc` | `auth` Actionへ渡す完全修飾Provider名 |
| `GCP_CI_SERVICE_ACCOUNT` | Yes | `sa-ci-controls@...iam.gserviceaccount.com` | WIFで偽装するサービスアカウント |
| `CI_GCP_PROJECT` | Yes | `prj-data-ci` | dry run・テスト用Project |
| `STAGING_GCP_PROJECT` | Yes | `prj-data-stg` | Staging検証先 |
| `MAX_BYTES_BILLED` | Yes | `10737418240` | CIクエリごとの最大bytes |
| `TF_VERSION` | No | `1.16.2` | Terraform version |
| `CONFTEST_VERSION` | No | `0.56.0` | Conftest version |
| `CHECKOV_VERSION` | No | `3.2.301` | Checkov version |

Variablesは公開されても認証情報にならない値だけにする。Provider名やサービスアカウント名は秘密ではないが、ログへ不用意に出力しない。

### 7.2 GitHub Secrets

WIF構成では、通常、GCPサービスアカウントキーJSONをSecretへ登録しない。必要なSecretがある場合は、外部APIのテスト用トークンや署名検証用の値など、対象Job・Environment・Repositoryを限定する。

| Secret | 方針 |
|---|---|
| GCPサービスアカウントキー | 原則作成・保存しない。WIFへ移行する |
| 外部APIテストトークン | Staging Environment専用、期限と所有者を設定 |
| SFTP検証鍵 | 本番と分離し、Secret Manager参照を優先 |
| 署名検証用公開情報 | 秘密でなければVariablesまたはRepositoryファイルへ置く |

### 7.3 GitHub Environment

`staging`と`production`を分ける。production Environmentには、Required reviewers、対象ブランチ・タグ制限、Environment Secretの分離を設定する。GitHub公式も、EnvironmentをOIDCポリシーへ含める場合はProtection Rulesを設定することを推奨している。[2]

## 8. Workflow設定

```yaml
permissions:
  contents: read
  id-token: write

steps:
  - uses: actions/checkout@v4
  - uses: google-github-actions/auth@v3
    with:
      workload_identity_provider: ${{ vars.GCP_WORKLOAD_IDENTITY_PROVIDER }}
      service_account: ${{ vars.GCP_CI_SERVICE_ACCOUNT }}
  - uses: google-github-actions/setup-gcloud@v2
  - run: gcloud auth list
```

`id-token: write`はGitHub OIDCトークンの取得権限であり、Google Cloudリソースへの書込み権限そのものではない。実際のアクセスは、WIFの条件とサービスアカウント権限の組み合わせで決まる。[2]

`actions/checkout`は認証Actionより先に実行する。認証Actionの生成資格情報ファイルを成果物へ含めないよう、`.gitignore`と`.dockerignore`へ`gha-creds-*.json`を追加する。[3]

## 9. 動作確認

```bash
gcloud iam workload-identity-pools providers describe "$PROVIDER_ID" \
  --project="$GCP_PROJECT_ID" \
  --location=global \
  --workload-identity-pool="$POOL_ID"

gcloud iam service-accounts get-iam-policy "$CI_SERVICE_ACCOUNT" \
  --project="$GCP_PROJECT_ID"
```

GitHub Actionsでは、まず読み取り専用の検証Jobで次を確認する。

- `gcloud auth list`に期待するサービスアカウントが表示される
- `gcloud projects describe`が許可されたProjectだけで成功する
- BigQuery dry runがCI ProjectまたはStagingで成功する
- 本番Datasetの一覧取得・書込みが意図どおり拒否される
- 期待Repository以外、main以外、未承認Environmentからの認証が拒否される

WIF Pool、Provider、IAM権限の反映には時間がかかる場合がある。公式Actionドキュメントは、反映に最大5分程度かかる場合があると説明している。[3]

## 10. ローテーション・無効化・インシデント対応

WIFでは長期サービスアカウントキーの定期ローテーションは不要になる。一方で、Repository削除、Organization変更、Workflow変更、サービスアカウント権限変更は監視する。

侵害または誤設定が疑われる場合は、次の順序で対応する。

1. Providerのattribute conditionを一時的に厳格化する。
2. CIサービスアカウントの対象Dataset権限を一時停止する。
3. GitHub Environmentのデプロイを停止する。
4. Cloud Audit LogsとGitHub Actions実行履歴を照合する。
5. WIF Provider、サービスアカウント、IAM Conditionsを修正する。
6. Stagingで認証・拒否テストを行う。
7. 事後レビューと例外台帳を更新する。

## References

[1]: https://cloud.google.com/iam/docs/workload-identity-federation-with-deployment-pipelines "Workload Identity Federation with deployment pipelines"
[2]: https://docs.github.com/actions/deployment/security-hardening-your-deployments/configuring-openid-connect-in-google-cloud-platform "Configuring OpenID Connect in Google Cloud Platform"
[3]: https://github.com/google-github-actions/auth "google-github-actions/auth"
[4]: https://docs.github.com/actions/security-for-github-actions/security-hardening-your-deployments/about-security-hardening-with-openid-connect "About security hardening with OpenID Connect"

---

**運用開始条件**：セキュリティ責任者、GCP基盤責任者、Repository管理者が、Provider条件、Repository・Organizationの数値ID、Environment保護、CIサービスアカウント権限、失効手順を承認する。
