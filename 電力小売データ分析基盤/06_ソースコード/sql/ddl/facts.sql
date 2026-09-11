-- =============================================================================
-- 電力小売データ分析基盤
-- Silver 層 ファクト（fact_*）DDL
-- 根拠：基本設計書 第8章（テーブル定義）・詳細設計書 第2部 1. 需要・発電実績の3層物理分割原則、詳細設計書 第2部 3. 市場・計画・BG精算ファクト定義詳細
-- 注意：型・NOT NULL は設計書の記載に従う。
--       設計書に型の記載がない列は、命名規約から型を定めている。
--       デプロイ前に dev 環境で DDL レビュー（13.1／フェーズ1完了条件）を行うこと。
-- =============================================================================

-- FX-01 JEPXスポット価格
CREATE TABLE IF NOT EXISTS fact_jepx_spot_prices (
  jepx_price_id                      INT64 NOT NULL OPTIONS(description = '価格データID'),
  target_date                        DATE OPTIONS(description = '対象日／コマ：受渡日'),
  slot_number                        INT64 OPTIONS(description = '対象日／コマ：受渡日'),
  area_code                          STRING OPTIONS(description = 'エリアコード'),
  system_price                       NUMERIC NOT NULL OPTIONS(description = 'システムプライス：円/kWh'),
  area_price                         NUMERIC NOT NULL OPTIONS(description = 'エリアプライス：円/kWh'),
  sell_volume                        NUMERIC OPTIONS(description = '売り／買い入札量：kWh'),
  buy_volume                         NUMERIC OPTIONS(description = '売り／買い入札量：kWh'),
  contract_volume                    NUMERIC OPTIONS(description = '約定量：kWh'),
  tax_type                           STRING NOT NULL OPTIONS(description = '税区分：税抜 固定。逆算・丸めを行わない'),
  fetched_at                         TIMESTAMP OPTIONS(description = '取得日時'),
  ingestion_run_id                   STRING OPTIONS(description = 'パイプライン実行ID（命名・運用定義書 11.3）'),
  loaded_at                          TIMESTAMP OPTIONS(description = 'BigQueryへのロード日時UTC'),
  pipeline_version                   STRING OPTIONS(description = '処理コードまたはモデルのバージョン'),
  PRIMARY KEY (jepx_price_id) NOT ENFORCED
)
PARTITION BY target_date
CLUSTER BY area_code
OPTIONS (
  require_partition_filter = TRUE,
  description = 'fact_jepx_spot_prices'
);

-- FX-02 JEPX時間前価格
CREATE TABLE IF NOT EXISTS fact_jepx_intraday_prices (
  intraday_price_id                  INT64 NOT NULL OPTIONS(description = 'ID'),
  target_date                        DATE OPTIONS(description = '対象日／コマ／エリア'),
  slot_number                        INT64 OPTIONS(description = '対象日／コマ／エリア'),
  area_code                          STRING OPTIONS(description = '対象日／コマ／エリア'),
  vwap_price                         NUMERIC OPTIONS(description = '加重平均約定価格'),
  contract_volume                    NUMERIC OPTIONS(description = '約定量'),
  last_price                         NUMERIC OPTIONS(description = '最終約定価格'),
  ingestion_run_id                   STRING OPTIONS(description = 'パイプライン実行ID（命名・運用定義書 11.3）'),
  loaded_at                          TIMESTAMP OPTIONS(description = 'BigQueryへのロード日時UTC'),
  pipeline_version                   STRING OPTIONS(description = '処理コードまたはモデルのバージョン'),
  PRIMARY KEY (intraday_price_id) NOT ENFORCED
)
PARTITION BY target_date
CLUSTER BY area_code
OPTIONS (
  require_partition_filter = TRUE,
  description = 'fact_jepx_intraday_prices'
);

-- FX-03 インバランス料金
CREATE TABLE IF NOT EXISTS fact_imbalance_prices (
  imbalance_price_id                 INT64 NOT NULL OPTIONS(description = 'ID'),
  target_date                        DATE OPTIONS(description = '対象日／コマ／エリア'),
  slot_number                        INT64 OPTIONS(description = '対象日／コマ／エリア'),
  area_code                          STRING OPTIONS(description = '対象日／コマ／エリア'),
  imbalance_price                    NUMERIC NOT NULL OPTIONS(description = 'インバランス料金単価：円/kWh'),
  price_status                       STRING NOT NULL OPTIONS(description = '単価ステータス：暫定／確定／更正'),
  adjustment_term                    NUMERIC OPTIONS(description = '補正項：制度改定に備えた予備'),
  tax_type                           STRING NOT NULL OPTIONS(description = '税区分：受領時の区分をそのまま保持（Silver では丸め・換算しない）。税込の場合は Gold で ÷(1+税率)（未丸め）'),
  revision_count                     INT64 OPTIONS(description = '更正回数／最終更正日時：更正が届くたびに加算・更新'),
  revised_at                         TIMESTAMP OPTIONS(description = '更正回数／最終更正日時：更正が届くたびに加算・更新'),
  ingestion_run_id                   STRING OPTIONS(description = 'パイプライン実行ID（命名・運用定義書 11.3）'),
  loaded_at                          TIMESTAMP OPTIONS(description = 'BigQueryへのロード日時UTC'),
  pipeline_version                   STRING OPTIONS(description = '処理コードまたはモデルのバージョン'),
  PRIMARY KEY (imbalance_price_id) NOT ENFORCED
)
PARTITION BY target_date
CLUSTER BY area_code
OPTIONS (
  require_partition_filter = TRUE,
  description = 'fact_imbalance_prices'
);

