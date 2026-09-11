# BigQuery データ基盤開発運用ガイドライン

## v1.0 初版

| 項目 | 内容 |
|:---|:---|
| 文書種別 | データ基盤設計・実装・運用標準 |
| 対象 | GCP / BigQueryを中心とする企業データ基盤 |
| 対象データ | SAP、Dynamics 365、Salesforce、イベント、BI、AI/MLデータ |
| 適用範囲 | 命名、データモデル、品質、権限、PII、コスト、CI/CD、DR/BCP、AI/ML利用管理 |
| 版 | v1.0 |
| 改訂日 | 2026-09-10 |
| 文書オーナー | 組織で指定する |
| 承認者 | データ責任者、セキュリティ責任者、基盤責任者 |
| 状態 | 初版（承認後に正式適用） |

> 本書は、2026年9月時点の組織標準案である。実際の正式適用には、組織の承認記録、対象GCP環境、利用ツールのバージョン、法令、社内セキュリティ基準の確認を必要とする。本書は改訂可能な管理文書であり、将来の製品仕様や業務要件の変更を妨げない。

### 本書の適用限界

本書は、GCPおよびBigQueryを中心とするデータ基盤の技術・運用・ガバナンス標準である。本書は法律意見、適法性の保証、監査意見、認証を構成しない。対象データ、利用目的、本人、国・地域、業種、契約、委託先、AI用途を特定し、法務、個人情報保護責任者、セキュリティ責任者、AI責任者が適用可否を判断する。

本書単独では、個人情報保護、越境移転、著作権、営業秘密、AI規制、業界固有規制への対応は完結しない。データ分類規程、個人情報保護規程、AI利用規程、著作権・ライセンス基準、委託先管理規程、削除・保持台帳を併用する。

---

## 1. 本書の読み方

### 1.1 規則の強度

| 区分 | 定義 | 例外の扱い |
|:---|:---|:---|
| **必須** | 本番公開前に満たす統制要件 | データ責任者、セキュリティ責任者、基盤責任者の承認が必要 |
| **標準** | 正当な理由がない限り採用する設計方式 | 不採用理由と代替策を記録する |
| **推奨** | 効果、費用、運用負荷を評価して採用する方式 | プロジェクト判断とする |
| **例** | 理解のための記述やコード例 | 本番へ無検証で適用しない |

本書の保持期間、パーティション列、クラスタリング列、BI粒度、閾値は、全資産へ一律適用する値ではない。データ量、増加率、主要クエリ、SLA、法令、保持要件に基づき決定する。

### 1.2 用語

| 用語 | 定義 |
|:---|:---|
| データオーナー | データの業務的意味、利用目的、品質基準、アクセス承認を担う責任者 |
| データスチュワード | 定義、メタデータ、品質、分類、利用ルールを管理する担当者 |
| データプロダクト | 利用者、粒度、SLA、品質、所有者を持つ公開データ資産 |
| 破壊的変更 | 既存のクエリ、BI、ML、外部連携、権限、データ意味を変更・停止させる変更 |
| PII | 個人を識別または識別可能にする情報。分類は社内規程に従う |
| 業務PIT | SCD Type 2等の有効期間に基づく指定時点照会 |
| BigQuery Time Travel | BigQueryのシステム時刻に基づく過去データ復元 |
| 冪等性 | 同じ入力と処理版を再実行しても業務データが重複・変質しない性質 |

---

## 2. 全レイヤー共通の基本原則

1. BigQueryのデータセット、テーブル、ビュー、カラム、モデル名はASCII小文字のsnake_caseを標準とする。
2. BigQueryオブジェクト名に日本語、全角文字、空白、ハイフン、キャメルケースを使用しない。
3. 略語は組織用語集へ登録されたものだけを使用する。
4. データ資産の説明文には、業務上の意味、1行の粒度、単位、時刻基準、更新頻度、所有者を記載する。
5. スキーマ、意味、権限、保持期間、粒度の変更は変更管理の対象とする。
6. `TIMESTAMP`は絶対時刻として扱い、保存時はUTCを標準とする。業務日付は業務タイムゾーンを明記した`DATE`とする。
7. 確定金額は通貨、精度、丸め規則を定義した上で`NUMERIC`または`BIGNUMERIC`を使用する。近似値が適切な予測値・統計値には`FLOAT64`を使用できる。
8. 下流利用者には、Silverの実装テーブルではなく、契約化されたGoldまたはServing資産を原則公開する。
9. 大規模テーブルは、実際のアクセスパターンに基づいてパーティション、クラスタリング、事前集計、マテリアライズドビュー等を選択する。
10. 品質不合格データを公開しない仕組みを構築し、品質ルールごとに重大度、公開対象、フォールバック、再処理方法を定義する。
11. 秘密情報、暗号鍵、アクセストークンをSQL、Git、ログ、データ辞書の説明文に記載しない。
12. 原データの保存、変換、公開、監査を分離し、誰が何をいつ変更したか追跡可能にする。

---

## 3. GCPプロジェクト、環境、リージョン

### 3.1 環境分離

開発、検証、本番は、原則としてGCPプロジェクトを分離する。

```text
prj-data-dev
prj-data-stg
prj-data-prod
```

アプリケーションコード、SQL、ビュー定義に本番プロジェクトIDを直接埋め込んではならない。

### 3.2 環境参照

| 実行環境 | 方式 |
|:---|:---|
| dbt | `ref()`、`source()`、環境別target |
| Dataform | `ref()`、環境変数、release configuration |
| Terraform | provider、variable、環境別ディレクトリまたはworkspace |
| 汎用SQL | CI/CDまたはテンプレート展開で環境を注入 |
| BI | 環境別接続設定。SQL本文に環境名を埋め込まない |

本書のSQL例にある`${GCP_PROJECT_ID}`はテンプレート変数である。実行前に実際のプロジェクトIDへ展開し、未展開のまま実行してはならない。

CIでは次の文字列を検出した場合にデプロイを拒否する。

