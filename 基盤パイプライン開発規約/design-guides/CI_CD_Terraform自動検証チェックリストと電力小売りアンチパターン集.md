# データ基盤統制 実装チェックリストと電力小売りアンチパターン集

**版**：1.0

**適用基準**：[データ基盤汎用デザインガイド v1.0](データ基盤汎用デザインガイド.md)

**個別適用**：[電力小売りデータ基盤 個別デザインガイド v1.0](電力小売りデータ基盤個別デザインガイド.md)

## 0. 実装環境標準

本書のローカル実行とCI/CD実装で使用するツールの推奨バージョンは、[ローカル開発環境標準](ローカル開発環境標準.md)を正とする。CIのTerraformバージョンはWorkflowの`TF_VERSION`と一致させる。

## 1. 目的と適用範囲

本書は、汎用デザインガイドv1.0と電力小売り個別ガイドv1.0に定義された統制を、実際のCI/CDパイプライン、Terraform、BigQuery SQL、Dataform、デプロイ後監視で自動検証するための実装チェックリストである。既存の正式ガイド本文を変更せず、実装時の検証標準として利用する。

統制は、次の4層に分けて実装する。

| 層 | 目的 | 主な検証手段 | 実行タイミング |
|---|---|---|---|
| Terraform静的検査 | GCPリソース、IAM、境界、暗号、保持設定の誤りを拒否する | `terraform fmt`、`validate`、`plan`、OPA / Conftest、Checkov等 | Pull Request、デプロイ前 |
| SQL・Dataform検査 | スキーマ、Policy Tag、パーティション、PII、粒度、品質を検査する | SQL lint、compile、dry run、静的ルール、Dataform assertion | Pull Request、ビルド |
| 結合・受入テスト | 実際の権限、行制御、公開ゲート、再実行、コストを検証する | テストプロジェクト、代表ユーザー、BQ Job統計 | Staging、リリース前 |
| 継続監視 | デプロイ後の権限逸脱、費用急増、ログ欠損、TTL逸脱を検知する | Cloud Asset Inventory、Audit Logs、Billing Export、BQ INFORMATION_SCHEMA | 日次、月次、イベント時 |

本書の検査は、単なる文字列検索だけで合格にしてはならない。生成SQL、Terraform plan、実行主体、対象プロジェクト、実際のクエリ実行結果を組み合わせて判定する。

## 2. CI/CDパイプラインの標準ゲート

### 2.1 Pull Requestゲート

| ゲート | 必須チェック | 不合格条件 | 主な統制ID |
|---|---|---|---|
| PR-01 | 形式・構文 | Terraform、YAML、SQL、Dataformの構文エラー | SEC-22、SEC-24 |
| PR-02 | Secret scan | 秘密鍵、APIキー、keyset、Secret値の検出 | SEC-20、SEC-21、ESEC-17 |
| PR-03 | IAM差分 | Owner / Editor等の過剰権限、無期限特権、意図しない公開 | SEC-03〜SEC-08、ESEC-04〜ESEC-05 |
| PR-04 | データ分類 | 新規列・資産に分類、Policy Tag、所有者、保持期限がない | SEC-09〜SEC-13、ESEC-01〜ESEC-05 |
| PR-05 | SQL安全性 | Gold / Servingが原PII、鍵、未承認Silver、マスク列JOINを参照 | SEC-10〜SEC-12、ESEC-02〜ESEC-05 |
| PR-06 | パーティション | 大規模時間系テーブルに適切なパーティションまたは承認済み例外がない | COST-07、ECOST-03、ECOST-17 |
| PR-07 | コスト回帰 | dry run費用がベースラインまたは上限を超える | COST-05〜COST-08、ECOST-03〜ECOST-06 |
| PR-08 | 破壊的変更 | 列削除、型変更、粒度変更、Policy Tag削除に移行計画がない | SEC-27 |
| PR-09 | コンテナ・依存 | 脆弱性、未固定イメージ、root実行、未承認依存 | SEC-22〜SEC-24 |
| PR-10 | Terraform計画 | 未承認プロジェクト、リージョン、サービス、ネットワーク境界の変更 | SEC-01、SEC-02、SEC-16〜SEC-19 |

