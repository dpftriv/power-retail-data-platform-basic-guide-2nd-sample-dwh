-- =============================================================================
-- 電力小売データ分析基盤
-- Gold 層 マート（t_*）DDL
-- 生成元：電力小売データ分析基盤.md（第9章のテーブル定義）
-- 注意：本ファイルは設計書の項目定義から機械生成した骨組み（正本は設計書）。
--       型・NOT NULL は設計書の記載に従い、記載のない列は命名から推定している。
--       デプロイ前に dev 環境で DDL レビュー（13.1／フェーズ1完了条件）を行うこと。
-- =============================================================================

-- T-01 日報損益マート
CREATE TABLE IF NOT EXISTS agg_daily_pnl (
  target_date                        DATE NOT NULL OPTIONS(description = '対象日／コマ'),
  slot_number                        INT64 NOT NULL OPTIONS(description = '対象日／コマ'),
  area_code                          STRING NOT NULL OPTIONS(description = 'エリア／BG：需要BG・発電BG共通'),
  bg_code                            STRING NOT NULL OPTIONS(description = 'エリア／BG：需要BG・発電BG共通'),
  direction                          STRING NOT NULL OPTIONS(description = '流向：INBOUND（需要：系統→需要家）／OUTBOUND（発電：発電所→系統）／STORAGE（蓄電）。行の種類。需要側 INSERT は INBOUND、発電側 INSERT は OUTBOUND、第16章のオプションは STORAGE を固定で書く'),
  segment                            STRING NOT NULL OPTIONS(description = 'セグメント：direction=INBOUND：低圧／高圧／特高、direction=OUTBOUND：発電、direction=STORAGE：蓄電池。direction と segment の組合せは 13.1 ⑬ で検証する'),
  menu_type                          STRING NOT NULL OPTIONS(description = 'メニュー種別：固定単価／市場連動（需要行）、FIP／非FIP（発電行）、蓄電（蓄電行）。同一セグメントに両方が共存するため主キーに含める'),
  demand_kwh                         NUMERIC NOT NULL OPTIONS(description = '需要実績量（受電端）：発電行は 0'),
  demand_kwh_sending_end             NUMERIC NOT NULL OPTIONS(description = '需要実績量（送電端換算）：10.2 の損失補正後'),
  generation_kwh                     NUMERIC NOT NULL OPTIONS(description = '発電実績量（送電端）：放電量を含む。需要行は 0'),
  imbalance_kwh                      NUMERIC NOT NULL OPTIONS(description = 'インバランス量：BGネッティング後を送電端需要比で按分'),
  revenue                            NUMERIC NOT NULL OPTIONS(description = '売上（税抜）：下記 rev_* の和'),
  rev_energy                         NUMERIC NOT NULL OPTIONS(description = '売上内訳：従量電力量料金：固定単価または市場連動単価 × 受電端kWh'),
  rev_fuel_adj                       NUMERIC NOT NULL OPTIONS(description = '売上内訳：燃料費調整額：市場連動は常に 0（13.1 ⑦）'),
  rev_levy_incl_tax                  NUMERIC NOT NULL OPTIONS(description = '売上内訳：再エネ賦課金（税込総額）：需要実績量 × 税込公表単価。税込のまま・未丸めで保持する正の値。月次精算・検算 #2 はこの列の月間合計に D-32 の丸めを適用してから税抜化する（10.7）'),
  rev_levy                           NUMERIC NOT NULL OPTIONS(description = '売上内訳：再エネ賦課金（税抜換算・日次参考値）：rev_levy_incl_tax ÷ (1+税率)、未丸め。日次の revenue・gross_profit の表示にのみ使う参考値。月次確定時に「月間税込総額を丸めてから税抜化した値」との差を settlement_rounding_adjustment に計上する'),
  rev_base_est                       NUMERIC NOT NULL OPTIONS(description = '売上内訳：基本料金（日割試算）：resolved_contract_kw（V-07）または契約kW × base_rate ÷ 月日数 ÷ 48。低圧アンペア契約は dim_ampere_rates.retail_base_rate ÷ 月日数 ÷ 48。月次確定は B-08'),
  rev_market_sales                   NUMERIC NOT NULL OPTIONS(description = '売上内訳：市場売電（発電）：発電量 × エリアプライス。課税。JEPX がマイナス価格のコマは負の売上として残す（10.9）'),
  rev_fip_premium                    NUMERIC NOT NULL OPTIONS(description = '売上内訳：FIPプレミアム：発電量 × GREATEST(0, F−A)。不課税'),
  rev_balancing_premium              NUMERIC NOT NULL OPTIONS(description = '売上内訳：バランシングコスト：発電量 × total_balancing_premium。不課税'),
  procurement_cost                   NUMERIC NOT NULL OPTIONS(description = '調達原価（税抜）：下記 cost_*（cost_gen_charge・cost_levy_passthrough を含む）＋ fixed_fee_* の和'),
  cost_jepx_spot                     NUMERIC NOT NULL OPTIONS(description = '原価内訳：JEPX約定代金：fact_jepx_trades.contracted_amount を BG 内で送電端需要比按分'),
  cost_jepx_fee                      NUMERIC NOT NULL OPTIONS(description = '原価内訳：JEPX従量手数料：取引＋決済代行（買）。発電行は売り手数料'),
  cost_procurement_contract          NUMERIC NOT NULL OPTIONS(description = '原価内訳：相対・PPA・先物：相対・PPA の精算額（FX-09、エリア按分）＋先物差金の割戻し（10.8.3、BG按分）'),
  cost_imbalance                     NUMERIC NOT NULL OPTIONS(description = '原価内訳：インバランス：agg_imbalance_daily.imbalance_amount の按分'),
  cost_wheeling_variable             NUMERIC NOT NULL OPTIONS(description = '原価内訳：託送電力量料金：受電端kWh × demand_variable_rate'),
  cost_wheeling_fixed_est            NUMERIC NOT NULL OPTIONS(description = '原価内訳：託送基本料金（日割試算）：契約kW × demand_fixed_rate ÷ 月日数 ÷ 48。低圧アンペア契約は dim_ampere_rates.wheeling_base_rate ÷ 月日数 ÷ 48。rev_base_est と対で持つ'),
  cost_capacity_contribution         NUMERIC NOT NULL OPTIONS(description = '原価内訳：容量拠出金：受電端kWh × 一律kWh単価（R-6）'),
  cost_nonfossil_certificate         NUMERIC NOT NULL OPTIONS(description = '原価内訳：非化石証書：環境価値付きメニューの受電端kWh × 証書単価（D-33、10.8.5）。付与なしメニューは 0'),
  cost_gen_charge                    NUMERIC NOT NULL OPTIONS(description = '原価内訳：発電側課金：発電行（direction=\'OUTBOUND\'）のみ。契約出力(kW) × 発電側課金単価 × (1−割引率) の月割試算＋従量課金単価分（10.10）。需要行は 0'),
  cost_levy_passthrough              NUMERIC NOT NULL OPTIONS(description = '原価内訳：再エネ賦課金納付（パススルー）：rev_levy と同額。需要家から預かった賦課金を費用負担調整機関へそのまま納付する原価。売上側の rev_levy と相殺され、粗利には影響しない（10.7・利益階層③）。発電行は 0'),
  fixed_fee_provisional              NUMERIC NOT NULL OPTIONS(description = '定額手数料（暫定）：当日約定量（買）× 前月実績ベース単価（10.8.1）'),
  fixed_fee_final                    NUMERIC NOT NULL OPTIONS(description = '定額手数料（月次確定差額）：月末日行以外は 0'),
  settlement_rounding_adjustment     NUMERIC NOT NULL OPTIONS(description = '請求丸め調整：D-32 の丸めとコマ積算の差。月末日行以外は 0'),
  contribution_margin                NUMERIC NOT NULL OPTIONS(description = 'コマ限界利益（利益階層①）：需要行：rev_energy − cost_jepx_spot − cost_jepx_fee − cost_procurement_contract、発電行：rev_market_sales − cost_jepx_fee。市場調達と小売／売電価格の純粋なスプレッド（10.13）'),
  gross_profit                       NUMERIC NOT NULL OPTIONS(description = '粗利（利益階層②＝③）：revenue − procurement_cost。賦課金は売上（rev_levy）と原価（cost_levy_passthrough）の双方に同額計上されるため相殺され、調整後売上総利益（②）と会計上の粗利（③）は同値になる（10.13）'),
  margin_per_kwh                     NUMERIC OPTIONS(description = 'kWhあたり限界利益：gross_profit ÷ (demand_kwh + generation_kwh)。賦課金の影響を受けない。分母 0 は NULL'),
  base_data_status                   STRING NOT NULL OPTIONS(description = '集計時ステータス：速報値／確報値／確定値'),
  applied_rate_refs                  JSON OPTIONS(description = '適用単価参照：使用した単価・パラメータのID群'),
  is_verified                        BOOL NOT NULL OPTIONS(description = '検算フラグ：11.3 の検算 #1〜#3 を全て通過で TRUE'),
  ingestion_run_id                   STRING OPTIONS(description = 'パイプライン実行ID（命名・運用定義書 11.3）'),
  loaded_at                          TIMESTAMP OPTIONS(description = 'BigQueryへのロード日時UTC'),
  pipeline_version                   STRING OPTIONS(description = '処理コードまたはモデルのバージョン'),
  PRIMARY KEY (target_date, slot_number, area_code, bg_code, direction, segment, menu_type) NOT ENFORCED
)
PARTITION BY target_date
CLUSTER BY area_code, direction, segment, bg_code
OPTIONS (
  require_partition_filter = TRUE,
  description = 'agg_daily_pnl'
);