-- FX-04 電力先物価格
CREATE TABLE IF NOT EXISTS fact_futures_prices (
  futures_id                         INT64 NOT NULL OPTIONS(description = 'ID'),
  trade_date                         DATE OPTIONS(description = '取引日'),
  exchange                           STRING OPTIONS(description = '取引所'),
  contract_month                     STRING OPTIONS(description = '限月'),
  product_type                       STRING OPTIONS(description = '商品種別'),
  area_code                          STRING OPTIONS(description = 'エリア'),
  settlement_price                   NUMERIC OPTIONS(description = '清算値'),
  open_interest                      NUMERIC OPTIONS(description = '建玉／出来高'),
  volume                             NUMERIC OPTIONS(description = '建玉／出来高'),
  ingestion_run_id                   STRING OPTIONS(description = 'パイプライン実行ID（命名・運用定義書 11.3）'),
  loaded_at                          TIMESTAMP OPTIONS(description = 'BigQueryへのロード日時UTC'),
  pipeline_version                   STRING OPTIONS(description = '処理コードまたはモデルのバージョン'),
  PRIMARY KEY (futures_id) NOT ENFORCED
)
PARTITION BY trade_date
CLUSTER BY exchange, product_type
OPTIONS (
  description = 'fact_futures_prices'
);

-- FX-05 FIP参照価格（A値）
CREATE TABLE IF NOT EXISTS fact_fip_reference_prices (
  target_month                       STRING NOT NULL OPTIONS(description = '対象年月：YYYYMM'),
  fuel_code                          STRING NOT NULL OPTIONS(description = '電源種別コード'),
  area_code                          STRING NOT NULL OPTIONS(description = 'エリアコード'),
  reference_price                    NUMERIC NOT NULL OPTIONS(description = '市場参照価格（A値）：円/kWh・税抜'),
  value_status                       STRING NOT NULL OPTIONS(description = '値のステータス：PROVISIONAL（自社試算）／FINAL（GIO公表）'),
  non_fossil_value                   NUMERIC OPTIONS(description = '非化石価値相当額：公表仕様に含まれる場合'),
  published_date                     DATE OPTIONS(description = '公表日／取込日時：暫定行の published_date は自社試算バッチの実行日'),
  fetched_at                         TIMESTAMP OPTIONS(description = '公表日／取込日時：暫定行の published_date は自社試算バッチの実行日'),
  ingestion_run_id                   STRING OPTIONS(description = 'パイプライン実行ID（命名・運用定義書 11.3）'),
  loaded_at                          TIMESTAMP OPTIONS(description = 'BigQueryへのロード日時UTC'),
  pipeline_version                   STRING OPTIONS(description = '処理コードまたはモデルのバージョン'),
  PRIMARY KEY (target_month, fuel_code, area_code) NOT ENFORCED
)
OPTIONS (
  description = 'fact_fip_reference_prices'
);

-- FX-06 市場連動単価（算出結果）
CREATE TABLE IF NOT EXISTS fact_market_linked_prices (
  linked_price_id                    INT64 NOT NULL OPTIONS(description = 'ID'),
  rate_menu_code                     STRING OPTIONS(description = '料金メニューコード／エリアコード'),
  area_code                          STRING OPTIONS(description = '料金メニューコード／エリアコード'),
  scope_key                          STRING OPTIONS(description = '適用スコープキー'),
  target_date                        DATE OPTIONS(description = '対象日／コマ'),
  slot_number                        INT64 OPTIONS(description = '対象日／コマ'),
  calculated_price                   NUMERIC OPTIONS(description = '算出市場連動単価'),
  market_component                   NUMERIC OPTIONS(description = '内訳：市場価格部分'),
  wheeling_component                 NUMERIC OPTIONS(description = '内訳：託送部分'),
  procurement_adj_component          NUMERIC OPTIONS(description = '内訳：調達調整部分'),
  margin_component                   NUMERIC OPTIONS(description = '内訳：手数料部分'),
  applied_param_id                   INT64 OPTIONS(description = '適用パラメータID'),
  calculated_at                      TIMESTAMP OPTIONS(description = '算出日時'),
  ingestion_run_id                   STRING OPTIONS(description = 'パイプライン実行ID（命名・運用定義書 11.3）'),
  loaded_at                          TIMESTAMP OPTIONS(description = 'BigQueryへのロード日時UTC'),
  pipeline_version                   STRING OPTIONS(description = '処理コードまたはモデルのバージョン'),
  PRIMARY KEY (linked_price_id) NOT ENFORCED
)
PARTITION BY target_date
CLUSTER BY area_code, rate_menu_code
OPTIONS (
  require_partition_filter = TRUE,
  description = 'fact_market_linked_prices'
);

-- FX-07 JEPX約定明細
CREATE TABLE IF NOT EXISTS fact_jepx_trades (
  trade_id                           INT64 NOT NULL OPTIONS(description = '約定ID'),
  exchange_ref_id                    STRING OPTIONS(description = '取引所参照ID：突合キー'),
  market_type                        STRING NOT NULL OPTIONS(description = '市場種別：スポット／時間前'),
  target_date                        DATE OPTIONS(description = '対象日／コマ／エリア'),
  slot_number                        INT64 OPTIONS(description = '対象日／コマ／エリア'),
  area_code                          STRING OPTIONS(description = '対象日／コマ／エリア'),
  trade_side                         STRING NOT NULL OPTIONS(description = '売買区分：買／売'),
  contracted_kwh                     NUMERIC NOT NULL OPTIONS(description = '約定量(kWh)'),
  contracted_price                   NUMERIC NOT NULL OPTIONS(description = '約定価格／約定金額：円/kWh／円'),
  contracted_amount                  NUMERIC NOT NULL OPTIONS(description = '約定価格／約定金額：円/kWh／円'),
  transaction_fee                    NUMERIC NOT NULL OPTIONS(description = '取引手数料(円)：D-27 から算出し確定保持'),
  settlement_fee                     NUMERIC NOT NULL OPTIONS(description = '決済代行手数料(円)：同上'),
  bg_code                            STRING OPTIONS(description = '紐付けBGコード：損益の帰属先'),
  fetched_at                         TIMESTAMP OPTIONS(description = '取込日時'),
  ingestion_run_id                   STRING OPTIONS(description = 'パイプライン実行ID（命名・運用定義書 11.3）'),
  loaded_at                          TIMESTAMP OPTIONS(description = 'BigQueryへのロード日時UTC'),
  pipeline_version                   STRING OPTIONS(description = '処理コードまたはモデルのバージョン'),
  PRIMARY KEY (trade_id) NOT ENFORCED
)
PARTITION BY target_date
CLUSTER BY area_code, bg_code
OPTIONS (
  require_partition_filter = TRUE,
  description = 'fact_jepx_trades'
);

