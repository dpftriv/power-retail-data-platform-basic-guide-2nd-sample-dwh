-- 電力小売データ分析基盤
-- ddl/scd2_validation_customer_contracts.sql
-- 正本：電力小売データ分析基盤.md（該当節の参照実装を抽出）
-- 注意：${GCP_PROJECT_ID} と ${BQ_DATASET_*} はテンプレート変数。CI/CD で環境別の値へ展開してから実行する
--       （命名・運用定義書 3.2）。未展開のまま実行してはならない。

-- 契約履歴マスタの登録前検証（移行ステージング／マスタ更新プロシージャの前段で実行）
-- 本番テーブルの監査に使う場合は FROM 句を dim_customer_contracts に差し替える
WITH sorted_contracts AS (
  SELECT contract_history_id, customer_id, rate_menu_code, start_date, end_date,
         LEAD(start_date)          OVER (PARTITION BY customer_id ORDER BY start_date, contract_history_id) AS next_start_date,
         LEAD(contract_history_id) OVER (PARTITION BY customer_id ORDER BY start_date, contract_history_id) AS next_contract_history_id
  FROM `${GCP_PROJECT_ID}.${BQ_DATASET_STAGING}.migration_customer_contracts`
),
validation_flagged AS (
  SELECT customer_id, contract_history_id AS current_history_id, next_contract_history_id,
         start_date AS current_start_date, end_date AS current_end_date, next_start_date,
         CASE
           WHEN start_date > end_date                                            THEN 'ERR_DATE_INVERSION_START_AFTER_END'
           WHEN next_start_date IS NOT NULL AND next_start_date <= end_date       THEN 'ERR_SCD2_OVERLAP_DETECTED'
           WHEN end_date <> DATE '9999-12-31'
                AND next_start_date IS NOT NULL
                AND DATE_ADD(end_date, INTERVAL 1 DAY) <> next_start_date          THEN 'ERR_SCD2_GAP_DETECTED'
           WHEN end_date <> DATE '9999-12-31' AND next_start_date IS NULL          THEN 'WARN_SCD2_NO_OPEN_RECORD'   -- 最新レコードが閉じている（解約済みなら正常）
           ELSE 'OK'
         END AS validation_status
  FROM sorted_contracts
)
SELECT customer_id, validation_status, current_history_id, current_start_date, current_end_date,
       next_contract_history_id AS conflicting_history_id, next_start_date AS conflicting_start_date,
       FORMAT('需要家ID: %s において %s を検知。現在の履歴ID(%s: %s〜%s) と 次の履歴ID(%s: 開始日 %s) の接続が不正です。',
              customer_id,
              CASE validation_status
                WHEN 'ERR_DATE_INVERSION_START_AFTER_END' THEN '「開始日 ＞ 終了日」の逆転'
                WHEN 'ERR_SCD2_OVERLAP_DETECTED'          THEN '「期間の重複」'
                WHEN 'ERR_SCD2_GAP_DETECTED'              THEN '「期間の隙間（無契約期間）」'
                ELSE validation_status END,
              current_history_id, CAST(current_start_date AS STRING), CAST(current_end_date AS STRING),
              COALESCE(next_contract_history_id, '-'), COALESCE(CAST(next_start_date AS STRING), '-')) AS error_message
FROM validation_flagged
WHERE validation_status <> 'OK'
ORDER BY customer_id, current_start_date;