-- T-02 インバランス日次マート
CREATE TABLE IF NOT EXISTS agg_imbalance_daily (
  target_date                        DATE NOT NULL OPTIONS(description = '対象日／コマ／BG'),
  slot_number                        INT64 NOT NULL OPTIONS(description = '対象日／コマ／BG'),
  bg_code                            STRING NOT NULL OPTIONS(description = '対象日／コマ／BG'),
  area_code                          STRING OPTIONS(description = 'エリアコード'),
  plan_kwh                           NUMERIC OPTIONS(description = '計画量／実績量（送電端 kWh）'),
  actual_kwh                         NUMERIC OPTIONS(description = '計画量／実績量（送電端 kWh）'),
  gross_imbalance_kwh                NUMERIC OPTIONS(description = 'ネッティング前／後インバランス量'),
  net_imbalance_kwh                  NUMERIC OPTIONS(description = 'ネッティング前／後インバランス量'),
  imbalance_price                    NUMERIC OPTIONS(description = '適用単価'),
  imbalance_amount                   NUMERIC OPTIONS(description = '精算額'),
  price_status                       STRING OPTIONS(description = '単価ステータス'),
  ingestion_run_id                   STRING OPTIONS(description = 'パイプライン実行ID（命名・運用定義書 11.3）'),
  loaded_at                          TIMESTAMP OPTIONS(description = 'BigQueryへのロード日時UTC'),
  pipeline_version                   STRING OPTIONS(description = '処理コードまたはモデルのバージョン'),
  PRIMARY KEY (target_date, slot_number, bg_code) NOT ENFORCED
)
PARTITION BY target_date
CLUSTER BY area_code, bg_code
OPTIONS (
  require_partition_filter = TRUE,
  description = 'agg_imbalance_daily'
);

