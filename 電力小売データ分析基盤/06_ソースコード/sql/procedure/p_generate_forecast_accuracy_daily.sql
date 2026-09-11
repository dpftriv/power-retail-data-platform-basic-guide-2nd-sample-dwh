-- 電力小売データ分析基盤
-- procedure/p_generate_forecast_accuracy_daily.sql
-- 根拠：詳細設計書 第3部 6. 需要予測精度（MAPE／バイアス）自動監査ロジック仕様
-- 注意：${GCP_PROJECT_ID} と ${BQ_DATASET_*} はテンプレート変数。CI/CD で環境別の値へ展開してから実行する
--       （命名・運用定義書 3.2）。未展開のまま実行してはならない。

-- 監査列（規約 18.1）：
--   p_run_id           … パイプライン実行ID。Workflows の execution ID 等、
--                        複数ジョブをまたいで一意な値をオーケストレータから渡す。
--                        BigQuery の job_id は補助的な追跡情報であり、この列には使わない。
--   p_pipeline_version … 処理コードの版。CI/CD がデプロイ時に注入した値
--                        （Git コミットSHA、リリースタグ等）を渡す。
--   loaded_at          … 各文の実行時刻（CURRENT_TIMESTAMP()、UTC）。
CREATE OR REPLACE PROCEDURE p_generate_forecast_accuracy_daily(IN p_target_date DATE, IN p_run_id STRING, IN p_pipeline_version STRING)
BEGIN
  DELETE FROM agg_forecast_accuracy_daily WHERE target_date = p_target_date;   -- べき等（対象日パーティション）

  INSERT INTO agg_forecast_accuracy_daily (
    target_date, demand_point_number, model_version,
    actual_kwh_sending_end, plan_kwh_sending_end, absolute_error_kwh,
    mape, wape, bias_kwh, bias_ratio, slots_evaluated,
    is_public_holiday, is_customer_holiday, expected_load_ratio, snapshot_loaded_at, ingestion_run_id, loaded_at, pipeline_version)
  WITH
  da_plan AS (   -- 前日計画（DA）の最新版。SENDING_END を優先し、なければ RECEIVING_END
    SELECT demand_point_number, slot_number, forecast_value_kw, plan_basis, COALESCE(model_version, 'UNKNOWN') AS model_version
    FROM fact_dem_plans
    WHERE target_date = p_target_date AND plan_type = 'DA'
    QUALIFY ROW_NUMBER() OVER (PARTITION BY demand_point_number, slot_number
                               ORDER BY CASE plan_basis WHEN 'SENDING_END' THEN 0 ELSE 1 END, plan_version DESC) = 1
  ),
  slot_level AS (
    SELECT
      act.target_date, act.demand_point_number, plan.model_version, act.slot_number,
      act.actual_value_kwh / (1 - loss.loss_rate)                                   AS slot_actual_sending_kwh,   -- 10.2
      CASE plan.plan_basis
        WHEN 'SENDING_END'   THEN plan.forecast_value_kw * 0.5
        WHEN 'RECEIVING_END' THEN plan.forecast_value_kw * 0.5 / (1 - loss.loss_rate)
      END                                                                          AS slot_plan_sending_kwh,     -- 10.3.1 基準統一
      cal.is_public_holiday,
      CASE WHEN ch.account_holiday_date IS NOT NULL THEN 1 ELSE 0 END               AS is_customer_holiday,
      COALESCE(ch.expected_load_ratio, 1.0)                                        AS expected_load_ratio
    FROM fact_dem_actuals_daily act
    JOIN dim_dem_customers cust ON act.demand_point_number = cust.demand_point_number
    JOIN da_plan plan         ON act.demand_point_number = plan.demand_point_number AND act.slot_number = plan.slot_number
    JOIN dim_loss_rates loss    ON act.area_code = loss.area_code AND cust.voltage_class = loss.voltage_class
                             AND act.target_date BETWEEN loss.start_date AND loss.end_date
    JOIN dim_date_calendar cal  ON act.target_date = cal.target_date
    LEFT JOIN dim_account_holidays ch
                              ON cust.account_id = ch.account_id AND act.target_date = ch.account_holiday_date
                             AND (ch.demand_point_number IS NULL OR ch.demand_point_number = act.demand_point_number)
    WHERE act.target_date = p_target_date
      -- 実潮流でない値をモデルの実力評価に混ぜない（13.4）。
      --   6 = 一送の推定検針（通信障害等で一送が推定した確定値）
      --   7 = 試運転期間（発電側のみ。需要側には現れないが値域として除外しておく）
      AND act.cleansing_flag NOT IN (6, 7)
  ),
  daily AS (
    SELECT
      target_date, demand_point_number, model_version,
      SUM(slot_actual_sending_kwh)                                        AS actual_kwh_sending_end,
      SUM(slot_plan_sending_kwh)                                          AS plan_kwh_sending_end,
      SUM(ABS(slot_actual_sending_kwh - slot_plan_sending_kwh))           AS absolute_error_kwh,
      -- MAPE：実績 0 のコマは SAFE_DIVIDE → NULL となり AVG から除外される（参考指標）
      AVG(SAFE_DIVIDE(ABS(slot_actual_sending_kwh - slot_plan_sending_kwh), slot_actual_sending_kwh)) * 100 AS mape,
      -- WAPE：日合計で割るため実績 0 コマの影響を受けない（閾値判定の主指標）
      SAFE_DIVIDE(SUM(ABS(slot_actual_sending_kwh - slot_plan_sending_kwh)), SUM(slot_actual_sending_kwh)) * 100 AS wape,
      SUM(slot_actual_sending_kwh - slot_plan_sending_kwh)                AS bias_kwh,
      SAFE_DIVIDE(SUM(slot_actual_sending_kwh - slot_plan_sending_kwh), SUM(slot_plan_sending_kwh)) AS bias_ratio,
      COUNT(*)                                                            AS slots_evaluated,
      MAX(is_public_holiday)                                              AS is_public_holiday,
      MAX(is_customer_holiday)                                            AS is_customer_holiday,
      MIN(expected_load_ratio)                                            AS expected_load_ratio
    FROM slot_level
    GROUP BY 1, 2, 3
  )
  SELECT target_date, demand_point_number, model_version,
         actual_kwh_sending_end, plan_kwh_sending_end, absolute_error_kwh,
         mape, wape, bias_kwh, bias_ratio, slots_evaluated,
         is_public_holiday, is_customer_holiday, expected_load_ratio, CURRENT_TIMESTAMP(),
         p_run_id, CURRENT_TIMESTAMP(), p_pipeline_version
  FROM daily;
END;
