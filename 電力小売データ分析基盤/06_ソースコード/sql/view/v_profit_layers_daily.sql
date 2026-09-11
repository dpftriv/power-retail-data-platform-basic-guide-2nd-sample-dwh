-- 電力小売データ分析基盤
-- view/v_profit_layers_daily.sql
-- 根拠：詳細設計書 第3部 1. 日報損益マート生成コアバッチのロジック詳細仕様
-- 注意：${GCP_PROJECT_ID} と ${BQ_DATASET_*} はテンプレート変数。CI/CD で環境別の値へ展開してから実行する
--       （命名・運用定義書 3.2）。未展開のまま実行してはならない。

CREATE OR REPLACE VIEW v_profit_layers_daily AS
SELECT target_date, area_code, bg_code,
       SUM(demand_kwh)                                   AS demand_kwh,
       SUM(generation_kwh)                               AS generation_kwh,
       SUM(contribution_margin)                          AS layer1_contribution_margin,
       SUM(gross_profit)                                 AS layer2_adjusted_gross_profit,
       SUM(revenue)                                      AS layer3_revenue_incl_levy,
       SUM(procurement_cost)                             AS layer3_cost_incl_levy_passthrough,
       SUM(gross_profit)                                 AS layer3_gross_profit,           -- ②と同値
       SUM(rev_levy)                                     AS levy_revenue_excl_tax,
       SUM(rev_levy_incl_tax)                            AS levy_revenue_incl_tax,
       SAFE_DIVIDE(SUM(gross_profit), SUM(demand_kwh) + SUM(generation_kwh)) AS margin_per_kwh
FROM agg_daily_pnl
WHERE is_verified
GROUP BY target_date, area_code, bg_code;