-- T-03 コマ別集約マート
CREATE TABLE IF NOT EXISTS agg_slot_summary_active (
  target_date                        DATE NOT NULL OPTIONS(description = '対象日／コマ：Active は対象日から過去2年以内のみ'),
  slot_number                        INT64 NOT NULL OPTIONS(description = '対象日／コマ：Active は対象日から過去2年以内のみ'),
  area_code                          STRING NOT NULL OPTIONS(description = 'エリア／セグメント：低圧／高圧／特高／発電／蓄電池'),
  segment                            STRING NOT NULL OPTIONS(description = 'エリア／セグメント：低圧／高圧／特高／発電／蓄電池'),
  total_demand_kwh                   NUMERIC NOT NULL OPTIONS(description = '需要量（受電端／送電端）'),
  total_demand_sending_kwh           NUMERIC NOT NULL OPTIONS(description = '需要量（受電端／送電端）'),
  total_generation_kwh               NUMERIC NOT NULL OPTIONS(description = '発電量（送電端）'),
  jepx_spot_price                    NUMERIC NOT NULL OPTIONS(description = 'JEPXスポット価格：当該コマのエリアプライス（転記）'),
  imbalance_price                    NUMERIC NOT NULL OPTIONS(description = 'インバランス単価：転記'),
  total_revenue                      NUMERIC NOT NULL OPTIONS(description = '売上／原価／粗利：agg_daily_pnl をセグメントに集約'),
  total_procurement_cost             NUMERIC NOT NULL OPTIONS(description = '売上／原価／粗利：agg_daily_pnl をセグメントに集約'),
  total_gross_profit                 NUMERIC NOT NULL OPTIONS(description = '売上／原価／粗利：agg_daily_pnl をセグメントに集約'),
  ingestion_run_id                   STRING OPTIONS(description = 'パイプライン実行ID（命名・運用定義書 11.3）'),
  loaded_at                          TIMESTAMP OPTIONS(description = 'BigQueryへのロード日時UTC'),
  pipeline_version                   STRING OPTIONS(description = '処理コードまたはモデルのバージョン'),
  PRIMARY KEY (target_date, slot_number, area_code, segment) NOT ENFORCED
)
PARTITION BY target_date
CLUSTER BY area_code, segment
OPTIONS (
  require_partition_filter = TRUE, partition_expiration_days = 737,
  description = 'agg_slot_summary_active'
);