### 2.2 Stagingゲート

| ゲート | 実行テスト | 不合格条件 | 主な証跡 |
|---|---|---|---|
| STG-01 | Terraform plan適用 | 想定外リソース、IAM、Policy、鍵、TTL差分 | plan、適用ログ |
| STG-02 | Dataform compile / assertion | 依存解決失敗、Critical assertion失敗 | compile結果、DQ結果 |
| STG-03 | BigQuery dry run | 対象期間外の走査、費用上限超過 | Job ID、bytes processed |
| STG-04 | 代表クエリ実行 | 粒度、件数、金額、電力量、48コマ、SCDが不合格 | テスト結果 |
| STG-05 | 権限テスト | 許可対象が読めない、禁止対象が読める | ユーザー別クエリ結果 |
| STG-06 | エクスポートテスト | 未承認のExtract / Copy / BI共有が可能 | Job監査ログ |
| STG-07 | 冪等性テスト | 同じ入力の再実行で二重計上、訂正破壊、件数差異 | 1回目・2回目比較 |
| STG-08 | 復旧テスト | データ、IAM、Policy Tag、鍵、Auditを復元できない | 復元結果、RPO / RTO |

### 2.3 本番デプロイゲート

本番デプロイは、Pull RequestゲートとStagingゲートの全合格、変更承認、費用見積もり、ロールバックまたは前回正常版への復帰手順が揃った場合だけ許可する。月次精算、制度マスタ、確定値、PII権限、監査ログ設定の変更には、通常のアプリケーション変更より高い承認レベルを要求する。

## 3. Terraform自動検証項目

### 3.1 必須チェック一覧

| ID | Terraform対象 | 自動検証 | 不合格条件 | 推奨実装 |
|---|---|---|---|---|
| TF-01 | Provider / Project | プロジェクトID、環境、許可リージョンを検証 | 本番IDのハードコード、未承認リージョン、devからprod参照 | `terraform validate`、OPA |
| TF-02 | BigQuery Dataset | データセットロケーション、環境、分類、所有者を検証 | ロケーション不一致、説明・所有者欠落 | Terraform planポリシー |
| TF-03 | BigQuery Table | パーティション、クラスタ、TTL、説明、ラベルを検証 | 大規模ファクトにpartitionなし、TTLなし、ラベル欠落 | OPA / Checkov相当 |
| TF-04 | Partition Filter | `require_partition_filter`を検証 | 例外台帳なしでFALSEまたは未設定 | OPA |
| TF-05 | PII Policy Tag | 列分類とPolicy Tagの対応を検証 | PII列にPolicy Tagなし、Goldへ原PII公開 | schema metadata検査 |
| TF-06 | Row Access Policy | エリア、BG、顧客、担当範囲を検証 | 期待するprincipal・filterがない | 実環境結合テスト |
| TF-07 | IAM | principal、role、condition、期限を検証 | allUsers、allAuthenticatedUsers、Owner / Editor、無期限特権 | `terraform show -json` + OPA |
| TF-08 | Service Account | SA用途とロールの分離を検証 | CI、取込、PII、BI、DQが同一SA | 命名規則・IAMグラフ検査 |
| TF-09 | Secret Manager | Secret本体と参照権限を分離 | secret値をtfvars / stateへ投入、開発と本番共有 | Secret参照検査 |
| TF-10 | Cloud KMS | 鍵ロケーション、ローテーション、管理者分離を検証 | rotationなし、利用者が管理権限を持つ | KMS policy検査 |
| TF-11 | Logging | Audit Logs、Log Router、専用保存先を検証 | Data Access未収集、監査ログ保存先が削除可能 | Logging policy検査 |
| TF-12 | VPC SC / Network | perimeter、Private Access、外部出口を検証 | 本番データが境界外、任意外部通信 | Access Context / Network検査 |
| TF-13 | GCS | uniform access、公開禁止、Lifecycle、保持を検証 | ACL混在、公開可能、原本TTLなし | OPA / API検査 |
| TF-14 | Cloud Run / Functions | ingress、SA、Secret、イメージDigestを検証 | unauthenticated、default SA、tag参照 | plan JSON検査 |
| TF-15 | Budget / Billing | 予算、通知、Billing Export、ラベルを検証 | 通知先なし、費用配賦不能 | Billing API検査 |
| TF-16 | Reservation | workload、project assignment、リージョンを検証 | 月次精算・速報・BIの意図しない共有 | Reservation設定検査 |
| TF-17 | Retention | BQ partition expiration、GCS lifecycle、legal holdを検証 | 速報・Sandbox・一時資産が無期限 | 期限ポリシー |
| TF-18 | DR | バックアップ、復元対象、鍵、IAM、Policy Tagを検証 | データのみで権限・鍵・監査を復元できない | DR planレビュー |