```text
${GCP_PROJECT_ID}
${BQ_DATASET}
TODO
CHANGE_ME
```

### 3.3 リージョン

BigQueryデータセット、ジョブ、外部接続、BI接続のリージョンを整合させる。Cloud KMSを使用する場合は、鍵のロケーションとBigQueryジョブの実行ロケーションが利用方式の要件を満たすことを確認する。リージョンの固定値をコードへ記載する場合は、対象データセットと一致することをCIまたはデプロイ前検査で確認する。

---

## 4. データレイヤーとデータセット

| レイヤー | 目的 | 公開方針 |
|:---|:---|:---|
| Bronze | 原データ受領、再処理、監査、ソース仕様保持 | 基盤運用者に限定 |
| Silver | 型変換、標準化、名寄せ、重複除去、履歴管理 | エンドユーザーへ直接公開しない |
| Gold | 業務定義済みのBI、分析、AI公開契約 | 契約と権限を満たす利用者へ公開 |
| Serving | BI、API、業務処理向けの性能・コスト最適化 | 利用目的とSLAを定義して公開 |
| Quarantine | 品質不合格、変換不能、規格外データの隔離 | 一般公開しない |
| Audit | 実行履歴、品質判定、件数、差分、再処理履歴 | 運用・監査関係者へ公開 |
| Sandbox | 期限付きの探索的分析 | 所有者、期限、削除日を必須化 |

### 4.1 データセット命名

基本形式は次のとおりとする。

```text
[layer]_[domain_or_source]
```

例：

```text
bronze_sap
bronze_salesforce
silver_customer
silver_sales
gold_sales_mart
serving_finance
quarantine_salesforce
audit_pipeline
sandbox_team_a
```

データセット名だけでアクセス権を付与してはならない。権限はIAM、Policy Tag、Row Access Policy、認可ビュー、専用テーブル等で明示的に設定する。

### 4.2 保持期間

保持期間は法令、契約、監査、再処理、削除要求、復旧要件、費用に基づきデータプロダクトごとに定義する。Bronze、Silver、Goldへ一律の保持日数を無検証で適用してはならない。

---


### 4.3 Time Travelと物理ストレージ費用

BigQuery Time Travelの保持期間はデータセットまたはプロジェクト単位で管理する。保持期間はデフォルト7日、設定可能な範囲は2日以上7日以下である。[8]

頻繁にMERGE、UPDATE、DELETE、CREATE OR REPLACEを行う履歴テーブルでは、Time TravelとFail-safeによる保持データが増える可能性がある。短縮を検討する場合は、業務上必要な復旧期間とRPOを満たすこと、物理ストレージ課金モデルであること、Fail-safeの追加保持期間は設定変更できないこと、必要なスナップショットやバックアップを別途用意すること、データセット単位の設定変更が他テーブルへ与える影響を確認することを必須とする。論理ストレージ課金では、Time Travel短縮による同じ費用効果が得られない場合がある。

SCD Type 2の業務履歴とTime Travelは代替関係ではない。業務PITの保持要件はSCD履歴またはスナップショットで満たし、Time Travelは障害復旧要件として別に評価する。

## 5. テーブル・ビュー命名

### 5.1 基本形式

```text
[prefix]_[business_entity_or_content]_[suffix]
```

### 5.2 プレフィックス

| プレフィックス | 用途 | 例 |
|:---|:---|:---|
| `dim_` | ディメンション、マスタ | `dim_customer` |
| `fact_` | 取引、イベント、実績 | `fact_opportunity` |
| `agg_` | 明示的な事前集計 | `agg_sales_by_customer` |
| `v_` | 利用者向け論理ビュー | `v_customer_pipeline` |
| `feat_` | ML特徴量 | `feat_customer_churn` |
| `stg_` | 一時変換 | `stg_opportunity_cleaned` |
| `snap_` | スナップショット | `snap_customer_daily` |

`fact_`だからパーティション必須、`dim_`だからクラスタリング必須とはしない。データ量、アクセスパターン、保持要件、実測コストに基づき決定する。

### 5.3 サフィックス

| サフィックス | 用途 |
|:---|:---|
| `_historical`、`_history` |  |
| `_snapshot` | 特定時点の状態 |
| `_latest` | 最新状態。定義を説明文に記載 |
| `_inference` | ML推論結果 |
| `_v2` | 互換性を維持できない公開契約の新バージョン |

### 5.4 日付シャード

新規のSilver、Gold、Serving資産では、日付をテーブル名に埋め込む方式を標準としない。

```text
推奨: fact_sales を DATE(sale_at) でパーティション
非推奨: fact_sales_20260910
```

ソース受領、外部製品制約、既存移行では例外を許可する。例外には所有者、移行期限、廃止計画、代替クエリを記録する。

---

## 6. カラム命名、型、意味

### 6.1 標準サフィックス

| サフィックス | 意味 | 標準型 | 例 |
|:---|:---|:---|:---|
| `_id` | 識別子 | `STRING`または要件に適した型 | `customer_id` |
| `_at` | 絶対日時 | `TIMESTAMP` | `created_at` |
| `_dt` | 業務日付 | `DATE` | `close_dt` |
| `_dttm` | タイムゾーンを持たない日時 | `DATETIME` | `store_open_dttm` |
| `_amt` | 金額 | `NUMERIC`または`BIGNUMERIC` | `contract_amt` |
| `_qty` | 数量 | `INT64`または`NUMERIC` | `order_qty` |
| `_cnt` | 件数 | `INT64` | `order_cnt` |
| `_is`、`_has` | 真偽値 | `BOOL` | `is_closed` |
| `_cd`、`_code` | コード | `STRING` | `country_cd` |
| `_json` | 半構造化データ | `JSON` | `payload_json` |
| `_score` | スコア、確率 | `FLOAT64`または`NUMERIC` | `churn_score` |
| `_embedding` | ベクトル | `ARRAY<FLOAT64>`等 | `customer_embedding` |