-- FX-08 連系線割当・値差
CREATE TABLE IF NOT EXISTS fact_interconnection_allocations (
  allocation_id                      INT64 NOT NULL OPTIONS(description = 'ID'),
  target_date                        DATE OPTIONS(description = '対象日／コマ'),
  slot_number                        INT64 OPTIONS(description = '対象日／コマ'),
  from_area_code                     STRING OPTIONS(description = '送電元／送電先エリア'),
  to_area_code                       STRING OPTIONS(description = '送電元／送電先エリア'),
  interconnection_name               STRING OPTIONS(description = '連系線区間名'),
  operational_capacity_kw            NUMERIC OPTIONS(description = '運用容量(kW)：広域機関公表値'),
  allocated_capacity_kw              NUMERIC OPTIONS(description = '自社BG割当容量(kW)：割当方式は制度に依存'),
  actual_flow_kw                     NUMERIC OPTIONS(description = '実潮流(kW)'),
  is_congested                       BOOL NOT NULL OPTIONS(description = '混雑フラグ'),
  from_area_price                    NUMERIC OPTIONS(description = '送電元／送電先エリアプライス：転記'),
  to_area_price                      NUMERIC OPTIONS(description = '送電元／送電先エリアプライス：転記'),
  price_spread                       NUMERIC OPTIONS(description = 'エリア間値差：送電先 − 送電元'),
  spread_amount                      NUMERIC OPTIONS(description = '値差影響額：自社潮流分'),
  ftr_contract_id                    STRING OPTIONS(description = '間接送電権契約ID'),
  refund_amount                      NUMERIC OPTIONS(description = '還付額：保有時のみ'),
  bg_code                            STRING OPTIONS(description = 'BGコード'),
  data_status                        STRING NOT NULL OPTIONS(description = 'データ区分：暫定／確定'),
  ingestion_run_id                   STRING OPTIONS(description = 'パイプライン実行ID（命名・運用定義書 11.3）'),
  loaded_at                          TIMESTAMP OPTIONS(description = 'BigQueryへのロード日時UTC'),
  pipeline_version                   STRING OPTIONS(description = '処理コードまたはモデルのバージョン'),
  PRIMARY KEY (allocation_id) NOT ENFORCED
)
PARTITION BY target_date
CLUSTER BY bg_code
OPTIONS (
  require_partition_filter = TRUE,
  description = 'fact_interconnection_allocations'
);

-- FX-09 相対・PPA精算明細
CREATE TABLE IF NOT EXISTS fact_procurement_settlements (
  settlement_id                      INT64 NOT NULL OPTIONS(description = '精算ID'),
  procurement_contract_id            STRING OPTIONS(description = '調達契約ID'),
  target_date                        DATE OPTIONS(description = '対象日／コマ／エリア'),
  slot_number                        INT64 OPTIONS(description = '対象日／コマ／エリア'),
  area_code                          STRING OPTIONS(description = '対象日／コマ／エリア'),
  delivered_kwh                      NUMERIC NOT NULL OPTIONS(description = '受渡量(kWh)'),
  unit_price                         NUMERIC NOT NULL OPTIONS(description = '適用単価(円/kWh)：固定、または市場連動＋差金の結果'),
  settlement_amount                  NUMERIC NOT NULL OPTIONS(description = '精算金額(円)：受領値のまま保持（丸め・税抜換算しない。1.5）'),
  tax_type_received                  STRING NOT NULL OPTIONS(description = '受領時税区分：税抜／税込／不課税。相手先通知の表示区分をそのまま持つ。税込の場合のみ Gold（11.5）で ÷(1+税率) を未丸めで適用（レビューで追加。D-28 の tax_type は契約の課税区分で、受領明細の表示区分とは別）'),
  data_status                        STRING NOT NULL OPTIONS(description = 'データ区分：暫定（自社計算）／確定（相手先通知）'),
  ingestion_run_id                   STRING OPTIONS(description = 'パイプライン実行ID（命名・運用定義書 11.3）'),
  loaded_at                          TIMESTAMP OPTIONS(description = 'BigQueryへのロード日時UTC'),
  pipeline_version                   STRING OPTIONS(description = '処理コードまたはモデルのバージョン'),
  PRIMARY KEY (settlement_id) NOT ENFORCED
)
PARTITION BY target_date
CLUSTER BY area_code, procurement_contract_id
OPTIONS (
  require_partition_filter = TRUE,
  description = 'fact_procurement_settlements'
);