### 3.2 Terraformで拒否すべきIAM設定例

次のような設定は、電力小売りの機微データ基盤ではCIで拒否する。

```hcl
# 悪い例：プロジェクト全体へ人間ユーザーに広範な管理権限を付与する
resource "google_project_iam_member" "bad_editor" {
  project = var.prod_project_id
  role    = "roles/editor"
  member  = "user:analyst@example.com"
}

# 悪い例：BigQueryデータセットを全員へ公開する
resource "google_bigquery_dataset_iam_member" "bad_public_reader" {
  project    = var.prod_project_id
  dataset_id = google_bigquery_dataset.gold.dataset_id
  role       = "roles/bigquery.dataViewer"
  member     = "allUsers"
}
```

```hcl
# 良い例：用途専用サービスアカウントへ、対象データセットの必要権限だけを付与する
resource "google_service_account" "settlement_job" {
  project      = var.prod_project_id
  account_id   = "sa-settlement-job"
  display_name = "月次精算専用実行主体"
}

resource "google_bigquery_dataset_iam_member" "settlement_writer" {
  project    = var.prod_project_id
  dataset_id = google_bigquery_dataset.gold_settlement.dataset_id
  role       = "roles/bigquery.dataEditor"
  member     = "serviceAccount:${google_service_account.settlement_job.email}"
}

# 良い例：一時的な調査権限には期限条件を付与する
resource "google_project_iam_member" "temporary_investigator" {
  project = var.prod_project_id
  role    = "roles/bigquery.jobUser"
  member  = "group:approved-investigators@example.com"

  condition {
    title       = "incident-investigation-expiry"
    description = "障害調査の期限付きジョブ実行権限"
    expression  = "request.time < timestamp('2026-09-30T23:59:59Z')"
  }
}
```

`roles/bigquery.dataEditor`で十分とは限らない。実際の書込み対象を専用データセット、専用テーブル、または処理経路に限定し、確定値・監査ログ・制度マスタへの更新権限を同時に付与しない。

## 4. SQL / Dataform自動検証項目

