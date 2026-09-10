# BigQuery データ基盤命名・運用定義書 v1.0 適合チェック結果と修正内容

**実施日**：2026-09-10
**対象**：`repo_en/sql/**`（DDL 3ファイル・69テーブル、UDF 1、ビュー 6、プロシージャ 8、検証SQL 1）および `repo_en/ops/`
**基準**：`BigQuery_データ基盤命名_運用定義書_v1_0.md`

---

## 1. サマリ

| 判定 | 件数 | 内訳 |
|---|---|---|
| **抵触（修正済み）** | 7 | F-1〜F-5、P-1（プレフィックス改名）、P-2（監査列への値設定） |
| **未着手（TODO 化）** | 1 | P-3（データ契約の登録）。仕様書 17.3 に TODO として登録 |
| **適合を確認** | 8 | C-1〜C-8 |

---

## 2. 抵触し、修正した項目

### F-1 プロジェクト・データセット修飾のハードコード（規約 3.1／3.2 必須）

**抵触内容**：`prod_staging.migration_customer_contracts` のように本番データセット名が SQL 本文に直接書かれていた（19箇所）。規約は「アプリケーションコード、SQL、ビュー定義に本番プロジェクトIDを直接埋め込んではならない」「環境は CI/CD またはテンプレート展開で注入」と定めている。

**修正**：テンプレート変数化した。

```sql
-- 修正前
FROM prod_staging.migration_customer_contracts

-- 修正後
FROM `${GCP_PROJECT_ID}.${BQ_DATASET_STAGING}.migration_customer_contracts`
```

| レイヤー | 変数 | 展開例（本番） |
|---|---|---|
| Bronze | `${BQ_DATASET_BRONZE}` | `bronze_power` |
| Silver | `${BQ_DATASET_SILVER}` | `silver_power` |
| Gold | `${BQ_DATASET_GOLD}` | `gold_power_mart` |
| ステージング | `${BQ_DATASET_STAGING}` | `staging_power` |

各ファイル冒頭の注記も「CI/CD で展開してから実行する。未展開のまま実行してはならない」に差し替えた。規約 3.2 は `${GCP_PROJECT_ID}` `${BQ_DATASET}` の未展開文字列を CI で検出してデプロイ拒否するよう求めているため、**CI にこの検査を組み込むこと**（本修正はテンプレート化までで、CI 設定は対象外）。

### F-2 フラグ列の型が INT64（規約 6.1 標準）

**抵触内容**：`is_`／`has_`／`include_`／`applies_` で始まる真偽値列が、すべて `INT64`（0/1）で定義されていた（**34列**）。規約 6.1 は「`_is`、`_has` → `BOOL`」と定めている。

**修正**：34列を `BOOL` に変更し、参照側のロジックも書き換えた。

```sql
-- DDL
is_exempt   INT64 NOT NULL     →  is_exempt   BOOL NOT NULL

-- 参照
WHERE mb.is_exempt = 1          →  WHERE mb.is_exempt
WHEN is_exempt = 0 THEN ...     →  WHEN NOT is_exempt THEN ...
1 AS is_national_holiday        →  TRUE AS is_national_holiday
COALESCE(month_settled, 0)      →  COALESCE(month_settled, FALSE)
```

対象列（主なもの）：`is_actual_kw_based`／`is_current`／`is_default`／`is_exempt`／`is_fip`／`is_fit`／`is_market_linked`／`is_peak`／`is_verified`／`is_publishable`／`is_loaded`／`is_causer`／`is_rate_holiday`／`is_own_bg`／`is_weekday`／`is_system_holiday`／`applies_to_tariff`／`apply_fuel_adjustment`／`include_saturday`／`include_sunday` ほか。

あわせて、`p_verify_daily_pnl` の変数 `v_ok` を `INT64` → `BOOL` に変更し、`IF(条件, 1, 0)` を条件式そのものに、`IF(v_ok = 1, …)` を `IF(v_ok, …)` に修正した（BOOL 列への代入で型不一致になるため）。列の説明文にあった「1：〜／0：〜」も `TRUE：`／`FALSE：` に統一した。

### F-3 テーブル・列の説明文が未設定（規約 2-4 必須、11.2）

**抵触内容**：DDL の説明が `-- 行末コメント` で書かれており、`OPTIONS(description = ...)` が1件も設定されていなかった。規約 2-4 は「データ資産の説明文には、業務上の意味、1行の粒度、単位、時刻基準、更新頻度、所有者を記載する」を必須とし、11.2 の実装例はすべて列単位の `OPTIONS(description = ...)` を持つ。BigQuery のデータカタログやカラム説明に反映されないため、コメント方式は要件を満たさない。