### 6.2 金額

金額列には、通貨コード、税込・税抜、符号、小数桁、丸め規則、為替換算、返品・取消・値引きの扱いをデータ辞書へ記載する。

確定した財務・請求・売上金額に`FLOAT64`を使用してはならない。予測値や統計値で近似値が適切な場合は`FLOAT64`を使用できる。

### 6.3 NULL

NULL、空文字、未知、未設定、該当なし、論理削除済みを混同してはならない。各列の説明文にNULLの意味と入力不能時の処理を記載する。

---

## 7. STRUCT、ARRAY、JSON

1. Bronzeでは、ソース原文のネスト構造を監査・再処理目的で保持してよい。
2. Silver以降では、頻繁に検索、JOIN、集計するJSONキーを物理カラムへ切り出す。
3. ネストは原則2階層以内とする。超える場合は利用目的、アクセス方法、性能テストを記録する。
4. ARRAYを`UNNEST`する場合は、行数増加と結果粒度を説明文へ記載する。
5. 金額と件数を集計する場合、親行と子行の重複計上をテストする。
6. BI向けGold資産では、ARRAYと未加工JSONを原則として直接公開しない。
7. APIやデータサイエンス向けのネスト公開は、利用者、粒度、クエリ例を契約へ記載する。

---

## 8. PII・機密情報

### 8.1 基本方針

カラム名の`_pii_high`や`_pii_med`は補助的な分類であり、アクセス制御ではない。強制制御はPolicy Tag、IAM、Row Access Policy、認可ビュー、専用テーブル等で行う。BigQueryでは列レベルアクセス制御と動的データマスキングを組み合わせられる。[1]

### 8.2 保護方式

| 目的 | 標準方式 |
|:---|:---|
| 表示だけ隠す | Policy Tag、動的データマスキング、認可ビュー |
| 同一人物を照合する | 管理鍵付きHMACまたは決定論的暗号化 |
| 原値へ戻す | AEAD暗号化またはトークン化 |
| 外部連携 | 契約済みトークン化または疑似識別子 |
| 集計公開 | 集計、少数セル抑制、必要に応じた匿名化 |

単純なSHA-256をPIIの安全なマスキングまたは匿名化として扱ってはならない。氏名、メール、電話番号は候補値が限定され、辞書攻撃を受けやすい。

### 8.3 原PIIの分離

原PIIは`restricted_pii`等の専用データセットへ分離する。一般BI利用者やアナリストへ原PIIを直接公開してはならない。復号処理は専用サービスアカウントまたは限定された処理経路へ閉じ込める。

### 8.4 疑似識別子の生成

Goldの利用者クエリで原PIIを読み、暗号化する設計を標準としてはならない。疑似識別子は、制限されたETLまたは専用サービスで事前生成し、Goldは疑似識別子だけを参照する。

```text
restricted_pii
  └─ PII原値
       └─ 制限されたETL / 専用サービス
            └─ HMACまたは決定論的暗号化
                 └─ customer_pseudonym
                      └─ Goldビュー
```

疑似識別子は、用途、鍵バージョン、正規化方式バージョンを管理する。同じ入力が同じ出力になる方式は頻度情報と同一性を漏らすため、公開範囲を限定する。

### 8.5 暗号化キー

暗号鍵または平文keysetをSQL、Git、一般テーブル、ログ、BIへ保存してはならない。BigQuery AEAD関数を使用する場合は、Cloud KMSで保護したkeyset、実行主体、鍵ローテーション、復号権限、監査ログを別途設計する。[2]

Goldビューは鍵テーブルを直接参照せず、事前生成済みの疑似識別子テーブルを参照する。

---


### 8.6 マスキング列のJOIN

動的データマスキングで置換された列を、下流クエリのJOINキーとして使用してはならない。NULL、既定値、一般化値、方式の異なるハッシュ値は、同一人物の照合キーとして保証されず、誤結合、未結合、同一値への集中によるファンアウトを引き起こす可能性がある。

JOINが必要な場合は、用途、鍵バージョン、正規化方式を管理した事前生成済みの`customer_pseudonym`等を使用する。決定論的マスキングや決定論的暗号化をJOINに使用する場合も、同じ鍵、コンテキスト、正規化方式を利用することを契約へ記録し、承認済みの組み合わせだけを許可する。

## 9. スキーマ進化

### 9.1 変更分類

| 変更 | 分類 | 対応 |
|:---|:---|:---|
| NULL許容列の追加 | 後方互換 | 依存確認後に追加 |
| 説明文の更新 | 通常変更 | 意味が変わらないことを確認 |
| 列名変更 | 破壊的 | 互換列、互換ビュー、移行期間 |
| 型変更 | 原則破壊的 | 変換、併存、移行テスト |
| 列削除 | 破壊的 | 利用調査、通知、期限、削除 |
| 粒度変更 | 破壊的 | 新資産または新バージョン |
| PII分類引き上げ | 権限変更 | 権限、BI、エクスポートを再確認 |

### 9.2 廃止手順

1. カタログ、クエリ履歴、dbt、Dataform、BI、MLの依存関係を調査する。
2. 非推奨、廃止予定日、移行先を登録する。
3. 互換ビューまたは代替列を提供する。
4. 利用者へ通知し、移行状況を確認する。
5. 期限経過後に削除し、変更記録を保存する。

列名を`deprecated_`へ変更すること自体が破壊的変更になるため、名前変更だけで廃止管理を完了したとみなしてはならない。

### 9.3 変換不能値

変換不能値を黙ってNULLへ変換してはならない。原値または監査可能な表現を保持し、Quarantineへ隔離し、原因、件数、再処理方法を記録する。

---

## 10. パーティション、クラスタリング、コスト

### 10.1 パーティション選定

次を評価してパーティションの採否を決める。

- テーブル規模と増加率
- 主要クエリの時間範囲
- パーティションごとのデータ量
- 更新頻度とバックフィル方法
- 保持期限と削除要件
- BIツールがフィルターを生成できるか