-- FX-10 非化石証書購入
CREATE TABLE IF NOT EXISTS fact_nonfossil_certificate_purchases (
  purchase_id                        INT64 NOT NULL OPTIONS(description = '購入ID'),
  certificate_type                   STRING NOT NULL OPTIONS(description = '証書種別／対象年度：D-33 と同一区分'),
  fiscal_year                        INT64 NOT NULL OPTIONS(description = '証書種別／対象年度：D-33 と同一区分'),
  purchased_kwh                      NUMERIC NOT NULL OPTIONS(description = '購入量(kWh)'),
  unit_price                         NUMERIC NOT NULL OPTIONS(description = '購入単価（税抜）／購入金額：円/kWh ／ 円'),
  purchase_amount                    NUMERIC NOT NULL OPTIONS(description = '購入単価（税抜）／購入金額：円/kWh ／ 円'),
  purchase_date                      DATE NOT NULL OPTIONS(description = '購入日／市場：JEPX_NONFOSSIL／BILATERAL'),
  market                             STRING NOT NULL OPTIONS(description = '購入日／市場：JEPX_NONFOSSIL／BILATERAL'),
  allocation_status                  STRING NOT NULL OPTIONS(description = '割当状態：未割当／割当済／償却済'),
  ingestion_run_id                   STRING OPTIONS(description = 'パイプライン実行ID（命名・運用定義書 11.3）'),
  loaded_at                          TIMESTAMP OPTIONS(description = 'BigQueryへのロード日時UTC'),
  pipeline_version                   STRING OPTIONS(description = '処理コードまたはモデルのバージョン'),
  PRIMARY KEY (purchase_id) NOT ENFORCED
)
PARTITION BY purchase_date
OPTIONS (
  description = 'fact_nonfossil_certificate_purchases'
);

-- FT-01 発電計画
CREATE TABLE IF NOT EXISTS fact_gen_plans (
  gen_plan_id                        INT64 NOT NULL OPTIONS(description = '発電計画ID'),
  supply_point_number                STRING OPTIONS(description = '受給地点番号'),
  gen_bg_code                        STRING OPTIONS(description = '発電BGコード'),
  area_code                          STRING OPTIONS(description = 'エリアコード：非正規化'),
  target_date                        DATE OPTIONS(description = '対象日／コマ'),
  slot_number                        INT64 OPTIONS(description = '対象日／コマ'),
  plan_value_kw                      NUMERIC NOT NULL OPTIONS(description = '計画値(kW)：OCCTO提出値（送電端）'),
  plan_basis                         STRING NOT NULL OPTIONS(description = '計画値の基準：発電は原則 SENDING_END'),
  plan_type                          STRING NOT NULL OPTIONS(description = '計画種別：前日計画(DA)／当日計画(ID)'),
  plan_version                       INT64 NOT NULL OPTIONS(description = '計画バージョン：同一種別内の改訂番号'),
  submitted_at                       TIMESTAMP OPTIONS(description = '提出日時：GC判定'),
  created_at                         TIMESTAMP OPTIONS(description = '作成日時'),
  ingestion_run_id                   STRING OPTIONS(description = 'パイプライン実行ID（命名・運用定義書 11.3）'),
  loaded_at                          TIMESTAMP OPTIONS(description = 'BigQueryへのロード日時UTC'),
  pipeline_version                   STRING OPTIONS(description = '処理コードまたはモデルのバージョン'),
  PRIMARY KEY (gen_plan_id) NOT ENFORCED
)
PARTITION BY target_date
CLUSTER BY area_code, supply_point_number
OPTIONS (
  require_partition_filter = TRUE,
  description = 'fact_gen_plans'
);

-- FT-02 需要計画（需要予測）
CREATE TABLE IF NOT EXISTS fact_dem_plans (
  dem_plan_id                        INT64 NOT NULL OPTIONS(description = '需要計画ID'),
  demand_point_number                STRING OPTIONS(description = '需要地点番号'),
  dem_bg_code                        STRING OPTIONS(description = '需要BGコード'),
  area_code                          STRING OPTIONS(description = 'エリアコード'),
  target_date                        DATE OPTIONS(description = '対象日／コマ'),
  slot_number                        INT64 OPTIONS(description = '対象日／コマ'),
  forecast_value_kw                  NUMERIC NOT NULL OPTIONS(description = '予測需要量(kW)'),
  plan_basis                         STRING NOT NULL OPTIONS(description = '計画値の基準：SENDING_END（送電端：OCCTO提出値）／RECEIVING_END（受電端：予測モデルの生値）。精算対象の計画（plan_type がGC確定）は必ず SENDING_END'),
  plan_type                          STRING NOT NULL OPTIONS(description = '計画種別：前日計画(DA)／当日計画(ID)'),
  plan_version                       INT64 NOT NULL OPTIONS(description = '計画バージョン：同一種別内の改訂番号。上書きせず履歴保持'),
  model_version                      STRING OPTIONS(description = '予測モデルバージョン：精度追跡用'),
  weather_scenario_id                STRING OPTIONS(description = '気象シナリオID'),
  submitted_at                       TIMESTAMP OPTIONS(description = '提出日時：OCCTO への提出日時（GC判定）。予測のみの行は NULL'),
  created_at                         TIMESTAMP OPTIONS(description = '作成日時'),
  ingestion_run_id                   STRING OPTIONS(description = 'パイプライン実行ID（命名・運用定義書 11.3）'),
  loaded_at                          TIMESTAMP OPTIONS(description = 'BigQueryへのロード日時UTC'),
  pipeline_version                   STRING OPTIONS(description = '処理コードまたはモデルのバージョン'),
  PRIMARY KEY (dem_plan_id) NOT ENFORCED
)
PARTITION BY target_date
CLUSTER BY area_code, demand_point_number
OPTIONS (
  require_partition_filter = TRUE,
  description = 'fact_dem_plans'
);