| ID | SQL / Dataform対象 | 自動検証 | 不合格条件 |
|---|---|---|---|
| SQL-01 | DDL | `PARTITION BY`、`CLUSTER BY`、`require_partition_filter`、説明、分類を検証 | 大規模時間系資産に設定なし |
| SQL-02 | 公開層 | Gold / Servingの参照元を検査 | Bronze、Restricted PII、鍵テーブル、未承認Silverを参照 |
| SQL-03 | PII | 原PII列、鍵、平文keyset、メール・電話等の流出を検査 | Gold / Servingへ原PIIを投影 |
| SQL-04 | JOIN | マスク列、文字列ハッシュ、未承認疑似識別子のJOINを検査 | `masked_*`、`sha256_*`をJOINキーに使用 |
| SQL-05 | 粒度 | モデル契約とGROUP BY / JOINを照合 | 30分コマが重複、親子ARRAYで二重計上 |
| SQL-06 | 期間 | SCDの`valid_from` / `valid_to`条件を検査 | `is_current`だけで過去照会、期間条件欠落 |
| SQL-07 | 電力単位 | kW / kWh、受電端 / 送電端、税込 / 税抜を検査 | 単位混在、0埋め、無根拠換算 |
| SQL-08 | 速報成熟度 | 速報・確報・確定の優先順位を検査 | 上書き、二重計上、確定値の直接更新 |
| SQL-09 | DQゲート | 48コマ、単価、金額、電力量、BG按分、主キーを検査 | Critical DQ失敗でも公開 |
| SQL-10 | コスト | パーティション条件、対象日、エリア、地点範囲を検査 | 全期間走査、無制限バックフィル |
| SQL-11 | DML | `MERGE`、`UPDATE`、`DELETE`の対象範囲を検査 | 対象パーティション条件なし |
| SQL-12 | エクスポート | Extract / Copy対象と分類を検査 | 機微データを無承認宛先へ出力 |
| SQL-13 | 金額 | `NUMERIC` / `BIGNUMERIC`と丸め位置を検査 | `FLOAT64`、コマ単位丸め、費目欠落 |
| SQL-14 | 冪等性 | 実行ID、入力範囲、訂正方式を検査 | 再実行で重複、確定行の破壊 |

### 4.1 SQL静的検査の簡易ルール例

実運用ではSQL parserを利用し、次の文字列検査は補助的に使う。単純な正規表現だけで本番合否を決めない。

```bash
# 補助検査例：Gold / Serving SQLに原PII・鍵・危険なマスクJOINがないことを確認
set -euo pipefail

if rg -n -i '(customer_name|email|phone|address|plaintext_keyset|key_table)' models/gold models/serving; then
  echo "原PIIまたは鍵参照の疑いがあります" >&2
  exit 1
fi

if rg -n -i 'JOIN\s+.*(masked_|sha256_|hash_)' models/gold models/serving; then
  echo "マスク列または単純ハッシュのJOINを検出しました" >&2
  exit 1
fi

if rg -n -i 'UPDATE|DELETE|MERGE' models/finalized && \
   ! rg -n 'target_date|_PARTITIONDATE|partition_date' models/finalized; then
  echo "確定層DMLに対象パーティション条件がありません" >&2
  exit 1
fi
```

### 4.2 BigQuery dry runによるコストゲート例

CI用サービスアカウントは、検証用データセットのジョブ実行に限定する。dry runの見積もりと、実際の本番費用は別管理にする。

```bash
#!/usr/bin/env bash
set -euo pipefail

sql_file="$1"
project_id="$2"
max_bytes="$3"

bytes_processed=$(bq query \
  --project_id="${project_id}" \
  --use_legacy_sql=false \
  --dry_run \
  --format=prettyjson < "${sql_file}" \
  | jq -r '.totalBytesProcessed')

if [[ -z "${bytes_processed}" || "${bytes_processed}" == "null" ]]; then
  echo "dry runのbytes processedを取得できません" >&2
  exit 1
fi

if (( bytes_processed > max_bytes )); then
  echo "コストゲート失敗: ${bytes_processed} bytes > ${max_bytes} bytes" >&2
  exit 1
fi

echo "コストゲート合格: ${bytes_processed} bytes"
```

対象日限定のSQLであることは、dry runだけでなく、生成SQLのパーティション条件とテストデータの実行結果でも確認する。

## 5. Terraform / SQL / 実行テストの対応マトリクス