`fact_`という名前だけを理由に、特定のパーティション列を割り当ててはならない。

### 10.2 `require_partition_filter`

大規模な時間系テーブルでは、`require_partition_filter = TRUE`を標準とする。直接SQL、認可ビュー、BI、バックフィル、品質テスト、復旧処理で利用できることを検証する。

小規模、全期間走査が主目的、管理専用、適切なパーティション列がない場合は例外を認める。例外には理由、代替コスト制御、承認者を記録する。

BigQueryは、パーティション列に適切な条件がある場合、該当パーティションを削減できる。これはdry runと実行計画で検証する。[3]

### 10.3 フィルターの書き方

パーティション列への条件は、対象パーティションを削減できる形で記述する。関数使用の可否をすべてのクエリに対する絶対禁止事項として扱わず、パーティション方式、クエリ形状、ビュー展開、BI生成SQLを対象に検証する。

パーティションプルーニングとクラスタリングによるブロックプルーニングは別の最適化である。両者を混同してはならない。

### 10.4 クラスタリング

クラスタリング列は、頻繁なJOIN、等価フィルター、集計に使う列から選ぶ。採否、列順、列数、効果をbytes processedとレイテンシで検証する。BigQueryの利用上限や対象エディションを、実行環境で確認する。

### 10.5 コスト統制

- CIで代表クエリをdry runする。
- bytes processedと実行時間をベースラインと比較する。
- ジョブラベルに環境、チーム、データプロダクトを付与する。
- BIの期間フィルターと粒度をデータ契約に含める。
- クエリ、ストレージ、予約・スロット費用を分けて監視する。
- 費用急増時のアラート、所有者、停止・制限手順を定義する。

---


### 10.2.1 増分更新とバックフィル

`require_partition_filter = TRUE`を設定したテーブルでは、dbt、Dataform、Composer、Workflows等が発行する全クエリに対象パーティション条件が入ることを検証する。増分更新、特定期間のバックフィル、フルリフレッシュ、失敗後の再実行を別々にテストする。

dbt BigQueryアダプタを使用する場合、`_dbt_max_partition`等の機能や変数を採用するかどうかを、使用中のdbtバージョンの公式仕様で確認する。名称や挙動をバージョン非依存の標準として扱ってはならない。CIでは、生成SQLに対象パーティション条件があること、対象外の全期間走査がないこと、バックフィル範囲が意図した日付に限定されること、`require_partition_filter`による予期しないエラーがないこと、フルリフレッシュが承認済み手順としてのみ実行されることを確認する。


#### 10.4.1 複数クラスタリング列の順序

複数列を指定する場合、左から右の順序がストレージブロックの並びとクエリ最適化に影響する。順序は、単なるカーディナリティの高さだけで決めず、次の優先順位で決定する。

1. 単独または複合条件で頻繁にフィルターされる列。
2. 主要な期間、テナント、業務単位など、クエリの選択性を高める列。
3. JOIN、GROUP BY、ORDER BYで繰り返し使用される列。
4. データ分布、NULL率、更新方式、実行計画に基づく実測効果。

最初の列だけが使われるクエリと、複数列を先頭から順に使うクエリを分けてベンチマークする。高カーディナリティ列を常に最初に置くという一律ルールは採用しない。クラスタリング列は最大4列までとし、実際のBigQuery仕様と利用環境を確認する。[6]


#### 10.5.1 Slot、Edition、Reservation

bytes processedだけでは、予約型BigQueryの計算資源消費と待機を十分に評価できない。ステージング環境では、代表クエリと代表ワークロードについて、`total_slot_ms`またはJob統計、実行時間、キュー待機時間、シャッフル量、失敗率、Reservation、割り当てプロジェクト、リージョン、Edition、BI同時実行時のスロット使用量を記録する。

本番では、ELT、BI、データサイエンス、管理処理を必要に応じて別Reservationへ分離し、プロジェクトまたはフォルダの割り当てを管理する。[7]

同時実行数やプロジェクト単位のスロット上限を設定する場合は、利用可能な機能の提供段階、リージョン、Edition、組織ポリシーを確認する。Preview機能を必須統制にしてはならない。

## 11. DDL実装標準

### 11.1 実行条件

以下はGoogleSQLのテンプレートである。`${GCP_PROJECT_ID}`は実行前にCI/CDで置換する。置換後のSQLをdry runし、テスト用データセットへ適用してから本番へデプロイする。

本番での無計画な`CREATE OR REPLACE TABLE`を禁止する。列削除、型変更、Policy Tag削除、権限変更を伴う場合は、変更レビューと移行計画を必須とする。

### 11.2 ディメンション

```sql
CREATE OR REPLACE TABLE `${GCP_PROJECT_ID}.silver_customer.dim_customer`
(
  customer_id STRING OPTIONS(description = '統合顧客一意ID'),
  customer_name STRING OPTIONS(description = '顧客正式名称。PIIポリシータグの保護対象'),
  industry_cd STRING OPTIONS(description = '業種コード'),
  country_cd STRING OPTIONS(description = '国コード'),
  source_system_cd STRING OPTIONS(description = '主たるデータソース'),
  source_updated_at TIMESTAMP OPTIONS(description = 'ソース側最終更新日時UTC'),
  is_source_deleted BOOL OPTIONS(description = 'ソース側論理削除フラグ'),
  ingestion_run_id STRING OPTIONS(description = 'パイプライン実行ID'),
  loaded_at TIMESTAMP OPTIONS(description = 'BigQueryへのロード日時UTC'),
  pipeline_version STRING OPTIONS(description = '処理コードまたはモデルのバージョン')
)
CLUSTER BY customer_id
OPTIONS (
  description = '統合顧客ディメンション。利用者向け公開はGoldまたはServing経由とする。'
);
```

`CLUSTER BY customer_id`は、主要クエリとデータ量で効果を確認した上で採用する。効果がない場合は削除してよい。