-- T-03b コマ別集約マート（Cold）：Active と同一スキーマ。2年超〜10年。B-13 が bq cp でパーティションコピーする
CREATE TABLE IF NOT EXISTS agg_slot_summary_cold (
  target_date                        DATE NOT NULL OPTIONS(description = '対象日／コマ：Active は対象日から過去2年以内のみ'),
  slot_number                        INT64 NOT NULL OPTIONS(description = '対象日／コマ：Active は対象日から過去2年以内のみ'),
  area_code                          STRING NOT NULL OPTIONS(description = 'エリア／セグメント：低圧／高圧／特高／発電／蓄電池'),
  segment                            STRING NOT NULL OPTIONS(description = 'エリア／セグメント：低圧／高圧／特高／発電／蓄電池'),
  total_demand_kwh                   NUMERIC NOT NULL OPTIONS(description = '需要量（受電端／送電端）'),
  total_demand_sending_kwh           NUMERIC NOT NULL OPTIONS(description = '需要量（受電端／送電端）'),
  total_generation_kwh               NUMERIC NOT NULL OPTIONS(description = '発電量（送電端）'),
  jepx_spot_price                    NUMERIC NOT NULL OPTIONS(description = 'JEPXスポット価格：当該コマのエリアプライス（転記）'),
  imbalance_price                    NUMERIC NOT NULL OPTIONS(description = 'インバランス単価：転記'),
  total_revenue                      NUMERIC NOT NULL OPTIONS(description = '売上／原価／粗利：agg_daily_pnl をセグメントに集約'),
  total_procurement_cost             NUMERIC NOT NULL OPTIONS(description = '売上／原価／粗利：agg_daily_pnl をセグメントに集約'),
  total_gross_profit                 NUMERIC NOT NULL OPTIONS(description = '売上／原価／粗利：agg_daily_pnl をセグメントに集約'),
  ingestion_run_id                   STRING OPTIONS(description = 'パイプライン実行ID（命名・運用定義書 11.3）'),
  loaded_at                          TIMESTAMP OPTIONS(description = 'BigQueryへのロード日時UTC'),
  pipeline_version                   STRING OPTIONS(description = '処理コードまたはモデルのバージョン'),
  PRIMARY KEY (target_date, slot_number, area_code, segment) NOT ENFORCED
)
PARTITION BY target_date
CLUSTER BY area_code, segment
OPTIONS (
  require_partition_filter = TRUE,
  description = 'agg_slot_summary_cold'
);