| 統制 | Terraform静的 | SQL / Dataform静的 | Staging実行 | デプロイ後監視 |
|---|---|---|---|---|
| PII分離 | Dataset、IAM、Policy Tag | 原PII参照、鍵参照 | 代表ユーザーの拒否テスト | Data Access、DLP |
| 行・列アクセス | Row Access Policy、IAM | 公開列、WHERE条件 | ロール別クエリ | 権限差分、アクセスログ |
| パーティション | partition、filter設定 | WHERE条件、DML範囲 | dry run、Job統計 | 高額Job、全期間走査 |
| 速報・確報・確定 | Dataset / Table IAM | 優先統合、訂正方式 | 再送・再実行 | 二重計上、更新監視 |
| 制度マスタ | IAM、承認経路 | 適用期間、根拠ID | 改定前後差額 | マスタ変更ログ |
| 監査ログ | Log Router、保存先 | Audit列、実行ID | ログ受信テスト | 欠損、削除、異常参照 |
| コスト | Budget、Reservation、TTL | dry run、最大bytes | 代表負荷 | Billing Export、Slot |
| DR / BCP | Backup、KMS、IAM | 再生成SQL、契約 | 復元・再処理 | RPO / RTO実績 |

## 6. 電力小売り固有アンチパターン：良い例・悪い例

### 6.1 供給地点特定番号や原PIIを一般BIへ公開する

**悪い例**は、Silverの顧客テーブルを直接BIへ公開し、供給地点特定番号、氏名、住所をそのまま返す設計である。これは顧客・地点情報の過剰公開と再識別を招く。

```sql
-- 悪い例：原PIIと供給地点特定番号をBIへ直接公開
CREATE OR REPLACE VIEW `prod.gold.v_customer_power_usage` AS
SELECT
  customer_id,
  customer_name,
  address,
  supply_point_id,
  target_date,
  slot_number,
  usage_kwh
FROM `prod.silver.fact_customer_usage`;
```

```sql
-- 良い例：事前生成済み疑似識別子と必要最小限の集計だけを公開
CREATE OR REPLACE VIEW `prod.serving.v_customer_power_usage_summary` AS
SELECT
  customer_pseudonym,
  target_date,
  area_code,
  SUM(usage_kwh) AS total_usage_kwh,
  COUNT(DISTINCT slot_number) AS slot_count,
  MAX(publication_status) AS publication_status
FROM `prod.gold.fact_customer_usage_published`
WHERE publication_status = 'PUBLISHED'
GROUP BY customer_pseudonym, target_date, area_code;
```

原PIIから疑似識別子を生成する処理は、このビューで行わず、Restricted領域の専用ETLで実行する。供給地点特定番号を業務上表示する必要がある場合は、専用認可ビュー、Policy Tag、Row Access Policy、目的・期限付き権限を組み合わせる。

### 6.2 マスク列や単純SHA-256をJOINキーとして使う

**悪い例**では、動的マスキング値または単純ハッシュを異なるモデルの結合キーとして使用する。マスキング値はJOINキーとしての同一性を保証せず、単純ハッシュは候補値が限定されたPIIに対して辞書攻撃を受ける。

```sql
-- 悪い例：マスク値と単純SHA-256をJOINキーとして混在利用
SELECT
  u.target_date,
  SUM(u.usage_kwh) AS usage_kwh,
  SUM(b.gross_profit) AS gross_profit
FROM `prod.gold.usage_masked` AS u
JOIN `prod.gold.billing_sha256` AS b
  ON u.customer_name_masked = b.customer_name_sha256
GROUP BY u.target_date;
```

```sql
-- 良い例：用途、鍵バージョン、正規化方式を管理した事前生成済み疑似識別子を利用
SELECT
  u.target_date,
  SUM(u.usage_kwh) AS usage_kwh,
  SUM(b.gross_profit) AS gross_profit
FROM `prod.gold.fact_usage_pseudonymized` AS u
JOIN `prod.gold.fact_billing_pseudonymized` AS b
  ON u.customer_pseudonym = b.customer_pseudonym
 AND u.pseudonym_key_version = b.pseudonym_key_version
 AND u.normalization_version = b.normalization_version
GROUP BY u.target_date;
```

CIでは、`masked_`、`hash_`、`sha256_`等の列をJOIN条件へ使用するSQLを検出し、例外には疑似識別子の契約と承認記録を要求する。