### 11.3 日付パーティション付きファクト

```sql
CREATE OR REPLACE TABLE `${GCP_PROJECT_ID}.silver_sales.fact_opportunity`
(
  opportunity_id STRING OPTIONS(description = '商談一意ID'),
  customer_id STRING OPTIONS(description = '統合顧客ID'),
  opportunity_name STRING OPTIONS(description = '商談名'),
  stage_cd STRING OPTIONS(description = '商談フェーズコード'),
  opportunity_amt NUMERIC OPTIONS(description = '商談金額'),
  currency_cd STRING OPTIONS(description = '金額の通貨コード'),
  close_dt DATE OPTIONS(description = '商談完了予定日または完了日。パーティション列'),
  is_won BOOL OPTIONS(description = '受注フラグ'),
  is_closed BOOL OPTIONS(description = 'クローズフラグ'),
  source_system_cd STRING OPTIONS(description = 'データソース'),
  source_updated_at TIMESTAMP OPTIONS(description = 'ソース側最終更新日時UTC'),
  is_source_deleted BOOL OPTIONS(description = 'ソース側論理削除フラグ'),
  ingestion_run_id STRING OPTIONS(description = 'パイプライン実行ID'),
  loaded_at TIMESTAMP OPTIONS(description = 'BigQueryへのロード日時UTC'),
  pipeline_version STRING OPTIONS(description = '処理コードまたはモデルのバージョン')
)
PARTITION BY close_dt
CLUSTER BY customer_id
OPTIONS (
  require_partition_filter = TRUE,
  description = '商談ファクト。close_dtによるパーティションフィルターを要求する。'
);
```

### 11.4 SCD Type 2履歴

```sql
CREATE OR REPLACE TABLE `${GCP_PROJECT_ID}.silver_sales.fact_contract_history`
(
  contract_history_id STRING OPTIONS(description = '履歴レコードのサロゲートキー'),
  contract_id STRING OPTIONS(description = '契約番号。ナチュラルキー'),
  customer_id STRING OPTIONS(description = '統合顧客ID'),
  contract_start_dt DATE OPTIONS(description = '契約開始日'),
  contract_end_dt DATE OPTIONS(description = '契約終了日'),
  contract_amt NUMERIC OPTIONS(description = '契約金額'),
  currency_cd STRING OPTIONS(description = '金額の通貨コード'),
  plan_cd STRING OPTIONS(description = '契約プランコード'),
  valid_from_at TIMESTAMP OPTIONS(description = '有効開始日時UTC'),
  valid_to_at TIMESTAMP OPTIONS(description = '有効終了日時UTC'),
  is_current BOOL OPTIONS(description = '現在有効なレコードであることを示す'),
  source_system_cd STRING OPTIONS(description = 'データソース'),
  source_updated_at TIMESTAMP OPTIONS(description = 'ソース側最終更新日時UTC'),
  is_source_deleted BOOL OPTIONS(description = 'ソース側論理削除フラグ'),
  ingestion_run_id STRING OPTIONS(description = 'パイプライン実行ID'),
  loaded_at TIMESTAMP OPTIONS(description = 'BigQueryへのロード日時UTC'),
  pipeline_version STRING OPTIONS(description = '処理コードまたはモデルのバージョン')
)
PARTITION BY DATE(valid_from_at)
CLUSTER BY customer_id, contract_id
OPTIONS (
  require_partition_filter = TRUE,
  description = 'SCD Type 2契約履歴。業務PIT照会の期間条件を品質テストで検証する。'
);
```

`valid_to_at`の終端を`9999-12-31`とするかNULLとするかは、データプロダクト単位で統一する。SCD Type 2の業務PITとBigQuery Time Travelを混同してはならない。

---

## 12. 業務PIT照会

### 12.1 推奨クエリ

```sql
DECLARE target_timestamp TIMESTAMP DEFAULT TIMESTAMP('2025-12-31 23:59:59+00');

SELECT
  customer_id,
  COUNT(DISTINCT contract_id) AS historical_active_contract_cnt,
  SUM(contract_amt) AS historical_total_contract_amt
FROM `${GCP_PROJECT_ID}.silver_sales.fact_contract_history`
WHERE valid_from_at <= target_timestamp
  AND valid_to_at > target_timestamp
GROUP BY customer_id;
```

このクエリはSCD Type 2の業務有効期間を使う。`is_current`だけで過去状態を復元してはならない。

### 12.2 境界条件

- `valid_from_at < valid_to_at`
- 同一`contract_id`の有効期間が重複しない
- 同一`contract_id`で`is_current = TRUE`が最大1件
- 境界時刻で`valid_from_at`を含み、`valid_to_at`を含まない規則を統一する
- 未来開始、削除済み、訂正、NULL終端の扱いを定義する
- パーティション削減効果をdry runと実行計画で確認する

---

## 13. GoldとServingのデータ契約

各公開資産へ次を登録する。

- 1行の粒度
- 対象期間
- 更新頻度と鮮度SLA
- 金額の通貨、税、返品、取消の扱い
- NULLと削除済みの扱い
- 利用可能な結合キー
- 禁止される結合パターン
- コスト上の推奨フィルター
- オーナー、問い合わせ先、

Goldは利用者向け契約面であり、実体を論理ビューに限定しない。性能、費用、鮮度、更新方式に応じてテーブル、ビュー、マテリアライズドビュー、集計テーブルを選択する。

### 13.1 期間限定ビュー