-- FT-03 / FT-06 速報
CREATE TABLE IF NOT EXISTS fact_gen_actuals_stream (
  stream_id                          INT64 NOT NULL OPTIONS(description = 'ID'),
  supply_point_number                STRING OPTIONS(description = '地点番号'),
  area_code                          STRING OPTIONS(description = 'エリアコード'),
  target_date                        DATE OPTIONS(description = '対象日／コマ'),
  slot_number                        INT64 OPTIONS(description = '対象日／コマ'),
  actual_value_kwh                   NUMERIC NOT NULL OPTIONS(description = '実績値(kWh)：未検証の生値'),
  inserted_at                        TIMESTAMP NOT NULL OPTIONS(description = '取込日時：重複時は最新を採用'),
  source_type                        STRING OPTIONS(description = 'ソース区分：スマメ／自社パルス／送配電API'),
  ingestion_run_id                   STRING OPTIONS(description = 'パイプライン実行ID（命名・運用定義書 11.3）'),
  loaded_at                          TIMESTAMP OPTIONS(description = 'BigQueryへのロード日時UTC'),
  pipeline_version                   STRING OPTIONS(description = '処理コードまたはモデルのバージョン'),
  PRIMARY KEY (stream_id) NOT ENFORCED
)
PARTITION BY DATE(inserted_at)
CLUSTER BY area_code, supply_point_number
OPTIONS (
  require_partition_filter = TRUE, partition_expiration_days = 7,
  description = 'fact_gen_actuals_stream'
);

-- (需要側) FT-03 / FT-06 速報
CREATE TABLE IF NOT EXISTS fact_dem_actuals_stream (
  stream_id                          INT64 NOT NULL OPTIONS(description = 'ID'),
  demand_point_number                STRING OPTIONS(description = '地点番号'),
  area_code                          STRING OPTIONS(description = 'エリアコード'),
  target_date                        DATE OPTIONS(description = '対象日／コマ'),
  slot_number                        INT64 OPTIONS(description = '対象日／コマ'),
  actual_value_kwh                   NUMERIC NOT NULL OPTIONS(description = '実績値(kWh)：未検証の生値'),
  inserted_at                        TIMESTAMP NOT NULL OPTIONS(description = '取込日時：重複時は最新を採用'),
  source_type                        STRING OPTIONS(description = 'ソース区分：スマメ／自社パルス／送配電API'),
  ingestion_run_id                   STRING OPTIONS(description = 'パイプライン実行ID（命名・運用定義書 11.3）'),
  loaded_at                          TIMESTAMP OPTIONS(description = 'BigQueryへのロード日時UTC'),
  pipeline_version                   STRING OPTIONS(description = '処理コードまたはモデルのバージョン'),
  PRIMARY KEY (stream_id) NOT ENFORCED
)
PARTITION BY DATE(inserted_at)
CLUSTER BY area_code, demand_point_number
OPTIONS (
  require_partition_filter = TRUE, partition_expiration_days = 7,
  description = 'fact_dem_actuals_stream'
);

-- FT-13 速報最新行キャッシュ
CREATE TABLE IF NOT EXISTS fact_gen_actuals_stream_latest (
  supply_point_number                STRING NOT NULL OPTIONS(description = '地点番号／対象日／コマ：1行に集約'),
  target_date                        DATE NOT NULL OPTIONS(description = '地点番号／対象日／コマ：1行に集約'),
  slot_number                        INT64 NOT NULL OPTIONS(description = '地点番号／対象日／コマ：1行に集約'),
  area_code                          STRING OPTIONS(description = 'エリアコード'),
  actual_value_kwh                   NUMERIC NOT NULL OPTIONS(description = '実績値(kWh)：最新の inserted_at を持つ値'),
  source_inserted_at                 TIMESTAMP NOT NULL OPTIONS(description = '元の取込日時'),
  refreshed_at                       TIMESTAMP NOT NULL OPTIONS(description = '更新日時：マイクロバッチの実行時刻'),
  ingestion_run_id                   STRING OPTIONS(description = 'パイプライン実行ID（命名・運用定義書 11.3）'),
  loaded_at                          TIMESTAMP OPTIONS(description = 'BigQueryへのロード日時UTC'),
  pipeline_version                   STRING OPTIONS(description = '処理コードまたはモデルのバージョン'),
  PRIMARY KEY (supply_point_number, target_date, slot_number) NOT ENFORCED
)
PARTITION BY target_date
CLUSTER BY area_code, supply_point_number
OPTIONS (
  require_partition_filter = TRUE, partition_expiration_days = 7,
  description = 'fact_gen_actuals_stream_latest'
);

-- (需要側) FT-13 速報最新行キャッシュ
CREATE TABLE IF NOT EXISTS fact_dem_actuals_stream_latest (
  demand_point_number                STRING NOT NULL OPTIONS(description = '地点番号／対象日／コマ：1行に集約'),
  target_date                        DATE NOT NULL OPTIONS(description = '地点番号／対象日／コマ：1行に集約'),
  slot_number                        INT64 NOT NULL OPTIONS(description = '地点番号／対象日／コマ：1行に集約'),
  area_code                          STRING OPTIONS(description = 'エリアコード'),
  actual_value_kwh                   NUMERIC NOT NULL OPTIONS(description = '実績値(kWh)：最新の inserted_at を持つ値'),
  source_inserted_at                 TIMESTAMP NOT NULL OPTIONS(description = '元の取込日時'),
  refreshed_at                       TIMESTAMP NOT NULL OPTIONS(description = '更新日時：マイクロバッチの実行時刻'),
  ingestion_run_id                   STRING OPTIONS(description = 'パイプライン実行ID（命名・運用定義書 11.3）'),
  loaded_at                          TIMESTAMP OPTIONS(description = 'BigQueryへのロード日時UTC'),
  pipeline_version                   STRING OPTIONS(description = '処理コードまたはモデルのバージョン'),
  PRIMARY KEY (demand_point_number, target_date, slot_number) NOT ENFORCED
)
PARTITION BY target_date
CLUSTER BY area_code, demand_point_number
OPTIONS (
  require_partition_filter = TRUE, partition_expiration_days = 7,
  description = 'fact_dem_actuals_stream_latest'
);