-- T-04 月次経営サマリ
CREATE TABLE IF NOT EXISTS agg_monthly_summary (
  target_month                       STRING NOT NULL OPTIONS(description = '対象年月：YYYYMM'),
  month_start_date                   DATE NOT NULL OPTIONS(description = '月初日：パーティション列。PARSE_DATE(\'%Y%m01\', target_month)'),
  area_code                          STRING NOT NULL OPTIONS(description = 'エリア／セグメント'),
  segment                            STRING NOT NULL OPTIONS(description = 'エリア／セグメント'),
  key_customer_id                    STRING NOT NULL OPTIONS(description = '主要顧客ID：上位N社は個別、その他は ALL_OTHER'),
  monthly_demand_kwh                 NUMERIC NOT NULL OPTIONS(description = '月間需要量／発電量：受電端／送電端'),
  monthly_generation_kwh             NUMERIC NOT NULL OPTIONS(description = '月間需要量／発電量：受電端／送電端'),
  monthly_revenue                    NUMERIC NOT NULL OPTIONS(description = '月間売上（税抜）：基本料金の確定値を含む。再エネ賦課金は monthly_levy_incl_tax を丸め・税抜化した値で算入する'),
  monthly_levy_incl_tax              NUMERIC NOT NULL OPTIONS(description = '月間再エネ賦課金（税込総額）：Σ rev_levy_incl_tax。請求システムの「税込月額」との突合値（10.7）'),
  monthly_levy_excl_tax              NUMERIC NOT NULL OPTIONS(description = '月間再エネ賦課金（税抜・丸め後）：monthly_levy_incl_tax に D-32 の丸めを適用してから ÷ (1+税率)'),
  monthly_procurement_cost           NUMERIC NOT NULL OPTIONS(description = '月間調達原価（税抜）'),
  fixed_fee_adjustment               NUMERIC NOT NULL OPTIONS(description = '定額手数料 確定差額：日次暫定合計との差（10.8.1）'),
  settlement_rounding_adjustment     NUMERIC NOT NULL OPTIONS(description = '請求丸め調整：D-32'),
  monthly_gross_profit               NUMERIC NOT NULL OPTIONS(description = '月間粗利（税抜）'),
  active_points_count                INT64 NOT NULL OPTIONS(description = '有効地点数：当月中に供給中だった地点数'),
  ingestion_run_id                   STRING OPTIONS(description = 'パイプライン実行ID（命名・運用定義書 11.3）'),
  loaded_at                          TIMESTAMP OPTIONS(description = 'BigQueryへのロード日時UTC'),
  pipeline_version                   STRING OPTIONS(description = '処理コードまたはモデルのバージョン'),
  PRIMARY KEY (target_month, area_code, segment, key_customer_id) NOT ENFORCED
)
PARTITION BY month_start_date
CLUSTER BY area_code, segment
OPTIONS (
  require_partition_filter = TRUE,
  description = 'agg_monthly_summary'
);