### 6.3 速報・確報・確定を1テーブルへ上書きする

**悪い例**は、同じ主キーの速報を確報・確定で更新し、受領順序と訂正履歴を失わせる設計である。

```sql
-- 悪い例：速報・確報・確定を同じテーブルへ上書きする
MERGE `prod.silver.fact_power_usage` t
USING `prod.bronze.latest_usage_file` s
ON t.supply_point_id = s.supply_point_id
AND t.target_date = s.target_date
AND t.slot_number = s.slot_number
WHEN MATCHED THEN UPDATE SET
  usage_kwh = s.usage_kwh,
  status = s.status,
  updated_at = CURRENT_TIMESTAMP()
WHEN NOT MATCHED THEN INSERT ROW;
```

```sql
-- 良い例：成熟度別の物理資産を保持し、公開用ビューで優先順位を明示する
CREATE OR REPLACE VIEW `prod.gold.v_usage_timeline` AS
WITH ranked AS (
  SELECT *, 3 AS maturity_priority FROM `prod.silver.fact_usage_confirmed`
  UNION ALL
  SELECT *, 2 AS maturity_priority FROM `prod.silver.fact_usage_provisional`
  UNION ALL
  SELECT *, 1 AS maturity_priority FROM `prod.silver.fact_usage速報`
), selected AS (
  SELECT * EXCEPT(row_number)
  FROM (
    SELECT
      ranked.*,
      ROW_NUMBER() OVER (
        PARTITION BY supply_point_id, target_date, slot_number
        ORDER BY maturity_priority DESC, received_at DESC
      ) AS row_number
    FROM ranked
  )
  WHERE row_number = 1
)
SELECT * FROM selected;
```

確定値の訂正は、通常の上書きではなく、訂正理由、訂正元、訂正後、実行ID、承認者を持つ訂正レコードと再計算履歴で管理する。

### 6.4 単価未解決を0埋めして日報を公開する

**悪い例**は、制度単価、JEPX単価、託送料金、インバランス単価が見つからないときに0を代入し、計算を続行する設計である。

```sql
-- 悪い例：単価未解決を0として売上・原価を計算する
SELECT
  target_date,
  slot_number,
  usage_kwh,
  COALESCE(jepx_price, 0) AS jepx_price,
  usage_kwh * COALESCE(jepx_price, 0) AS procurement_cost
FROM `prod.silver.fact_usage_and_price`;
```

```sql
-- 良い例：単価未解決をCriticalとして隔離し、公開可否を制御する
SELECT
  target_date,
  slot_number,
  usage_kwh,
  jepx_price,
  usage_kwh * jepx_price AS procurement_cost,
  CASE
    WHEN jepx_price IS NULL THEN 'CRITICAL_PRICE_UNRESOLVED'
    ELSE 'OK'
  END AS dq_status,
  CASE
    WHEN jepx_price IS NULL THEN FALSE
    ELSE TRUE
  END AS publishable
FROM `prod.silver.fact_usage_and_price`;
```

Dataform assertionまたは同等のDQジョブで`publishable = FALSE`を検出し、Gold・Serving・BI抽出を前回正常版へ固定する。

### 6.5 kWとkWh、受電端と送電端を混在させる

**悪い例**は、平均電力kWを電力量kWhとして扱い、受電端の値を送電端の値と直接比較する設計である。

```sql
-- 悪い例：単位・基準点が列名から不明で、直接差し引いている
SELECT
  target_date,
  demand_value - generation_value AS imbalance_value
FROM `prod.silver.fact_power_values`;
```

