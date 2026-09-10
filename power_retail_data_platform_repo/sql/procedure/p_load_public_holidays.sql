-- 電力小売データ分析基盤
-- procedure/p_load_public_holidays.sql
-- 正本：電力小売データ分析基盤.md（該当節の参照実装を抽出）
-- 注意：${GCP_PROJECT_ID} と ${BQ_DATASET_*} はテンプレート変数。CI/CD で環境別の値へ展開してから実行する
--       （命名・運用定義書 3.2）。未展開のまま実行してはならない。

-- Bronze：1行1レコードで無加工保持（GCS へステージングした CSV を外部テーブル／LOAD で取り込む前提）
CREATE TABLE IF NOT EXISTS holiday_csv_raw (
  raw_line   STRING,
  line_no    INT64,
  file_hash  STRING,
  loaded_at  TIMESTAMP DEFAULT CURRENT_TIMESTAMP()
);
CREATE TABLE IF NOT EXISTS holiday_csv_quarantine (
  raw_line   STRING, line_no INT64, file_hash STRING, reason STRING,
  loaded_at  TIMESTAMP DEFAULT CURRENT_TIMESTAMP()
);

-- 監査列（規約 18.1）：
--   p_run_id           … パイプライン実行ID。Workflows の execution ID 等、
--                        複数ジョブをまたいで一意な値をオーケストレータから渡す。
--                        BigQuery の job_id は補助的な追跡情報であり、この列には使わない。
--   p_pipeline_version … 処理コードの版。CI/CD がデプロイ時に注入した値
--                        （Git コミットSHA、リリースタグ等）を渡す。
--   loaded_at          … 各文の実行時刻（CURRENT_TIMESTAMP()、UTC）。
CREATE OR REPLACE PROCEDURE p_load_public_holidays(IN p_file_hash STRING, IN p_run_id STRING, IN p_pipeline_version STRING)
BEGIN
  DECLARE v_parsed_rows      INT64;
  DECLARE v_quarantine_rows  INT64;
  DECLARE v_prev_rows        INT64;
  DECLARE v_has_this_year    INT64;
  DECLARE v_has_next_year    INT64;
  DECLARE v_dup_rows         INT64;
  DECLARE v_min_ratio        NUMERIC DEFAULT 0.9;   -- 設定値 HOLIDAY_CSV_MIN_ROW_RATIO

  -- 1) パース（失敗行は NULL のまま残す）
  CREATE OR REPLACE TEMP TABLE tmp_parsed AS
  WITH split AS (
    SELECT line_no, raw_line,
           TRIM(SPLIT(raw_line, ',')[SAFE_OFFSET(0)]) AS raw_date,
           TRIM(SPLIT(raw_line, ',')[SAFE_OFFSET(1)]) AS raw_name
    FROM holiday_csv_raw
    WHERE file_hash = p_file_hash AND raw_line IS NOT NULL AND TRIM(raw_line) <> ''
  )
  SELECT line_no, raw_line, raw_name,
         COALESCE(SAFE.PARSE_DATE('%Y/%m/%d', raw_date),
                  SAFE.PARSE_DATE('%Y-%m-%d', raw_date),
                  SAFE.PARSE_DATE('%Y%m%d',   raw_date)) AS h_date
  FROM split;

  -- 2) 検疫：ヘッダー行（最初のパース失敗行）以外のパース失敗行
  INSERT INTO holiday_csv_quarantine (raw_line, line_no, file_hash, reason)
  SELECT raw_line, line_no, p_file_hash, 'DATE_PARSE_FAILED'
  FROM tmp_parsed
  WHERE h_date IS NULL
    AND line_no <> (SELECT MIN(line_no) FROM tmp_parsed WHERE h_date IS NULL);

  -- 3) 受入条件の評価
  SET v_parsed_rows     = (SELECT COUNT(*) FROM tmp_parsed WHERE h_date IS NOT NULL);
  SET v_quarantine_rows = (SELECT COUNT(*) FROM holiday_csv_quarantine WHERE file_hash = p_file_hash);
  SET v_prev_rows       = (SELECT COUNT(*) FROM dim_public_holidays WHERE source = 'DIGITAL_AGENCY_CSV' AND holiday_type <> 'REVOKED');
  SET v_has_this_year   = (SELECT COUNT(*) FROM tmp_parsed WHERE h_date = DATE(EXTRACT(YEAR FROM CURRENT_DATE('Asia/Tokyo')), 1, 1));
  SET v_has_next_year   = (SELECT COUNT(*) FROM tmp_parsed WHERE h_date = DATE(EXTRACT(YEAR FROM CURRENT_DATE('Asia/Tokyo')) + 1, 1, 1));
  SET v_dup_rows        = (SELECT COUNT(*) FROM (SELECT h_date FROM tmp_parsed WHERE h_date IS NOT NULL GROUP BY h_date HAVING COUNT(*) > 1));

  IF v_parsed_rows < CAST(v_prev_rows * v_min_ratio AS INT64)
     OR v_quarantine_rows > 3
     OR v_has_this_year = 0 OR v_has_next_year = 0
     OR v_dup_rows > 0 THEN
    -- 受入不可：マスタを触らず記録とアラートのみ（B-11 は起動しない）
    INSERT INTO agg_data_quality_daily (target_date, area_code, side, total_expected_slots, missing_slots_count,
                                      cleansed_flag_1_count, cleansed_flag_2_count, cleansed_flag_3_count, cleansed_flag_4_count,
                                      cleansing_ratio, null_rate_count, energy_balance_diff_kwh, unresolved_area_count, is_publishable, ingestion_run_id, loaded_at, pipeline_version)
  VALUES (CURRENT_DATE('Asia/Tokyo'), 'ALL', 'SYSTEM', 0, 0, 0, 0, 0, 0, 0, 0, 0, v_quarantine_rows, FALSE, p_run_id, CURRENT_TIMESTAMP(), p_pipeline_version);
    -- アラート送信は呼び出し側（Composer）が本プロシージャの戻り値（RAISE ではなく正常終了＋ステータス）で判定する
    SELECT 'HOLIDAY_CSV_REJECTED' AS status, v_parsed_rows AS parsed_rows, v_quarantine_rows AS quarantine_rows, v_prev_rows AS prev_rows;
    RETURN;
  END IF;

  -- 4) UPSERT（BigQuery は ON CONFLICT を持たないため MERGE）
  MERGE dim_public_holidays t
  USING (
    SELECT h_date AS holiday_date,
           CASE WHEN raw_name LIKE '%振替%'         THEN 'SUBSTITUTE'
                WHEN raw_name IN ('休日', '国民の休日') THEN 'BRIDGE'
                WHEN raw_name LIKE '%の日' OR raw_name LIKE '%記念日' OR raw_name IN ('元日','春分の日','秋分の日','憲法記念日','天皇誕生日') THEN 'NATIONAL'
                ELSE 'TEMPORARY' END AS holiday_type,
           raw_name AS holiday_name
    FROM tmp_parsed WHERE h_date IS NOT NULL
  ) s
  ON t.holiday_date = s.holiday_date
  WHEN MATCHED AND (t.holiday_name <> s.holiday_name OR t.holiday_type <> s.holiday_type) THEN
    UPDATE SET holiday_name = s.holiday_name, holiday_type = s.holiday_type,
               registered_date = CURRENT_DATE('Asia/Tokyo'), source = 'DIGITAL_AGENCY_CSV'
  WHEN NOT MATCHED BY TARGET THEN
    INSERT (holiday_date, holiday_type, holiday_name, is_national_holiday, source, registered_date)
    VALUES (s.holiday_date, s.holiday_type, s.holiday_name, TRUE, 'DIGITAL_AGENCY_CSV', CURRENT_DATE('Asia/Tokyo'))
  WHEN NOT MATCHED BY SOURCE
       AND t.source = 'DIGITAL_AGENCY_CSV' AND t.holiday_type <> 'REVOKED'
       AND t.holiday_date >= DATE_TRUNC(CURRENT_DATE('Asia/Tokyo'), YEAR) THEN
    UPDATE SET holiday_type = 'REVOKED', registered_date = CURRENT_DATE('Asia/Tokyo');   -- 履歴を残す（削除しない）

  SELECT 'HOLIDAY_CSV_LOADED' AS status, v_parsed_rows AS parsed_rows, v_quarantine_rows AS quarantine_rows, v_prev_rows AS prev_rows;
END;