-- FT-04 / FT-07 確報
CREATE TABLE IF NOT EXISTS fact_gen_actuals_daily (
  supply_point_number                STRING NOT NULL OPTIONS(description = '地点番号／対象日／コマ'),
  target_date                        DATE NOT NULL OPTIONS(description = '地点番号／対象日／コマ'),
  slot_number                        INT64 NOT NULL OPTIONS(description = '地点番号／対象日／コマ'),
  area_code                          STRING OPTIONS(description = 'エリアコード'),
  actual_value_kwh                   NUMERIC NOT NULL OPTIONS(description = '実績値(kWh)：クレンジング後の採用値'),
  raw_value_kwh                      NUMERIC OPTIONS(description = '生値(kWh)：補完前の値（監査用）'),
  cleansing_flag                     INT64 NOT NULL OPTIONS(description = 'クレンジングフラグ：0 正常／1 マイナス補正／2 線形補完／3 前日・前週コピー／4 計画値代替／5 プロファイル配分（訪問検針地点の月間総量を標準負荷曲線で48コマへ配分。B-04b）／6 一送推定検針（通信障害等で一送が推定した確定値。分析時に除外可能）'),
  data_status                        STRING NOT NULL OPTIONS(description = 'データステータス：確報値'),
  updated_at                         TIMESTAMP NOT NULL OPTIONS(description = '更新日時'),
  ingestion_run_id                   STRING OPTIONS(description = 'パイプライン実行ID（命名・運用定義書 11.3）'),
  loaded_at                          TIMESTAMP OPTIONS(description = 'BigQueryへのロード日時UTC'),
  pipeline_version                   STRING OPTIONS(description = '処理コードまたはモデルのバージョン'),
  PRIMARY KEY (supply_point_number, target_date, slot_number) NOT ENFORCED
)
PARTITION BY target_date
CLUSTER BY area_code, supply_point_number
OPTIONS (
  require_partition_filter = TRUE,
  description = 'fact_gen_actuals_daily'
);

-- (需要側) FT-04 / FT-07 確報
CREATE TABLE IF NOT EXISTS fact_dem_actuals_daily (
  demand_point_number                STRING NOT NULL OPTIONS(description = '地点番号／対象日／コマ'),
  target_date                        DATE NOT NULL OPTIONS(description = '地点番号／対象日／コマ'),
  slot_number                        INT64 NOT NULL OPTIONS(description = '地点番号／対象日／コマ'),
  area_code                          STRING OPTIONS(description = 'エリアコード'),
  actual_value_kwh                   NUMERIC NOT NULL OPTIONS(description = '実績値(kWh)：クレンジング後の採用値'),
  raw_value_kwh                      NUMERIC OPTIONS(description = '生値(kWh)：補完前の値（監査用）'),
  cleansing_flag                     INT64 NOT NULL OPTIONS(description = 'クレンジングフラグ：0 正常／1 マイナス補正／2 線形補完／3 前日・前週コピー／4 計画値代替／5 プロファイル配分（訪問検針地点の月間総量を標準負荷曲線で48コマへ配分。B-04b）／6 一送推定検針（通信障害等で一送が推定した確定値。分析時に除外可能）'),
  data_status                        STRING NOT NULL OPTIONS(description = 'データステータス：確報値'),
  updated_at                         TIMESTAMP NOT NULL OPTIONS(description = '更新日時'),
  ingestion_run_id                   STRING OPTIONS(description = 'パイプライン実行ID（命名・運用定義書 11.3）'),
  loaded_at                          TIMESTAMP OPTIONS(description = 'BigQueryへのロード日時UTC'),
  pipeline_version                   STRING OPTIONS(description = '処理コードまたはモデルのバージョン'),
  PRIMARY KEY (demand_point_number, target_date, slot_number) NOT ENFORCED
)
PARTITION BY target_date
CLUSTER BY area_code, demand_point_number
OPTIONS (
  require_partition_filter = TRUE,
  description = 'fact_dem_actuals_daily'
);

-- FT-05 / FT-08 確定
CREATE TABLE IF NOT EXISTS fact_gen_actuals_settled (
  supply_point_number                STRING NOT NULL OPTIONS(description = '地点番号／対象日／コマ'),
  target_date                        DATE NOT NULL OPTIONS(description = '地点番号／対象日／コマ'),
  slot_number                        INT64 NOT NULL OPTIONS(description = '地点番号／対象日／コマ'),
  batch_id                           STRING NOT NULL OPTIONS(description = '取込バッチID：監査証跡。訂正レコードは新しい batch_id を持つため主キーに含める'),
  area_code                          STRING OPTIONS(description = 'エリアコード'),
  actual_value_kwh                   NUMERIC NOT NULL OPTIONS(description = '実績値(kWh)：送配電の公式検針確定値。訂正レコードは差分（符号付き）'),
  record_type                        STRING NOT NULL OPTIONS(description = 'レコード種別：ORIGINAL（初回取込）／CORRECTION（打ち消し・差分）'),
  data_status                        STRING NOT NULL OPTIONS(description = 'データステータス：確定値'),
  settled_received_date              DATE NOT NULL OPTIONS(description = '確定受領日：統合ビューの境界判定は FT-11 で行い、本列は証跡用'),
  ingestion_run_id                   STRING OPTIONS(description = 'パイプライン実行ID（命名・運用定義書 11.3）'),
  loaded_at                          TIMESTAMP OPTIONS(description = 'BigQueryへのロード日時UTC'),
  pipeline_version                   STRING OPTIONS(description = '処理コードまたはモデルのバージョン'),
  PRIMARY KEY (supply_point_number, target_date, slot_number, batch_id) NOT ENFORCED
)
PARTITION BY target_date
CLUSTER BY area_code, supply_point_number
OPTIONS (
  require_partition_filter = TRUE,
  description = 'fact_gen_actuals_settled'
);

