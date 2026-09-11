-- 電力小売データ分析基盤
-- procedure/p_validate_and_gate_customer_contracts.sql
-- 根拠：詳細設計書 第1部 4. マスタデータ移行（データクレンジング）手順
-- 注意：${GCP_PROJECT_ID} と ${BQ_DATASET_*} はテンプレート変数。CI/CD で環境別の値へ展開してから実行する
--       （命名・運用定義書 3.2）。未展開のまま実行してはならない。

-- 監査列（規約 18.1）：
--   p_run_id           … パイプライン実行ID。Workflows の execution ID 等、
--                        複数ジョブをまたいで一意な値をオーケストレータから渡す。
--                        BigQuery の job_id は補助的な追跡情報であり、この列には使わない。
--   p_pipeline_version … 処理コードの版。CI/CD がデプロイ時に注入した値
--                        （Git コミットSHA、リリースタグ等）を渡す。
--   loaded_at          … 各文の実行時刻（CURRENT_TIMESTAMP()、UTC）。
CREATE OR REPLACE PROCEDURE p_validate_and_gate_customer_contracts(IN p_batch_id STRING, IN p_run_id STRING, IN p_pipeline_version STRING)
BEGIN
  DECLARE v_error_count INT64 DEFAULT 0;
  DECLARE v_alert_msg   STRING;
  DECLARE v_run_id      STRING DEFAULT GENERATE_UUID();
  DECLARE v_started_at  TIMESTAMP DEFAULT CURRENT_TIMESTAMP();

  CREATE OR REPLACE TEMP TABLE tmp_contract_validation_errors AS
  WITH src AS (
    SELECT s.*, cust.voltage_class, cust.is_actual_kw_based, cust.area_code AS cust_area_code
    FROM `${GCP_PROJECT_ID}.${BQ_DATASET_STAGING}.migration_customer_contracts` s
    LEFT JOIN dim_dem_customers cust ON s.customer_id = cust.customer_id
    WHERE s.batch_id = p_batch_id
  ),
  sorted AS (
    SELECT *,
           LEAD(start_date)          OVER (PARTITION BY customer_id ORDER BY start_date, contract_history_id) AS next_start_date,
           LEAD(contract_history_id) OVER (PARTITION BY customer_id ORDER BY start_date, contract_history_id) AS next_contract_history_id
    FROM src
  ),
  flagged AS (
    SELECT customer_id, contract_history_id, start_date, end_date, next_contract_history_id, next_start_date,
      CASE
        WHEN start_date > end_date                                                                       THEN 'ERR_DATE_INVERSION_START_AFTER_END'
        WHEN next_start_date IS NOT NULL AND next_start_date <= end_date                                  THEN 'ERR_SCD2_OVERLAP_DETECTED'
        WHEN end_date <> DATE '9999-12-31' AND next_start_date IS NOT NULL
             AND DATE_ADD(end_date, INTERVAL 1 DAY) <> next_start_date                                    THEN 'ERR_SCD2_GAP_DETECTED'
        WHEN contract_status = '解約' AND end_date = DATE '9999-12-31'                                    THEN 'ERR_TERMINATED_BUT_OPEN'
        WHEN contract_status = '供給中' AND end_date <> DATE '9999-12-31' AND next_start_date IS NULL      THEN 'ERR_ACTIVE_BUT_CLOSED'
        WHEN (contract_kw IS NULL) = (contract_ampere IS NULL)                                            THEN 'ERR_KW_AMPERE_EXCLUSIVITY'      -- 13.1 ⑭
        WHEN contract_ampere IS NOT NULL AND (voltage_class <> '低圧' OR is_actual_kw_based)          THEN 'ERR_AMPERE_ONLY_FOR_LOW_VOLTAGE' -- 13.1 ⑭
        WHEN procurement_contract_id IS NOT NULL AND NOT EXISTS (                                         -- 13.1 ⑮
               SELECT 1 FROM dim_procurement_contracts pc
               WHERE pc.procurement_contract_id = sorted.procurement_contract_id
                 AND pc.area_code = sorted.cust_area_code
                 AND sorted.start_date BETWEEN pc.start_date AND pc.end_date)                              THEN 'ERR_PROCUREMENT_CONTRACT_INVALID'
        WHEN end_date <> DATE '9999-12-31' AND next_start_date IS NULL                                    THEN 'WARN_SCD2_NO_OPEN_RECORD'
        ELSE 'OK'
      END AS error_code
    FROM sorted
  )
  SELECT * FROM flagged WHERE error_code LIKE 'ERR_%';

  SET v_error_count = (SELECT COUNT(*) FROM tmp_contract_validation_errors);

  IF v_error_count > 0 THEN
    SET v_alert_msg = (
      SELECT FORMAT('【移行遮断】batch_id=%s：SCD2不整合 %d 件。例：需要家 %s / %s / 履歴 %s (%s〜%s) / 次履歴 %s (%s)',
                    p_batch_id, v_error_count, customer_id, error_code, contract_history_id,
                    CAST(start_date AS STRING), CAST(end_date AS STRING),
                    COALESCE(next_contract_history_id, '-'), COALESCE(CAST(next_start_date AS STRING), '-'))
      FROM tmp_contract_validation_errors LIMIT 1);
    -- 例外の前に実行ログへ FAILED を記録（RAISE 後の文は実行されない）
    INSERT INTO fact_batch_run_log (run_id, batch_id, target_date, started_at, finished_at, status, result_status, message, ingestion_run_id, loaded_at, pipeline_version)
  VALUES (v_run_id, 'B-09_VAL', CURRENT_DATE('Asia/Tokyo'), v_started_at, CURRENT_TIMESTAMP(), 'FAILED', 'REJECTED_BY_QUALITY_GATE', v_alert_msg, p_run_id, CURRENT_TIMESTAMP(), p_pipeline_version);
    RAISE USING MESSAGE = v_alert_msg;
  END IF;

  INSERT INTO fact_batch_run_log (run_id, batch_id, target_date, started_at, finished_at, status, result_status, message, ingestion_run_id, loaded_at, pipeline_version)
  VALUES (v_run_id, 'B-09_VAL', CURRENT_DATE('Asia/Tokyo'), v_started_at, CURRENT_TIMESTAMP(), 'SUCCESS', 'PASSED',
          FORMAT('batch_id=%s のSCD2検証を通過', p_batch_id), p_run_id, CURRENT_TIMESTAMP(), p_pipeline_version);
END;