-- T-05 データ品質日次
CREATE TABLE IF NOT EXISTS agg_data_quality_daily (
  target_date                        DATE NOT NULL OPTIONS(description = '対象日／エリア／側：side＝発電／需要'),
  area_code                          STRING NOT NULL OPTIONS(description = '対象日／エリア／側：side＝発電／需要'),
  side                               STRING NOT NULL OPTIONS(description = '対象日／エリア／側：side＝発電／需要'),
  total_expected_slots               INT64 NOT NULL OPTIONS(description = '期待総コマ数：有効地点数 × 48'),
  missing_slots_count                INT64 NOT NULL OPTIONS(description = '欠番コマ数：13.1 の欠番検知'),
  cleansing_ratio                    NUMERIC NOT NULL OPTIONS(description = '補完率：(フラグ1〜4の和) ÷ 期待総コマ数。月次KPI'),
  null_rate_count                    INT64 NOT NULL OPTIONS(description = '単価NULL件数：検算 #3。公開可否のゲート'),
  energy_balance_diff_kwh            NUMERIC NOT NULL OPTIONS(description = '電力量突合差：検算 #1'),
  unresolved_area_count              INT64 NOT NULL OPTIONS(description = '未名寄せ件数：12.6 の検疫テーブルへ隔離した行数'),
  is_publishable                     BOOL NOT NULL OPTIONS(description = '日報公開可否：検算を全て通過し、抽出更新（14.10）へ流してよければ 1'),
  ingestion_run_id                   STRING OPTIONS(description = 'パイプライン実行ID（命名・運用定義書 11.3）'),
  loaded_at                          TIMESTAMP OPTIONS(description = 'BigQueryへのロード日時UTC'),
  pipeline_version                   STRING OPTIONS(description = '処理コードまたはモデルのバージョン'),
  PRIMARY KEY (target_date, area_code, side) NOT ENFORCED
)
PARTITION BY target_date
CLUSTER BY area_code, side
OPTIONS (
  require_partition_filter = TRUE,
  description = 'agg_data_quality_daily'
);

-- T-06 需要予測精度日次
CREATE TABLE IF NOT EXISTS agg_forecast_accuracy_daily (
  target_date                        DATE NOT NULL OPTIONS(description = '対象日／地点／モデルバージョン'),
  demand_point_number                STRING NOT NULL OPTIONS(description = '対象日／地点／モデルバージョン'),
  model_version                      STRING NOT NULL OPTIONS(description = '対象日／地点／モデルバージョン'),
  actual_kwh_sending_end             NUMERIC NOT NULL OPTIONS(description = '実績量（送電端）：日合計'),
  plan_kwh_sending_end               NUMERIC NOT NULL OPTIONS(description = '計画量（送電端）：前日提出（DA）の kW × 0.5 の日合計'),
  absolute_error_kwh                 NUMERIC NOT NULL OPTIONS(description = '絶対誤差：Σ'),
  mape                               NUMERIC NOT NULL OPTIONS(description = 'MAPE：コマ平均絶対パーセント誤差'),
  wape                               NUMERIC OPTIONS(description = 'WAPE：Σ'),
  bias_kwh                           NUMERIC NOT NULL OPTIONS(description = 'バイアス：Σ(実績 − 計画)。プラス＝過小予測、マイナス＝過大予測'),
  bias_ratio                         NUMERIC OPTIONS(description = 'バイアス率：bias_kwh ÷ plan_kwh_sending_end。地点規模に依らない登録漏れ判定に使う'),
  slots_evaluated                    INT64 NOT NULL OPTIONS(description = '評価コマ数：実績・計画が揃ったコマ数。48 未満なら計画欠損'),
  is_public_holiday                  BOOL NOT NULL OPTIONS(description = '休日属性：「公的休日＝0 かつ顧客休日＝0（登録なし）なのにバイアス率が大きなマイナス」なら顧客休日の登録漏れの疑い（15.4・Q-13）'),
  is_customer_holiday                BOOL NOT NULL OPTIONS(description = '休日属性：「公的休日＝0 かつ顧客休日＝0（登録なし）なのにバイアス率が大きなマイナス」なら顧客休日の登録漏れの疑い（15.4・Q-13）'),
  expected_load_ratio                NUMERIC OPTIONS(description = '想定稼働率：dim_account_holidays.expected_load_ratio（登録なしは 1.00）。予測モデルがこの値を織り込んでいたかの検証用'),
  snapshot_loaded_at                 TIMESTAMP NOT NULL OPTIONS(description = '生成日時'),
  ingestion_run_id                   STRING OPTIONS(description = 'パイプライン実行ID（命名・運用定義書 11.3）'),
  loaded_at                          TIMESTAMP OPTIONS(description = 'BigQueryへのロード日時UTC'),
  pipeline_version                   STRING OPTIONS(description = '処理コードまたはモデルのバージョン'),
  PRIMARY KEY (target_date, demand_point_number, model_version) NOT ENFORCED
)
PARTITION BY target_date
CLUSTER BY demand_point_number
OPTIONS (
  require_partition_filter = TRUE,
  description = 'agg_forecast_accuracy_daily'
);

