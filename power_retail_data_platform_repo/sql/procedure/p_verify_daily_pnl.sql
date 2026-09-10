-- 電力小売データ分析基盤
-- procedure/p_verify_daily_pnl.sql
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
CREATE OR REPLACE PROCEDURE p_verify_daily_pnl(IN p_target_date DATE, IN p_run_id STRING, IN p_pipeline_version STRING)
BEGIN
  DECLARE v_balance_diff NUMERIC;
  DECLARE v_total_demand NUMERIC;
  DECLARE v_amount_errors INT64;
  DECLARE v_pk_dups INT64;
  DECLARE v_direction_errors INT64;
  DECLARE v_null_rate_rows INT64;
  DECLARE v_ok BOOL;

  -- #1 電力量突合（送電端）
  SET (v_total_demand, v_balance_diff) = (
    SELECT AS STRUCT
      SUM(demand_kwh_sending_end),
      SUM(demand_kwh_sending_end) - SUM(generation_kwh) - SUM(imbalance_kwh)
        - (SELECT COALESCE(SUM(CASE trade_side WHEN '買' THEN contracted_kwh ELSE -contracted_kwh END), 0)
           FROM fact_jepx_trades WHERE target_date = p_target_date)
    FROM agg_daily_pnl WHERE target_date = p_target_date);

  -- #2 金額整合（前段）
  SET v_amount_errors = (
    SELECT COUNT(*) FROM agg_daily_pnl
    WHERE target_date = p_target_date
      AND (ABS(revenue - (rev_energy + rev_fuel_adj + rev_levy + rev_base_est + rev_market_sales + rev_fip_premium + rev_balancing_premium)) > 0.000001
        OR ABS(procurement_cost - (cost_jepx_spot + cost_jepx_fee + cost_procurement_contract + cost_imbalance + cost_wheeling_variable
                                   + cost_wheeling_fixed_est + cost_capacity_contribution + cost_nonfossil_certificate + cost_gen_charge
                                   + cost_levy_passthrough + fixed_fee_provisional + fixed_fee_final)) > 0.000001
        OR ABS(gross_profit - (revenue - procurement_cost)) > 0.000001));
  SET v_pk_dups = (
    SELECT COUNT(*) FROM (
      SELECT 1 FROM agg_daily_pnl WHERE target_date = p_target_date
      GROUP BY target_date, slot_number, area_code, bg_code, direction, segment, menu_type HAVING COUNT(*) > 1));
  SET v_direction_errors = (
    SELECT COUNT(*) FROM agg_daily_pnl
    WHERE target_date = p_target_date
      AND NOT ((direction = 'INBOUND'  AND segment IN ('低圧','高圧','特高') AND menu_type IN ('固定単価','市場連動') AND generation_kwh = 0)
            OR (direction = 'OUTBOUND' AND segment = '発電' AND menu_type IN ('FIP','非FIP') AND demand_kwh = 0)
            OR (direction = 'STORAGE'  AND segment = '蓄電池')));

  -- #3 単価網羅（STEP 0 で停止しているはずだが、二重に確認）
  SET v_null_rate_rows = (
    SELECT COUNT(*) FROM agg_daily_pnl
    WHERE target_date = p_target_date AND direction = 'INBOUND'
      AND (JSON_VALUE(applied_rate_refs, '$.loss_ids[0]') IS NULL OR JSON_VALUE(applied_rate_refs, '$.wheeling_ids[0]') IS NULL));

  SET v_ok = (ABS(v_balance_diff) <= v_total_demand * 0.001 AND v_amount_errors = 0 AND v_pk_dups = 0
              AND v_direction_errors = 0 AND v_null_rate_rows = 0);

  UPDATE agg_daily_pnl SET is_verified = v_ok WHERE target_date = p_target_date;

  MERGE agg_data_quality_daily t
  USING (SELECT p_target_date AS target_date, 'ALL' AS area_code, 'SYSTEM' AS side) s
  ON t.target_date = s.target_date AND t.area_code = s.area_code AND t.side = s.side
  WHEN MATCHED THEN UPDATE SET
    energy_balance_diff_kwh = v_balance_diff, null_rate_count = v_null_rate_rows,
    unresolved_area_count = v_amount_errors + v_pk_dups + v_direction_errors, is_publishable = v_ok
  WHEN NOT MATCHED THEN INSERT (target_date, area_code, side, total_expected_slots, missing_slots_count,
                                cleansed_flag_1_count, cleansed_flag_2_count, cleansed_flag_3_count, cleansed_flag_4_count,
                                cleansing_ratio, null_rate_count, energy_balance_diff_kwh, unresolved_area_count, is_publishable)
    VALUES (s.target_date, s.area_code, s.side, 0, 0, 0, 0, 0, 0, 0, v_null_rate_rows, v_balance_diff,
            v_amount_errors + v_pk_dups + v_direction_errors, v_ok);

  INSERT INTO fact_batch_run_log (run_id, batch_id, target_date, started_at, finished_at, status, result_status, message, ingestion_run_id, loaded_at, pipeline_version)
  VALUES (GENERATE_UUID(), 'B-05_VERIFY', p_target_date, CURRENT_TIMESTAMP(), CURRENT_TIMESTAMP(),
          'SUCCESS', IF(v_ok, 'VERIFIED', 'NOT_VERIFIED'),
          FORMAT('balance_diff=%t amount_err=%d pk_dup=%d dir_err=%d null_rate=%d', v_balance_diff, v_amount_errors, v_pk_dups, v_direction_errors, v_null_rate_rows), p_run_id, CURRENT_TIMESTAMP(), p_pipeline_version);
END;