```sql
CREATE OR REPLACE VIEW `${GCP_PROJECT_ID}.gold_sales_mart.v_customer_pipeline_last_365_days`
OPTIONS (
  description = '顧客別未クローズ商談。Asia/Tokyoの当日から過去365日。1行=1顧客。'
)
AS
SELECT
  c.customer_id,
  p.customer_pseudonym,
  c.industry_cd,
  COUNT(o.opportunity_id) AS open_opportunity_cnt,
  COALESCE(SUM(o.opportunity_amt), NUMERIC '0') AS total_pipeline_amt,
  COALESCE(
    SUM(IF(o.stage_cd = 'proposal', o.opportunity_amt, NUMERIC '0')),
    NUMERIC '0'
  ) AS proposal_stage_amt,
  COALESCE(
    SUM(IF(o.stage_cd = 'negotiation', o.opportunity_amt, NUMERIC '0')),
    NUMERIC '0'
  ) AS negotiation_stage_amt
FROM `${GCP_PROJECT_ID}.silver_customer.dim_customer` AS c
LEFT JOIN `${GCP_PROJECT_ID}.silver_customer.customer_pseudonym` AS p
  ON c.customer_id = p.customer_id
LEFT JOIN `${GCP_PROJECT_ID}.silver_sales.fact_opportunity` AS o
  ON c.customer_id = o.customer_id
  AND o.is_closed = FALSE
  AND o.close_dt >= DATE_SUB(CURRENT_DATE('Asia/Tokyo'), INTERVAL 365 DAY)
GROUP BY
  c.customer_id,
  p.customer_pseudonym,
  c.industry_cd;
```

このビューは原PIIと暗号鍵を参照しない。`customer_pseudonym`は、制限されたETLまたは専用サービスで事前生成されていることを前提とする。

`CURRENT_DATE('Asia/Tokyo')`を使用するため、実行日によって結果が変化する。監査報告や再現性が必要な用途には、対象日を固定した物理マートまたはスナップショットを使用する。

`ON`句に期間条件を置くことだけで、パーティションプルーニングやBIの安全な実行が保証されるわけではない。実際のBI接続で検証する。

---

## 14. データ品質

### 14.1 重大度

| 重大度 | 例 | 失敗時動作 |
|:---|:---|:---|
| Critical | 主キー重複、金額二重計上、PII漏えい | 公開停止、アラート、承認必須 |
| High | 更新遅延、件数急減、SCD期間重複 | 前回正常版を維持し、再処理 |
| Medium | NULL率上昇、未知コード増加 | 警告、公開継続を担当者判断 |
| Low | 軽微な表記揺れ | 隔離または次回改善 |

### 14.2 dbtテスト例

以下はdbt Coreと`dbt_utils`を使用する場合の例である。採用するdbtとパッケージのバージョンを固定し、CIで`dbt parse`、`dbt compile`、`dbt test`を実行する。

```yaml
version: 2

models:
  - name: fact_opportunity
    description: "全社商談ファクトテーブル。1行=1商談。"
    columns:
      - name: opportunity_id
        description: "商談一意ID"
        tests:
          - unique
          - not_null

      - name: customer_id
        description: "統合顧客ID"
        tests:
          - not_null

      - name: opportunity_amt
        description: "商談金額"
        tests:
          - not_null
          - dbt_utils.expression_is_true:
              expression: "opportunity_amt >= 0"

      - name: stage_cd
        description: "商談フェーズコード"
        tests:
          - accepted_values:
              values:
                - lead
                - qualification
                - proposal
                - negotiation
                - won
                - lost
```

### 14.3 BigQuery SQLテスト

各クエリは、異常がない場合に0行を返すことを期待する。

```sql
-- 主キー重複
SELECT
  opportunity_id,
  COUNT(*) AS row_count
FROM `${GCP_PROJECT_ID}.silver_sales.fact_opportunity`
GROUP BY opportunity_id
HAVING COUNT(*) > 1;
```

```sql
-- SCD Type 2の期間逆転
SELECT
  contract_history_id,
  valid_from_at,
  valid_to_at
FROM `${GCP_PROJECT_ID}.silver_sales.fact_contract_history`
WHERE valid_from_at >= valid_to_at;
```

```sql
-- SCD Type 2の現在レコード重複
SELECT
  contract_id,
  COUNTIF(is_current) AS current_count
FROM `${GCP_PROJECT_ID}.silver_sales.fact_contract_history`
GROUP BY contract_id
HAVING COUNTIF(is_current) > 1;
```

```sql
-- 商談金額の負数
SELECT
  opportunity_id,
  opportunity_amt
FROM `${GCP_PROJECT_ID}.silver_sales.fact_opportunity`
WHERE opportunity_amt < 0;
```

Great Expectations等のPython実装は、本文へ未検証のコードを埋め込まず、採用バージョン、Data Context、Datasource、Checkpointを固定したリポジトリで管理する。「完全準拠」「ランタイムエラーを完全排除」といった断定は、実行環境のCI結果がある場合だけ使用する。

---

## 15. 冪等性と再実行

| データ特性 | 推奨方式 |
|:---|:---|
| 最新状態ディメンション | ビジネスキーを使うMERGE |
| 再生成可能な日付ファクト | 対象パーティションの置換または再生成 |
| 追記専用イベント | 一意なイベントIDによる重複排除付きappend |
| 監査ログ | append-only、保持、重複、改ざん検知を定義 |
| 履歴 | SCD Type 2と期間整合性検証 |
| 集計 | 入力範囲と集計キーを固定して再生成またはMERGE |

`INSERT INTO`を一律禁止しない。append-only資産には、イベントID、再送、遅延到着、削除イベント、保持期間を定義する。

同じ入力スナップショットと処理バージョンを再実行した場合、実行時刻等の管理列を除き、出力行集合と業務値が一致することを検証する。

---

## 16. ファンアウトとBI

複数ファクトを無計画に同時JOINしてはならない。

```text
非推奨:
  dim_customer
    ├─ fact_opportunity
    └─ fact_contract

推奨:
  dim_customer
    ├─ agg_opportunity_by_customer
    └─ agg_contract_by_customer
```

子テーブルを同じ粒度へ事前集約してからJOINする。BI側の`COUNT(DISTINCT)`だけでファンアウトを隠蔽してはならない。

BIツールは、原則としてGoldまたはServingだけを参照する。Silver、未集約ARRAY、未加工JSONを直接Exploreやデータソースへ公開しない。

---

## 17. AI、ML、ベクトル

