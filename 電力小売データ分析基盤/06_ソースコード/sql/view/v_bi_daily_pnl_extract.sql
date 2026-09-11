-- 電力小売データ分析基盤
-- view/v_bi_daily_pnl_extract.sql
-- 根拠：詳細設計書 第4部 1. BI抽出同期・完了監視プロシージャのロジック詳細仕様
-- 注意：${GCP_PROJECT_ID} と ${BQ_DATASET_*} はテンプレート変数。CI/CD で環境別の値へ展開してから実行する
--       （命名・運用定義書 3.2）。未展開のまま実行してはならない。

CREATE OR REPLACE VIEW v_bi_daily_pnl_extract AS
SELECT
    target_date, area_code, bg_code, direction, segment, menu_type, base_data_status,
    SUM(demand_kwh)             AS total_demand_kwh,
    SUM(demand_kwh_sending_end) AS total_demand_sending_kwh,
    SUM(generation_kwh)         AS total_generation_kwh,
    SUM(revenue)                AS total_revenue,
    SUM(rev_levy)               AS total_levy_revenue,          -- 賦課金（税抜換算・参考値）は粗利分析で除外できるよう別持ち
    SUM(rev_levy_incl_tax)      AS total_levy_incl_tax,         -- 税込総額
    SUM(procurement_cost)       AS total_procurement_cost,
    SUM(cost_jepx_spot)         AS total_jepx_spot_cost,
    SUM(cost_jepx_fee)          AS total_jepx_fee_cost,
    SUM(cost_procurement_contract) AS total_procurement_contract_cost,   -- 相対・PPA・先物（ヘッジ効果の可視化）
    SUM(cost_imbalance)         AS total_imbalance_cost,
    SUM(cost_wheeling_variable + cost_wheeling_fixed_est) AS total_wheeling_cost,
    SUM(cost_capacity_contribution) AS total_capacity_cost,
    SUM(cost_nonfossil_certificate) AS total_certificate_cost,
    SUM(cost_gen_charge)        AS total_gen_charge_cost,
    SUM(contribution_margin)    AS total_contribution_margin,           -- 利益階層①
    SUM(gross_profit)           AS total_gross_profit,                  -- 利益階層②＝③
    CURRENT_TIMESTAMP()         AS extract_generated_at         -- 14.10 の同期チェックに使う
FROM agg_daily_pnl
-- 抽出容量の上限に収めるため直近13ヶ月に限定（月初から前年同月を含む）
WHERE target_date >= DATE_SUB(DATE_TRUNC(CURRENT_DATE('Asia/Tokyo'), MONTH), INTERVAL 12 MONTH)
  -- 検算 NG の日は BI へ流さない（品質ゲート）
  AND is_verified
GROUP BY target_date, area_code, bg_code, direction, segment, menu_type, base_data_status;