```sql
-- 良い例：単位と基準点を列・契約へ明示し、送電端kWhへ統一してから計算する
WITH normalized AS (
  SELECT
    target_date,
    slot_number,
    demand_kw * NUMERIC '0.5' AS demand_kwh_received,
    generation_kwh_sent,
    loss_rate,
    demand_kw * NUMERIC '0.5' / (NUMERIC '1.0' - loss_rate)
      AS demand_kwh_sent
  FROM `prod.silver.fact_power_interval_normalized`
)
SELECT
  target_date,
  slot_number,
  demand_kwh_sent,
  generation_kwh_sent,
  demand_kwh_sent - generation_kwh_sent AS imbalance_kwh
FROM normalized;
```

`loss_rate`がNULL、1以上、負値の場合は計算を継続せず、QuarantineまたはCritical DQへ送る。

### 6.6 制度マスタを担当者が直接本番更新する

**悪い例**は、料金、損失率、FIP、容量拠出金などを本番テーブルへ直接更新することである。

```hcl
# 悪い例：広い編集権限を制度担当者の個人アカウントへ付与
resource "google_bigquery_dataset_iam_member" "bad_master_editor" {
  project    = var.prod_project_id
  dataset_id = "gold_settlement"
  role       = "roles/bigquery.dataEditor"
  member     = "user:operator@example.com"
}
```

```hcl
# 良い例：制度マスタの登録、承認、反映をサービスアカウントとCI/CDへ分離
resource "google_service_account" "master_release" {
  project    = var.prod_project_id
  account_id = "sa-master-release"
}

resource "google_bigquery_table_iam_member" "master_release_writer" {
  project    = var.prod_project_id
  dataset_id = "silver_master"
  table_id   = "dim_tariff_master"
  role       = "roles/bigquery.dataEditor"
  member     = "serviceAccount:${google_service_account.master_release.email}"
}
```

CIでは、制度マスタ変更に適用開始日、終了日、根拠資料ID、変更理由、承認者、影響期間、差額試算結果があることを検査する。経理・精算担当者へ本番テーブルの恒常的な編集権限を与えず、承認済みパイプラインからのみ反映する。

### 6.7 月次確定後に全期間を一括再計算する

**悪い例**は、制度改定や訂正の影響範囲を特定せず、全期間・全エリア・全地点を対象に再計算することである。

```sql
-- 悪い例：対象期間を指定せず全履歴を再計算
CREATE OR REPLACE TABLE `prod.gold.agg_daily_pnl` AS
SELECT * FROM `prod.intermediate.recalculate_all_history`;
```

```sql
-- 良い例：承認済みの対象日・エリア・制度年度だけを再生成
DECLARE affected_from DATE DEFAULT DATE '2026-08-01';
DECLARE affected_to   DATE DEFAULT DATE '2026-08-31';

DELETE FROM `prod.gold.agg_daily_pnl`
WHERE target_date BETWEEN affected_from AND affected_to
  AND area_code IN ('HOKKAIDO', 'TOHOKU')
  AND settlement_version = '制度改定2026_08';

INSERT INTO `prod.gold.agg_daily_pnl`
SELECT *
FROM `prod.intermediate.recalculate_daily_pnl`
WHERE target_date BETWEEN affected_from AND affected_to
  AND area_code IN ('HOKKAIDO', 'TOHOKU');
```

この処理は、実行前にdry run、対象件数、予想bytes、最大費用、差額見込み、承認者をAuditへ記録する。フルリフレッシュは例外扱いとする。

### 6.8 速報ストリームを経営BIへ直接接続する

**悪い例**は、48コマの速報ファクトを経営ダッシュボードがライブスキャンする設計である。

```sql
-- 悪い例：BIが速報の全履歴を直接スキャンする
SELECT
  area_code,
  target_date,
  slot_number,
  usage_kwh,
  updated_at
FROM `prod.silver.fact_usage速報`
WHERE area_code = @area_code;
```

```sql
-- 良い例：公開可否を通過した日次Serving資産を期間限定で参照する
SELECT
  area_code,
  target_date,
  total_usage_kwh,
  total_gross_profit,
  publication_status
FROM `prod.serving.agg_daily_power_kpi`
WHERE target_date BETWEEN @from_date AND @to_date
  AND publication_status = 'PUBLISHED';
```

