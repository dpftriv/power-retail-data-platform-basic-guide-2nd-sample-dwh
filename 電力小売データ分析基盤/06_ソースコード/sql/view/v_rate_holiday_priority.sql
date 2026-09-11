-- 電力小売データ分析基盤
-- sql/view/v_rate_holiday_priority.sql
-- 根拠：基本設計書 10.5（V-06 料金用休日ビュー）
-- 注意：${GCP_PROJECT_ID} と ${BQ_DATASET_*} はテンプレート変数。CI/CD で環境別の値へ展開してから実行する
--       （命名・運用定義書 3.2）。未展開のまま実行してはならない。

CREATE OR REPLACE VIEW v_rate_holiday_priority AS
SELECT
    c.target_date, c.day_of_week,
    -- 1. 自社の約款休日（最優先） 2. 土日祝（dim_public_holidays は土日行を含む） 3. 平日
    (self_h.account_holiday_date IS NOT NULL OR pub.holiday_date IS NOT NULL) AS is_rate_holiday,
    CASE WHEN self_h.account_holiday_date IS NOT NULL THEN 'COMPANY'
         WHEN pub.holiday_date IS NOT NULL            THEN 'PUBLIC'
         ELSE NULL END                                                        AS holiday_source,
    self_h.holiday_reason AS company_holiday_reason,
    pub.holiday_name      AS public_holiday_name
FROM dim_date_calendar c
LEFT JOIN dim_account_holidays self_h
       ON c.target_date = self_h.account_holiday_date
      AND self_h.account_id = 'ACCOUNT_SELF'
      AND self_h.demand_point_number IS NULL
      AND self_h.applies_to_tariff
LEFT JOIN dim_public_holidays pub
       ON c.target_date = pub.holiday_date;
