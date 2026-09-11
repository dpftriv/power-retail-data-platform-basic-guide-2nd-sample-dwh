-- 電力小売データ分析基盤
-- function/udf_validate_demand_point_number.sql
-- 根拠：詳細設計書 第1部 4. マスタデータ移行（データクレンジング）手順、詳細設計書 第3部 7. 先頭3桁地点特定番号検証関数の仕様
-- 注意：${GCP_PROJECT_ID} と ${BQ_DATASET_*} はテンプレート変数。CI/CD で環境別の値へ展開してから実行する
--       （命名・運用定義書 3.2）。未展開のまま実行してはならない。

CREATE OR REPLACE FUNCTION udf_validate_demand_point_number(
  demand_point_number STRING, area_code STRING, voltage_class STRING
) RETURNS STRING AS (
  CASE
    -- ① 桁数・型：22桁の半角数字
    WHEN demand_point_number IS NULL
      OR NOT REGEXP_CONTAINS(demand_point_number, r'^[0-9]{22}$')                  THEN 'ERR_FORMAT_NOT_22_DIGITS'
    -- ② スコープ：先頭2桁が 01〜09（沖縄 10 はスコープ外）。dim_areas の登録範囲と同一（13.1 ⑤）
    WHEN SUBSTR(demand_point_number, 1, 2) NOT IN ('01','02','03','04','05','06','07','08','09') THEN 'ERR_AREA_OUT_OF_SCOPE'
    -- ③ エリア：登録された area_code と一致
    WHEN SUBSTR(demand_point_number, 1, 2) <> area_code                            THEN 'ERR_AREA_MISMATCH'
    -- ④ 電圧区分（3桁目）：低圧 = 0、高圧・特高 = 1
    WHEN voltage_class = '低圧'           AND SUBSTR(demand_point_number, 3, 1) <> '0' THEN 'ERR_VOLTAGE_DIGIT_LOW'
    WHEN voltage_class IN ('高圧', '特高') AND SUBSTR(demand_point_number, 3, 1) <> '1' THEN 'ERR_VOLTAGE_DIGIT_HIGH'
    WHEN voltage_class NOT IN ('低圧', '高圧', '特高')                               THEN 'ERR_VOLTAGE_CLASS_UNKNOWN'
    ELSE 'OK'
  END
);

-- 移行・取込バッチでの強制拒否（ゲート）
IF EXISTS (
  SELECT 1 FROM `${GCP_PROJECT_ID}.${BQ_DATASET_STAGING}.raw_migration_customers`
  WHERE udf_validate_demand_point_number(demand_point_number, area_code, voltage_class) <> 'OK'
) THEN
  RAISE USING MESSAGE = (
    SELECT FORMAT('移行データに無効な地点番号: %s (地点: %s, 件数: %d)',
                  ANY_VALUE(err), ANY_VALUE(demand_point_number), COUNT(*))
    FROM (SELECT demand_point_number,
                 udf_validate_demand_point_number(demand_point_number, area_code, voltage_class) AS err
          FROM `${GCP_PROJECT_ID}.${BQ_DATASET_STAGING}.raw_migration_customers`)
    WHERE err <> 'OK');
END IF;
