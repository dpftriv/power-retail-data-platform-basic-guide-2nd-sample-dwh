-- 電力小売データ分析基盤
-- procedure/p_generate_daily_pnl.sql
-- 根拠：詳細設計書 第3部 1. 日報損益マート生成コアバッチのロジック詳細仕様
-- 注意：${GCP_PROJECT_ID} と ${BQ_DATASET_*} はテンプレート変数。CI/CD で環境別の値へ展開してから実行する
--       （命名・運用定義書 3.2）。未展開のまま実行してはならない。

-- 監査列（規約 18.1）：
--   p_run_id           … パイプライン実行ID。Workflows の execution ID 等、
--                        複数ジョブをまたいで一意な値をオーケストレータから渡す。
--                        BigQuery の job_id は補助的な追跡情報であり、この列には使わない。
--   p_pipeline_version … 処理コードの版。CI/CD がデプロイ時に注入した値
--                        （Git コミットSHA、リリースタグ等）を渡す。
--   loaded_at          … 各文の実行時刻（CURRENT_TIMESTAMP()、UTC）。
CREATE OR REPLACE PROCEDURE p_generate_daily_pnl(IN p_target_date DATE, IN p_run_id STRING, IN p_pipeline_version STRING)
BEGIN
  DECLARE v_missing_slots INT64;
  DECLARE v_null_rates    INT64;

  -- ───────────────────────────────────────────────────────────
  -- STEP 0  前提チェック（NG なら中断し、中途半端な日報を出さない）
  -- ───────────────────────────────────────────────────────────
  -- 0-1 対象日の48コマが需要実績に揃っているか（地点ごと）
  SET v_missing_slots = (
    SELECT COUNT(*) FROM (
      SELECT demand_point_number, COUNT(DISTINCT slot_number) AS n
      FROM fact_dem_actuals_daily WHERE target_date = p_target_date
      GROUP BY demand_point_number HAVING n < 48));
  IF v_missing_slots > 0 THEN
    RAISE USING MESSAGE = FORMAT('欠番あり: %d 地点', v_missing_slots);
  END IF;

  -- 0-2 対象日の単価が全て引けるか（損失率・託送・JEPX・容量拠出金・賦課金・アンペア料金）
  SET v_null_rates = (
    SELECT COUNT(*)
    FROM fact_dem_actuals_daily dem
    JOIN dim_dem_customers cust USING (demand_point_number)
    LEFT JOIN dim_loss_rates loss
      ON dem.area_code = loss.area_code AND cust.voltage_class = loss.voltage_class
     AND dem.target_date BETWEEN loss.start_date AND loss.end_date
    LEFT JOIN dim_customer_contracts c0
      ON cust.customer_id = c0.customer_id AND dem.target_date BETWEEN c0.start_date AND c0.end_date
    LEFT JOIN dim_wheeling_rates whl
      ON dem.area_code = whl.area_code AND cust.voltage_class = whl.voltage_class
     AND dem.target_date BETWEEN whl.start_date AND whl.end_date
     AND ((c0.wheeling_menu_name IS NOT NULL AND whl.menu_name = c0.wheeling_menu_name)
          OR (c0.wheeling_menu_name IS NULL AND whl.is_default))
    LEFT JOIN fact_jepx_spot_prices jepx
      ON dem.target_date = jepx.target_date AND dem.slot_number = jepx.slot_number
     AND dem.area_code = jepx.area_code
    LEFT JOIN dim_capacity_contribution_rates cap
      ON dem.area_code = cap.area_code
     AND dem.target_date BETWEEN cap.start_date AND cap.end_date
    LEFT JOIN dim_meter_reading_cycles mrc
      ON dem.demand_point_number = mrc.demand_point_number
     AND dem.target_date BETWEEN mrc.period_start_date AND mrc.period_end_date
    LEFT JOIN dim_fit_levy_rates levy
      ON mrc.billing_month BETWEEN levy.start_billing_month AND levy.end_billing_month
    LEFT JOIN dim_ampere_rates amp
      ON c0.contract_ampere IS NOT NULL
     AND c0.rate_menu_code = amp.rate_menu_code AND dem.area_code = amp.area_code
     AND c0.contract_ampere = amp.ampere
     AND dem.target_date BETWEEN amp.start_date AND amp.end_date
    WHERE dem.target_date = p_target_date
      AND (loss.loss_rate IS NULL OR whl.demand_variable_rate IS NULL
           OR jepx.area_price IS NULL OR cap.capacity_kwh_rate IS NULL
           OR mrc.billing_month IS NULL OR levy.fit_levy_rate_incl_tax IS NULL
           OR (c0.contract_ampere IS NOT NULL AND amp.ampere_rate_id IS NULL)));
  IF v_null_rates > 0 THEN
    RAISE USING MESSAGE = FORMAT('単価NULL: %d 行', v_null_rates);
  END IF;

  -- ───────────────────────────────────────────────────────────
  -- STEP 1  べき等性：対象日パーティションを削除
  -- ───────────────────────────────────────────────────────────
  DELETE FROM agg_daily_pnl WHERE target_date = p_target_date;

  -- ───────────────────────────────────────────────────────────
  -- STEP 2  需要側：コマ別の売上・原価
  -- ───────────────────────────────────────────────────────────
  INSERT INTO agg_daily_pnl (
    target_date, slot_number, area_code, bg_code, direction, segment, menu_type,
    demand_kwh, demand_kwh_sending_end, generation_kwh, imbalance_kwh,
    revenue, rev_energy, rev_fuel_adj, rev_levy_incl_tax, rev_levy, rev_base_est,
    rev_market_sales, rev_fip_premium, rev_balancing_premium,
    procurement_cost, cost_jepx_spot, cost_jepx_fee, cost_procurement_contract, cost_imbalance,
    cost_wheeling_variable, cost_wheeling_fixed_est, cost_capacity_contribution, cost_nonfossil_certificate, cost_gen_charge, cost_levy_passthrough,
    fixed_fee_provisional, fixed_fee_final, settlement_rounding_adjustment,
    contribution_margin, gross_profit, margin_per_kwh, base_data_status, applied_rate_refs, is_verified,
    ingestion_run_id, loaded_at, pipeline_version)
  WITH
  -- 2-1 料金用休日（自社の約款休日を最優先、なければ土日祝）
  rate_holiday AS (
    SELECT c.target_date,
           CASE WHEN self_h.account_holiday_date IS NOT NULL THEN 1
                WHEN pub.holiday_date IS NOT NULL            THEN 1
                ELSE 0 END AS is_rate_holiday
    FROM dim_date_calendar c
    LEFT JOIN dim_account_holidays self_h
      ON c.target_date = self_h.account_holiday_date
     AND self_h.account_id = 'ACCOUNT_SELF'
     AND self_h.demand_point_number IS NULL
     AND self_h.applies_to_tariff
    LEFT JOIN dim_public_holidays pub ON c.target_date = pub.holiday_date
    WHERE c.target_date = p_target_date),

  -- 2-2 従量手数料（買）を対象日で1行に畳む
  fee_buy AS (
    SELECT SUM(unit_rate) AS fee_rate_kwh
    FROM dim_jepx_transaction_fees
    WHERE p_target_date BETWEEN start_date AND end_date
      AND market_type = 'スポット' AND charge_method = 'PER_KWH' AND trade_side = '買'),

  -- 2-3 定額手数料の暫定単価（前月実績 ÷ 前月総約定量。10.8.1）
  fee_fixed_provisional AS (
    SELECT SAFE_DIVIDE(
             (SELECT SUM(unit_rate) FROM dim_jepx_transaction_fees
               WHERE charge_method = 'FIXED_MONTHLY'
                 AND DATE_SUB(DATE_TRUNC(p_target_date, MONTH), INTERVAL 1 DAY) BETWEEN start_date AND end_date),
             (SELECT SUM(contracted_kwh) FROM fact_jepx_trades
               WHERE trade_side = '買'
                 AND target_date BETWEEN DATE_TRUNC(DATE_SUB(p_target_date, INTERVAL 1 MONTH), MONTH)
                                     AND DATE_SUB(DATE_TRUNC(p_target_date, MONTH), INTERVAL 1 DAY))
           ) AS fixed_fee_rate_kwh),

  -- 2-3b 基本料金の日割試算に使う「1コマあたり契約kW」（10.11 / 11.2 STEP 4）
  --      実量制は V-07 の当月値（暫定を含む）、それ以外は契約kW。グループ実量制は地点数で等分（確定按分は月次 B-08）
  base_fee_est AS (
    -- kW × 単価の計算をバイパスする。base_fee_est_slot_yen / wheeling_fixed_est_slot_yen は「1コマあたりの円」
    -- そのものを返し、kW契約は「1コマあたりkW」（kw_per_slot）のまま返して既存の menu.base_rate 乗算に載せる。
    SELECT cust.demand_point_number,
           c.contract_ampere,
           SAFE_DIVIDE(
             CASE WHEN cust.is_actual_kw_based THEN pk.resolved_contract_kw ELSE c.contract_kw END,
             COUNT(*) OVER (PARTITION BY COALESCE(c.contract_group_id, cust.demand_point_number))
               * EXTRACT(DAY FROM LAST_DAY(p_target_date)) * 48) AS kw_per_slot,
           SAFE_DIVIDE(CASE WHEN amp.tax_type = '税込' THEN amp.retail_base_rate / (1 + tx.tax_rate) ELSE amp.retail_base_rate END,   -- 税込公表値は Gold で未丸め税抜化
             COUNT(*) OVER (PARTITION BY COALESCE(c.contract_group_id, cust.demand_point_number))
               * EXTRACT(DAY FROM LAST_DAY(p_target_date)) * 48) AS ampere_retail_slot_yen,
           SAFE_DIVIDE(CASE WHEN amp.tax_type = '税込' THEN amp.wheeling_base_rate / (1 + tx.tax_rate) ELSE amp.wheeling_base_rate END,
             COUNT(*) OVER (PARTITION BY COALESCE(c.contract_group_id, cust.demand_point_number))
               * EXTRACT(DAY FROM LAST_DAY(p_target_date)) * 48) AS ampere_wheeling_slot_yen
    FROM dim_dem_customers cust
    JOIN dim_customer_contracts c ON cust.customer_id = c.customer_id
                               AND p_target_date BETWEEN c.start_date AND c.end_date
    LEFT JOIN v_actual_peak_kw_resolver pk
           ON pk.billing_unit_key = COALESCE(c.contract_group_id, cust.demand_point_number)
          AND pk.target_month     = FORMAT_DATE('%Y%m', p_target_date)
    LEFT JOIN dim_ampere_rates amp
           ON c.contract_ampere IS NOT NULL
          AND c.rate_menu_code = amp.rate_menu_code AND cust.area_code = amp.area_code
          AND c.contract_ampere = amp.ampere
          AND p_target_date BETWEEN amp.start_date AND amp.end_date
    LEFT JOIN dim_tax_rates tx ON p_target_date BETWEEN tx.start_date AND tx.end_date AND NOT tx.is_reduced),

  -- 2-3c 専属調達契約（Dedication）：専属先が設定された契約の精算額は、専属先の需要地点にのみ配分する（10.8.4）。
  --      prepared が参照するため、prepared より前に定義する
  dedicated_contracts AS (
    SELECT DISTINCT c.procurement_contract_id
    FROM dim_customer_contracts c
    WHERE c.procurement_contract_id IS NOT NULL AND p_target_date BETWEEN c.start_date AND c.end_date),
  dedicated_totals AS (   -- 専属契約ごとの配分先合計送電端需要量（コマ単位）
    SELECT c.procurement_contract_id, dem.slot_number,
           SUM(dem.actual_value_kwh / (1 - loss.loss_rate)) AS total_sending_kwh
    FROM dim_customer_contracts c
    JOIN dim_dem_customers cust    ON c.customer_id = cust.customer_id
    JOIN fact_dem_actuals_daily dem ON cust.demand_point_number = dem.demand_point_number AND dem.target_date = p_target_date
    JOIN dim_loss_rates loss       ON dem.area_code = loss.area_code AND cust.voltage_class = loss.voltage_class
                                 AND dem.target_date BETWEEN loss.start_date AND loss.end_date
    WHERE c.procurement_contract_id IS NOT NULL AND p_target_date BETWEEN c.start_date AND c.end_date
    GROUP BY 1,2),
  dedicated_alloc AS (     -- 需要地点ごとの専属契約按分額（コマ単位）
    SELECT cust.demand_point_number, dem.slot_number,
           (CASE WHEN ps.tax_type_received = '税込' THEN ps.settlement_amount / (1 + tx.tax_rate) ELSE ps.settlement_amount END)
             * SAFE_DIVIDE(dem.actual_value_kwh / (1 - loss.loss_rate), dt.total_sending_kwh)   AS dedicated_cost_slot
    FROM dim_customer_contracts c
    JOIN dim_dem_customers cust    ON c.customer_id = cust.customer_id
    JOIN fact_dem_actuals_daily dem ON cust.demand_point_number = dem.demand_point_number AND dem.target_date = p_target_date
    JOIN dim_loss_rates loss       ON dem.area_code = loss.area_code AND cust.voltage_class = loss.voltage_class
                                 AND dem.target_date BETWEEN loss.start_date AND loss.end_date
    JOIN fact_procurement_settlements ps ON ps.procurement_contract_id = c.procurement_contract_id
                                      AND ps.target_date = dem.target_date AND ps.slot_number = dem.slot_number
    JOIN dim_procurement_contracts pc   ON ps.procurement_contract_id = pc.procurement_contract_id
    JOIN dim_tax_rates tx               ON ps.target_date BETWEEN tx.start_date AND tx.end_date AND NOT tx.is_reduced
    JOIN dedicated_totals dt          ON dt.procurement_contract_id = c.procurement_contract_id AND dt.slot_number = dem.slot_number
    WHERE c.procurement_contract_id IS NOT NULL AND p_target_date BETWEEN c.start_date AND c.end_date),

  -- 2-4 需要実績に契約・単価・カレンダーを結合（全て対象日で期間解決）
  prepared AS (
    SELECT
      dem.target_date, dem.slot_number, dem.area_code,
      c.dem_bg_code                               AS bg_code,
      cust.voltage_class                          AS segment,
      menu.is_market_linked,
      dem.actual_value_kwh                        AS demand_kwh,
      dem.actual_value_kwh / (1 - loss.loss_rate) AS demand_kwh_sending_end,     -- 10.2
      levy.fit_levy_rate_incl_tax                 AS levy_rate_incl_tax,         -- 税込の公表単価のまま（D-14）検針月基準
      tax.tax_rate                                AS tax_rate,                   -- dim_tax_rates を対象日で解決
      CASE WHEN NOT menu.apply_fuel_adjustment THEN 0
           WHEN fuel.tax_type_published = '税込' THEN fuel.fuel_adj_rate / (1 + tax.tax_rate)   -- Gold で未丸め税抜化（1.5）
           ELSE fuel.fuel_adj_rate END               AS fuel_adj_rate,
      cap.capacity_kwh_rate,
      CASE WHEN menu.env_value_type = 'NONE' THEN 0 ELSE cert.unit_price END AS cert_rate,   -- 非化石証書単価（10.8.5）
      -- D-11 託送従量単価の動的解決（一律／季節別時間帯別の両対応）
      CASE
        WHEN slot.jepx_time_class = '夜間'                   THEN COALESCE(whl.variable_rate_night,       whl.demand_variable_rate)
        WHEN rh.is_rate_holiday AND whl.holiday_day_rate_rule = 'STANDARD' THEN whl.demand_variable_rate
        WHEN rh.is_rate_holiday AND cal.power_season = '夏季'              THEN COALESCE(whl.variable_rate_summer_day,  whl.demand_variable_rate)   -- SEASONAL
        WHEN rh.is_rate_holiday AND cal.power_season = '冬季'              THEN COALESCE(whl.variable_rate_winter_day,  whl.demand_variable_rate)
        WHEN rh.is_rate_holiday                                            THEN whl.demand_variable_rate
        WHEN cal.power_season = '夏季' AND slot.is_peak   THEN COALESCE(whl.variable_rate_summer_peak, whl.demand_variable_rate)
        WHEN cal.power_season = '夏季'                        THEN COALESCE(whl.variable_rate_summer_day,  whl.demand_variable_rate)
        WHEN cal.power_season = '冬季'                        THEN COALESCE(whl.variable_rate_winter_day,  whl.demand_variable_rate)
        ELSE                                                       whl.demand_variable_rate
      END                                         AS applied_wheeling_variable_rate,
      res.final_market_linked_price               AS market_linked_price,        -- V-09（特約解決・クランプ済み）
      -- 基本料金の日割試算：アンペア契約は dim_ampere_rates の固定額、それ以外は kW × 単価（10.11 でアンペア分岐追加）
      CASE WHEN bfe.contract_ampere IS NOT NULL THEN COALESCE(bfe.ampere_retail_slot_yen, 0)
           ELSE COALESCE(bfe.kw_per_slot, 0) * menu.base_rate END          AS base_fee_est_slot,
      CASE WHEN bfe.contract_ampere IS NOT NULL THEN COALESCE(bfe.ampere_wheeling_slot_yen, 0)
           ELSE COALESCE(bfe.kw_per_slot, 0) * whl.demand_fixed_rate END   AS wheeling_fixed_est_slot,
      -- 10.6 固定単価の分岐（rate_priority_rule で夜間／休日の優先を切替）
      CASE
        WHEN menu.rate_priority_rule = 'HOLIDAY_FIRST' AND rh.is_rate_holiday THEN menu.holiday_rate
        WHEN slot.jepx_time_class = '夜間'                                           THEN menu.night_rate
        WHEN rh.is_rate_holiday                                                 THEN menu.holiday_rate
        WHEN cal.power_season = '夏季' AND slot.is_peak                         THEN menu.weekday_summer_peak_rate
        WHEN cal.power_season = '夏季'                                              THEN menu.weekday_summer_day_rate
        ELSE                                                                             menu.weekday_day_rate
      END AS fixed_unit_price,
      menu.rate_menu_code, loss.loss_rate_id, whl.wheeling_rate_id, cap.capacity_rate_id, levy.levy_rate_id,
      COALESCE(ded.dedicated_cost_slot, 0)        AS dedicated_cost_slot      -- 専属調達契約の直接配賦（10.8.4）
    FROM fact_dem_actuals_daily dem
    JOIN dim_dem_customers cust      ON dem.demand_point_number = cust.demand_point_number
    JOIN dim_customer_contracts c    ON cust.customer_id = c.customer_id
                                  AND dem.target_date BETWEEN c.start_date AND c.end_date
    JOIN dim_rate_menus menu         ON c.rate_menu_code = menu.rate_menu_code
                                  AND dem.target_date BETWEEN menu.start_date AND menu.end_date
    JOIN dim_date_calendar cal       ON dem.target_date = cal.target_date
    JOIN dim_slot_calendar slot      ON dem.slot_number = slot.slot_number
    JOIN rate_holiday rh           ON dem.target_date = rh.target_date
    JOIN dim_loss_rates loss         ON dem.area_code = loss.area_code AND cust.voltage_class = loss.voltage_class
                                  AND dem.target_date BETWEEN loss.start_date AND loss.end_date
    JOIN dim_wheeling_rates whl      ON dem.area_code = whl.area_code AND cust.voltage_class = whl.voltage_class
                                  AND dem.target_date BETWEEN whl.start_date AND whl.end_date
                                  AND ((c.wheeling_menu_name IS NOT NULL AND whl.menu_name = c.wheeling_menu_name)
                                       OR (c.wheeling_menu_name IS NULL AND whl.is_default))
    JOIN dim_capacity_contribution_rates cap
                                   ON dem.area_code = cap.area_code
                                  AND dem.target_date BETWEEN cap.start_date AND cap.end_date
    JOIN dim_meter_reading_cycles mrc ON dem.demand_point_number = mrc.demand_point_number
                                  AND dem.target_date BETWEEN mrc.period_start_date AND mrc.period_end_date
    JOIN dim_fit_levy_rates levy     ON mrc.billing_month BETWEEN levy.start_billing_month AND levy.end_billing_month
    JOIN dim_tax_rates tax           ON dem.target_date BETWEEN tax.start_date AND tax.end_date AND NOT tax.is_reduced
    LEFT JOIN dim_nonfossil_certificate_prices cert
                                   ON cert.certificate_type = menu.env_value_type
                                  AND cert.fiscal_year = cal.fiscal_year
                                  AND dem.target_date BETWEEN cert.start_date AND cert.end_date
    LEFT JOIN dim_fuel_adjustments fuel
                                   ON dem.area_code = fuel.area_code AND cust.voltage_class = fuel.voltage_class
                                  AND FORMAT_DATE('%Y%m', dem.target_date) = fuel.target_month
    LEFT JOIN v_market_linked_price_resolver res
                                   ON dem.demand_point_number = res.demand_point_number
                                  AND dem.target_date = res.target_date AND dem.slot_number = res.slot_number   -- V-09（10.4.1）
    LEFT JOIN base_fee_est bfe     ON dem.demand_point_number = bfe.demand_point_number
    LEFT JOIN dedicated_alloc ded  ON dem.demand_point_number = ded.demand_point_number AND dem.slot_number = ded.slot_number
    -- 特約の優先解決とクランプは V-09 内で完結。この位置での追加処理は不要
    WHERE dem.target_date = p_target_date),

  -- 2-5 BG 単位の市場調達原価（約定明細から。10.8 / 10.8.1）。約定代金と従量手数料は別列に分ける
  bg_procurement AS (
    SELECT t.target_date, t.slot_number, t.area_code, t.bg_code,
           SUM(t.contracted_kwh)                       AS bought_kwh,
           SUM(t.contracted_amount)                    AS market_cost,
           SUM(t.transaction_fee + t.settlement_fee)   AS fee_cost
    FROM fact_jepx_trades t
    WHERE t.target_date = p_target_date AND t.trade_side = '買'
    GROUP BY 1,2,3,4),

  -- 2-6 BG 単位のインバランス精算額（10.3）
  bg_imbalance AS (
    SELECT target_date, slot_number, bg_code,
           SUM(net_imbalance_kwh) AS imbalance_kwh, SUM(imbalance_amount) AS imbalance_cost
    FROM agg_imbalance_daily WHERE target_date = p_target_date
    GROUP BY 1,2,3),

  -- 2-7 先物ヘッジのコマ割戻し（10.8.3：Base は全コマ、Peak は取引所営業日の 17〜40 のみ）
  futures_adj AS (
    SELECT p_target_date AS target_date, s.slot_number, pc.area_code,
           SUM(pc.contract_kw * 0.5 * (pc.contract_price - fp.settlement_price)
               * CASE WHEN pc.delivery_profile = 'ベース' THEN 1
                      WHEN pc.delivery_profile = 'ピーク'
                       AND s.fwd_product_type = 'Base_and_Peak'
                       AND fx_biz.is_business_day THEN 1
                      ELSE 0 END) AS futures_adjustment
    FROM dim_procurement_contracts pc
    JOIN dim_slot_calendar s ON TRUE
    JOIN fact_futures_prices fp
      ON fp.contract_month = FORMAT_DATE('%Y%m', p_target_date) AND fp.area_code = pc.area_code
     AND fp.product_type = CASE pc.delivery_profile WHEN 'ベース' THEN 'Base' ELSE 'Peak' END
     AND fp.trade_date = (SELECT MAX(trade_date) FROM fact_futures_prices WHERE trade_date <= p_target_date)
    JOIN (SELECT c.target_date,
                 CASE WHEN c.day_of_week IN ('Sat','Sun') THEN 0
                      WHEN pub.is_national_holiday THEN 0
                      WHEN d.is_treated_as_holiday THEN 0 ELSE 1 END AS is_business_day
          FROM dim_date_calendar c
          LEFT JOIN dim_public_holidays pub ON c.target_date = pub.holiday_date
          LEFT JOIN dim_holiday_rule_details d ON d.holiday_rule_code = 'FUTURES_PEAK'
                                             AND d.holiday_type = pub.holiday_type
          WHERE c.target_date = p_target_date) fx_biz ON TRUE
    WHERE pc.contract_type = '先物'
      AND p_target_date BETWEEN pc.start_date AND pc.end_date
    GROUP BY 1,2,3),

  -- 2-7b 相対・PPA の精算明細（10.8.4）。専属契約（2-3c）を除いた分をエリア単位で取り、送電端需要比で按分する
  --      バーチャルPPA は unit_price に差金が入っているため、市場原価と二重計上にならない
  bilateral AS (
    SELECT ps.target_date, ps.slot_number, ps.area_code,
           SUM(CASE WHEN ps.tax_type_received = '税込' THEN ps.settlement_amount / (1 + tx.tax_rate)   -- 受領値は Silver に税込のまま。Gold で未丸め税抜化（FX-09）
                    ELSE ps.settlement_amount END) AS bilateral_cost
    FROM fact_procurement_settlements ps
    JOIN dim_procurement_contracts pc ON ps.procurement_contract_id = pc.procurement_contract_id
    JOIN dim_tax_rates tx ON ps.target_date BETWEEN tx.start_date AND tx.end_date AND NOT tx.is_reduced
    WHERE ps.target_date = p_target_date
      AND ps.procurement_contract_id NOT IN (SELECT procurement_contract_id FROM dedicated_contracts)
    GROUP BY 1,2,3),

  -- 2-8 セグメント集計。売上・原価は費目ごとの総額で持ち、合成単価を作らない（1.5 計算順序）
  seg AS (
    SELECT target_date, slot_number, area_code, bg_code,
           'INBOUND' AS direction,                                                          -- T-01 主キー第5軸（流向：需要 ①）
           segment,
           CASE WHEN is_market_linked THEN '市場連動' ELSE '固定単価' END AS menu_type,
           SUM(demand_kwh)             AS demand_kwh,
           SUM(demand_kwh_sending_end) AS demand_kwh_sending_end,
           -- 10.7 売上（税抜）
           SUM(CASE WHEN is_market_linked THEN demand_kwh * market_linked_price
                    ELSE demand_kwh * fixed_unit_price END)                                 AS energy_revenue,
           SUM(CASE WHEN is_market_linked THEN 0 ELSE demand_kwh * fuel_adj_rate END)   AS fuel_adj_revenue,
           SUM(demand_kwh * levy_rate_incl_tax)                                              AS levy_incl_tax,  -- 税込総額（正の値。月次で丸め→税抜化。10.7 ⑥）
           SUM(demand_kwh * levy_rate_incl_tax / (1 + tax_rate))                             AS levy_revenue,   -- 税抜換算の日次参考値
           SUM(base_fee_est_slot)                                                            AS base_fee_revenue,
           -- 10.8 のうち需要量・契約kWに比例する原価
           SUM(demand_kwh * applied_wheeling_variable_rate)                                  AS wheeling_cost,  -- D-11 の時間帯別単価を解決済み
           SUM(wheeling_fixed_est_slot)                                                      AS wheeling_fixed_cost,
           SUM(demand_kwh * capacity_kwh_rate)                                               AS capacity_cost,
           SUM(demand_kwh * COALESCE(cert_rate, 0))                                          AS cert_cost,      -- 非化石証書（10.8.5）
           SUM(dedicated_cost_slot)                                                          AS dedicated_procurement_cost,  -- 専属調達契約（10.8.4）
           ANY_VALUE(fixed_fee_rate_kwh) AS fixed_fee_rate_kwh,
           TO_JSON_STRING(STRUCT(ARRAY_AGG(DISTINCT rate_menu_code) AS menus,
                                 ARRAY_AGG(DISTINCT loss_rate_id) AS loss_ids,
                                 ARRAY_AGG(DISTINCT wheeling_rate_id) AS wheeling_ids,
                                 ARRAY_AGG(DISTINCT capacity_rate_id) AS capacity_ids,
                                 ARRAY_AGG(DISTINCT levy_rate_id) AS levy_ids)) AS applied_rate_refs
    FROM prepared CROSS JOIN fee_fixed_provisional
    GROUP BY 1,2,3,4,5,6,7),

  bg_total AS (
    SELECT target_date, slot_number, area_code, bg_code,
           SUM(demand_kwh_sending_end) AS bg_sending_kwh
    FROM seg GROUP BY 1,2,3,4),

  area_total AS (
    SELECT target_date, slot_number, area_code,
           SUM(demand_kwh_sending_end) AS area_sending_kwh
    FROM seg GROUP BY 1,2,3),

  -- 2-9 BG 単位・エリア単位の原価を送電端需要比でセグメントへ按分し、費目別に確定
  costed AS (
    SELECT s.*,
           SAFE_DIVIDE(s.demand_kwh_sending_end, bt.bg_sending_kwh)   AS bg_share,
           COALESCE(bi.imbalance_kwh, 0)
             * SAFE_DIVIDE(s.demand_kwh_sending_end, bt.bg_sending_kwh)                        AS imbalance_kwh,
           COALESCE(bp.market_cost, 0)
             * SAFE_DIVIDE(s.demand_kwh_sending_end, bt.bg_sending_kwh)                        AS cost_jepx_spot,
           COALESCE(bp.fee_cost, 0)
             * SAFE_DIVIDE(s.demand_kwh_sending_end, bt.bg_sending_kwh)                        AS cost_jepx_fee,
           COALESCE(fa.futures_adjustment, 0)
             * SAFE_DIVIDE(s.demand_kwh_sending_end, bt.bg_sending_kwh)
           + COALESCE(bl.bilateral_cost, 0)
             * SAFE_DIVIDE(s.demand_kwh_sending_end, ar.area_sending_kwh)
           + s.dedicated_procurement_cost                                                      -- 専属調達契約：比率按分せず直接計上
                                                                                                 AS cost_procurement_contract,
           COALESCE(bi.imbalance_cost, 0)
             * SAFE_DIVIDE(s.demand_kwh_sending_end, bt.bg_sending_kwh)                        AS cost_imbalance,
           -- 定額手数料の暫定計上：当日の約定量（買）× 前月実績ベース暫定単価 を需要比で按分（10.8.1）
           COALESCE(bp.bought_kwh, 0) * COALESCE(s.fixed_fee_rate_kwh, 0)
             * SAFE_DIVIDE(s.demand_kwh_sending_end, bt.bg_sending_kwh)                        AS fixed_fee_provisional
    FROM seg s
    JOIN bg_total   bt USING (target_date, slot_number, area_code, bg_code)
    JOIN area_total ar USING (target_date, slot_number, area_code)
    LEFT JOIN bg_procurement bp USING (target_date, slot_number, area_code, bg_code)
    LEFT JOIN bg_imbalance   bi USING (target_date, slot_number, bg_code)
    LEFT JOIN futures_adj    fa USING (target_date, slot_number, area_code)
    LEFT JOIN bilateral      bl USING (target_date, slot_number, area_code))

  SELECT
    target_date, slot_number, area_code, bg_code, direction, segment, menu_type,
    demand_kwh, demand_kwh_sending_end,
    0                                                                                   AS generation_kwh,
    imbalance_kwh,
    -- 売上 ＝ 費目別総額の和（賦課金は税抜換算の参考値 levy_revenue を算入。精算は levy_incl_tax を使う）
    energy_revenue + fuel_adj_revenue + levy_revenue + base_fee_revenue                 AS revenue,
    energy_revenue, fuel_adj_revenue, levy_incl_tax, levy_revenue, base_fee_revenue,
    0, 0, 0,                                        -- rev_market_sales / rev_fip_premium / rev_balancing_premium は発電行のみ
    -- 調達原価 ＝ 費目別総額の和（10.8）
    cost_jepx_spot + cost_jepx_fee + cost_procurement_contract + cost_imbalance
      + wheeling_cost + wheeling_fixed_cost + capacity_cost + cert_cost + levy_revenue + fixed_fee_provisional   AS procurement_cost,
    cost_jepx_spot, cost_jepx_fee, cost_procurement_contract, cost_imbalance,
    wheeling_cost, wheeling_fixed_cost, capacity_cost, cert_cost,
    0                                                                                   AS cost_gen_charge,        -- 需要行は 0（発電側課金は発電行のみ）
    levy_revenue                                                                        AS cost_levy_passthrough,  -- 賦課金の納付原価（売上側 rev_levy と同額で相殺。10.14）
    fixed_fee_provisional,
    0                                                                                   AS fixed_fee_final,               -- 月次確定（B-08）で月末日行にのみ計上
    0                                                                                   AS settlement_rounding_adjustment,-- 同上（D-32）
    energy_revenue - (cost_jepx_spot + cost_jepx_fee + cost_procurement_contract)         AS contribution_margin,  -- 利益階層①（10.14）
    (energy_revenue + fuel_adj_revenue + levy_revenue + base_fee_revenue)
      - (cost_jepx_spot + cost_jepx_fee + cost_procurement_contract + cost_imbalance
         + wheeling_cost + wheeling_fixed_cost + capacity_cost + cert_cost + levy_revenue + fixed_fee_provisional) AS gross_profit,   -- 利益階層②＝③
    SAFE_DIVIDE(
      (energy_revenue + fuel_adj_revenue + base_fee_revenue)
      - (cost_jepx_spot + cost_jepx_fee + cost_procurement_contract + cost_imbalance
         + wheeling_cost + wheeling_fixed_cost + capacity_cost + cert_cost + fixed_fee_provisional),
      demand_kwh)                                                                         AS margin_per_kwh,       -- 賦課金は両側相殺のため含めない
    '確報値'                                                                            AS base_data_status,
    applied_rate_refs,
    FALSE                                                                               AS is_verified,
    p_run_id, CURRENT_TIMESTAMP(), p_pipeline_version
  FROM costed;

  -- ───────────────────────────────────────────────────────────
  -- STEP 3  発電側（FIP 含む）：コマ別の売上（10.9）
  -- ───────────────────────────────────────────────────────────
  INSERT INTO agg_daily_pnl (
    target_date, slot_number, area_code, bg_code, direction, segment, menu_type,
    demand_kwh, demand_kwh_sending_end, generation_kwh, imbalance_kwh,
    revenue, rev_energy, rev_fuel_adj, rev_levy_incl_tax, rev_levy, rev_base_est,
    rev_market_sales, rev_fip_premium, rev_balancing_premium,
    procurement_cost, cost_jepx_spot, cost_jepx_fee, cost_procurement_contract, cost_imbalance,
    cost_wheeling_variable, cost_wheeling_fixed_est, cost_capacity_contribution, cost_nonfossil_certificate, cost_gen_charge, cost_levy_passthrough,
    fixed_fee_provisional, fixed_fee_final, settlement_rounding_adjustment,
    contribution_margin, gross_profit, margin_per_kwh, base_data_status, applied_rate_refs, is_verified,
    ingestion_run_id, loaded_at, pipeline_version)
  WITH fee_sell AS (
    SELECT SUM(unit_rate) AS fee_rate_kwh FROM dim_jepx_transaction_fees
    WHERE p_target_date BETWEEN start_date AND end_date
      AND market_type = 'スポット' AND charge_method = 'PER_KWH' AND trade_side = '売'),
  trial AS (   -- 試運転判定（D-05）。試運転期間は売上計上区分で切り替え、FIP は商業運転開始日以降に限定
    SELECT gen_point_id, supply_point_number,
           (trial_start_date IS NOT NULL
            AND p_target_date >= trial_start_date
            AND (commercial_operation_date IS NULL OR p_target_date < commercial_operation_date)) AS is_trial,
           COALESCE(trial_revenue_treatment, 'EXCLUDE')                                            AS trial_revenue_treatment,
           (commercial_operation_date IS NOT NULL AND p_target_date >= commercial_operation_date)  AS is_commercial
    FROM dim_gen_supply_points
    WHERE p_target_date BETWEEN start_date AND end_date),
  a_value AS (   -- 確定A値があればそれ、なければ暫定（FX-05）
    SELECT fuel_code, area_code, reference_price
    FROM fact_fip_reference_prices
    WHERE target_month = FORMAT_DATE('%Y%m', p_target_date)
    QUALIFY ROW_NUMBER() OVER (PARTITION BY fuel_code, area_code
                               ORDER BY CASE value_status WHEN 'FINAL' THEN 0 ELSE 1 END) = 1)
  SELECT
    gen.target_date, gen.slot_number, gen.area_code, gp.gen_bg_code,
    'OUTBOUND' AS direction,                                                                        -- T-01 主キー第5軸（流向：発電 ①）
    '発電' AS segment,
    CASE WHEN gp.is_fip THEN 'FIP' ELSE '非FIP' END AS menu_type,
    0, 0, SUM(gen.actual_value_kwh), 0,
    -- 売上：市場売電（課税）＋ P値・バランシングコスト（不課税）。売り手数料は原価側（10.9）
    -- 試運転期間（D-05）：市場売電は trial_revenue_treatment で切替、FIP は商業運転開始日以降に限定
    SUM(CASE WHEN tr.is_trial AND tr.trial_revenue_treatment = 'EXCLUDE' THEN 0
             ELSE gen.actual_value_kwh * jepx.area_price END)
      + SUM(CASE WHEN gp.is_fip AND NOT tr.is_trial THEN gen.actual_value_kwh * GREATEST(0, gp.fip_f_price - av.reference_price) ELSE 0 END)
      + SUM(CASE WHEN gp.is_fip AND NOT tr.is_trial THEN gen.actual_value_kwh * COALESCE(bc.total_balancing_premium, 0) ELSE 0 END)   AS revenue,
    0, 0, 0, 0, 0,                                                                                  -- 需要側の内訳（rev_energy / rev_fuel_adj / rev_levy_incl_tax / rev_levy / rev_base_est）は 0
    SUM(CASE WHEN tr.is_trial AND tr.trial_revenue_treatment = 'EXCLUDE' THEN 0
             ELSE gen.actual_value_kwh * jepx.area_price END)                                       AS rev_market_sales,      -- マイナス価格のコマは負のまま
    SUM(CASE WHEN gp.is_fip AND NOT tr.is_trial THEN gen.actual_value_kwh * GREATEST(0, gp.fip_f_price - av.reference_price) ELSE 0 END) AS rev_fip_premium,
    SUM(CASE WHEN gp.is_fip AND NOT tr.is_trial THEN gen.actual_value_kwh * COALESCE(bc.total_balancing_premium, 0) ELSE 0 END)          AS rev_balancing_premium,
    -- 原価：売り手数料 ＋ 発電側課金（10.10）
    SUM(gen.actual_value_kwh * COALESCE(fs.fee_rate_kwh, 0))
      + IF(ANY_VALUE(gcd.gen_charge_start_basis) = 'GRID_CONNECTION' OR ANY_VALUE(tr.is_commercial),   -- 課金起算（D-34）
           SAFE_DIVIDE(ANY_VALUE(gp.contract_kw) * ANY_VALUE(whl_g.gen_charge_rate) * (1 - COALESCE(ANY_VALUE(gcd.discount_rate), 0)),
                       EXTRACT(DAY FROM LAST_DAY(gen.target_date)) * 48)
           + SUM(gen.actual_value_kwh * COALESCE(whl_g.gen_charge_kwh_rate, 0)), 0)                  AS procurement_cost,
    0, SUM(gen.actual_value_kwh * COALESCE(fs.fee_rate_kwh, 0)), 0, 0, 0, 0, 0, 0,     -- jepx_spot / jepx_fee / procurement_contract / imbalance / wheeling_variable / wheeling_fixed_est / capacity_contribution / nonfossil_certificate（発電行はいずれも0。cost_jepx_feeのみ非0）
    IF(ANY_VALUE(gcd.gen_charge_start_basis) = 'GRID_CONNECTION' OR ANY_VALUE(tr.is_commercial),
       SAFE_DIVIDE(ANY_VALUE(gp.contract_kw) * ANY_VALUE(whl_g.gen_charge_rate) * (1 - COALESCE(ANY_VALUE(gcd.discount_rate), 0)),
                   EXTRACT(DAY FROM LAST_DAY(gen.target_date)) * 48)
       + SUM(gen.actual_value_kwh * COALESCE(whl_g.gen_charge_kwh_rate, 0)), 0)                      AS cost_gen_charge,   -- 10.10・試運転期間は起算基準で切替
    0                                                                                               AS cost_levy_passthrough,
    0, 0, 0,
    SUM(CASE WHEN tr.is_trial AND tr.trial_revenue_treatment = 'EXCLUDE' THEN 0
             ELSE gen.actual_value_kwh * jepx.area_price END)
      - SUM(gen.actual_value_kwh * COALESCE(fs.fee_rate_kwh, 0))                                    AS contribution_margin,  -- 利益階層①（発電）：市場売電 − 売り手数料
    NULL, NULL, '確報値', NULL, FALSE,
    p_run_id, CURRENT_TIMESTAMP(), p_pipeline_version
  FROM fact_gen_actuals_daily gen
  JOIN dim_gen_supply_points gp ON gen.supply_point_number = gp.supply_point_number
                              AND gen.target_date BETWEEN gp.start_date AND gp.end_date
  JOIN trial tr               ON gp.supply_point_number = tr.supply_point_number
  JOIN dim_plants pl            ON gp.plant_id = pl.plant_id
  JOIN dim_date_calendar cal    ON gen.target_date = cal.target_date
  LEFT JOIN dim_wheeling_rates whl_g
                               ON gp.area_code = whl_g.area_code AND gp.voltage_class = whl_g.voltage_class
                              AND gen.target_date BETWEEN whl_g.start_date AND whl_g.end_date AND whl_g.is_default
  LEFT JOIN dim_gen_charge_discount_rates gcd
                               ON gp.area_code = gcd.area_code AND gp.gen_charge_type = gcd.gen_charge_type
                              AND gen.target_date BETWEEN gcd.start_date AND gcd.end_date
  JOIN fact_jepx_spot_prices jepx ON gen.target_date = jepx.target_date AND gen.slot_number = jepx.slot_number
                              AND gen.area_code = jepx.area_code
  LEFT JOIN a_value av        ON pl.fuel_code = av.fuel_code AND gen.area_code = av.area_code
  LEFT JOIN dim_fip_bg_privileges bc
                              ON bc.cert_fiscal_year = gp.fip_cert_fiscal_year
                             AND bc.delivery_fiscal_year = cal.fiscal_year
                             AND bc.fuel_code = pl.fuel_code AND bc.area_code = gen.area_code
  CROSS JOIN fee_sell fs
  WHERE gen.target_date = p_target_date
  GROUP BY 1,2,3,4,5,6,7;

  -- 粗利・限界利益を発電行に設定（行の種類は segment ではなく direction で判定する）
  UPDATE agg_daily_pnl SET gross_profit = revenue - procurement_cost,
                         margin_per_kwh = SAFE_DIVIDE(revenue - procurement_cost, generation_kwh)
  WHERE target_date = p_target_date AND direction = 'OUTBOUND';

  -- ───────────────────────────────────────────────────────────
  -- STEP 4  検算（11.3）→ agg_data_quality_daily。NG は要確認フラグ
  -- ───────────────────────────────────────────────────────────
  CALL p_verify_daily_pnl(p_target_date, p_run_id, p_pipeline_version);   -- 検算 #1〜#3 を実行し is_verified を更新

  -- ───────────────────────────────────────────────────────────
  -- STEP 5 ⭐ 蓄電・揚水（オプション。未導入時は省略）
  -- ───────────────────────────────────────────────────────────
  -- CALL p_generate_battery_pnl(p_target_date, p_run_id, p_pipeline_version);   -- 第16章（初期導入ではペンディング。導入時にコメント解除）

  -- ───────────────────────────────────────────────────────────
  -- STEP 6  集約マート（11.2 STEP 9）
  -- ───────────────────────────────────────────────────────────
  CALL p_generate_forecast_accuracy_daily(p_target_date, p_run_id, p_pipeline_version);   -- T-06
  -- CALL p_generate_slot_summary(p_target_date, p_run_id, p_pipeline_version);           -- T-03（別途）
END;
