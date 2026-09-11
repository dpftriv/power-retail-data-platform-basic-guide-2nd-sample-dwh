-- 電力小売データ分析基盤
-- view/v_market_linked_price_resolver.sql
-- 根拠：詳細設計書 第3部 4. 特約自動上書き解決および上下限クランプビューのロジック詳細仕様
-- 注意：${GCP_PROJECT_ID} と ${BQ_DATASET_*} はテンプレート変数。CI/CD で環境別の値へ展開してから実行する
--       （命名・運用定義書 3.2）。未展開のまま実行してはならない。

CREATE OR REPLACE VIEW v_market_linked_price_resolver AS
WITH scored AS (
  SELECT
    dem.target_date, dem.slot_number, dem.area_code, cust.demand_point_number, cust.customer_id, c.rate_menu_code,
    jepx.area_price AS jepx_spot_price, loss.loss_rate,
    CASE   -- D-11 託送従量単価（11.5 prepared と同一ロジック。holiday_day_rate_rule を含む）
      WHEN slot.jepx_time_class = '夜間'                                     THEN COALESCE(whl.variable_rate_night,       whl.demand_variable_rate)
      WHEN rh.is_rate_holiday AND whl.holiday_day_rate_rule = 'STANDARD' THEN whl.demand_variable_rate
      WHEN rh.is_rate_holiday AND cal.power_season = '夏季'              THEN COALESCE(whl.variable_rate_summer_day,  whl.demand_variable_rate)
      WHEN rh.is_rate_holiday AND cal.power_season = '冬季'              THEN COALESCE(whl.variable_rate_winter_day,  whl.demand_variable_rate)
      WHEN rh.is_rate_holiday                                            THEN whl.demand_variable_rate
      WHEN cal.power_season = '夏季' AND slot.is_peak                    THEN COALESCE(whl.variable_rate_summer_peak, whl.demand_variable_rate)
      WHEN cal.power_season = '夏季'                                         THEN COALESCE(whl.variable_rate_summer_day,  whl.demand_variable_rate)
      WHEN cal.power_season = '冬季'                                         THEN COALESCE(whl.variable_rate_winter_day,  whl.demand_variable_rate)
      ELSE whl.demand_variable_rate END AS applied_wheeling_variable_rate,
    p.param_id, p.scope_level, p.procurement_adj_rate, p.retail_margin_rate, p.operation_fee_rate,
    p.capacity_pass_through_rate, p.price_cap, p.price_floor,
    CASE p.scope_level WHEN 'POINT' THEN 1 WHEN 'CUSTOMER' THEN 2 ELSE 3 END AS priority_score
  FROM fact_dem_actuals_daily dem
  JOIN dim_dem_customers cust      ON dem.demand_point_number = cust.demand_point_number
  JOIN dim_customer_contracts c    ON cust.customer_id = c.customer_id AND dem.target_date BETWEEN c.start_date AND c.end_date
  JOIN dim_rate_menus menu         ON c.rate_menu_code = menu.rate_menu_code AND dem.target_date BETWEEN menu.start_date AND menu.end_date
  JOIN dim_date_calendar cal       ON dem.target_date = cal.target_date
  JOIN dim_slot_calendar slot      ON dem.slot_number = slot.slot_number
  JOIN v_rate_holiday_priority rh ON dem.target_date = rh.target_date
  JOIN dim_loss_rates loss         ON dem.area_code = loss.area_code AND cust.voltage_class = loss.voltage_class
                                AND dem.target_date BETWEEN loss.start_date AND loss.end_date
  JOIN dim_wheeling_rates whl      ON dem.area_code = whl.area_code AND cust.voltage_class = whl.voltage_class
                                AND dem.target_date BETWEEN whl.start_date AND whl.end_date
                                AND ((c.wheeling_menu_name IS NOT NULL AND whl.menu_name = c.wheeling_menu_name)
                                     OR (c.wheeling_menu_name IS NULL AND whl.is_default))
  JOIN fact_jepx_spot_prices jepx   ON dem.target_date = jepx.target_date AND dem.slot_number = jepx.slot_number AND dem.area_code = jepx.area_code
  JOIN dim_market_linked_parameters p
                                 ON c.rate_menu_code = p.rate_menu_code AND dem.area_code = p.area_code
                                AND (p.voltage_class IS NULL OR p.voltage_class = cust.voltage_class)     -- D-25 の電圧クラス（NULL＝全電圧）
                                AND dem.target_date BETWEEN p.start_date AND p.end_date
                                AND p.approved_by IS NOT NULL                                            -- 承認済み行のみ（10.4／13.1 ⑫）
                                AND (p.scope_level = 'MENU'
                                     OR (p.scope_level = 'CUSTOMER' AND p.customer_id = cust.customer_id)
                                     OR (p.scope_level = 'POINT'    AND p.demand_point_number = dem.demand_point_number))
  WHERE menu.is_market_linked
),
resolved AS (
  SELECT * FROM scored
  QUALIFY ROW_NUMBER() OVER (PARTITION BY target_date, slot_number, demand_point_number
                             ORDER BY priority_score, param_id DESC) = 1     -- 同順位は改定通番の新しい行（13.1 ⑫ で重複自体を禁止）
),
calc AS (
  SELECT *,
         jepx_spot_price / (1 - loss_rate) + applied_wheeling_variable_rate
           + COALESCE(procurement_adj_rate, 0) + COALESCE(retail_margin_rate, 0)
           + COALESCE(operation_fee_rate, 0) + COALESCE(capacity_pass_through_rate, 0)   AS raw_price
  FROM resolved
)
SELECT target_date, slot_number, area_code, demand_point_number, customer_id, rate_menu_code,
       param_id, scope_level, jepx_spot_price, applied_wheeling_variable_rate, raw_price,
       -- クランプ（NULL 安全：上限・下限が未設定なら生値をそのまま通す。LEAST/GREATEST は NULL を返すため CASE で分岐）
       CASE WHEN price_cap   IS NOT NULL AND raw_price > price_cap   THEN price_cap
            WHEN price_floor IS NOT NULL AND raw_price < price_floor THEN price_floor
            ELSE raw_price END                                                             AS final_market_linked_price,
       CASE WHEN price_cap   IS NOT NULL AND raw_price > price_cap   THEN 'CLAMPED_BY_CAP'
            WHEN price_floor IS NOT NULL AND raw_price < price_floor THEN 'CLAMPED_BY_FLOOR'
            ELSE 'RAW' END                                                                 AS clamp_status
FROM calc;