-- (需要側) FT-05 / FT-08 確定
CREATE TABLE IF NOT EXISTS fact_dem_actuals_settled (
  demand_point_number                STRING NOT NULL OPTIONS(description = '地点番号／対象日／コマ'),
  target_date                        DATE NOT NULL OPTIONS(description = '地点番号／対象日／コマ'),
  slot_number                        INT64 NOT NULL OPTIONS(description = '地点番号／対象日／コマ'),
  batch_id                           STRING NOT NULL OPTIONS(description = '取込バッチID：監査証跡。訂正レコードは新しい batch_id を持つため主キーに含める'),
  area_code                          STRING OPTIONS(description = 'エリアコード'),
  actual_value_kwh                   NUMERIC NOT NULL OPTIONS(description = '実績値(kWh)：送配電の公式検針確定値。訂正レコードは差分（符号付き）'),
  record_type                        STRING NOT NULL OPTIONS(description = 'レコード種別：ORIGINAL（初回取込）／CORRECTION（打ち消し・差分）'),
  data_status                        STRING NOT NULL OPTIONS(description = 'データステータス：確定値'),
  settled_received_date              DATE NOT NULL OPTIONS(description = '確定受領日：統合ビューの境界判定は FT-11 で行い、本列は証跡用'),
  ingestion_run_id                   STRING OPTIONS(description = 'パイプライン実行ID（命名・運用定義書 11.3）'),
  loaded_at                          TIMESTAMP OPTIONS(description = 'BigQueryへのロード日時UTC'),
  pipeline_version                   STRING OPTIONS(description = '処理コードまたはモデルのバージョン'),
  PRIMARY KEY (demand_point_number, target_date, slot_number, batch_id) NOT ENFORCED
)
PARTITION BY target_date
CLUSTER BY area_code, demand_point_number
OPTIONS (
  require_partition_filter = TRUE,
  description = 'fact_dem_actuals_settled'
);

-- FT-15 月次検針値
CREATE TABLE IF NOT EXISTS fact_monthly_meter_readings (
  demand_point_number                STRING NOT NULL OPTIONS(description = '需要地点番号＋請求月：D-31 と同一キー'),
  billing_month                      STRING NOT NULL OPTIONS(description = '需要地点番号＋請求月：D-31 と同一キー'),
  period_start_date                  DATE NOT NULL OPTIONS(description = '検針期間 開始日／終了日：D-31 と一致すること（13.1 で検証）'),
  period_end_date                    DATE NOT NULL OPTIONS(description = '検針期間 開始日／終了日：D-31 と一致すること（13.1 で検証）'),
  index_prev                         NUMERIC OPTIONS(description = '前回指針／今回指針：指針値（乗率適用前）'),
  index_curr                         NUMERIC OPTIONS(description = '前回指針／今回指針：指針値（乗率適用前）'),
  multiplier                         NUMERIC OPTIONS(description = '乗率：計器の乗率'),
  total_kwh                          NUMERIC NOT NULL OPTIONS(description = '月間電力量(kWh)：一送の検針票の確定総量（受電端）'),
  reading_type                       STRING NOT NULL OPTIONS(description = '検針区分：VISIT／ESTIMATED'),
  received_at                        TIMESTAMP NOT NULL OPTIONS(description = '受領日／取込バッチID'),
  batch_id                           STRING NOT NULL OPTIONS(description = '受領日／取込バッチID'),
  ingestion_run_id                   STRING OPTIONS(description = 'パイプライン実行ID（命名・運用定義書 11.3）'),
  loaded_at                          TIMESTAMP OPTIONS(description = 'BigQueryへのロード日時UTC'),
  pipeline_version                   STRING OPTIONS(description = '処理コードまたはモデルのバージョン'),
  PRIMARY KEY (demand_point_number, billing_month) NOT ENFORCED
)
OPTIONS (
  description = 'fact_monthly_meter_readings'
);

-- FT-12 BG構成員別インバランス
CREATE TABLE IF NOT EXISTS fact_bg_member_imbalance (
  target_date                        DATE NOT NULL OPTIONS(description = '対象日／コマ'),
  slot_number                        INT64 NOT NULL OPTIONS(description = '対象日／コマ'),
  bg_code                            STRING NOT NULL OPTIONS(description = 'BGコード'),
  bg_member_id                       STRING NOT NULL OPTIONS(description = '構成員ID'),
  area_code                          STRING OPTIONS(description = 'エリアコード：非正規化'),
  member_plan_kwh                    NUMERIC NOT NULL OPTIONS(description = '構成員計画量(kWh)：GC時点の計画 × 0.5'),
  member_actual_kwh                  NUMERIC NOT NULL OPTIONS(description = '構成員実績量(kWh)：送電端換算'),
  member_imbalance_kwh               NUMERIC NOT NULL OPTIONS(description = '構成員インバランス量 I_i：符号付き（実績 − 計画）'),
  bg_net_imbalance_kwh               NUMERIC NOT NULL OPTIONS(description = 'BG全体インバランス量 I_bg：同一コマのBG合計。非正規化'),
  is_causer                          BOOL NOT NULL OPTIONS(description = '原因者フラグ：sign(I_i) = sign(I_bg) なら 1'),
  imbalance_price                    NUMERIC NOT NULL OPTIONS(description = '適用単価 P'),
  price_status                       STRING NOT NULL OPTIONS(description = '単価ステータス：暫定／確定'),
  bg_total_amount                    NUMERIC NOT NULL OPTIONS(description = 'BG全体精算額 C_bg'),
  allocation_method_applied          STRING NOT NULL OPTIONS(description = '適用按分方式：算出時点の dim_balancing_groups.allocation_method を固定保持'),
  allocated_amount_raw               NUMERIC NOT NULL OPTIONS(description = '按分額（未丸め）：方式の計算式どおりの値（丸めなし）。監査・再計算用'),
  allocated_amount                   NUMERIC NOT NULL OPTIONS(description = '按分額 A_i：符号付き（受取はマイナス）。BG協定書が1円単位精算を規定するため、規約順守として1円に丸めた値（1.5 の例外）'),
  rounding_adjustment                NUMERIC OPTIONS(description = '端数調整額：rounding_rule により負担者にのみ計上'),
  calculated_at                      TIMESTAMP NOT NULL OPTIONS(description = '算出日時'),
  ingestion_run_id                   STRING OPTIONS(description = 'パイプライン実行ID（命名・運用定義書 11.3）'),
  loaded_at                          TIMESTAMP OPTIONS(description = 'BigQueryへのロード日時UTC'),
  pipeline_version                   STRING OPTIONS(description = '処理コードまたはモデルのバージョン'),
  PRIMARY KEY (target_date, slot_number, bg_code, bg_member_id) NOT ENFORCED
)
PARTITION BY target_date
CLUSTER BY area_code, bg_code
OPTIONS (
  require_partition_filter = TRUE,
  description = 'fact_bg_member_imbalance'
);

