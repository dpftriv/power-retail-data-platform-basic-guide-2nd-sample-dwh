-- 電力小売データ分析基盤
-- procedure/p_monitor_bi_extract_sync.sql
-- 根拠：詳細設計書 第4部 1. BI抽出同期・完了監視プロシージャのロジック詳細仕様
-- 注意：${GCP_PROJECT_ID} と ${BQ_DATASET_*} はテンプレート変数。CI/CD で環境別の値へ展開してから実行する
--       （命名・運用定義書 3.2）。未展開のまま実行してはならない。

-- 監査列（規約 18.1）：
--   p_run_id           … パイプライン実行ID。Workflows の execution ID 等、
--                        複数ジョブをまたいで一意な値をオーケストレータから渡す。
--                        BigQuery の job_id は補助的な追跡情報であり、この列には使わない。
--   p_pipeline_version … 処理コードの版。CI/CD がデプロイ時に注入した値
--                        （Git コミットSHA、リリースタグ等）を渡す。
--   loaded_at          … 各文の実行時刻（CURRENT_TIMESTAMP()、UTC）。
CREATE OR REPLACE PROCEDURE p_monitor_bi_extract_sync(IN p_target_date DATE, IN p_datasource_id STRING, IN p_run_id STRING, IN p_pipeline_version STRING)
BEGIN
  DECLARE v_all_verified   INT64;
  DECLARE v_batch_done_at  TIMESTAMP;
  DECLARE v_extract_jobs   INT64;

  -- 1) 品質ゲート：対象日の全行が検算通過
  SET v_all_verified = (SELECT COALESCE(MIN(is_verified), 0) FROM agg_daily_pnl WHERE target_date = p_target_date);
  SET v_batch_done_at = (SELECT MAX(finished_at) FROM fact_batch_run_log WHERE batch_id = 'B-05' AND target_date = p_target_date AND status = 'SUCCESS');

  IF v_all_verified = 0 OR v_batch_done_at IS NULL THEN
    MERGE agg_data_quality_daily t
    USING (SELECT p_target_date AS target_date, 'ALL' AS area_code, 'SYSTEM' AS side) s
    ON t.target_date = s.target_date AND t.area_code = s.area_code AND t.side = s.side
    WHEN MATCHED THEN UPDATE SET NOT is_publishable
    WHEN NOT MATCHED THEN INSERT (target_date, area_code, side, total_expected_slots, missing_slots_count,
                                  cleansed_flag_1_count, cleansed_flag_2_count, cleansed_flag_3_count, cleansed_flag_4_count,
                                  cleansing_ratio, null_rate_count, energy_balance_diff_kwh, unresolved_area_count, is_publishable)
                          VALUES (s.target_date, s.area_code, s.side, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, FALSE);
    SELECT 'BLOCKED_NOT_VERIFIED' AS status, p_target_date AS target_date;
    RETURN;
  END IF;

  -- 2) 抽出更新ジョブの検知（B-05 完了後に、対象データソースが抽出用ビューを読んで正常終了したジョブ）
  SET v_extract_jobs = (
    SELECT COUNT(*)
    FROM `region-asia-northeast1`.INFORMATION_SCHEMA.JOBS_BY_PROJECT j
    WHERE j.creation_time >= v_batch_done_at
      AND j.creation_time >= TIMESTAMP_SUB(CURRENT_TIMESTAMP(), INTERVAL 3 HOUR)   -- パーティション絞り込み（スキャン抑制）
      AND j.state = 'DONE' AND j.error_result IS NULL
      AND EXISTS (SELECT 1 FROM UNNEST(j.labels) l WHERE l.key = 'requestor' AND l.value = 'looker_studio')
      AND EXISTS (SELECT 1 FROM UNNEST(j.labels) l WHERE l.key = 'looker_studio_datasource_id' AND l.value = p_datasource_id)
      AND EXISTS (SELECT 1 FROM UNNEST(j.referenced_tables) r WHERE r.table_id = 'v_bi_daily_pnl_extract'));

  IF v_extract_jobs > 0 THEN
    MERGE agg_data_quality_daily t
    USING (SELECT p_target_date AS target_date, 'ALL' AS area_code, 'SYSTEM' AS side) s
    ON t.target_date = s.target_date AND t.area_code = s.area_code AND t.side = s.side
    WHEN MATCHED THEN UPDATE SET is_publishable
    WHEN NOT MATCHED THEN INSERT (target_date, area_code, side, total_expected_slots, missing_slots_count,
                                  cleansed_flag_1_count, cleansed_flag_2_count, cleansed_flag_3_count, cleansed_flag_4_count,
                                  cleansing_ratio, null_rate_count, energy_balance_diff_kwh, unresolved_area_count, is_publishable)
                          VALUES (s.target_date, s.area_code, s.side, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, TRUE);
    SELECT 'PUBLISHED' AS status, p_target_date AS target_date;
  ELSE
    SELECT 'EXTRACT_NOT_DETECTED' AS status, p_target_date AS target_date;   -- Composer がリトライ。6回目でもこの値ならアラート
  END IF;
END;
