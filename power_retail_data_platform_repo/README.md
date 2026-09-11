# 電力小売データ分析基盤 リポジトリ構成

```
spec.md                                             設計仕様書（正本）
docs/
  design_detail.md                                  詳細設計書（4ファイル境界。本文は論理名。SQL は相対リンク）
  profit_layer_definitions.md                       損益分析定義書（損益概念・利益5階層・物理列マッピング）
sql/
  ddl/        masters.sql / facts.sql / marts.sql    Silver マスタ・ファクト、Gold マートの DDL
              scd2_validation_customer_contracts.sql  契約履歴の重複・隙間・逆転検証 SQL
  function/   udf_validate_demand_point_number.sql     地点番号 先頭3桁検証 UDF
  view/       実績時系列統合、実量kW判定、市場連動単価解決、利益階層、BI抽出
  procedure/  日報損益、検算、BG按分、祝日取込、訪問検針プロファイル配分、予測精度、BI抽出完了監視、契約移行ゲート
  ALL_IN_ONE.sql   全 SQL をデプロイ順に結合した版
ops/          b13_archive_slot_summary.sh            コマ別集約マートの Active→Cold パーティションコピー
```

- 本バンドルはファイル名・フォルダ名をすべて英数字（ASCII）にした版。展開環境による文字化けを避けるため。**ファイルの中身（日本語の本文・コメント）はそのまま**。
- 日本語ファイル名版は別バンドル（`電力小売データ分析基盤_清書版.zip`）を参照。内容は同一。
- データセット命名：`prod_bronze`／`prod_silver`／`prod_mart`／`prod_staging`（`spec.md` 6.0 章）。SQL はデータセット修飾を持たず、デプロイスクリプトで付与する。
- DDL は設計仕様書の項目定義から生成した骨組みであり、デプロイ前に dev 環境でレビューする（`spec.md` 13.1／18.3）。