-- FT-10 マスタ変更監査ログ
CREATE TABLE IF NOT EXISTS fact_master_change_log (
  log_id                             INT64 NOT NULL OPTIONS(description = 'ログID'),
  table_name                         STRING NOT NULL OPTIONS(description = '対象テーブル'),
  record_key                         STRING NOT NULL OPTIONS(description = '対象キー：主キー値の連結'),
  operation                          STRING NOT NULL OPTIONS(description = '操作種別：INSERT / UPDATE / DELETE / CORRECT'),
  before_json                        JSON OPTIONS(description = '変更前／変更後：変更列のみ'),
  after_json                         JSON OPTIONS(description = '変更前／変更後：変更列のみ'),
  reason                             STRING NOT NULL OPTIONS(description = '変更理由'),
  changed_by                         STRING NOT NULL OPTIONS(description = '実行者／承認者'),
  approved_by                        STRING NOT NULL OPTIONS(description = '実行者／承認者'),
  changed_at                         TIMESTAMP NOT NULL OPTIONS(description = '実行日時'),
  ingestion_run_id                   STRING OPTIONS(description = 'パイプライン実行ID（命名・運用定義書 11.3）'),
  loaded_at                          TIMESTAMP OPTIONS(description = 'BigQueryへのロード日時UTC'),
  pipeline_version                   STRING OPTIONS(description = '処理コードまたはモデルのバージョン'),
  PRIMARY KEY (log_id) NOT ENFORCED
)
PARTITION BY DATE(changed_at)
OPTIONS (
  description = 'fact_master_change_log'
);

-- FT-14 バッチ実行ログ
CREATE TABLE IF NOT EXISTS fact_batch_run_log (
  run_id                             STRING NOT NULL OPTIONS(description = '実行ID'),
  batch_id                           STRING NOT NULL OPTIONS(description = 'バッチID：12.2 の B-nn'),
  target_date                        DATE OPTIONS(description = '対象日：対象日を持たないバッチは NULL'),
  started_at                         TIMESTAMP NOT NULL OPTIONS(description = '開始／終了日時'),
  finished_at                        TIMESTAMP NOT NULL OPTIONS(description = '開始／終了日時'),
  status                             STRING NOT NULL OPTIONS(description = '状態：RUNNING／SUCCESS／FAILED／SKIPPED'),
  result_status                      STRING OPTIONS(description = '戻り値：プロシージャが返した status（例：HOLIDAY_CSV_REJECTED、PUBLISHED）'),
  message                            STRING OPTIONS(description = 'メッセージ：エラー内容・件数'),
  ingestion_run_id                   STRING OPTIONS(description = 'パイプライン実行ID（命名・運用定義書 11.3）'),
  loaded_at                          TIMESTAMP OPTIONS(description = 'BigQueryへのロード日時UTC'),
  pipeline_version                   STRING OPTIONS(description = '処理コードまたはモデルのバージョン'),
  PRIMARY KEY (run_id) NOT ENFORCED
)
PARTITION BY target_date
OPTIONS (
  require_partition_filter = TRUE,
  description = 'fact_batch_run_log'
);

-- FT-11 確定値受領状況
CREATE TABLE IF NOT EXISTS fact_settlement_receipts (
  area_code                          STRING NOT NULL OPTIONS(description = 'エリアコード／対象年月'),
  target_month                       STRING NOT NULL OPTIONS(description = 'エリアコード／対象年月'),
  side                               STRING NOT NULL OPTIONS(description = '側：発電／需要'),
  expected_date                      DATE NOT NULL OPTIONS(description = '期待受領日：検針日（または月末）＋ 一送の N 営業日（TS_BUSINESS ルールで営業日をカウント）。カレンダー日付で固定しない'),
  received_date                      DATE OPTIONS(description = '受領日：NULL＝未受領'),
  received_count                     INT64 OPTIONS(description = '受領件数／期待件数：地点数×日数×48 との突合'),
  expected_count                     INT64 OPTIONS(description = '受領件数／期待件数：地点数×日数×48 との突合'),
  is_loaded                          BOOL NOT NULL OPTIONS(description = '取込完了フラグ：統合ビューの境界判定に使う（4.3）'),
  ingestion_run_id                   STRING OPTIONS(description = 'パイプライン実行ID（命名・運用定義書 11.3）'),
  loaded_at                          TIMESTAMP OPTIONS(description = 'BigQueryへのロード日時UTC'),
  pipeline_version                   STRING OPTIONS(description = '処理コードまたはモデルのバージョン'),
  PRIMARY KEY (area_code, target_month, side) NOT ENFORCED
)
OPTIONS (
  description = 'fact_settlement_receipts'
);