需給監視だけは速報専用の低遅延ビューを利用できるが、対象期間、利用者、Slot、最大bytes、更新頻度を契約へ記録し、経営BIと分離する。

## 7. CI/CDの実装成果物

最低限、次の成果物をリポジトリへ配置する。

```text
ci/
  terraform-check.sh
  sql-static-check.sh
  bq-dry-run.sh
  policy-test.sh
  cost-regression.sh
  secret-scan.sh
  export-policy-check.sh
policies/
  terraform.rego
  iam.rego
  bigquery.rego
  labels.rego
  retention.rego
tests/
  access/
    expected-access.yaml
  dq/
    power-usage.yml
  cost/
    query-budgets.yml
  fixtures/
   速報_conflict.sql
   制度単価_missing.sql
```

CIの判定結果には、コミットSHA、Terraform planハッシュ、SQLモデル版、実行プロジェクト、リージョン、ジョブID、bytes processed、判定ルール版を含める。これにより、後から「どのコードとポリシーで公開を許可したか」を追跡できる。

## 8. 導入順序

最初に、Terraform planのIAM・公開設定・Policy Tag・パーティション・ラベル検査を必須化する。次に、SQL/DataformのPII参照、マスク列JOIN、対象日フィルター、Critical DQ、48コマ、単価未解決検査を追加する。その後、Stagingでロール別アクセス、速報・確報・確定の再実行、月次精算の差分再計算、dry run費用を検証する。最後に、Billing Export、Audit Logs、Slot、権限差分、TTL逸脱を日次監視へ移行する。

本番では、検査を一度にすべて自動拒否へ切り替えず、最初は監査のみ、次に警告、最後にCritical項目を拒否する段階導入が安全である。ただし、原PIIの一般公開、`allUsers`への本番データ公開、確定値の無監査上書き、対象期間なしの高額バックフィルは初日から拒否対象とする。

## 9. 自動検証サンプルコード

本書のTerraform検査を実装するサンプルコード、Conftest / OPAのRego、Checkovカスタムチェック、GitHub Actionsワークフローは、次の補助成果物に分離して管理する。

[Terraform統制ポリシー・CI/CDサンプル](ci-policy-samples/README.md)

補助成果物には、Terraform plan JSONを対象とするConftestポリシー、BigQuery固有のパーティション・ラベル検査、Checkovカスタムチェック、Pull Request・Staging・dry runゲートを含む。サンプルは利用するTerraform Provider、Checkov、Conftestのバージョンに合わせて、組織のfixtureと閾値を設定したうえで本番採用する。

## References

[1]: /home/ubuntu/output/design-guides/data-platform-generic-design-guide.md "データ基盤汎用デザインガイド v1.0"
[2]: /home/ubuntu/output/design-guides/electricity-retail-data-platform-design-guide.md "電力小売りデータ基盤 個別デザインガイド v1.0"
[3]: /home/ubuntu/upload/bigquery-guideline.md "BigQuery データ基盤開発運用ガイドライン"
[4]: https://cloud.google.com/docs/terraform "Terraform on Google Cloud documentation"
[5]: https://cloud.google.com/iam/docs/conditions-overview "IAM Conditions overview"
[6]: https://cloud.google.com/bigquery/docs/column-level-security-intro "Introduction to column-level access control"
[7]: https://cloud.google.com/bigquery/docs/partitioned-tables "Introduction to partitioned tables"
[8]: https://cloud.google.com/bigquery/docs/reservations-intro "BigQuery reservations introduction"
[9]: https://cloud.google.com/billing/docs/how-to/export-data-bigquery "Export Cloud Billing data to BigQuery"

---

**運用開始条件**：本書のCritical検査を本番デプロイの必須ゲートにする前に、基盤責任者、セキュリティ責任者、データ責任者、需給運用責任者、経理・精算責任者、FinOps責任者が、例外、閾値、ロール、費用上限、緊急時の解除手順を承認する。