### 17.1 AI利用の最低管理要件

AIまたはMLに利用するデータは、ユースケース、目的、責任者、入力項目、学習・微調整・推論・RAGの区分、出力の利用先、影響を受ける人、モデル提供者、保存場所、ログ保持、削除方法を台帳化する。

個人情報、営業秘密、著作物、機密情報を外部AIサービスへ入力する場合は、利用目的、契約、学習利用、保存、再委託、削除、国外移転、アクセス制御を事前確認する。[9] [10] [11]ベクトル、チャンク、埋込み、検索ログ、プロンプト、回答は、原文と同じまたは適切な高い分類で管理し、ベクトル化だけで匿名化済みと判断してはならない。

個人の雇用、信用、価格、保険、医療、教育その他の重要な権利利益へ影響する用途では、人間による確認、異議申立て、救済、バイアス評価、性能監視、モデル変更管理を別途定義する。[12] [13] [14] [15]

1. ML特徴量テーブルへ`feat_`プレフィックスを使用する。
2. 特徴量へ生成日時、対象時点、特徴量バージョンを付与する。
3. 学習時点より後の情報が混入するデータリーケージを検査する。
4. PIIは目的、必要性、モデルリスクを確認し、最小限だけ使用する。
5. ベクトルへモデル名、次元数、生成日時、入力データ識別子を記録する。
6. ベクトルをBI向けGoldへ直接公開しない。

---

## 18. IAM、監査、メタデータ

- 一般利用者へ`roles/bigquery.admin`を付与しない。
- 人間の利用者とパイプラインサービスアカウントを分離する。
- サービスアカウントは必要なデータセット、テーブル、ジョブ操作だけを許可する。
- PII列へPolicy Tag等を設定する。
- Row Access Policyを使う場合は、Lookupテーブル、BI、性能、互換性を検証する。[4]
- 原PII、疑似識別子、復号権限、エクスポート権限を分離する。
- PII参照、権限変更、エクスポート、コピー、削除を監査ログで監視する。

### 18.1 監査メタデータ

| 列 | 意味 |
|:---|:---|
| `source_system_cd` | 元システム |
| `source_record_id` | ソースレコードID |
| `source_updated_at` | ソース側更新日時 |
| `is_source_deleted` | ソース削除フラグ |
| `ingestion_run_id` | パイプライン実行ID |
| `ingestion_batch_id` | 取り込みバッチID |
| `loaded_at` | ロード日時UTC |
| `pipeline_version` | 処理コードまたはモデルの版 |
| `record_hash` | 変更検知用ハッシュ。PIIを直接含めない |

`bq_job_id`を保持する場合は補助的な追跡情報とする。複数ジョブで構成される処理の主キーには`ingestion_run_id`を使用する。

---

## 19. IaCと変更管理

Terraform等の承認済みIaCで、次の主要リソースを管理する。

- データセット
- テーブルとスキーマ
- ビューとルーティン
- パーティションとクラスタリング
- Policy Tagとデータポリシー
- IAM
- Row Access Policy
- 監視、アラート、ログ設定

本番の手動DDLは原則禁止する。緊急変更を行った場合は、事後にコードへ反映し、環境差分を解消する。

---

## 20. CI/CD

本番マージまたはデプロイ前に、次を自動実行する。

- SQL lintとフォーマット
- BigQuery dry runまたは構文検証
- dbt `parse`、`compile`、`test`
- Dataform compileとassertion
- PII分類と公開差分の検査
- プレースホルダー残存検査
- Terraform `fmt`、`validate`、`plan`
- 破壊的変更と依存関係の検査
- 代表クエリのbytes processed比較
- 冪等性テスト
- Critical品質失敗時にGold公開を止めるゲート

実行例を本文へ追加する場合は、対象製品のバージョン、必要権限、入力テーブル、検証方法を併記する。未検証コードを「プロダクションコード」や「完全準拠」と表現してはならない。

---

## 21. 非同期BigQueryジョブ

### 21.1 状態判定

BigQuery Job APIの状態は、次の3状態で判定する。`errorResult`は最終エラー、`errors[]`は実行中に発生したエラー一覧である。[5]

| 条件 | 処理 |
|:---|:---|
| `state != DONE` | 最大待機時間、最大試行回数、指数バックオフを適用して継続 |
| `state == DONE`かつ`errorResult`あり | 失敗。後続公開を停止 |
| `state == DONE`かつ`errorResult`なし | 成功。品質検証へ進む |

### 21.2 二重発行防止

再試行時は、実行ID、入力範囲、対象テーブル、コードバージョンを永続化する。同一実行IDが成功済みの場合は再発行しない。ジョブIDだけを冪等性キーとみなしてはならない。

Workflows等の具体的なYAMLは、採用製品のバージョンを固定した別のImplementation Guideで管理し、本書へ未検証のコードを埋め込まない。

---

## 22. DR、BCP、バックアップ

業務重要度ごとにRPO、RTO、復旧方法、責任者を定義する。バックアップの存在だけでなく、定期的な復元テストを必須とする。

復元テストでは、次を確認する。

- 指定時点まで復元できる
- IAM、Policy Tag、Row Access Policyが復元される
- BIと下流連携が再接続できる
- 重複なく再処理できる
- RPO/RTOを満たす
- 監査証跡を追跡できる

---

## 23. 例外管理

例外には次を記録する。

- 対象資産
- 適用する規則
- 例外理由
- リスク評価
- 代替統制
- 所有者
- 承認者
- 有効期限
- 解消計画

期限のない恒久例外を作成してはならない。期限到来時に、継続、解消、規則改訂のいずれかを判断する。

---

## 24. 本番公開チェックリスト

### 24.1 文書と設計

- [ ] 文書オーナー、承認者、改訂責任者が登録されている。
- [ ] データオーナー、スチュワード、運用担当者が定義されている。
- [ ] 1行の粒度、主キー、更新方式、保持期間が定義されている。
- [ ] PII、機密区分、アクセス経路、エクスポート可否が定義されている。
- [ ] 下流資産と破壊的変更の影響が確認されている。

