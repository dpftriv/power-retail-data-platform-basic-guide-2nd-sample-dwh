-- 電力小売データ分析基盤
-- procedure/p_calculate_bg_member_imbalance.sql
-- 正本：電力小売データ分析基盤.md（該当節の参照実装を抽出）
-- 注意：${GCP_PROJECT_ID} と ${BQ_DATASET_*} はテンプレート変数。CI/CD で環境別の値へ展開してから実行する
--       （命名・運用定義書 3.2）。未展開のまま実行してはならない。

-- 監査列（規約 18.1）：
--   p_run_id           … パイプライン実行ID。Workflows の execution ID 等、
--                        複数ジョブをまたいで一意な値をオーケストレータから渡す。
--                        BigQuery の job_id は補助的な追跡情報であり、この列には使わない。
--   p_pipeline_version … 処理コードの版。CI/CD がデプロイ時に注入した値
--                        （Git コミットSHA、リリースタグ等）を渡す。
--   loaded_at          … 各文の実行時刻（CURRENT_TIMESTAMP()、UTC）。
CREATE OR REPLACE PROCEDURE p_calculate_bg_member_imbalance(IN p_target_date DATE, IN p_run_id STRING, IN p_pipeline_version STRING)
BEGIN
  -- ─────────────────────────────────────────────
  -- STEP 1  地点 → 構成員：計画・実績を送電端に揃えてコマ×構成員で合算（10.3.1）
  -- ─────────────────────────────────────────────
  CREATE OR REPLACE TEMP TABLE tmp_member AS
  SELECT dem.target_date, dem.slot_number, mb.bg_code, dem.area_code, mb.bg_member_id,
         ANY_VALUE(mb.is_exempt)                                                          AS is_exempt,
         ANY_VALUE(mb.share_ratio)                                                        AS share_ratio,
         SUM(dem.actual_value_kwh / (1 - loss.loss_rate))                                 AS member_actual_kwh,   -- 受電端 → 送電端
         SUM(CASE plan.plan_basis
               WHEN 'SENDING_END'   THEN COALESCE(plan.forecast_value_kw, 0) * 0.5
               WHEN 'RECEIVING_END' THEN COALESCE(plan.forecast_value_kw, 0) * 0.5 / (1 - loss.loss_rate)
               ELSE 0 END)                                                                AS member_plan_kwh
  FROM fact_dem_actuals_daily dem
  JOIN dim_dem_customers cust      ON dem.demand_point_number = cust.demand_point_number
  JOIN dim_account pt             ON cust.account_id = pt.account_id
  JOIN dim_customer_contracts c    ON cust.customer_id = c.customer_id
                                AND dem.target_date BETWEEN c.start_date AND c.end_date
  JOIN dim_bg_members mb           ON c.dem_bg_code = mb.bg_code
                                -- 地点と構成員は取引先ID で紐付ける（13.1 ⑨ 網羅）。
                                -- 個人需要家（entity_type='INDIVIDUAL'）は BG 構成員にならないため、
                                -- 自社（ACCOUNT_SELF）が代表する需要として按分する（13.1 ⑯）
                                AND mb.account_id = IF(pt.entity_type = 'INDIVIDUAL', 'ACCOUNT_SELF', cust.account_id)
                                AND dem.target_date BETWEEN mb.start_date AND mb.end_date
  JOIN dim_loss_rates loss         ON dem.area_code = loss.area_code AND cust.voltage_class = loss.voltage_class
                                AND dem.target_date BETWEEN loss.start_date AND loss.end_date
  LEFT JOIN (                                                                                -- GC 時点（ID）の最新版計画
      SELECT demand_point_number, target_date, slot_number, forecast_value_kw, plan_basis   -- FT-02 の列名は forecast_value_kw
      FROM fact_dem_plans
      WHERE target_date = p_target_date AND plan_type = 'ID'
      QUALIFY ROW_NUMBER() OVER (PARTITION BY demand_point_number, slot_number ORDER BY plan_version DESC) = 1
  ) plan                         ON dem.demand_point_number = plan.demand_point_number
                                AND dem.target_date = plan.target_date AND dem.slot_number = plan.slot_number
  WHERE dem.target_date = p_target_date
  GROUP BY 1, 2, 3, 4, 5;

  -- ─────────────────────────────────────────────
  -- STEP 2  BG 集計（I_bg, Σ|I_j|, 原因者側 Σ|I_j|, 有効構成員数）
  -- ─────────────────────────────────────────────
  CREATE OR REPLACE TEMP TABLE tmp_bg AS
  SELECT target_date, slot_number, bg_code, area_code,
         SUM(member_actual_kwh - member_plan_kwh)                                         AS bg_net_imbalance_kwh,
         SUM(CASE WHEN NOT is_exempt THEN ABS(member_actual_kwh - member_plan_kwh) END)   AS bg_gross_abs_kwh,
         SUM(CASE WHEN NOT is_exempt
                   AND SIGN(member_actual_kwh - member_plan_kwh)
                       = SIGN(SUM(member_actual_kwh - member_plan_kwh) OVER (PARTITION BY target_date, slot_number, bg_code))
                  THEN ABS(member_actual_kwh - member_plan_kwh) END)                      AS causer_abs_kwh,
         COUNTIF(NOT is_exempt)                                                           AS active_member_count
  FROM tmp_member
  GROUP BY 1, 2, 3, 4;

  -- ─────────────────────────────────────────────
  -- STEP 3  暫定按分額（方式は dim_balancing_groups.allocation_method）
  -- ─────────────────────────────────────────────
  CREATE OR REPLACE TEMP TABLE tmp_alloc AS
  SELECT m.*,
         m.member_actual_kwh - m.member_plan_kwh                                          AS member_imbalance_kwh,
         b.bg_net_imbalance_kwh, b.bg_gross_abs_kwh, b.causer_abs_kwh, b.active_member_count,
         p.imbalance_price, p.price_status,
         b.bg_net_imbalance_kwh * p.imbalance_price                                       AS bg_total_amount,
         bg.allocation_method,
         CASE WHEN SIGN(m.member_actual_kwh - m.member_plan_kwh) = SIGN(b.bg_net_imbalance_kwh) THEN 1 ELSE 0 END AS is_causer,
         CASE
           WHEN m.is_exempt THEN 'EXEMPT'
           WHEN bg.allocation_method = 'INDIVIDUAL'  THEN 'INDIVIDUAL'
           WHEN bg.allocation_method = 'FIXED_SHARE' THEN 'FIXED_SHARE'
           WHEN bg.allocation_method = 'CAUSER_PAYS' AND COALESCE(b.causer_abs_kwh, 0) > 0  THEN 'CAUSER_PAYS'
           WHEN COALESCE(b.bg_gross_abs_kwh, 0) > 0  THEN 'SIMPLE_RATIO'
           ELSE 'EQUAL_SPLIT'                                                              -- Σ|I_j| = 0：均等按分（0 除算回避）
         END AS method_applied
  FROM tmp_member m
  JOIN tmp_bg b              USING (target_date, slot_number, bg_code, area_code)
  JOIN dim_balancing_groups bg ON m.bg_code = bg.bg_code AND m.target_date BETWEEN bg.start_date AND bg.end_date
  JOIN fact_imbalance_prices p  ON m.target_date = p.target_date AND m.slot_number = p.slot_number AND m.area_code = p.area_code;

  -- ─────────────────────────────────────────────
  -- STEP 4  べき等：対象日パーティションを削除して再作成
  -- ─────────────────────────────────────────────
  DELETE FROM fact_bg_member_imbalance WHERE target_date = p_target_date;

  -- ─────────────────────────────────────────────
  -- STEP 5  端数調整（Σ A_i = C_bg を1円単位で成立）と INSERT
  -- ─────────────────────────────────────────────
  INSERT INTO fact_bg_member_imbalance (
    target_date, slot_number, bg_code, bg_member_id, area_code,
    member_plan_kwh, member_actual_kwh, member_imbalance_kwh, bg_net_imbalance_kwh, is_causer,
    imbalance_price, price_status, bg_total_amount,
    allocation_method_applied, allocated_amount_raw, allocated_amount, rounding_adjustment, calculated_at, ingestion_run_id, loaded_at, pipeline_version)
  WITH raw AS (
    SELECT *,
      CASE method_applied
        WHEN 'EXEMPT'       THEN 0
        WHEN 'INDIVIDUAL'   THEN -member_imbalance_kwh * imbalance_price                             -- ④ A_i = −I_i × P
        WHEN 'FIXED_SHARE'  THEN bg_total_amount * share_ratio                                        -- ② A_i = C_bg × share_i
        WHEN 'CAUSER_PAYS'  THEN CASE WHEN is_causer
                                      THEN bg_total_amount * SAFE_DIVIDE(ABS(member_imbalance_kwh), causer_abs_kwh) ELSE 0 END  -- ③
        WHEN 'SIMPLE_RATIO' THEN bg_total_amount * SAFE_DIVIDE(ABS(member_imbalance_kwh), bg_gross_abs_kwh)              -- ①
        ELSE                     SAFE_DIVIDE(bg_total_amount, active_member_count)                     -- 均等
      END AS raw_amount
    FROM tmp_alloc
  ),
  ranked AS (
    SELECT *,
      ROUND(raw_amount, 0) AS rounded_amount,
      bg_total_amount - SUM(ROUND(raw_amount, 0)) OVER (PARTITION BY target_date, slot_number, bg_code) AS bg_delta,
      -- 端数の負担者：免責でない構成員のうち |I_i| 最大（規約が代表者負担なら member_role = 'REPRESENTATIVE' を先頭に）
      ROW_NUMBER() OVER (PARTITION BY target_date, slot_number, bg_code
                         ORDER BY is_exempt ASC, ABS(member_imbalance_kwh) DESC, bg_member_id) AS rnk
    FROM raw
  )
  SELECT target_date, slot_number, bg_code, bg_member_id, area_code,
         member_plan_kwh, member_actual_kwh, member_imbalance_kwh, bg_net_imbalance_kwh, is_causer,
         imbalance_price, price_status, bg_total_amount,
         method_applied                                                          AS allocation_method_applied,
         raw_amount                                                              AS allocated_amount_raw,
         CASE WHEN rnk = 1 THEN rounded_amount + bg_delta ELSE rounded_amount END AS allocated_amount,
         CASE WHEN rnk = 1 THEN bg_delta ELSE 0 END                               AS rounding_adjustment,
         CURRENT_TIMESTAMP()                                                      AS calculated_at,
         p_run_id, CURRENT_TIMESTAMP(), p_pipeline_version
  FROM ranked;

  -- 検算（13.1 ⑨ 合計一致）：一致しないコマがあれば中断
  IF EXISTS (
    SELECT 1 FROM fact_bg_member_imbalance
    WHERE target_date = p_target_date
    GROUP BY target_date, slot_number, bg_code
    HAVING ABS(SUM(allocated_amount) - ANY_VALUE(ROUND(bg_total_amount, 0))) > 0
  ) THEN
    RAISE USING MESSAGE = FORMAT('BG按分の合計不一致: %t', p_target_date);
  END IF;
END;
