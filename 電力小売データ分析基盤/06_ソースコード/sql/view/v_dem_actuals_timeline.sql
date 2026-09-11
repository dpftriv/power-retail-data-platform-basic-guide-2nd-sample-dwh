-- 電力小売データ分析基盤
-- view/v_dem_actuals_timeline.sql
-- 根拠：詳細設計書 第2部 2. 実績3層時系列統合ビューの設計
-- 注意：${GCP_PROJECT_ID} と ${BQ_DATASET_*} はテンプレート変数。CI/CD で環境別の値へ展開してから実行する
--       （命名・運用定義書 3.2）。未展開のまま実行してはならない。

CREATE OR REPLACE VIEW v_dem_actuals_timeline AS
-- ① 確定値の取込が完了した月 → settled
--    訂正は打ち消しレコードの追記で行う（12.4）ため、地点×日×コマで合算して1行にする
SELECT demand_point_number, area_code, target_date, slot_number,
       SUM(actual_value_kwh) AS actual_value_kwh, '確定値' AS data_status
FROM fact_dem_actuals_settled
GROUP BY demand_point_number, area_code, target_date, slot_number
UNION ALL
-- ② 確定値が未到着の月（昨日まで） → daily
--    境界は fact_settlement_receipts（FT-11）で動的に判定し、固定の月初判定は使わない
SELECT d.demand_point_number, d.area_code, d.target_date, d.slot_number,
       d.actual_value_kwh, '確報値' AS data_status
FROM fact_dem_actuals_daily d
WHERE d.target_date < CURRENT_DATE('Asia/Tokyo')
  AND NOT EXISTS (
        SELECT 1 FROM fact_settlement_receipts rc
        WHERE rc.area_code    = d.area_code
          AND rc.target_month = FORMAT_DATE('%Y%m', d.target_date)
          AND rc.side         = '需要'
          AND rc.is_loaded)
UNION ALL
-- ③ 当日、および確報がまだ展開されていない過去日 → 速報の最新行キャッシュ（fact_dem_actuals_stream_latest, FT-13）
--    速報層の範囲を「当日」固定にせず、直近7日のうち daily に行が存在しないコマまで広げる。
SELECT s.demand_point_number, s.area_code, s.target_date, s.slot_number,
       s.actual_value_kwh, '速報値' AS data_status
FROM fact_dem_actuals_stream_latest s
WHERE s.target_date BETWEEN DATE_SUB(CURRENT_DATE('Asia/Tokyo'), INTERVAL 7 DAY) AND CURRENT_DATE('Asia/Tokyo')  -- 静的なパーティション絞り込み
  AND (s.target_date = CURRENT_DATE('Asia/Tokyo')
       OR NOT EXISTS (SELECT 1 FROM fact_dem_actuals_daily d
                      WHERE d.target_date = s.target_date          -- パーティション列で絞る
                        AND d.demand_point_number = s.demand_point_number
                        AND d.slot_number = s.slot_number))
  AND NOT EXISTS (
        SELECT 1 FROM fact_settlement_receipts rc
        WHERE rc.area_code    = s.area_code
          AND rc.target_month = FORMAT_DATE('%Y%m', s.target_date)
          AND rc.side         = '需要'
          AND rc.is_loaded);