### 24.2 実装

- [ ] 命名規則、説明文、型、単位が適合している。
- [ ] SQL、YAML、Terraformの構文検証が完了している。
- [ ] DDLをdry runし、テスト用データセットで実行している。
- [ ] dbtまたはDataformのcompileと品質テストが成功している。
- [ ] 同じ入力を再実行しても業務データが重複しない。
- [ ] 未解決プレースホルダーが存在しない。

### 24.3 セキュリティ

- [ ] 一般利用者が原PIIへアクセスできない。
- [ ] PII列へPolicy Tagまたは代替制御が設定されている。
- [ ] 疑似識別子が制限された処理で生成されている。
- [ ] 暗号鍵、Secret、トークンがコードとログへ露出していない。
- [ ] BI、エクスポート、共有、コピーの経路を確認している。
- [ ] 監査ログとアラートが設定されている。

### 24.4 コストと運用

- [ ] パーティションとクラスタリングの効果を実測している。
- [ ] `require_partition_filter`の直接SQL、ビュー、BI、バックフィルを検証している。
- [ ] 鮮度、件数、品質、費用、失敗を監視できる。
- [ ] 障害時の公開停止、前回正常版、再処理手順がある。
- [ ] RPO/RTOと復元テスト結果がある。
- [ ] 問い合わせ先、エスカレーション、が登録されている。

---

## 付録A：実行手順

### A.1 DDL

1. `${GCP_PROJECT_ID}`を対象環境のプロジェクトIDへ展開する。
2. 対象データセットのリージョンとジョブのロケーションを確認する。
3. BigQuery dry runで構文と参照先を確認する。
4. テスト用データセットへ適用する。
5. パーティション、クラスタリング、権限、Policy Tagを検証する。
6. CIの承認後に本番へデプロイする。

### A.2 プレースホルダー検査

```bash
if grep -R -n -E '\$\{GCP_PROJECT_ID\}|\$\{BQ_DATASET\}|TODO|CHANGE_ME' .; then
  echo 'Unresolved placeholder found' >&2
  exit 1
fi
```

この検査を本番デプロイ前のCIへ組み込む。SQL、鍵、PIIをCIログへ出力してはならない。

### A.3 コードサンプルの管理

本書のSQLは実装標準例である。実行用のSQL、dbt、Dataform、Terraform、Workflowsは、対象バージョンを固定したリポジトリへ保存し、CIで検証した成果物だけを本番へ適用する。本書へ新たなコード例を追加する場合も、構文、権限、リージョン、入力データ、期待結果をテストへ含める。

## 付録B：v1.0初版受入テスト

| 分類 | 合格条件 |
|:---|:---|
| 増分処理 | dbt、Dataform等の生成SQLが対象パーティションだけを走査する |
| バックフィル | 指定期間外の走査と書き込みが発生しない |
| 冪等性 | 同じ入力と処理版の再実行で重複・二重計上が発生しない |
| Slot | `total_slot_ms`、実行時間、キュー待機、シャッフル量を比較できる |
| Reservation | ELT、BI、MLの割り当て、リージョン、Editionを確認している |
| クラスタリング | 列順を実ワークロードで比較し、採用理由を説明できる |
| PII | Policy Tag、行制御、IAM、エクスポート経路を検証している |
| 疑似識別子 | 正規化、鍵バージョン、コンテキストが契約どおり一致している |
| マスキング | マスク済み表示列をJOINキーに使用していない |
| AI/ML | 入力データ、モデル、出力、権限、ログ、削除を追跡できる |
| Time Travel | RPO、課金モデル、保持期間、Fail-safe、バックアップを確認している |
| DR/BCP | RTO/RPOに基づきコード、データ、権限、鍵、依存を復旧できる |

## References

本文中の参照番号に対応する一次資料・公式資料を以下に示す。

- [1] [Introduction to column-level access control | BigQuery](https://cloud.google.com/bigquery/docs/column-level-security-intro)
- [2] [AEAD encryption functions | BigQuery](https://cloud.google.com/bigquery/docs/reference/standard-sql/aead_encryption_functions)
- [3] [Introduction to partitioned tables | BigQuery](https://docs.cloud.google.com/bigquery/docs/partitioned-tables)
- [4] [Introduction to row-level security | BigQuery](https://docs.cloud.google.com/bigquery/docs/row-level-security-intro)
- [5] [Job resource | BigQuery REST API](https://cloud.google.com/bigquery/docs/reference/rest/v2/Job)
- [6] [Introduction to clustered tables | BigQuery](https://cloud.google.com/bigquery/docs/clustered-tables)
- [7] [Understand reservations | BigQuery](https://cloud.google.com/bigquery/docs/reservations-workload-management)
- [8] [Data retention with time travel and fail-safe | BigQuery](https://cloud.google.com/bigquery/docs/time-travel)
- [9] [個人情報の保護に関する法律についてのガイドライン（通則編）](https://www.ppc.go.jp/personalinfo/legal/guidelines_tsusoku/)
- [10] [生成AIサービスの利用に関する注意喚起等について](https://www.ppc.go.jp/news/careful_information/230602_AI_utilize_alert/)
- [11] [AIと著作権について](https://www.bunka.go.jp/seisaku/chosakuken/aiandcopyright.html)
- [12] [AI事業者ガイドライン（第1.2版）](https://www.meti.go.jp/shingikai/mono_info_service/ai_shakai_jisso/20260331_report.html)
- [13] [Regulation (EU) 2016/679 (GDPR)](https://eur-lex.europa.eu/eli/reg/2016/679/oj/eng)
- [14] [Regulation (EU) 2024/1689 (EU AI Act)](https://eur-lex.europa.eu/eli/reg/2024/1689/oj/eng)
- [15] [AI Risk Management Framework](https://www.nist.gov/itl/ai-risk-management-framework)
---



