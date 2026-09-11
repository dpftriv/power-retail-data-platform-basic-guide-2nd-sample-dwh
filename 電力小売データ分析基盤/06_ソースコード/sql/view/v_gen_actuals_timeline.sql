-- 電力小売データ分析基盤
-- view/v_gen_actuals_timeline.sql
-- 根拠：詳細設計書 第2部 2. 実績3層時系列統合ビューの設計
-- 注意：${GCP_PROJECT_ID} と ${BQ_DATASET_*} はテンプレート変数。CI/CD で環境別の値へ展開してから実行する
--       （命名・運用定義書 3.2）。未展開のまま実行してはならない。

CREATE OR REPLACE VIEW v_gen_actuals_timeline AS
-- ① 確定値の取込が完了した月 → settled（訂正レコードを合算して地点×日×コマで1行）
SELECT supply_point_number, area_code, target_date, slot_number,
       SUM(actual_value_kwh) AS actual_value_kwh, '確定値' AS data_status
FROM fact_gen_actuals_settled
GROUP BY supply_point_number, area_code, target_date, slot_number
UNION ALL
-- ② 確定値が未到着の月（昨日まで） → daily。境界は FT-11 で動的に判定
SELECT g.supply_point_number, g.area_code, g.target_date, g.slot_number,
       g.actual_value_kwh, '確報値' AS data_status
FROM fact_gen_actuals_daily g
WHERE g.target_date < CURRENT_DATE('Asia/Tokyo')
  AND NOT EXISTS (
        SELECT 1 FROM fact_settlement_receipts rc
        WHERE rc.area_code    = g.area_code
          AND rc.target_month = FORMAT_DATE('%Y%m', g.target_date)
          AND rc.side         = '発電'
          AND rc.is_loaded)
UNION ALL
-- ③ 当日、および確報未展開の過去日 → 速報の最新行キャッシュ（FT-13）。ストリーム本体は読まない
SELECT s.supply_point_number, s.area_code, s.target_date, s.slot_number,
       s.actual_value_kwh, '速報値' AS data_status
FROM fact_gen_actuals_stream_latest s
WHERE s.target_date BETWEEN DATE_SUB(CURRENT_DATE('Asia/Tokyo'), INTERVAL 7 DAY) AND CURRENT_DATE('Asia/Tokyo')
  AND (s.target_date = CURRENT_DATE('Asia/Tokyo')
       OR NOT EXISTS (SELECT 1 FROM fact_gen_actuals_daily g
                      WHERE g.target_date = s.target_date
                        AND g.supply_point_number = s.supply_point_number
                        AND g.slot_number = s.slot_number))
  AND NOT EXISTS (
        SELECT 1 FROM fact_settlement_receipts rc
        WHERE rc.area_code    = s.area_code
          AND rc.target_month = FORMAT_DATE('%Y%m', s.target_date)
          AND rc.side         = '発電'
          AND rc.is_loaded);