-- T-08 BG月次精算
CREATE TABLE IF NOT EXISTS agg_bg_settlement_monthly (
  target_month                       STRING NOT NULL OPTIONS(description = '対象年月／BG／構成員'),
  bg_code                            STRING NOT NULL OPTIONS(description = '対象年月／BG／構成員'),
  bg_member_id                       STRING NOT NULL OPTIONS(description = '対象年月／BG／構成員'),
  month_start_date                   DATE OPTIONS(description = '月初日'),
  member_gross_imbalance_kwh         NUMERIC OPTIONS(description = '構成員インバランス量（絶対値合計）：I_i'),
  member_net_imbalance_kwh           NUMERIC OPTIONS(description = '構成員インバランス量（符号付き合計）'),
  causer_slot_count                  INT64 OPTIONS(description = '原因者コマ数'),
  bg_total_amount                    NUMERIC OPTIONS(description = 'BG全体精算額（月次）'),
  netting_benefit_amount             NUMERIC OPTIONS(description = '相殺効果（月次）'),
  allocated_amount                   NUMERIC OPTIONS(description = '按分額（月次）'),
  admin_fee_amount                   NUMERIC OPTIONS(description = '運営手数料'),
  cap_adjustment                     NUMERIC OPTIONS(description = '責任上限適用額'),
  invoice_reconciliation_amount      NUMERIC OPTIONS(description = '一送請求差額'),
  settlement_amount                  NUMERIC OPTIONS(description = '最終請求・還元額'),
  price_status                       STRING OPTIONS(description = '単価ステータス'),
  settlement_status                  STRING OPTIONS(description = '精算ステータス'),
  notified_amount                    NUMERIC OPTIONS(description = '代表者通知額（参照）'),
  variance_amount                    NUMERIC OPTIONS(description = '差異'),
  ingestion_run_id                   STRING OPTIONS(description = 'パイプライン実行ID（命名・運用定義書 11.3）'),
  loaded_at                          TIMESTAMP OPTIONS(description = 'BigQueryへのロード日時UTC'),
  pipeline_version                   STRING OPTIONS(description = '処理コードまたはモデルのバージョン'),
  PRIMARY KEY (target_month, bg_code, bg_member_id) NOT ENFORCED
)
PARTITION BY month_start_date
CLUSTER BY bg_code
OPTIONS (
  require_partition_filter = TRUE,
  description = 'agg_bg_settlement_monthly'
);

-- T-09 顧客休日スナップショット
CREATE TABLE IF NOT EXISTS snap_customer_holiday (
  target_date                        DATE NOT NULL OPTIONS(description = '対象日／地点'),
  demand_point_number                STRING NOT NULL OPTIONS(description = '対象日／地点'),
  customer_id                        STRING OPTIONS(description = '需要家ID／事業者ID：D-26 の account_id'),
  account_id                         STRING OPTIONS(description = '需要家ID／事業者ID：D-26 の account_id'),
  account_holiday_type               STRING NOT NULL OPTIONS(description = '休日区分：OBON／SHUTDOWN 等'),
  expected_load_ratio                NUMERIC NOT NULL OPTIONS(description = '想定稼働率：予測モデルが直接参照（例：0.15）'),
  snapshot_loaded_at                 TIMESTAMP NOT NULL OPTIONS(description = '書込日時：書き出した過去日は書き換えない（再現性）'),
  ingestion_run_id                   STRING OPTIONS(description = 'パイプライン実行ID（命名・運用定義書 11.3）'),
  loaded_at                          TIMESTAMP OPTIONS(description = 'BigQueryへのロード日時UTC'),
  pipeline_version                   STRING OPTIONS(description = '処理コードまたはモデルのバージョン'),
  PRIMARY KEY (target_date, demand_point_number) NOT ENFORCED
)
PARTITION BY target_date
CLUSTER BY demand_point_number
OPTIONS (
  require_partition_filter = TRUE,
  description = 'snap_customer_holiday'
);