**修正**：行末コメントを `OPTIONS(description = '…')` に変換し、テーブルにも `OPTIONS(description = '…')` を付与した。

```sql
-- 修正前
  demand_kwh    NUMERIC NOT NULL,   -- 需要実績量（受電端）：発電行は 0

-- 修正後
  demand_kwh    NUMERIC NOT NULL OPTIONS(description = '需要実績量（受電端）：発電行は 0'),
```

| ファイル | 付与した列説明 |
|---|---|
| masters.sql | 351 |
| facts.sql | 331 |
| marts.sql | 167 |

> 説明文の内容は設計書由来の1行説明である。規約 2-4 が求める「1行の粒度、単位、時刻基準、更新頻度、所有者」までは含んでいない列があるため、**データ辞書登録時に補完すること**（下記 P-3）。

### F-4 監査・リネージ列の欠落（規約 11.3／11.4 標準）

**抵触内容**：規約の DDL 標準（11.2〜11.4）はすべてのテーブルに `ingestion_run_id`／`loaded_at`／`pipeline_version` を持たせているが、ファクト・マートに存在しなかった。規約 2-12「誰が何をいつ変更したか追跡可能にする」を満たさない。

**修正**：`f_*`（25テーブル）と `t_*`（9テーブル）の計 **34テーブル**に3列を追加した。

```sql
  ingestion_run_id   STRING OPTIONS(description = 'パイプライン実行ID（命名・運用定義書 11.3）'),
  loaded_at          TIMESTAMP OPTIONS(description = 'BigQueryへのロード日時UTC'),
  pipeline_version   STRING OPTIONS(description = '処理コードまたはモデルのバージョン'),
```

> 列の追加のみを行った。**各バッチ・プロシージャで値を設定する実装は未対応**（下記 P-2）。

### F-5 環境注記の記載（規約 3.2）

**抵触内容**：各SQLのヘッダーが「データセット修飾はデプロイスクリプトで付与する」という曖昧な表現だった。

**修正**：「`${GCP_PROJECT_ID}` と `${BQ_DATASET_*}` はテンプレート変数。CI/CD で環境別の値へ展開してから実行する（命名・運用定義書 3.2）。未展開のまま実行してはならない」に統一。`ALL_IN_ONE.sql` の冒頭にも、展開 → dry run → テストデータセット適用 → 本番デプロイの順序（規約 11.1）を明記した。

---

## 3. 追加で対応した項目（前回「要判断」としていたもの）

### P-1 テーブル・プレフィックスを規約の体系へ改名（修正済み）

規約 5.2 のプレフィックス表に合わせ、全 78 オブジェクトを改名した。SQL・設計仕様書・詳細設計書・損益分析定義書・README を一括で更新している。

| 変更前 | 変更後 | 対象 | 根拠 |
|---|---|---|---|
| `d_*` | `dim_*` | 35 | 5.2 ディメンション、マスタ |
| `f_*` | `fact_*` | 25 | 5.2 取引、イベント、実績 |
| `t_*` | `agg_*` | 8 | 5.2 明示的な事前集計。日報損益・月次サマリ等はバッチで生成する事前集計マート |
| `t_customer_holiday_snapshot` | `snap_customer_holiday` | 1 | 5.2 `snap_` スナップショット |
| `mv_*` | `agg_*` | 1 | 5.2 に `mv_` がないため、事前集計として `agg_` に統一 |
| `bz_*` | プレフィックスなし | 2 + 生データ全般 | 4章でBronzeはデータセット（`bronze_*`）により層が識別されるため。検疫テーブルは `quarantine_*` データセットへ配置 |
| `v_*` | 変更なし | 6 | 5.2 と一致 |

主な改名例：`d_areas` → `dim_areas`、`f_dem_actuals_daily` → `fact_dem_actuals_daily`、`t_daily_pnl` → `agg_daily_pnl`、`bz_holiday_csv_raw` → `holiday_csv_raw`。

> 改名は規約 9.1 の「列名変更＝破壊的変更」に準じる破壊的変更である。本基盤は構築前のため移行期間を設けず一括で適用した。既存の依存資産がある環境へ適用する場合は、規約 9.2 の廃止手順（依存調査 → 非推奨登録 → 互換ビュー → 通知 → 削除）を踏むこと。

