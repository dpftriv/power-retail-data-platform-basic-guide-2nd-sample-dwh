-- 電力小売データ分析基盤
-- procedure/p_execute_load_profile_allocation.sql
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
CREATE OR REPLACE PROCEDURE p_execute_load_profile_allocation(IN p_billing_month STRING, IN p_run_id STRING, IN p_pipeline_version STRING)   -- 例 '202605'
BEGIN
  DECLARE v_run_id STRING DEFAULT GENERATE_UUID();
  DECLARE v_started_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP();
  DECLARE v_points INT64;

  -- 1) 前提：対象月に有効なプロファイルが存在する
  IF NOT EXISTS (SELECT 1 FROM dim_load_profiles
                 WHERE PARSE_DATE('%Y%m%d', p_billing_month || '01') BETWEEN start_date AND end_date) THEN
    INSERT INTO fact_batch_run_log (run_id, batch_id, target_date, started_at, finished_at, status, result_status, message, ingestion_run_id, loaded_at, pipeline_version)
  VALUES (v_run_id, 'B-04b', NULL, v_started_at, CURRENT_TIMESTAMP(), 'FAILED', 'NO_PROFILE',
            FORMAT('請求月 %s の標準負荷プロファイル（D-36）が未登録', p_billing_month), p_run_id, CURRENT_TIMESTAMP(), p_pipeline_version);
    RAISE USING MESSAGE = FORMAT('【B-04b 中断】請求月 %s の D-36 未登録', p_billing_month);
  END IF;

  -- 2) 日付骨格：電力季節と曜日区分（曜日区分は一送の託送用休日ルールで判定。自社の約款休日は使わない）
  CREATE OR REPLACE TEMP TABLE tmp_spine AS
  SELECT cal.target_date, cal.power_season,
         CASE WHEN cal.day_of_week IN ('Sat','Sun') OR pub.holiday_date IS NOT NULL
                   OR EXISTS (SELECT 1 FROM dim_account_holidays ch
                              WHERE ch.account_id = 'ACCOUNT_SELF' AND ch.account_holiday_date = cal.target_date
                                AND ch.applies_to_tariff AND ch.demand_point_number IS NULL)
              THEN '休日' ELSE '平日' END AS day_type
  FROM dim_date_calendar cal
  LEFT JOIN dim_public_holidays pub ON cal.target_date = pub.holiday_date AND pub.holiday_type <> 'REVOKED'
  WHERE cal.target_date BETWEEN DATE_SUB(PARSE_DATE('%Y%m%d', p_billing_month || '01'), INTERVAL 2 MONTH)
                            AND DATE_ADD(PARSE_DATE('%Y%m%d', p_billing_month || '01'), INTERVAL 1 MONTH);

  -- 3) 地点×請求月ごとの分母（検針期間内の全日×48コマの比率合計）と配分
  CREATE OR REPLACE TEMP TABLE tmp_alloc AS
  WITH base AS (
    SELECT mr.demand_point_number, mr.billing_month, mr.total_kwh, cust.area_code,
           d AS target_date, sp.power_season, sp.day_type, mrc.load_profile_code
    FROM fact_monthly_meter_readings mr
    JOIN dim_meter_reading_cycles mrc USING (demand_point_number, billing_month)
    JOIN dim_dem_customers cust       ON mr.demand_point_number = cust.demand_point_number
    CROSS JOIN UNNEST(GENERATE_DATE_ARRAY(mrc.period_start_date, mrc.period_end_date)) AS d
    JOIN tmp_spine sp ON sp.target_date = d
    WHERE mr.billing_month = p_billing_month AND mr.reading_type = 'VISIT'
  ),
  expanded AS (
    SELECT b.*, p.slot_number, p.ratio
    FROM base b
    JOIN dim_load_profiles p ON p.load_profile_code = b.load_profile_code
                          AND p.power_season = b.power_season AND p.day_type = b.day_type
                          AND b.target_date BETWEEN p.start_date AND p.end_date
    JOIN dim_areas a ON a.area_code = b.area_code AND p.area_code = a.area_code
  )
  SELECT demand_point_number, target_date, slot_number, area_code,
         total_kwh * SAFE_DIVIDE(ratio, SUM(ratio) OVER (PARTITION BY demand_point_number, billing_month)) AS actual_value_kwh
  FROM expanded;

  SET v_points = (SELECT COUNT(DISTINCT demand_point_number) FROM tmp_alloc);

  -- 4) 確報層へ UPSERT（べき等）。raw_value_kwh は「補完前のコマ値」が存在しないため NULL
  MERGE fact_dem_actuals_daily t
  USING tmp_alloc s
  ON t.demand_point_number = s.demand_point_number AND t.target_date = s.target_date AND t.slot_number = s.slot_number
  WHEN MATCHED THEN UPDATE SET actual_value_kwh = s.actual_value_kwh, raw_value_kwh = NULL, cleansing_flag = 5, updated_at = CURRENT_TIMESTAMP()
  WHEN NOT MATCHED THEN INSERT (demand_point_number, target_date, slot_number, area_code, actual_value_kwh, raw_value_kwh, cleansing_flag, data_status, updated_at)
    VALUES (s.demand_point_number, s.target_date, s.slot_number, s.area_code, s.actual_value_kwh, NULL, 5, '確報値', CURRENT_TIMESTAMP());

  INSERT INTO fact_batch_run_log (run_id, batch_id, target_date, started_at, finished_at, status, result_status, message, ingestion_run_id, loaded_at, pipeline_version)
  VALUES (v_run_id, 'B-04b', NULL, v_started_at, CURRENT_TIMESTAMP(), 'SUCCESS', 'PROFILED',
          FORMAT('請求月 %s：訪問検針 %d 地点を配分', p_billing_month, v_points), p_run_id, CURRENT_TIMESTAMP(), p_pipeline_version);
END;
