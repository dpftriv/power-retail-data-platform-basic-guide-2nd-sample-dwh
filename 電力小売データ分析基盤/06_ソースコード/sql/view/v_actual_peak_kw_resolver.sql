-- 電力小売データ分析基盤
-- view/v_actual_peak_kw_resolver.sql
-- 根拠：詳細設計書 第3部 5. 高圧実量制契約kW動的判定ロジック仕様
-- 注意：${GCP_PROJECT_ID} と ${BQ_DATASET_*} はテンプレート変数。CI/CD で環境別の値へ展開してから実行する
--       （命名・運用定義書 3.2）。未展開のまま実行してはならない。

CREATE OR REPLACE VIEW v_actual_peak_kw_resolver AS
WITH slot_kw_base AS (
  -- STEP 1：コマごとに、個別またはグループ単位で電力量を合算し kW 換算
  SELECT
    a.target_date, a.slot_number, cust.voltage_class,
    COALESCE(c.contract_group_id, a.demand_point_number) AS billing_unit_key,
    SUM(a.actual_value_kwh) * 2                          AS slot_kw,
    MIN(CASE WHEN a.data_status = '確定値' THEN 1 ELSE 0 END) AS all_settled
  FROM v_dem_actuals_timeline a                         -- 確定→確報→速報を1本化した Silver ビュー
  JOIN dim_dem_customers cust      ON a.demand_point_number = cust.demand_point_number
  JOIN dim_customer_contracts c    ON cust.customer_id = c.customer_id
                                AND a.target_date BETWEEN c.start_date AND c.end_date
  WHERE cust.is_actual_kw_based
  GROUP BY 1, 2, 3, 4
),
monthly_max_kw AS (
  -- STEP 2：月ごとの最高 kW（最大需要電力）。実績のある月にしか行が立たない
  SELECT
    EXTRACT(YEAR FROM target_date) * 12 + EXTRACT(MONTH FROM target_date) AS month_index,  -- 年跨ぎで連続する月番号
    billing_unit_key, voltage_class,
    MAX(slot_kw)          AS monthly_max_demand_kw,
    MIN(all_settled)      AS month_settled
  FROM slot_kw_base
  GROUP BY 1, 2, 3
),
unit_span AS (
  SELECT
    COALESCE(c.contract_group_id, cust.demand_point_number)                        AS billing_unit_key,
    ANY_VALUE(cust.voltage_class)                                                  AS voltage_class,
    EXTRACT(YEAR FROM MIN(c.start_date)) * 12 + EXTRACT(MONTH FROM MIN(c.start_date)) AS first_month_index,
    EXTRACT(YEAR FROM CURRENT_DATE('Asia/Tokyo')) * 12 + EXTRACT(MONTH FROM CURRENT_DATE('Asia/Tokyo')) AS last_month_index
  FROM dim_dem_customers cust
  JOIN dim_customer_contracts c ON cust.customer_id = c.customer_id
  WHERE cust.is_actual_kw_based
  GROUP BY 1
),
month_spine AS (
  -- 判定単位 × 暦月（欠損月も1行ずつ生成する）
  SELECT u.billing_unit_key, u.voltage_class, m AS month_index,
         FORMAT('%04d%02d', DIV(m - 1, 12), MOD(m - 1, 12) + 1) AS target_month
  FROM unit_span u, UNNEST(GENERATE_ARRAY(u.first_month_index, u.last_month_index)) AS m
),
filled AS (
  -- 骨格を左に置いて LEFT JOIN。実績のない月は monthly_max_demand_kw = NULL の行として存在させる
  SELECT s.target_month, s.month_index, s.billing_unit_key, s.voltage_class,
         k.monthly_max_demand_kw, k.month_settled,
         CASE WHEN k.month_index IS NULL THEN 1 ELSE 0 END AS is_missing_month
  FROM month_spine s
  LEFT JOIN monthly_max_kw k
    ON s.billing_unit_key = k.billing_unit_key AND s.month_index = k.month_index
)
-- STEP 3：当月を含む過去12ヶ月（暦月）の最大値を契約電力として判定（結合ではなくウィンドウで）
SELECT
  target_month, billing_unit_key, voltage_class,
  monthly_max_demand_kw                                   AS current_month_max_kw,   -- 欠損月は NULL
  MAX(monthly_max_demand_kw) OVER (
    PARTITION BY billing_unit_key
    ORDER BY month_index
    ROWS BETWEEN 11 PRECEDING AND CURRENT ROW)            AS resolved_contract_kw,   -- 骨格が暦月で連続しているので ROWS で12行＝12暦月。NULL は無視される
  COUNT(monthly_max_demand_kw) OVER (
    PARTITION BY billing_unit_key
    ORDER BY month_index
    ROWS BETWEEN 11 PRECEDING AND CURRENT ROW)            AS months_with_actuals,    -- 実績のある月数
  COUNT(*) OVER (
    PARTITION BY billing_unit_key
    ORDER BY month_index
    ROWS BETWEEN 11 PRECEDING AND CURRENT ROW)            AS months_since_contract,  -- 契約開始からの暦月数（12未満なら新規契約）
  SUM(is_missing_month) OVER (
    PARTITION BY billing_unit_key
    ORDER BY month_index
    ROWS BETWEEN 11 PRECEDING AND CURRENT ROW)            AS missing_months_in_window, -- 窓内の欠損月数（1以上ならアラート。13.2）
  CASE WHEN MIN(COALESCE(month_settled, 0)) OVER (
    PARTITION BY billing_unit_key
    ORDER BY month_index
    ROWS BETWEEN 11 PRECEDING AND CURRENT ROW) = 1 THEN 0 ELSE 1 END AS is_provisional   -- 欠損月は未確定扱い
FROM filled;