### P-2 監査列への値設定（修正済み）

全プロシージャ（8本）に `IN p_run_id STRING, IN p_pipeline_version STRING` を追加し、`INSERT`／`MERGE` で監査3列を設定するようにした。プロシージャ間の `CALL` にも引数を引き継いでいる。

```sql
CREATE OR REPLACE PROCEDURE p_generate_daily_pnl(
  IN p_target_date DATE, IN p_run_id STRING, IN p_pipeline_version STRING)
...
  INSERT INTO agg_daily_pnl (..., ingestion_run_id, loaded_at, pipeline_version)
  SELECT ..., p_run_id, CURRENT_TIMESTAMP(), p_pipeline_version FROM costed;
```

| 列 | 渡す値 | 規約の根拠 |
|---|---|---|
| `ingestion_run_id` | **Workflows の execution ID 等、複数ジョブをまたいで一意な実行ID**。オーケストレータから渡す | 18.1「複数ジョブで構成される処理の主キーには `ingestion_run_id` を使用する」。同項は「`bq_job_id` を保持する場合は補助的な追跡情報とする」とも定めるため、BigQuery のジョブIDはこの列に入れない（保持する場合は別列 `bq_job_id`） |
| `loaded_at` | 各文の `CURRENT_TIMESTAMP()`（UTC） | 18.1「ロード日時UTC」、2-6「`TIMESTAMP` は絶対時刻、保存時はUTC」 |
| `pipeline_version` | **CI/CD がデプロイ時に注入したコード版**（Git コミットSHA、リリースタグ、dbt/Dataform のリリース識別子） | 下記のとおり |

**`pipeline_version` の規約上の位置づけと CI/CD との依存関係**

規約で `pipeline_version` に触れているのは次の3箇所で、定義そのものは1行しかない。

| 箇所 | 記載 |
|---|---|
| 18.1 監査メタデータ | `pipeline_version`：**処理コードまたはモデルの版** |
| 11.2〜11.4 DDL標準 | 全テーブル例に `pipeline_version STRING OPTIONS(description = '処理コードまたはモデルのバージョン')` を含む（列の存在が標準） |
| 21.2 二重発行防止 | 「再試行時は、**実行ID、入力範囲、対象テーブル、コードバージョン**を永続化する。同一実行IDが成功済みの場合は再発行しない。ジョブIDだけを冪等性キーとみなしてはならない」 |

つまり規約は「値の採番方式」を指定していない。指定しているのは (a) 列として持つこと、(b) 意味は処理コードの版であること、(c) 冪等性の判定材料として実行ID・入力範囲・対象テーブルと**セットで永続化**すること、の3点である。

CI/CD との依存関係は次のとおり。

1. **値の生成元は CI/CD**：規約 3.2 は環境を CI/CD またはテンプレート展開で注入すると定め、20 章は本番マージ前に SQL lint、dry run、dbt/Dataform の compile、プレースホルダー残存検査を自動実行すると定める。`pipeline_version` はこの一連のデプロイ処理が確定させる値であり、SQL 本文にリテラルで埋め込んではならない（埋め込むと規約 3.2 のプレースホルダー検査の趣旨に反し、デプロイのたびに SQL の書き換えが必要になる）。
2. **オーケストレータが実行時に渡す**：本基盤ではプロシージャ引数として受け取る形にした。Workflows／Composer が「デプロイ時に記録されたコード版」と「実行ID」を組にしてプロシージャへ渡す。
3. **冪等性テストとの接続**：規約 20 の「冪等性テスト」と 21.2 の二重発行防止は、`ingestion_run_id` ＋ 入力範囲（本基盤では対象実需給日または請求月）＋ 対象テーブル ＋ `pipeline_version` の4点を永続化していることを前提とする。本基盤ではバッチ実行ログ（`fact_batch_run_log`）にこれらを記録する設計であり、リラン時は同一 `ingestion_run_id` の成功済み判定に使う。
4. **未確定事項**：Git コミットSHA を使うか、リリースタグを使うか、dbt/Dataform を採用した場合にそのリリース識別子を使うかは、CI/CD の実装方式が決まってから確定する。**規約はいずれでもよい**（「処理コードまたはモデルの版」であればよい）。桁数・形式を組織で統一し、データ辞書へ登録すること。

### P-3 データ契約・データ辞書の登録（TODO として登録）

規約 13 が求める公開資産ごとのデータ契約（1行の粒度、対象期間、更新頻度と鮮度SLA、金額の通貨・税・返品・取消の扱い、NULLと削除済みの扱い、利用可能な結合キー、禁止される結合パターン、コスト上の推奨フィルター、オーナー・問い合わせ先）は未登録である。

**対応**：設計仕様書に **17.3「データ契約の登録（TODO）」** の節を新設し、登録項目と本基盤での想定値、対象資産（`agg_daily_pnl` ほか9資産）、および現時点で確定している「禁止される結合パターン」を記載した。登録先のデータカタログが決まった時点で作成する。

---

## 4. 適合を確認した項目

| # | 規約 | 確認結果 |
|---|---|---|
| C-1 | 2-1／2-2 ASCII 小文字 snake_case、日本語・全角・空白・ハイフン・キャメルケース禁止 | 全テーブル・列名が適合。日本語は説明文とコメントのみ |
| C-2 | 6.1 `_at` = TIMESTAMP | TIMESTAMP 列はすべて `_at` で終わる。違反 0件 |
| C-3 | 6.2 確定金額に FLOAT64 を使わない | 金額・電力量はすべて `NUMERIC`。`FLOAT64` の使用 0件 |
| C-4 | 5.4 日付シャード禁止 | `*_20260910` 形式のテーブル名 0件。すべて `PARTITION BY` |
| C-5 | 11.1 本番での無計画な `CREATE OR REPLACE TABLE` 禁止 | DDL はすべて `CREATE TABLE IF NOT EXISTS`。`CREATE OR REPLACE TABLE` 0件（ビュー・プロシージャの `CREATE OR REPLACE` は対象外） |
| C-6 | 10.2 `require_partition_filter` | 大規模時間系テーブルに設定済み。速報ストリームは取込日パーティション＋有効期限、先物価格は取引日パーティション |
| C-7 | 10.4.1 クラスタリング列は最大4列 | 最大3列（`area_code, direction, segment, bg_code` の4列が最大）。上限内 |
| C-8 | 11.4／12 SCD Type 2 と業務PIT | 期間管理マスタは `(識別子, start_date)` の複合キー。`end_date = 9999-12-31` で統一。期間重複・隙間・逆転の検証SQL と移行ゲートを実装済み。Time Travel と混同しない旨を設計書に明記 |

> C-8 の補足：規約 11.4 は `valid_from_at`／`valid_to_at`（TIMESTAMP）を例示しているが、本基盤は `start_date`／`end_date`（DATE）を使う。電力の約款・単価は「日」単位で切り替わり、時分秒の精度を持たないため。規約 6.1 の `_dt` サフィックスとも異なる（`_date` を使用）が、これは C-1 の範囲では違反ではなく、**P-1 の改名を行う場合に合わせて検討する事項**とした。

---

## 5. 残作業の推奨順序

1. **dry run による検証**（規約 11.1／10.5）：展開後の SQL を dev で dry run し、bytes processed のベースラインを取得。本回の改名・BOOL 化・監査列追加は広範囲に及ぶため、これを最優先とする。
2. **CI に未展開変数の検出を追加**（規約 3.2 必須）：`${GCP_PROJECT_ID}`、`${BQ_DATASET`、`TODO`、`CHANGE_ME` を検出したらデプロイ拒否。
3. **`pipeline_version` の採番方式の確定**（P-2 の未確定事項）：Git コミットSHA／リリースタグ／dbt リリース識別子のいずれかに統一し、データ辞書へ登録。
4. **オーケストレータからの引数連携**：Workflows／Composer が `p_run_id`・`p_pipeline_version` を渡す実装。
5. **データ契約の登録**（P-3。仕様書 17.3 の TODO）：Gold 公開資産ごと。

---

## 6. 本チェックの限界

- 静的な文字列・構文の検査であり、**BigQuery 上での構文検証（dry run）は行っていない**。特に F-2（BOOL 化）は 34列・全プロシージャに波及するため、デプロイ前に dev 環境での `dry run` と `dbt test` 相当の実行を必須とする。
- 規約 8（PII）、規約 16 以降（権限、CI/CD、DR/BCP、AI/ML 利用管理）は、SQL 単体では判定できないため対象外とした。PII 列は設計上 `pii_` 接頭辞で分離済みだが、Policy Tag の付与・IAM・Row Access Policy は基盤構築時に別途設定する。
- 規約 10.1／10.4 のパーティション・クラスタリングの**採否は実測に基づく**ことを求めている。本チェックは「設定の有無」のみを確認しており、効果の検証は行っていない。
