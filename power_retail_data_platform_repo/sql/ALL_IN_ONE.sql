-- 電力小売データ分析基盤 : 全 SQL 結合版（デプロイ順：DDL → 関数 → ビュー → プロシージャ）
-- 生成: 2026-09-10
-- 注意：${GCP_PROJECT_ID} / ${BQ_DATASET_*} はテンプレート変数。CI/CD で展開してから dry run し、
--       テスト用データセットへ適用してから本番へデプロイする（命名・運用定義書 3.2 / 11.1）。

-- ============================================================
-- FILE: sql/ddl/masters.sql
-- ============================================================
-- =============================================================================
-- 電力小売データ分析基盤
-- Silver 層 マスタ（d_*）DDL
-- 生成元：電力小売データ分析基盤.md（第7章のテーブル定義）
-- 注意：本ファイルは設計書の項目定義から機械生成した骨組み（正本は設計書）。
--       型・NOT NULL は設計書の記載に従い、記載のない列は命名から推定している。
--       デプロイ前に dev 環境で DDL レビュー（13.1／フェーズ1完了条件）を行うこと。
-- =============================================================================

-- D-01 エリアマスタ
CREATE TABLE IF NOT EXISTS dim_areas (
  area_code                          STRING NOT NULL OPTIONS(description = 'エリアコード：01〜09。社内共通キー。供給地点特定番号の先頭2桁と完全連動'),
  area_name                          STRING NOT NULL OPTIONS(description = 'エリア名'),
  ts_company_name                    STRING NOT NULL OPTIONS(description = '一般送配電事業者名'),
  ts_operator_code                   STRING NOT NULL OPTIONS(description = '一般送配電事業者コード：託送請求・確報データのファイルヘッダーに入る送信元識別コード。送配電網を保有する一般送配電事業者に付与されエリアに1つ。小売電気事業者には割り当てられないため取引先マスタには持たない。先頭ゼロを含む文字列として保持し数値化しない'),
  occto_area_digit                   STRING NOT NULL OPTIONS(description = 'OCCTOエリア数字（1桁）：小売電気事業者コード（5桁）の下1桁に使うエリア識別数字。北海道1／東北2／東京3／中部4／北陸5／関西6／中国7／四国8／九州9。area_code の下1桁と一致する'),
  area_abbr                          STRING NOT NULL OPTIONS(description = '社内標準略称：画面・帳票・社内API で用いる'),
  jepx_alpha_code                    STRING NOT NULL OPTIONS(description = 'JEPX 英字表記：JEPX の CSV ヘッダー等で使われる英字表記（Tokyo など）'),
  occto_alpha_code                   STRING NOT NULL OPTIONS(description = 'OCCTO 英字略称：OCCTO システムの3文字略称（TKY など）'),
  frequency                          INT64 NOT NULL OPTIONS(description = '系統周波数：50 / 60'),
  is_jepx_area                       BOOL NOT NULL OPTIONS(description = 'JEPX 取引対象フラグ：9エリアは全て 1。外部IFとの互換のため列を維持'),
  PRIMARY KEY (area_code) NOT ENFORCED
)
OPTIONS (
  description = 'エリアマスタ。全国9エリア（沖縄除く）と外部機関コードの名寄せ対応表'
);

-- D-02 取引先マスタ
CREATE TABLE IF NOT EXISTS dim_account (
  account_id                         STRING NOT NULL OPTIONS(description = '取引先ID：自社は予約ID ACCOUNT_SELF。個人需要家は IND_ ＋ 需要家ID の規則で採番'),
  entity_type                        STRING NOT NULL OPTIONS(description = '法人個人区分：SELF（自社）／CORPORATE（法人）／INDIVIDUAL（個人）'),
  account_name                       STRING NOT NULL OPTIONS(description = '取引先名：法人は法人名（非PII）。個人は固定ラベル「個人需要家」。氏名は入れない（PIIは dim_dem_customers.pii_customer_name のみ）'),
  account_type                       STRING OPTIONS(description = '取引先種別：業種としての分類。大手電力／新電力／発電事業者／アグリゲーター／一般事業法人／個人。役割（顧客か仕入先か）はここで表さず役割フラグで持つ'),
  is_customer                        BOOL NOT NULL OPTIONS(description = '需要家フラグ：自社が電気を売る相手（需要側）。需要家マスタから参照される取引先は TRUE'),
  is_supplier                        BOOL NOT NULL OPTIONS(description = '供給者フラグ：自社が電気を買う相手（発電側）。相対・PPA の売り手、発電所の保有者は TRUE。需要家であり同時に売り手でもある取引先は is_customer と両方 TRUE'),
  is_bg_member                       BOOL NOT NULL OPTIONS(description = 'BG構成員フラグ：BG構成員マスタから参照される取引先は TRUE'),
  is_own_account                     BOOL NOT NULL OPTIONS(description = '自社フラグ：TRUE は ACCOUNT_SELF の1件のみ。自社は3つの役割フラグをすべて TRUE にしてよい'),
  licence_id                         STRING OPTIONS(description = '登録番号（A番号）：登録小売電気事業者の場合のみ。dim_registered_retailers への外部キー。顧客・個人は NULL。エリアごとの5桁コードは dim_retailer_area_codes で解決する'),
  official_account_code              STRING OPTIONS(description = '公的取引先コード：OCCTO 等の登録コード（小売事業者コード以外）'),
  corporate_number                   STRING OPTIONS(description = '法人番号：法人のみ。個人は NULL'),
  PRIMARY KEY (account_id) NOT ENFORCED
)
OPTIONS (
  description = 'D-02 取引先マスタ。自社・顧客（法人／個人）・相対取引先・BG構成員・発電所保有者を一元管理する。需要側と発電側の双方が登録され顧客とパートナーが混在するため、役割は単一区分ではなくフラグで持つ。個人の氏名は保持しない'
);

-- D-37 登録小売電気事業者マスタ
CREATE TABLE IF NOT EXISTS dim_registered_retailers (
  licence_id                         STRING NOT NULL OPTIONS(description = '登録番号（A番号）：資源エネルギー庁が登録小売電気事業者へ付与する登録番号。1社に全国で1つ。先頭の英字とゼロを含む文字列としてそのまま保持し数値化しない'),
  start_date                         DATE NOT NULL OPTIONS(description = '適用開始日：登録・商号変更に対応（期間管理）'),
  end_date                           DATE NOT NULL DEFAULT '9999-12-31' OPTIONS(description = '適用終了日：有効行は 9999-12-31'),
  registered_name                    STRING NOT NULL OPTIONS(description = '登録事業者名：登録簿上の名称。商号変更時は新しい期間の行を追加する'),
  corporate_number                   STRING OPTIONS(description = '法人番号：一覧に含まれる13桁。取引先マスタとの名寄せキー'),
  account_id                         STRING OPTIONS(description = '取引先ID：自社・取引のある事業者のみ紐付ける。取引のない他社は NULL'),
  is_own_retailer                    BOOL NOT NULL OPTIONS(description = '自社フラグ：TRUE は自社の1件のみ'),
  registered_date                    DATE NOT NULL OPTIONS(description = '登録日'),
  revoked_date                       DATE OPTIONS(description = '登録取消日：取消後も過去の電文・履歴の解決のため行を残す'),
  retailer_category                  STRING OPTIONS(description = '事業者区分：旧一般電気事業者／新電力 等'),
  source                             STRING NOT NULL OPTIONS(description = '情報ソース：資源エネルギー庁の登録小売電気事業者一覧'),
  fetched_date                       DATE NOT NULL OPTIONS(description = '取得日'),
  PRIMARY KEY (licence_id, start_date) NOT ENFORCED  -- 期間管理
)
OPTIONS (
  description = 'D-37 登録小売電気事業者マスタ。資源エネルギー庁の登録番号（A番号。1社に全国で1つ）。一覧から一括投入でき名寄せの起点になる'
);

-- D-38 小売事業者エリアコードマスタ
CREATE TABLE IF NOT EXISTS dim_retailer_area_codes (
  licence_id                         STRING NOT NULL OPTIONS(description = '登録番号（A番号）：dim_registered_retailers への外部キー。事業者単位の親'),
  area_code                          STRING NOT NULL OPTIONS(description = 'エリアコード：進出エリア。dim_areas への外部キー'),
  start_date                         DATE NOT NULL OPTIONS(description = '適用開始日：進出・撤退・コード改番に対応（期間管理）'),
  end_date                           DATE NOT NULL DEFAULT '9999-12-31' OPTIONS(description = '適用終了日：有効行は 9999-12-31'),
  occto_retail_code_5                STRING NOT NULL OPTIONS(description = '小売電気事業者コード（5桁）：OCCTO 発行。上4桁＝事業者固有コード、下1桁＝エリア（管轄）コード。同じ事業者でも販売エリアごとに下1桁が変わる。下1桁は dim_areas.occto_area_digit と一致する。先頭ゼロを含む文字列として保持。一括提供がないためスイッチング支援システム・供給計画届出書・JEPX取引明細から抽出する'),
  occto_operator_code_4              STRING NOT NULL OPTIONS(description = '事業者固有コード（上4桁）：全エリア共通。occto_retail_code_5 の上4桁。4桁のみを用いる電文で使う'),
  code_source                        STRING NOT NULL OPTIONS(description = '取得元：SWITCHING_SYSTEM／SUPPLY_PLAN／JEPX_TRADE／MANUAL'),
  source                             STRING NOT NULL OPTIONS(description = '情報ソース：抽出元のシステム名・ファイル名'),
  fetched_date                       DATE NOT NULL OPTIONS(description = '取得日'),
  PRIMARY KEY (licence_id, area_code, start_date) NOT ENFORCED  -- 事業者×エリアの期間管理
)
OPTIONS (
  description = 'D-38 小売事業者エリアコードマスタ。OCCTO の小売電気事業者コード（5桁）。1社×エリアごとに1つ存在し、D-37 の子（1対多）'
);

-- D-03 電源種別マスタ
CREATE TABLE IF NOT EXISTS dim_fuel_types (
  fuel_code                          STRING NOT NULL OPTIONS(description = '電源種別コード：SOL / WND / HYD / COL / LNG / NUC / BIO'),
  fuel_name                          STRING NOT NULL OPTIONS(description = '電源種別名'),
  category                           STRING OPTIONS(description = '大分類：再生可能エネルギー／化石燃料／原子力'),
  is_renewable                       BOOL NOT NULL OPTIONS(description = '再エネフラグ'),
  is_variable                        BOOL NOT NULL OPTIONS(description = '変動性電源フラグ：太陽光・風力＝1（欠損補完の方法が異なる）'),
  is_non_fossil                      BOOL NOT NULL OPTIONS(description = '非化石フラグ：非化石証書トラッキング用'),
  PRIMARY KEY (fuel_code) NOT ENFORCED
)
OPTIONS (
  description = '電源種別マスタ。燃料種別と特性（再エネ・変動性・非化石）'
);

-- D-04 発電所マスタ
CREATE TABLE IF NOT EXISTS dim_plants (
  plant_id                           STRING NOT NULL OPTIONS(description = '発電所ID'),
  plant_name                         STRING NOT NULL OPTIONS(description = '発電所名'),
  account_id                         STRING OPTIONS(description = '事業者ID'),
  fuel_code                          STRING OPTIONS(description = '電源種別コード'),
  capacity_kw                        NUMERIC NOT NULL OPTIONS(description = '認可出力(kW)：異常値検知の物理上限に使う'),
  panel_capacity_kw                  NUMERIC OPTIONS(description = 'パネル出力(kW)：太陽光の過積載判定用'),
  operation_start_date               DATE OPTIONS(description = '運転開始日：高経年化分析、FIP経過措置判定に使う。期間管理の start_date とは意味が異なるため別名にしている'),
  location                           STRING OPTIONS(description = '所在地'),
  latitude                           NUMERIC OPTIONS(description = '緯度／経度：気象予測データとの紐付け'),
  longitude                          NUMERIC OPTIONS(description = '緯度／経度：気象予測データとの紐付け'),
  PRIMARY KEY (plant_id) NOT ENFORCED
)
OPTIONS (
  description = '発電所マスタ。物理設備としての発電所属性（認可出力・電源種別・所在地）'
);

-- D-05 発電受給地点マスタ
CREATE TABLE IF NOT EXISTS dim_gen_supply_points (
  gen_point_id                       STRING NOT NULL OPTIONS(description = '発電地点ID：：物理地点（supply_point_number）に対して初回登録時に1回だけ発行し、属性変更（BG乗換・出力変更等）では同じ値を維持したまま新しい start_date の行を追加する'),
  supply_point_number                STRING OPTIONS(description = '受給地点番号：送配電連携の主キー。先頭3桁チェック（13.1 ③）を通過したもののみ'),
  plant_id                           STRING OPTIONS(description = '発電所ID：1発電所に複数地点がぶら下がる場合あり'),
  account_id                         STRING OPTIONS(description = '事業者ID：発電契約者'),
  area_code                          STRING OPTIONS(description = 'エリアコード：22桁の先頭2桁と一致必須'),
  gen_bg_code                        STRING OPTIONS(description = '発電BGコード'),
  voltage_class                      STRING NOT NULL OPTIONS(description = '電圧クラス区分：特高／高圧／低圧'),
  connected_voltage_kv               NUMERIC OPTIONS(description = '接続電圧(kV)：例：6.60, 22.00, 154.00'),
  contract_kw                        NUMERIC OPTIONS(description = '契約出力(kW)：発電側課金の計算基礎'),
  is_fit                             BOOL NOT NULL OPTIONS(description = 'FIT適用フラグ'),
  is_fip                             BOOL NOT NULL OPTIONS(description = 'FIP適用フラグ'),
  fip_f_price                        NUMERIC OPTIONS(description = 'FIP基準価格(F値)：円/kWh。国が電源ごとに指定する固定の基準価格'),
  fip_cert_fiscal_year               INT64 OPTIONS(description = 'FIP認定年度：D-15 の参照キー'),
  gen_charge_type                    STRING OPTIONS(description = '発電側課金区分：割引対象／割引なし。dim_gen_charge_discount_rates（D-34）の割引率解決キー'),
  trial_start_date                   DATE OPTIONS(description = '試運転開始日：系統連系後、試運転（コミッショニング）で系統へ電気を流し始めた日。試運転を行わない地点は NULL'),
  commercial_operation_date          DATE OPTIONS(description = '商業運転開始日（COD）：この日から通常運転として扱う。trial_start_date 以降かつ本列より前が試運転期間'),
  trial_revenue_treatment            STRING OPTIONS(description = '試運転中の売電計上区分：RECOGNIZE（売上計上する）／EXCLUDE（計上しない）。認定内容・系統連系契約・約款により異なるため地点ごとに設定する。NULL は EXCLUDE とみなす'),
  start_date                         DATE NOT NULL OPTIONS(description = '適用開始日'),
  end_date                           DATE NOT NULL DEFAULT '9999-12-31' OPTIONS(description = '適用終了日：有効行は 9999-12-31'),
  PRIMARY KEY (gen_point_id, start_date) NOT ENFORCED
)
OPTIONS (
  description = '発電受給地点マスタ。22桁の受給地点番号と制度属性（FIT/FIP）・発電BG【期間管理】主キーは業務識別子＋適用開始日の複合キー。識別子は改定時も変更しない（安定識別子）'
);

-- D-34 発電側課金割引率マスタ
CREATE TABLE IF NOT EXISTS dim_gen_charge_discount_rates (
  discount_rate_id                   INT64 NOT NULL OPTIONS(description = '割引率ID'),
  area_code                          STRING NOT NULL OPTIONS(description = 'エリアコード'),
  gen_charge_type                    STRING NOT NULL OPTIONS(description = '発電側課金区分：dim_gen_supply_points.gen_charge_type と同じ値域（割引対象／割引なし）'),
  gen_charge_start_basis             STRING NOT NULL OPTIONS(description = '課金起算基準：COMMERCIAL_OPERATION（商業運転開始日から課金）／GRID_CONNECTION（系統連系日＝試運転開始日から課金）。約款により分かれるため一送ごとに登録する'),
  discount_rate                      NUMERIC NOT NULL OPTIONS(description = '割引率：0〜1。割引なしは 0'),
  start_date                         DATE NOT NULL OPTIONS(description = '適用開始日'),
  end_date                           DATE NOT NULL DEFAULT '9999-12-31' OPTIONS(description = '適用終了日：有効行は 9999-12-31'),
  PRIMARY KEY (discount_rate_id) NOT ENFORCED
)
OPTIONS (
  description = '発電側課金割引率マスタ。エリア×割引区分の割引率【期間管理】期間管理（SCD Type 2）。版ごとにサロゲートキーを採番し、業務キー＋期間の重複・隙間を 13.1 ①② で検証する'
);

-- D-35 アンペア料金マスタ
CREATE TABLE IF NOT EXISTS dim_ampere_rates (
  ampere_rate_id                     INT64 NOT NULL OPTIONS(description = 'アンペア料金ID'),
  rate_menu_code                     STRING OPTIONS(description = '料金メニューコード：小売基本料金の対応先'),
  area_code                          STRING NOT NULL OPTIONS(description = 'エリアコード'),
  ampere                             INT64 NOT NULL OPTIONS(description = '契約アンペア(A)：10／15／20／30／40／50／60'),
  retail_base_rate                   NUMERIC NOT NULL OPTIONS(description = '小売基本料金（円/月）：dim_rate_menus.base_rate（円/kW・月）のアンペア版。税区分は tax_type に従う'),
  wheeling_base_rate                 NUMERIC NOT NULL OPTIONS(description = '託送基本料金（円/月）：dim_wheeling_rates.demand_fixed_rate（円/kW・月）のアンペア版。一送の低圧アンペア約款に対応'),
  tax_type                           STRING NOT NULL OPTIONS(description = '税区分：税抜／税込。公表値をそのまま丸めずに保持し、税込 の場合は日報バッチが ÷(1+税率) を未丸めで適用（1.5 の層別原則）'),
  start_date                         DATE NOT NULL OPTIONS(description = '適用開始日'),
  end_date                           DATE NOT NULL DEFAULT '9999-12-31' OPTIONS(description = '適用終了日：有効行は 9999-12-31'),
  PRIMARY KEY (ampere_rate_id) NOT ENFORCED
)
OPTIONS (
  description = 'アンペア料金マスタ。低圧アンペア契約の小売・託送の月額固定基本料金【期間管理】期間管理（SCD Type 2）。版ごとにサロゲートキーを採番し、業務キー＋期間の重複・隙間を 13.1 ①② で検証する'
);

-- D-06 需要家マスタ
CREATE TABLE IF NOT EXISTS dim_dem_customers (
  customer_id                        STRING NOT NULL OPTIONS(description = '需要家ID'),
  demand_point_number                STRING OPTIONS(description = '需要地点番号：先頭3桁チェック（13.1 ③ の UDF udf_validate_demand_point_number）を通過したもののみ'),
  account_id                         STRING NOT NULL OPTIONS(description = '事業者ID：法人需要家の会社ID。dim_account_holidays と結ぶ。個人は NULL'),
  area_code                          STRING OPTIONS(description = 'エリアコード'),
  voltage_class                      STRING NOT NULL OPTIONS(description = '電圧クラス区分：低圧／高圧／特高'),
  customer_type                      STRING OPTIONS(description = '需要種別：産業／業務／家庭'),
  is_actual_kw_based                 BOOL NOT NULL OPTIONS(description = '実量制フラグ：TRUE：最大需要電力で基本料金を決定'),
  parent_demand_point_number         STRING OPTIONS(description = '親需要地点番号：親子計量（ビル一括受電の子メーター）の場合の親メーターの22桁番号。単独計量は NULL'),
  created_at                         TIMESTAMP OPTIONS(description = '作成／更新日時'),
  updated_at                         TIMESTAMP OPTIONS(description = '作成／更新日時'),
  pii_customer_name                  STRING NOT NULL OPTIONS(description = '需要家名：PII。個人情報。初期はマスキングなし。将来 Policy Tags の対象列（15.3）。 の customer_name から改名'),
  pii_postal_code                    STRING OPTIONS(description = '郵便番号：PII'),
  pii_prefecture                     STRING OPTIONS(description = '都道府県：PII（分析用途で必要なら prefecture として非 PII 側へ分離してもよい）'),
  pii_address_line1                  STRING OPTIONS(description = '住所1／住所2：PII'),
  pii_address_line2                  STRING OPTIONS(description = '住所1／住所2：PII'),
  pii_phone_number                   STRING OPTIONS(description = '電話番号：PII'),
  pii_email                          STRING OPTIONS(description = 'メールアドレス：PII'),
  PRIMARY KEY (customer_id) NOT ENFORCED
)
OPTIONS (
  description = '需要家マスタ。需要家と22桁需要地点を1対1で管理。PII 列は pii_ 接頭辞で分離'
);

-- D-07 需要家契約履歴マスタ
CREATE TABLE IF NOT EXISTS dim_customer_contracts (
  contract_history_id                STRING NOT NULL OPTIONS(description = '契約履歴ID：：同一需要家の「継続中の契約」に対して初回登録時に1回だけ発行し、料金メニュー変更・BG乗換などの改定では同じ値を維持したまま新しい start_date の行を追加する。解約後に別契約として再契約した場合は新しい contract_history_id を発行する（継続 vs 再契約の区別）'),
  customer_id                        STRING OPTIONS(description = '需要家ID'),
  procurement_contract_id            STRING OPTIONS(description = '専属調達契約ID：。特定の相対・PPA契約（例：RE100顧客専用のコーポレートPPA）をこの需要家契約に専属させる場合に設定する。NULL の場合は従来どおりエリア全体の調達（dim_procurement_contracts の紐付けなし分）から送電端需要比で按分される（10.8.4・13.1 ⑮）'),
  contract_group_id                  STRING OPTIONS(description = '契約グループID：実量制の判定単位を決めるキー（確定）。NULL＝地点単体で最大kWを判定（個別判定）。値あり（例：GRP_KAISHA_001）＝同一IDを持つ全地点の同一コマ電力量を合算して判定（グループ実量制）。同一グループは同一 account_id・同一 voltage_class でなければならない（13.1 ⑪）'),
  rate_menu_code                     STRING OPTIONS(description = '料金メニューコード'),
  dem_bg_code                        STRING OPTIONS(description = '需要BGコード'),
  contract_kw                        NUMERIC OPTIONS(description = '契約電力(kW)：協議設定 or 実量制の適用値。低圧アンペア契約は NULL（contract_ampere を使う）'),
  contract_ampere                    INT64 OPTIONS(description = '契約アンペア(A)：低圧従量電灯の主流であるアンペア制（10A〜60A）の契約。contract_kw と contract_ampere はどちらか一方のみを持つ（13.1 ⑭）。高圧・特高、および低圧のkVA契約は NULL'),
  wheeling_menu_name                 STRING OPTIONS(description = '託送メニュー名：dim_wheeling_rates.menu_name の選択。NULL なら is_default の行を適用'),
  contract_status                    STRING NOT NULL OPTIONS(description = '契約状態：申込中／供給中／解約'),
  start_date                         DATE NOT NULL OPTIONS(description = '適用開始日'),
  end_date                           DATE NOT NULL DEFAULT '9999-12-31' OPTIONS(description = '適用終了日：有効行は 9999-12-31'),
  PRIMARY KEY (contract_history_id, start_date) NOT ENFORCED
)
OPTIONS (
  description = '需要家契約履歴マスタ。料金メニュー・需要BG・契約容量のプラン変更履歴【期間管理】主キーは業務識別子＋適用開始日の複合キー。識別子は改定時も変更しない（安定識別子）'
);

-- D-08 料金メニューマスタ（料金メニュー履歴）
CREATE TABLE IF NOT EXISTS dim_rate_menus (
  rate_menu_code                     STRING NOT NULL OPTIONS(description = '料金メニューコード：単価改定時は同じコードのまま新しい start_date の行を追加する（ から一貫。他5マスタも  でこの方式に統一：13.1 ⑮の対象一覧参照）'),
  rate_menu_name                     STRING NOT NULL OPTIONS(description = '料金メニュー名'),
  voltage_class                      STRING NOT NULL OPTIONS(description = '対象電圧クラス'),
  is_market_linked                   BOOL NOT NULL OPTIONS(description = '市場連動フラグ：TRUE：市場連動、FALSE：固定単価'),
  apply_fuel_adjustment              BOOL NOT NULL OPTIONS(description = '燃調適用フラグ：市場連動メニューでは必ず 0'),
  holiday_rule_code                  STRING OPTIONS(description = '休日判定ルールコード：メニューごとの休日定義'),
  base_rate                          NUMERIC OPTIONS(description = '基本料金単価：円/kW・月'),
  weekday_day_rate                   NUMERIC OPTIONS(description = '平日昼間単価（他季）：円/kWh'),
  weekday_summer_day_rate            NUMERIC OPTIONS(description = '平日昼間単価（夏季）'),
  weekday_summer_peak_rate           NUMERIC OPTIONS(description = '平日ピーク単価（夏季）'),
  night_rate                         NUMERIC OPTIONS(description = '夜間単価（通年）'),
  holiday_rate                       NUMERIC OPTIONS(description = '休日単価（通年）'),
  rate_priority_rule                 STRING NOT NULL OPTIONS(description = '単価判定優先ルール：NIGHT_FIRST（夜間優先）／HOLIDAY_FIRST（休日優先）。10.6 の分岐順を切り替える'),
  env_value_type                     STRING NOT NULL OPTIONS(description = '環境価値種別：NONE／FIT_NONFOSSIL／NONFIT_RENEWABLE／NONFIT_UNSPECIFIED。NONE 以外は D-33 の証書単価を原価に加算（10.8.5。レビューで表に正式追加）'),
  start_date                         DATE NOT NULL OPTIONS(description = '適用開始日'),
  end_date                           DATE NOT NULL DEFAULT '9999-12-31' OPTIONS(description = '適用終了日：有効行は 9999-12-31'),
  PRIMARY KEY (rate_menu_code, start_date) NOT ENFORCED
)
OPTIONS (
  description = '料金メニューマスタ（料金メニュー履歴）。固定単価表と環境価値種別の改定履歴【期間管理】主キーは業務識別子＋適用開始日の複合キー。識別子は改定時も変更しない（安定識別子）'
);

-- D-09 バランシンググループマスタ
CREATE TABLE IF NOT EXISTS dim_balancing_groups (
  bg_code                            STRING NOT NULL OPTIONS(description = 'BGコード：公的に付与される識別子： では単一列PKだったため、期間管理（規約改定・按分方式変更）に対応した複数バージョンの登録ができなかった。start_date を主キーに加える'),
  bg_name                            STRING NOT NULL OPTIONS(description = 'BG名'),
  bg_type                            STRING NOT NULL OPTIONS(description = 'BG種別：発電 / 需要'),
  bg_structure                       STRING NOT NULL OPTIONS(description = '運営形態：SINGLE（自社単独）／CONSORTIUM（共同運営）'),
  representative_account_id          STRING OPTIONS(description = '代表事業者ID：送配電事業者に対して一括で支払義務を負う者'),
  area_code                          STRING OPTIONS(description = '管轄エリアコード：同一企業でもエリアごとに別BG'),
  is_own_bg                          BOOL NOT NULL OPTIONS(description = '自社BGフラグ：TRUE：自社が代表、FALSE：他社BGに構成員として参加'),
  allocation_method                  STRING NOT NULL OPTIONS(description = '按分方式：SIMPLE_RATIO／FIXED_SHARE／CAUSER_PAYS／HYBRID（10.3.2）。BG規約が唯一の正（R-21）'),
  rounding_rule                      STRING NOT NULL OPTIONS(description = '端数処理ルール：按分後の端数を誰が負担するか（代表者／最大構成員／切捨て）'),
  allocation_granularity             STRING NOT NULL OPTIONS(description = '按分粒度：原則 SLOT（コマ単位）。MONTHLY は単価差が消えるため非推奨（10.3.3）'),
  start_date                         DATE NOT NULL OPTIONS(description = '適用開始日'),
  end_date                           DATE NOT NULL DEFAULT '9999-12-31' OPTIONS(description = '適用終了日：有効行は 9999-12-31'),
  PRIMARY KEY (bg_code, start_date) NOT ENFORCED
)
OPTIONS (
  description = 'バランシンググループマスタ。BG規約（按分方式・端数処理）の改定履歴【期間管理】主キーは業務識別子＋適用開始日の複合キー。識別子は改定時も変更しない（安定識別子）'
);

-- D-30 BG構成員マスタ
CREATE TABLE IF NOT EXISTS dim_bg_members (
  bg_member_id                       STRING NOT NULL OPTIONS(description = '構成員ID：：(bg_code, account_id) の初回登録時に1回だけ発行し、以降の属性変更（シェア変更・免責変更等）では同じ値を維持したまま新しい start_date の行を追加する（安定識別子）。従来は変更ごとに新IDを発行していたため、fact_bg_member_imbalance.bg_member_id を軸に同一構成員の履歴を追跡できなかった'),
  bg_code                            STRING OPTIONS(description = 'BGコード'),
  account_id                         STRING OPTIONS(description = '事業者ID：自社（ACCOUNT_SELF）も1構成員として登録'),
  member_role                        STRING NOT NULL OPTIONS(description = '役割：REPRESENTATIVE（代表）／MEMBER（構成員）'),
  share_ratio                        NUMERIC OPTIONS(description = '固定シェア：FIXED_SHARE 方式で使う比率。BG内の合計が 1.000000'),
  is_exempt                          BOOL NOT NULL OPTIONS(description = '免責フラグ：TRUE：規約上、按分対象外（例：代表者の運営手数料との相殺）'),
  liability_cap                      NUMERIC OPTIONS(description = '責任上限（円/月）：規約に上限がある場合。超過分は代表者負担など規約に従う'),
  admin_fee_rate                     NUMERIC OPTIONS(description = '運営手数料率：代表者が構成員から徴収する率（按分とは別建て）'),
  agreement_ref                      STRING OPTIONS(description = '規約参照：BG規約の版・条番号'),
  start_date                         DATE NOT NULL OPTIONS(description = '適用開始日'),
  end_date                           DATE NOT NULL DEFAULT '9999-12-31' OPTIONS(description = '適用終了日：有効行は 9999-12-31'),
  PRIMARY KEY (bg_member_id, start_date) NOT ENFORCED
)
OPTIONS (
  description = 'BG構成員マスタ。構成員のシェア・免責・責任上限の改定履歴【期間管理】主キーは業務識別子＋適用開始日の複合キー。識別子は改定時も変更しない（安定識別子）'
);

-- D-10 送電損失率マスタ
CREATE TABLE IF NOT EXISTS dim_loss_rates (
  loss_rate_id                       INT64 NOT NULL OPTIONS(description = '損失率ID'),
  area_code                          STRING OPTIONS(description = 'エリアコード'),
  voltage_class                      STRING NOT NULL OPTIONS(description = '電圧クラス区分'),
  loss_rate                          NUMERIC NOT NULL OPTIONS(description = '送電損失率：例：0.03900 ＝ 3.9%'),
  start_date                         DATE NOT NULL OPTIONS(description = '適用開始日'),
  end_date                           DATE NOT NULL DEFAULT '9999-12-31' OPTIONS(description = '適用終了日：有効行は 9999-12-31'),
  PRIMARY KEY (loss_rate_id) NOT ENFORCED
)
OPTIONS (
  description = '送電損失率マスタ。一送約款の送電損失率をエリア×電圧クラス別に期間管理【期間管理】期間管理（SCD Type 2）。版ごとにサロゲートキーを採番し、業務キー＋期間の重複・隙間を 13.1 ①② で検証する'
);

-- D-11 託送料金マスタ
CREATE TABLE IF NOT EXISTS dim_wheeling_rates (
  wheeling_rate_id                   INT64 NOT NULL OPTIONS(description = '託送料金ID'),
  area_code                          STRING OPTIONS(description = 'エリアコード'),
  voltage_class                      STRING NOT NULL OPTIONS(description = '電圧クラス区分'),
  menu_name                          STRING NOT NULL OPTIONS(description = 'メニュー名：一送約款上のメニュー名（例：一般料金メニュー／季節別時間帯別メニュー）。同一 (area_code, voltage_class) に複数メニューがある場合は dim_customer_contracts.wheeling_menu_name で選択（未設定なら is_default の行）'),
  is_default                         BOOL NOT NULL OPTIONS(description = '既定メニューフラグ：同一 (area_code, voltage_class, 期間) 内で 1 行のみ 1'),
  demand_fixed_rate                  NUMERIC NOT NULL OPTIONS(description = '需要側 基本料金単価：円/kW・月'),
  demand_variable_rate               NUMERIC NOT NULL OPTIONS(description = '需要側 電力量料金単価（標準）：円/kWh。一律メニューの従量単価、または時間帯別メニューの「その他季昼間」単価。時間帯別列が NULL のときのフォールバック先'),
  variable_rate_summer_day           NUMERIC OPTIONS(description = '需要側 夏季昼間単価：円/kWh。一律メニューは NULL'),
  variable_rate_summer_peak          NUMERIC OPTIONS(description = '需要側 夏季ピーク単価：円/kWh。同上'),
  variable_rate_winter_day           NUMERIC OPTIONS(description = '需要側 冬季昼間単価：円/kWh。約款に冬季の特掲がある一送に備える予備列。なければ NULL'),
  variable_rate_night                NUMERIC OPTIONS(description = '需要側 夜間単価：円/kWh（通年）。一律メニューは NULL'),
  holiday_day_rate_rule              STRING NOT NULL OPTIONS(description = '休日昼間の単価規則：STANDARD（休日昼間はその他季昼間単価）／SEASONAL（休日昼間も季節単価を適用。夏季ピークは平日のみ）。一送約款の差異をこの列で吸収する'),
  gen_charge_rate                    NUMERIC NOT NULL OPTIONS(description = '発電側 課金単価：円/kW・月'),
  gen_charge_kwh_rate                NUMERIC OPTIONS(description = '発電側 従量課金単価：円/kWh（制度に従い保持）'),
  tax_type                           STRING NOT NULL OPTIONS(description = '税区分：税抜固定（1.5）'),
  start_date                         DATE NOT NULL OPTIONS(description = '適用開始日'),
  end_date                           DATE NOT NULL DEFAULT '9999-12-31' OPTIONS(description = '適用終了日：有効行は 9999-12-31'),
  PRIMARY KEY (wheeling_rate_id) NOT ENFORCED
)
OPTIONS (
  description = '託送料金マスタ。基本料金と季節別時間帯別の電力量料金、発電側課金単価【期間管理】期間管理（SCD Type 2）。版ごとにサロゲートキーを採番し、業務キー＋期間の重複・隙間を 13.1 ①② で検証する'
);

-- D-12 燃料費調整単価マスタ
CREATE TABLE IF NOT EXISTS dim_fuel_adjustments (
  fuel_adj_id                        INT64 NOT NULL OPTIONS(description = '燃調単価ID'),
  area_code                          STRING OPTIONS(description = 'エリアコード'),
  voltage_class                      STRING NOT NULL OPTIONS(description = '電圧クラス区分：低圧／高圧・特高'),
  target_month                       STRING NOT NULL OPTIONS(description = '対象年月：例：202609'),
  fuel_adj_rate                      NUMERIC NOT NULL OPTIONS(description = '燃料費調整単価：円/kWh。マイナス値あり'),
  islands_adj_rate                   NUMERIC OPTIONS(description = '離島ユニバーサル単価'),
  is_capped                          BOOL NOT NULL OPTIONS(description = '上限適用フラグ：燃調上限に到達した月'),
  source_company                     STRING NOT NULL OPTIONS(description = '公表元'),
  published_date                     DATE OPTIONS(description = '公表日'),
  tax_type_published                 STRING NOT NULL OPTIONS(description = '税区分（公表時）：公表元により税込／税抜が混在する。Silver の fuel_adj_rate は公表値のまま（丸めない）。Gold の日報バッチがこの区分を見て税抜化する（1.5）'),
  PRIMARY KEY (fuel_adj_id) NOT ENFORCED
)
OPTIONS (
  description = '燃料費調整単価マスタ。エリア×電圧クラス×対象年月の公表単価（公表値のまま保持）'
);

-- D-25 市場連動独自パラメータマスタ
CREATE TABLE IF NOT EXISTS dim_market_linked_parameters (
  param_id                           INT64 NOT NULL OPTIONS(description = 'パラメータID'),
  rate_menu_code                     STRING OPTIONS(description = '料金メニューコード'),
  area_code                          STRING OPTIONS(description = 'エリアコード'),
  voltage_class                      STRING OPTIONS(description = '電圧クラス区分：NULL＝全電圧共通'),
  scope_level                        STRING NOT NULL OPTIONS(description = '適用スコープ：MENU（メニュー×エリア：標準）／CUSTOMER（顧客単体）／POINT（地点単体）。Q-17 の枠。現時点は MENU のみ運用し、特高の個別特約が確定した時点で CUSTOMER / POINT 行を追加する'),
  customer_id                        STRING OPTIONS(description = '顧客ID：scope_level = \'CUSTOMER\' のときのみ必須'),
  demand_point_number                STRING OPTIONS(description = '需要地点番号：scope_level = \'POINT\' のときのみ必須'),
  price_cap                          NUMERIC OPTIONS(description = '上限価格（キャップ）：円/kWh。特約で上限がある場合。予備枠'),
  price_floor                        NUMERIC OPTIONS(description = '最低保証単価：円/kWh。予備枠'),
  procurement_adj_rate               NUMERIC NOT NULL OPTIONS(description = '自社調達調整単価：円/kWh。JEPX高騰ヘッジ・相対調達差の吸収分'),
  retail_margin_rate                 NUMERIC NOT NULL OPTIONS(description = '小売固定手数料：円/kWh'),
  operation_fee_rate                 NUMERIC OPTIONS(description = '業務管理費等：円/kWh'),
  capacity_pass_through_rate         NUMERIC OPTIONS(description = '容量拠出金転嫁単価：転嫁する場合のみ'),
  reference_market                   STRING NOT NULL OPTIONS(description = '参照市場区分：スポット／時間前／加重平均'),
  revision_version                   INT64 NOT NULL OPTIONS(description = '改定通番'),
  start_date                         DATE NOT NULL OPTIONS(description = '適用開始日'),
  end_date                           DATE NOT NULL DEFAULT '9999-12-31' OPTIONS(description = '適用終了日：有効行は 9999-12-31'),
  approved_by                        STRING NOT NULL OPTIONS(description = '承認者／承認日時：自社裁量の単価のため承認証跡を必須とする'),
  approved_at                        TIMESTAMP NOT NULL OPTIONS(description = '承認者／承認日時：自社裁量の単価のため承認証跡を必須とする'),
  PRIMARY KEY (param_id) NOT ENFORCED
)
OPTIONS (
  description = '市場連動独自パラメータマスタ。自社裁量マージンと大口個別特約（承認証跡付き）【期間管理】期間管理（SCD Type 2）。版ごとにサロゲートキーを採番し、業務キー＋期間の重複・隙間を 13.1 ①② で検証する'
);

-- D-13 容量拠出金マスタ
CREATE TABLE IF NOT EXISTS dim_capacity_contribution_rates (
  capacity_rate_id                   INT64 NOT NULL OPTIONS(description = '拠出金ID'),
  area_code                          STRING OPTIONS(description = 'エリアコード'),
  fiscal_year                        INT64 NOT NULL OPTIONS(description = '会計年度'),
  capacity_kwh_rate                  NUMERIC NOT NULL OPTIONS(description = '電力量一律拠出金単価：円/kWh。日報の調達原価に用いる単価（確定）'),
  capacity_kw_rate                   NUMERIC OPTIONS(description = 'ピーク時kW拠出金単価：円/kW。予備枠。現行設計では使用しない。制度がピーク時kW按分へ移行した場合に備えて列だけ残す'),
  start_date                         DATE NOT NULL OPTIONS(description = '適用開始日'),
  end_date                           DATE NOT NULL DEFAULT '9999-12-31' OPTIONS(description = '適用終了日：有効行は 9999-12-31'),
  PRIMARY KEY (capacity_rate_id) NOT ENFORCED
)
OPTIONS (
  description = '容量拠出金マスタ。年度ごとの電力量比例拠出金単価【期間管理】期間管理（SCD Type 2）。版ごとにサロゲートキーを採番し、業務キー＋期間の重複・隙間を 13.1 ①② で検証する'
);

-- D-14 再エネ賦課金マスタ
CREATE TABLE IF NOT EXISTS dim_fit_levy_rates (
  levy_rate_id                       INT64 NOT NULL OPTIONS(description = '賦課金ID'),
  fiscal_year                        INT64 NOT NULL OPTIONS(description = '会計年度：賦課金年度（5月検針分〜翌4月検針分）'),
  fit_levy_rate_incl_tax             NUMERIC NOT NULL OPTIONS(description = '公表単価（税込）：円/kWh・全国一律。国の公表値をそのまま保持し、計算にもこの税込単価を使う（確定・Q-9）。単価を税抜化した列は持たない（端数ズレの原因になるため）'),
  apply_basis                        STRING NOT NULL OPTIONS(description = '適用基準：BILLING_MONTH 固定。日付（target_date）ではなく検針月（請求月）で切り替える'),
  start_billing_month                STRING NOT NULL OPTIONS(description = '適用開始請求月／終了請求月：例：202605〜202704（5月検針分から翌年4月検針分まで）'),
  end_billing_month                  STRING NOT NULL OPTIONS(description = '適用開始請求月／終了請求月：例：202605〜202704（5月検針分から翌年4月検針分まで）'),
  PRIMARY KEY (levy_rate_id) NOT ENFORCED
)
OPTIONS (
  description = '再エネ賦課金マスタ。国が年度ごとに公表する税込単価を検針月基準で管理'
);

-- D-31 検針サイクルマスタ
CREATE TABLE IF NOT EXISTS dim_meter_reading_cycles (
  demand_point_number                STRING NOT NULL OPTIONS(description = '需要地点番号'),
  billing_month                      STRING NOT NULL OPTIONS(description = '請求月：例：202605（5月検針分）'),
  period_start_date                  DATE NOT NULL OPTIONS(description = '検針期間 開始日／終了日：この期間のコマがこの請求月に属する'),
  period_end_date                    DATE NOT NULL OPTIONS(description = '検針期間 開始日／終了日：この期間のコマがこの請求月に属する'),
  meter_reading_date                 DATE OPTIONS(description = '検針日：検針票の日付'),
  reading_type                       STRING NOT NULL OPTIONS(description = '検針区分：SMART_30MIN（スマートメーター30分値）／VISIT（訪問検針：30分値なし、月1本の総量のみ）／ESTIMATED（一送推定：通信障害・災害時に約款に基づき一送が推定した確定値）。VISIT はプロファイル配分バッチ（B-04b）の起動条件、ESTIMATED は分析除外フラグ'),
  reading_schedule                   STRING NOT NULL OPTIONS(description = '検針方式：DISTRIBUTED（分散検針：検針日が月内でばらつく）／MONTH_END（月末一括検針：暦月と請求月が一致）'),
  load_profile_code                  STRING OPTIONS(description = '適用プロファイルコード：VISIT 地点のみ。dim_load_profiles（D-36）の標準負荷曲線を指定'),
  source                             STRING NOT NULL OPTIONS(description = '情報ソース：一送の検針データ／自社CIS'),
  PRIMARY KEY (demand_point_number, billing_month) NOT ENFORCED
)
OPTIONS (
  description = '検針サイクルマスタ。需要地点ごとの検針期間と請求月、検針区分・検針方式'
);

-- D-36 標準負荷プロファイルマスタ
CREATE TABLE IF NOT EXISTS dim_load_profiles (
  load_profile_id                    INT64 NOT NULL OPTIONS(description = 'プロファイルID'),
  area_code                          STRING NOT NULL OPTIONS(description = 'エリアコード'),
  load_profile_code                  STRING NOT NULL OPTIONS(description = 'プロファイルコード：一送公表の区分（例：低圧電灯／低圧動力／高圧業務）'),
  power_season                       STRING NOT NULL OPTIONS(description = '電力季節：夏季／冬季／その他季（dim_date_calendar.power_season と同値域）'),
  day_type                           STRING NOT NULL OPTIONS(description = '曜日区分：平日／休日'),
  slot_number                        INT64 NOT NULL OPTIONS(description = 'コマ番号：1〜48'),
  ratio                              NUMERIC NOT NULL OPTIONS(description = '配分比率：同一（エリア・コード・季節・曜日区分）内の48コマ合計が 1.000000'),
  start_date                         DATE NOT NULL OPTIONS(description = '適用開始日'),
  end_date                           DATE NOT NULL DEFAULT '9999-12-31' OPTIONS(description = '適用終了日：有効行は 9999-12-31'),
  PRIMARY KEY (load_profile_id) NOT ENFORCED
)
OPTIONS (
  description = '標準負荷プロファイルマスタ。訪問検針地点の月間総量を48コマへ配分する曲線【期間管理】期間管理（SCD Type 2）。版ごとにサロゲートキーを採番し、業務キー＋期間の重複・隙間を 13.1 ①② で検証する'
);

-- D-32 精算丸めルールマスタ
CREATE TABLE IF NOT EXISTS dim_settlement_rounding_rules (
  rounding_rule_id                   INT64 NOT NULL OPTIONS(description = 'ルールID'),
  settlement_source                  STRING NOT NULL OPTIONS(description = '精算元：JEPX_SPOT / JEPX_FEE / TS_WHEELING（一送託送）/ IMBALANCE / CAPACITY / BILATERAL'),
  area_code                          STRING OPTIONS(description = 'エリアコード：一送ごとに異なる場合に指定。NULL＝全エリア共通'),
  rounding_target                    STRING NOT NULL OPTIONS(description = '丸め対象：MONTHLY_TOTAL（月間電力量×単価の総額）／SLOT_AMOUNT（コマ約定額）／TAX_ONLY（税額のみ）'),
  rounding_method                    STRING NOT NULL OPTIONS(description = '丸め方式：ROUND（四捨五入）／FLOOR（切捨て）／CEIL（切上げ）'),
  rounding_unit                      INT64 NOT NULL OPTIONS(description = '丸め単位：1＝円未満、10、100'),
  tax_rounding_stage                 STRING NOT NULL OPTIONS(description = '税の丸め位置：AFTER_TOTAL（税抜総額→課税→丸め）／PER_SLOT（コマごとに課税・丸め）'),
  start_date                         DATE NOT NULL OPTIONS(description = '適用開始日'),
  end_date                           DATE NOT NULL DEFAULT '9999-12-31' OPTIONS(description = '適用終了日：有効行は 9999-12-31'),
  PRIMARY KEY (rounding_rule_id) NOT ENFORCED
)
OPTIONS (
  description = '精算丸めルールマスタ。請求元ごとの丸め対象・方式・単位・税の丸め位置【期間管理】期間管理（SCD Type 2）。版ごとにサロゲートキーを採番し、業務キー＋期間の重複・隙間を 13.1 ①② で検証する'
);

-- D-15 FIPバランシングコストマスタ
CREATE TABLE IF NOT EXISTS dim_fip_bg_privileges (
  cert_fiscal_year                   INT64 NOT NULL OPTIONS(description = 'FIP認定年度：発電設備が FIP 認定を受けた年度'),
  delivery_fiscal_year               INT64 NOT NULL OPTIONS(description = '実需給年度：発電が行われる年度。この軸で激変緩和措置が縮小・終了する'),
  fuel_code                          STRING NOT NULL OPTIONS(description = '電源種別コード'),
  area_code                          STRING NOT NULL OPTIONS(description = 'エリアコード'),
  base_balancing_cost                NUMERIC NOT NULL OPTIONS(description = '基本バランシングコスト：円/kWh。制度の基本部分'),
  subsidy_premium                    NUMERIC NOT NULL OPTIONS(description = '激変緩和上乗せ：円/kWh。経過措置による一律上乗せ。終了年度以降は 0 を明示登録する'),
  total_balancing_premium            NUMERIC NOT NULL OPTIONS(description = '合計バランシングコスト：base_balancing_cost + subsidy_premium。10.9 で用いる'),
  source                             STRING NOT NULL OPTIONS(description = '公表元／公表日：GIO（低炭素投資促進機構）等'),
  published_date                     DATE NOT NULL OPTIONS(description = '公表元／公表日：GIO（低炭素投資促進機構）等'),
  PRIMARY KEY (cert_fiscal_year, delivery_fiscal_year, fuel_code, area_code) NOT ENFORCED
)
OPTIONS (
  description = 'FIPバランシングコストマスタ。認定年度×実需給年度×電源×エリアの4軸で交付単価を管理'
);

-- D-16 消費税マスタ
CREATE TABLE IF NOT EXISTS dim_tax_rates (
  tax_rate_id                        INT64 NOT NULL OPTIONS(description = '消費税率ID'),
  tax_rate                           NUMERIC NOT NULL OPTIONS(description = '消費税率：例：0.1000'),
  is_reduced                         BOOL NOT NULL OPTIONS(description = '軽減税率フラグ'),
  start_date                         DATE NOT NULL OPTIONS(description = '適用開始日'),
  end_date                           DATE NOT NULL DEFAULT '9999-12-31' OPTIONS(description = '適用終了日：有効行は 9999-12-31'),
  PRIMARY KEY (tax_rate_id) NOT ENFORCED
)
OPTIONS (
  description = '消費税マスタ。税率改定および軽減税率の履歴【期間管理】期間管理（SCD Type 2）。版ごとにサロゲートキーを採番し、業務キー＋期間の重複・隙間を 13.1 ①② で検証する'
);

-- D-27 JEPX取引手数料マスタ
CREATE TABLE IF NOT EXISTS dim_jepx_transaction_fees (
  fee_id                             INT64 NOT NULL OPTIONS(description = '手数料ID'),
  market_type                        STRING NOT NULL OPTIONS(description = '市場種別：スポット／時間前／先渡／非化石'),
  fee_type                           STRING NOT NULL OPTIONS(description = '手数料種別：約定手数料／決済代行手数料／システム利用料／会費'),
  charge_method                      STRING NOT NULL OPTIONS(description = '課金方式：PER_KWH／PER_AMOUNT／FIXED_MONTHLY'),
  trade_side                         STRING NOT NULL OPTIONS(description = '売買区分：買 または 売。「両方」は使わず2行に分けて登録する（結合時の行増殖防止）'),
  unit_rate                          NUMERIC NOT NULL OPTIONS(description = '単価：円/kWh、料率、円/月（課金方式で意味が変わる）'),
  tax_type                           STRING NOT NULL OPTIONS(description = '税区分'),
  payee                              STRING NOT NULL OPTIONS(description = '支払先'),
  start_date                         DATE NOT NULL OPTIONS(description = '適用開始日'),
  end_date                           DATE NOT NULL DEFAULT '9999-12-31' OPTIONS(description = '適用終了日：有効行は 9999-12-31'),
  PRIMARY KEY (fee_id) NOT ENFORCED
)
OPTIONS (
  description = 'JEPX取引手数料マスタ。従量手数料と定額手数料の単価【期間管理】期間管理（SCD Type 2）。版ごとにサロゲートキーを採番し、業務キー＋期間の重複・隙間を 13.1 ①② で検証する'
);

-- D-28 相対・PPA調達契約マスタ
CREATE TABLE IF NOT EXISTS dim_procurement_contracts (
  procurement_contract_id            STRING NOT NULL OPTIONS(description = '調達契約ID：：同一契約の条件改定（単価改定等）では同じ値を維持したまま新しい start_date の行を追加する'),
  contract_type                      STRING NOT NULL OPTIONS(description = '契約種別：相対／PPA（フィジカル）／PPA（バーチャル）／先物'),
  counterparty_account_id            STRING OPTIONS(description = '相手先事業者ID'),
  area_code                          STRING OPTIONS(description = '受渡エリアコード'),
  delivery_profile                   STRING NOT NULL OPTIONS(description = '受渡形態：ベース／ピーク／実発電量連動'),
  contract_kw                        NUMERIC OPTIONS(description = '契約数量(kW)：ベース・ピークの場合'),
  contract_price                     NUMERIC OPTIONS(description = '契約単価(円/kWh)：固定の場合'),
  pricing_method                     STRING NOT NULL OPTIONS(description = '価格決定方式：固定／市場連動＋差金'),
  supply_point_number                STRING OPTIONS(description = '紐付け受給地点番号：フィジカルPPAで特定電源に紐付く場合'),
  tax_type                           STRING NOT NULL OPTIONS(description = '税区分：税抜／不課税（先物差金・バーチャルPPAの差金は不課税）'),
  start_date                         DATE NOT NULL OPTIONS(description = '適用開始日'),
  end_date                           DATE NOT NULL DEFAULT '9999-12-31' OPTIONS(description = '適用終了日：有効行は 9999-12-31'),
  PRIMARY KEY (procurement_contract_id, start_date) NOT ENFORCED
)
OPTIONS (
  description = '相対・PPA調達契約マスタ。契約条件の改定履歴【期間管理】主キーは業務識別子＋適用開始日の複合キー。識別子は改定時も変更しない（安定識別子）'
);

-- D-33 非化石証書価値マスタ
CREATE TABLE IF NOT EXISTS dim_nonfossil_certificate_prices (
  cert_price_id                      INT64 NOT NULL OPTIONS(description = '証書単価ID'),
  certificate_type                   STRING NOT NULL OPTIONS(description = '証書種別：FIT_NONFOSSIL（FIT非化石）／NONFIT_RENEWABLE（非FIT非化石・再エネ指定）／NONFIT_UNSPECIFIED（非FIT非化石・指定なし）'),
  fiscal_year                        INT64 NOT NULL OPTIONS(description = '対象年度：証書が対応する実需給年度'),
  unit_price                         NUMERIC NOT NULL OPTIONS(description = '証書単価（税抜）：円/kWh。オークション約定の加重平均、または相対単価'),
  price_source                       STRING NOT NULL OPTIONS(description = '単価ソース：JEPX_AUCTION／BILATERAL'),
  tax_type                           STRING NOT NULL OPTIONS(description = '税区分：税抜固定'),
  start_date                         DATE NOT NULL OPTIONS(description = '適用開始日'),
  end_date                           DATE NOT NULL DEFAULT '9999-12-31' OPTIONS(description = '適用終了日：有効行は 9999-12-31'),
  PRIMARY KEY (cert_price_id) NOT ENFORCED
)
OPTIONS (
  description = '非化石証書価値マスタ。証書種別×年度の調達単価【期間管理】期間管理（SCD Type 2）。版ごとにサロゲートキーを採番し、業務キー＋期間の重複・隙間を 13.1 ①② で検証する'
);

-- D-17 日付カレンダーマスタ
CREATE TABLE IF NOT EXISTS dim_date_calendar (
  target_date                        DATE NOT NULL OPTIONS(description = '対象日'),
  calendar_year                      INT64 NOT NULL OPTIONS(description = '暦年／暦月'),
  calendar_month                     INT64 NOT NULL OPTIONS(description = '暦年／暦月'),
  year_month                         STRING NOT NULL OPTIONS(description = '年月：202609'),
  fiscal_year                        INT64 OPTIONS(description = '会計年度'),
  fiscal_half_code                   STRING OPTIONS(description = '会計半期コード：例：2026-FH1'),
  fiscal_half_no                     INT64 NOT NULL OPTIONS(description = '会計半期番号：1：上期、2：下期'),
  fiscal_quarter_code                STRING OPTIONS(description = '会計四半期コード：例：2026-FQ2'),
  fiscal_quarter_no                  INT64 NOT NULL OPTIONS(description = '会計四半期番号：1〜4'),
  fiscal_month_no                    INT64 NOT NULL OPTIONS(description = '会計月次番号：4月開始なら 4月=1 … 3月=12'),
  day_of_fiscal_year                 INT64 NOT NULL OPTIONS(description = '会計年度内経過日数：前年同期比のオフセット計算用'),
  day_of_week                        STRING NOT NULL OPTIONS(description = '曜日区分／曜日番号：Mon〜Sun／1(月)〜7(日)'),
  day_of_week_no                     INT64 NOT NULL OPTIONS(description = '曜日区分／曜日番号：Mon〜Sun／1(月)〜7(日)'),
  is_weekday                         BOOL NOT NULL OPTIONS(description = '平日フラグ：月〜金かつ祝日でない'),
  is_public_holiday                  BOOL NOT NULL OPTIONS(description = '公的休日フラグ：土日祝。dim_public_holidays から導出'),
  is_national_holiday                BOOL NOT NULL OPTIONS(description = '国民の祝日フラグ：土日を除く祝日のみ 1'),
  holiday_type                       STRING OPTIONS(description = '休日区分／祝日名：dim_public_holidays を非正規化保持'),
  holiday_name                       STRING OPTIONS(description = '休日区分／祝日名：dim_public_holidays を非正規化保持'),
  is_system_holiday                  BOOL NOT NULL OPTIONS(description = '自社非稼働日フラグ：土日祝＋自社休業日。ETL・請求バッチの稼働制御'),
  power_season                       STRING NOT NULL OPTIONS(description = '電力季節区分：夏季／冬季／その他季'),
  daily_data_status                  STRING OPTIONS(description = '日次データステータス：速報／確報／確定（日報画面の表示切替）'),
  PRIMARY KEY (target_date) NOT ENFORCED
)
PARTITION BY target_date
OPTIONS (
  description = '日付カレンダーマスタ。過去10年〜未来10年の日付と会計期間・休日・電力季節の導出列'
);

-- D-18 30分コマカレンダーマスタ
CREATE TABLE IF NOT EXISTS dim_slot_calendar (
  slot_number                        INT64 NOT NULL OPTIONS(description = 'コマ番号：1〜48'),
  start_time                         STRING NOT NULL OPTIONS(description = '開始時刻／終了時刻'),
  end_time                           STRING NOT NULL OPTIONS(description = '開始時刻／終了時刻'),
  jepx_time_class                    STRING NOT NULL OPTIONS(description = '時間帯区分：昼間／夜間'),
  is_peak                            BOOL NOT NULL OPTIONS(description = 'ピークフラグ（現物・料金用）：料金メニューの夏季ピーク判定（例：13:00〜16:00）。先物とは独立'),
  fwd_product_type                   STRING NOT NULL OPTIONS(description = '先物対応区分：Base_Only／Base_and_Peak。先物商品（Base／日中ロード）がどのコマに対応するか'),
  PRIMARY KEY (slot_number) NOT ENFORCED
)
OPTIONS (
  description = '30分コマカレンダーマスタ。48コマの時間帯区分・現物ピーク・先物商品区分'
);

-- D-19 汎用休日マスタ
CREATE TABLE IF NOT EXISTS dim_public_holidays (
  holiday_date                       DATE NOT NULL OPTIONS(description = '休日日付'),
  holiday_type                       STRING NOT NULL OPTIONS(description = '休日区分コード：下表'),
  holiday_name                       STRING NOT NULL OPTIONS(description = '休日名称'),
  is_national_holiday                BOOL NOT NULL OPTIONS(description = '国民の祝日フラグ：TRUE：祝日法に基づく、FALSE：土日'),
  source                             STRING NOT NULL OPTIONS(description = '情報ソース：DIGITAL_AGENCY_CSV／GENERATED（土日）'),
  registered_date                    DATE NOT NULL OPTIONS(description = '登録日'),
  remarks                            STRING OPTIONS(description = '備考：臨時・特例の根拠'),
  PRIMARY KEY (holiday_date) NOT ENFORCED
)
OPTIONS (
  description = '汎用休日マスタ。土日とデジタル庁配信の公的休日を一元管理'
);

-- D-26 取引先休日マスタ
CREATE TABLE IF NOT EXISTS dim_account_holidays (
  account_holiday_id                 STRING NOT NULL OPTIONS(description = '取引先休日ID：サロゲートキー。業務キー (account_id, account_holiday_date, demand_point_number) は demand_point_number が NULL を取りうるため主キーにできない。重複は 13.1 で検証する'),
  account_id                         STRING NOT NULL OPTIONS(description = '会社ID：ACCOUNT_SELF（自社）または顧客の事業者ID'),
  account_holiday_date               DATE NOT NULL OPTIONS(description = '取引先休日日付'),
  demand_point_number                STRING OPTIONS(description = '適用需要地点：NULL＝その会社の全地点。工場ごとに休業日が違う場合に限定'),
  holiday_reason                     STRING NOT NULL OPTIONS(description = '休日理由'),
  account_holiday_type               STRING NOT NULL OPTIONS(description = '休日区分：YEAR_END / OBON / ANNIVERSARY / SHUTDOWN / OTHER'),
  expected_load_ratio                NUMERIC NOT NULL OPTIONS(description = '想定稼働率：平常日＝1.00 に対する比。完全停止＝0.00、半稼働＝0.50。予測モデルの特徴量としてそのまま使う数値。文字列の稼働レベルは持たない（区分は account_holiday_type で表す）'),
  applies_to_tariff                  BOOL NOT NULL OPTIONS(description = '料金適用フラグ：自社（ACCOUNT_SELF）の全社休日のみ意味を持つ。 TRUE＝供給約款で「当社が定める休日」として顧客の休日単価に適用する日。FALSE＝社内の業務休業日（バッチ・窓口の稼働制御のみ）。顧客企業の行は常に 0'),
  source                             STRING NOT NULL OPTIONS(description = '情報ソース：自社総務／顧客申告／営業ヒアリング'),
  registered_date                    DATE NOT NULL OPTIONS(description = '登録日／更新日時'),
  updated_at                         TIMESTAMP NOT NULL OPTIONS(description = '登録日／更新日時'),
  PRIMARY KEY (account_holiday_id) NOT ENFORCED
)
OPTIONS (
  description = '取引先休日マスタ。自社の約款休日と顧客企業の休業日・想定稼働率'
);

-- D-20 休日判定ルールマスタ
CREATE TABLE IF NOT EXISTS dim_holiday_rules (
  holiday_rule_code                  STRING NOT NULL OPTIONS(description = '休日判定ルールコード：STD, MENU_B, FORECAST, BATCH'),
  holiday_rule_name                  STRING NOT NULL OPTIONS(description = 'ルール名称'),
  rule_purpose                       STRING NOT NULL OPTIONS(description = '用途区分：料金／予測／業務カレンダー'),
  include_saturday                   BOOL NOT NULL OPTIONS(description = '土曜を休日扱い'),
  include_sunday                     BOOL NOT NULL OPTIONS(description = '日曜を休日扱い'),
  include_self_holiday               BOOL NOT NULL OPTIONS(description = '自社休日を含める：料金用途では applies_to_tariff の全社休日のみを対象とする'),
  include_customer_holiday           BOOL NOT NULL OPTIONS(description = '顧客休日を含める：需要予測用途のみ 1'),
  start_date                         DATE NOT NULL OPTIONS(description = '適用開始日'),
  end_date                           DATE NOT NULL DEFAULT '9999-12-31' OPTIONS(description = '適用終了日：有効行は 9999-12-31'),
  PRIMARY KEY (holiday_rule_code, start_date) NOT ENFORCED  -- 期間管理
)
OPTIONS (
  description = '休日判定ルールマスタ。用途・約款別の休日扱いの定義【期間管理】主キーは業務識別子＋適用開始日の複合キー。識別子は改定時も変更しない（安定識別子）'
);

-- D-21 休日判定ルール明細
CREATE TABLE IF NOT EXISTS dim_holiday_rule_details (
  holiday_rule_code                  STRING NOT NULL OPTIONS(description = '休日判定ルールコード'),
  holiday_type                       STRING NOT NULL OPTIONS(description = '休日区分コード'),
  is_treated_as_holiday              BOOL NOT NULL OPTIONS(description = '休日扱いフラグ'),
  PRIMARY KEY (holiday_rule_code, holiday_type) NOT ENFORCED
)
OPTIONS (
  description = '休日判定ルール明細。ルールコードと休日区分のマッピング'
);

-- D-22 会計年度マスタ
CREATE TABLE IF NOT EXISTS dim_fiscal_years (
  fiscal_year                        INT64 NOT NULL OPTIONS(description = '会計年度：例：2026'),
  fiscal_year_label                  STRING NOT NULL OPTIONS(description = 'ラベル：FY2026'),
  start_date                         DATE NOT NULL OPTIONS(description = '開始日／終了日：年度の所属はこの2列との BETWEEN で決める（関数で計算しない）'),
  end_date                           DATE NOT NULL DEFAULT '9999-12-31' OPTIONS(description = '開始日／終了日：年度の所属はこの2列との BETWEEN で決める（関数で計算しない）'),
  days_count                         INT64 NOT NULL OPTIONS(description = '日数／月数：通常 12 ヶ月。変則決算は 12 未満'),
  months_count                       INT64 NOT NULL OPTIONS(description = '日数／月数：通常 12 ヶ月。変則決算は 12 未満'),
  start_month                        INT64 NOT NULL OPTIONS(description = '開始月：将来年度を自動生成する際の既定値（最新の通常年度の値を引き継ぐ）'),
  is_irregular                       BOOL NOT NULL OPTIONS(description = '変則決算フラグ：TRUE：移行期の変則年度（例：9ヶ月決算）。13.1 ⑥ の「1年度＝2半期＝4四半期」検証を免除し、前年同期比の対象外とする'),
  is_current                         BOOL NOT NULL OPTIONS(description = '現在年度フラグ：日次で更新'),
  close_status                       STRING NOT NULL OPTIONS(description = '締め状態：未締め／仮締め／確定。確定期間へのリラン抑止に使う'),
  updated_at                         TIMESTAMP NOT NULL OPTIONS(description = '最終更新日時：カレンダー導出列の差分更新トリガー（12.8）'),
  PRIMARY KEY (fiscal_year) NOT ENFORCED
)
OPTIONS (
  description = '会計年度マスタ。決算期変更・変則決算に耐えるマスタ駆動型の年度定義【期間管理】期間管理（SCD Type 2）。版ごとにサロゲートキーを採番し、業務キー＋期間の重複・隙間を 13.1 ①② で検証する'
);

-- D-23 会計半期マスタ
CREATE TABLE IF NOT EXISTS dim_fiscal_halves (
  fiscal_half_code                   STRING NOT NULL OPTIONS(description = '会計半期コード：2026-FH1'),
  fiscal_year                        INT64 OPTIONS(description = '会計年度'),
  half_no                            INT64 NOT NULL OPTIONS(description = '半期番号／名称：1：上期、2：下期'),
  half_name                          STRING NOT NULL OPTIONS(description = '半期番号／名称：1：上期、2：下期'),
  start_date                         DATE NOT NULL OPTIONS(description = '開始日／終了日／日数'),
  end_date                           DATE NOT NULL DEFAULT '9999-12-31' OPTIONS(description = '開始日／終了日／日数'),
  days_count                         INT64 NOT NULL OPTIONS(description = '開始日／終了日／日数'),
  close_status                       STRING NOT NULL OPTIONS(description = '締め状態'),
  updated_at                         TIMESTAMP NOT NULL OPTIONS(description = '最終更新日時：12.8 の差分更新トリガー'),
  PRIMARY KEY (fiscal_half_code) NOT ENFORCED
)
OPTIONS (
  description = '会計半期マスタ。上期・下期の構成期間【期間管理】期間管理（SCD Type 2）。版ごとにサロゲートキーを採番し、業務キー＋期間の重複・隙間を 13.1 ①② で検証する'
);

-- D-24 会計四半期マスタ
CREATE TABLE IF NOT EXISTS dim_fiscal_quarters (
  fiscal_quarter_code                STRING NOT NULL OPTIONS(description = '会計四半期コード：2026-FQ2'),
  fiscal_year                        INT64 OPTIONS(description = '会計年度／会計半期コード'),
  fiscal_half_code                   STRING OPTIONS(description = '会計年度／会計半期コード'),
  quarter_no                         INT64 NOT NULL OPTIONS(description = '四半期番号／名称'),
  quarter_name                       STRING NOT NULL OPTIONS(description = '四半期番号／名称'),
  calendar_quarter                   STRING OPTIONS(description = '暦四半期：2026Q3（外部比較用）'),
  start_date                         DATE NOT NULL OPTIONS(description = '開始日／終了日／日数'),
  end_date                           DATE NOT NULL DEFAULT '9999-12-31' OPTIONS(description = '開始日／終了日／日数'),
  days_count                         INT64 NOT NULL OPTIONS(description = '開始日／終了日／日数'),
  close_status                       STRING NOT NULL OPTIONS(description = '締め状態'),
  updated_at                         TIMESTAMP NOT NULL OPTIONS(description = '最終更新日時：12.8 の差分更新トリガー'),
  PRIMARY KEY (fiscal_quarter_code) NOT ENFORCED
)
OPTIONS (
  description = '会計四半期マスタ。FQ1〜FQ4 の構成期間【期間管理】期間管理（SCD Type 2）。版ごとにサロゲートキーを採番し、業務キー＋期間の重複・隙間を 13.1 ①② で検証する'
);



-- ============================================================
-- FILE: sql/ddl/facts.sql
-- ============================================================
-- =============================================================================
-- 電力小売データ分析基盤
-- Silver 層 ファクト（f_*）DDL
-- 生成元：電力小売データ分析基盤.md（第8章のテーブル定義）
-- 注意：本ファイルは設計書の項目定義から機械生成した骨組み（正本は設計書）。
--       型・NOT NULL は設計書の記載に従い、記載のない列は命名から推定している。
--       デプロイ前に dev 環境で DDL レビュー（13.1／フェーズ1完了条件）を行うこと。
-- =============================================================================

-- FX-01 JEPXスポット価格
CREATE TABLE IF NOT EXISTS fact_jepx_spot_prices (
  jepx_price_id                      INT64 NOT NULL OPTIONS(description = '価格データID'),
  target_date                        DATE OPTIONS(description = '対象日／コマ：受渡日'),
  slot_number                        INT64 OPTIONS(description = '対象日／コマ：受渡日'),
  area_code                          STRING OPTIONS(description = 'エリアコード'),
  system_price                       NUMERIC NOT NULL OPTIONS(description = 'システムプライス：円/kWh'),
  area_price                         NUMERIC NOT NULL OPTIONS(description = 'エリアプライス：円/kWh'),
  sell_volume                        NUMERIC OPTIONS(description = '売り／買い入札量：kWh'),
  buy_volume                         NUMERIC OPTIONS(description = '売り／買い入札量：kWh'),
  contract_volume                    NUMERIC OPTIONS(description = '約定量：kWh'),
  tax_type                           STRING NOT NULL OPTIONS(description = '税区分：税抜 固定（確定）。逆算・丸めを行わない'),
  fetched_at                         TIMESTAMP OPTIONS(description = '取得日時'),
  ingestion_run_id                   STRING OPTIONS(description = 'パイプライン実行ID（命名・運用定義書 11.3）'),
  loaded_at                          TIMESTAMP OPTIONS(description = 'BigQueryへのロード日時UTC'),
  pipeline_version                   STRING OPTIONS(description = '処理コードまたはモデルのバージョン'),
  PRIMARY KEY (jepx_price_id) NOT ENFORCED
)
PARTITION BY target_date
CLUSTER BY area_code
OPTIONS (
  require_partition_filter = TRUE,
  description = 'fact_jepx_spot_prices'
);

-- FX-02 JEPX時間前価格
CREATE TABLE IF NOT EXISTS fact_jepx_intraday_prices (
  intraday_price_id                  INT64 NOT NULL OPTIONS(description = 'ID'),
  target_date                        DATE OPTIONS(description = '対象日／コマ／エリア'),
  slot_number                        INT64 OPTIONS(description = '対象日／コマ／エリア'),
  area_code                          STRING OPTIONS(description = '対象日／コマ／エリア'),
  vwap_price                         NUMERIC OPTIONS(description = '加重平均約定価格'),
  contract_volume                    NUMERIC OPTIONS(description = '約定量'),
  last_price                         NUMERIC OPTIONS(description = '最終約定価格'),
  ingestion_run_id                   STRING OPTIONS(description = 'パイプライン実行ID（命名・運用定義書 11.3）'),
  loaded_at                          TIMESTAMP OPTIONS(description = 'BigQueryへのロード日時UTC'),
  pipeline_version                   STRING OPTIONS(description = '処理コードまたはモデルのバージョン'),
  PRIMARY KEY (intraday_price_id) NOT ENFORCED
)
PARTITION BY target_date
CLUSTER BY area_code
OPTIONS (
  require_partition_filter = TRUE,
  description = 'fact_jepx_intraday_prices'
);

-- FX-03 インバランス料金
CREATE TABLE IF NOT EXISTS fact_imbalance_prices (
  imbalance_price_id                 INT64 NOT NULL OPTIONS(description = 'ID'),
  target_date                        DATE OPTIONS(description = '対象日／コマ／エリア'),
  slot_number                        INT64 OPTIONS(description = '対象日／コマ／エリア'),
  area_code                          STRING OPTIONS(description = '対象日／コマ／エリア'),
  imbalance_price                    NUMERIC NOT NULL OPTIONS(description = 'インバランス料金単価：円/kWh'),
  price_status                       STRING NOT NULL OPTIONS(description = '単価ステータス：暫定／確定／更正'),
  adjustment_term                    NUMERIC OPTIONS(description = '補正項：制度改定に備えた予備'),
  tax_type                           STRING NOT NULL OPTIONS(description = '税区分：受領時の区分をそのまま保持（Silver では丸め・換算しない）。税込の場合は Gold で ÷(1+税率)（未丸め）'),
  revision_count                     INT64 OPTIONS(description = '更正回数／最終更正日時：更正が届くたびに加算・更新'),
  revised_at                         TIMESTAMP OPTIONS(description = '更正回数／最終更正日時：更正が届くたびに加算・更新'),
  ingestion_run_id                   STRING OPTIONS(description = 'パイプライン実行ID（命名・運用定義書 11.3）'),
  loaded_at                          TIMESTAMP OPTIONS(description = 'BigQueryへのロード日時UTC'),
  pipeline_version                   STRING OPTIONS(description = '処理コードまたはモデルのバージョン'),
  PRIMARY KEY (imbalance_price_id) NOT ENFORCED
)
PARTITION BY target_date
CLUSTER BY area_code
OPTIONS (
  require_partition_filter = TRUE,
  description = 'fact_imbalance_prices'
);

-- FX-04 電力先物価格
CREATE TABLE IF NOT EXISTS fact_futures_prices (
  futures_id                         INT64 NOT NULL OPTIONS(description = 'ID'),
  trade_date                         DATE OPTIONS(description = '取引日'),
  exchange                           STRING OPTIONS(description = '取引所'),
  contract_month                     STRING OPTIONS(description = '限月'),
  product_type                       STRING OPTIONS(description = '商品種別'),
  area_code                          STRING OPTIONS(description = 'エリア'),
  settlement_price                   NUMERIC OPTIONS(description = '清算値'),
  open_interest                      NUMERIC OPTIONS(description = '建玉／出来高'),
  volume                             NUMERIC OPTIONS(description = '建玉／出来高'),
  ingestion_run_id                   STRING OPTIONS(description = 'パイプライン実行ID（命名・運用定義書 11.3）'),
  loaded_at                          TIMESTAMP OPTIONS(description = 'BigQueryへのロード日時UTC'),
  pipeline_version                   STRING OPTIONS(description = '処理コードまたはモデルのバージョン'),
  PRIMARY KEY (futures_id) NOT ENFORCED
)
PARTITION BY trade_date
CLUSTER BY exchange, product_type
OPTIONS (
  description = 'fact_futures_prices'
);

-- FX-05 FIP参照価格（A値）
CREATE TABLE IF NOT EXISTS fact_fip_reference_prices (
  target_month                       STRING NOT NULL OPTIONS(description = '対象年月：YYYYMM'),
  fuel_code                          STRING NOT NULL OPTIONS(description = '電源種別コード'),
  area_code                          STRING NOT NULL OPTIONS(description = 'エリアコード'),
  reference_price                    NUMERIC NOT NULL OPTIONS(description = '市場参照価格（A値）：円/kWh・税抜'),
  value_status                       STRING NOT NULL OPTIONS(description = '値のステータス：PROVISIONAL（自社試算）／FINAL（GIO公表）'),
  non_fossil_value                   NUMERIC OPTIONS(description = '非化石価値相当額：公表仕様に含まれる場合'),
  published_date                     DATE OPTIONS(description = '公表日／取込日時：暫定行の published_date は自社試算バッチの実行日'),
  fetched_at                         TIMESTAMP OPTIONS(description = '公表日／取込日時：暫定行の published_date は自社試算バッチの実行日'),
  ingestion_run_id                   STRING OPTIONS(description = 'パイプライン実行ID（命名・運用定義書 11.3）'),
  loaded_at                          TIMESTAMP OPTIONS(description = 'BigQueryへのロード日時UTC'),
  pipeline_version                   STRING OPTIONS(description = '処理コードまたはモデルのバージョン'),
  PRIMARY KEY (target_month, fuel_code, area_code) NOT ENFORCED
)
OPTIONS (
  description = 'fact_fip_reference_prices'
);

-- FX-06 市場連動単価（算出結果）
CREATE TABLE IF NOT EXISTS fact_market_linked_prices (
  linked_price_id                    INT64 NOT NULL OPTIONS(description = 'ID'),
  rate_menu_code                     STRING OPTIONS(description = '料金メニューコード／エリアコード'),
  area_code                          STRING OPTIONS(description = '料金メニューコード／エリアコード'),
  scope_key                          STRING OPTIONS(description = '適用スコープキー'),
  target_date                        DATE OPTIONS(description = '対象日／コマ'),
  slot_number                        INT64 OPTIONS(description = '対象日／コマ'),
  calculated_price                   NUMERIC OPTIONS(description = '算出市場連動単価'),
  market_component                   NUMERIC OPTIONS(description = '内訳：市場価格部分'),
  wheeling_component                 NUMERIC OPTIONS(description = '内訳：託送部分'),
  procurement_adj_component          NUMERIC OPTIONS(description = '内訳：調達調整部分'),
  margin_component                   NUMERIC OPTIONS(description = '内訳：手数料部分'),
  applied_param_id                   INT64 OPTIONS(description = '適用パラメータID'),
  calculated_at                      TIMESTAMP OPTIONS(description = '算出日時'),
  ingestion_run_id                   STRING OPTIONS(description = 'パイプライン実行ID（命名・運用定義書 11.3）'),
  loaded_at                          TIMESTAMP OPTIONS(description = 'BigQueryへのロード日時UTC'),
  pipeline_version                   STRING OPTIONS(description = '処理コードまたはモデルのバージョン'),
  PRIMARY KEY (linked_price_id) NOT ENFORCED
)
PARTITION BY target_date
CLUSTER BY area_code, rate_menu_code
OPTIONS (
  require_partition_filter = TRUE,
  description = 'fact_market_linked_prices'
);

-- FX-07 JEPX約定明細
CREATE TABLE IF NOT EXISTS fact_jepx_trades (
  trade_id                           INT64 NOT NULL OPTIONS(description = '約定ID'),
  exchange_ref_id                    STRING OPTIONS(description = '取引所参照ID：突合キー'),
  market_type                        STRING NOT NULL OPTIONS(description = '市場種別：スポット／時間前'),
  target_date                        DATE OPTIONS(description = '対象日／コマ／エリア'),
  slot_number                        INT64 OPTIONS(description = '対象日／コマ／エリア'),
  area_code                          STRING OPTIONS(description = '対象日／コマ／エリア'),
  trade_side                         STRING NOT NULL OPTIONS(description = '売買区分：買／売'),
  contracted_kwh                     NUMERIC NOT NULL OPTIONS(description = '約定量(kWh)'),
  contracted_price                   NUMERIC NOT NULL OPTIONS(description = '約定価格／約定金額：円/kWh／円'),
  contracted_amount                  NUMERIC NOT NULL OPTIONS(description = '約定価格／約定金額：円/kWh／円'),
  transaction_fee                    NUMERIC NOT NULL OPTIONS(description = '取引手数料(円)：D-27 から算出し確定保持'),
  settlement_fee                     NUMERIC NOT NULL OPTIONS(description = '決済代行手数料(円)：同上'),
  bg_code                            STRING OPTIONS(description = '紐付けBGコード：損益の帰属先'),
  fetched_at                         TIMESTAMP OPTIONS(description = '取込日時'),
  ingestion_run_id                   STRING OPTIONS(description = 'パイプライン実行ID（命名・運用定義書 11.3）'),
  loaded_at                          TIMESTAMP OPTIONS(description = 'BigQueryへのロード日時UTC'),
  pipeline_version                   STRING OPTIONS(description = '処理コードまたはモデルのバージョン'),
  PRIMARY KEY (trade_id) NOT ENFORCED
)
PARTITION BY target_date
CLUSTER BY area_code, bg_code
OPTIONS (
  require_partition_filter = TRUE,
  description = 'fact_jepx_trades'
);

-- FX-08 連系線割当・値差
CREATE TABLE IF NOT EXISTS fact_interconnection_allocations (
  allocation_id                      INT64 NOT NULL OPTIONS(description = 'ID'),
  target_date                        DATE OPTIONS(description = '対象日／コマ'),
  slot_number                        INT64 OPTIONS(description = '対象日／コマ'),
  from_area_code                     STRING OPTIONS(description = '送電元／送電先エリア'),
  to_area_code                       STRING OPTIONS(description = '送電元／送電先エリア'),
  interconnection_name               STRING OPTIONS(description = '連系線区間名'),
  operational_capacity_kw            NUMERIC OPTIONS(description = '運用容量(kW)：広域機関公表値'),
  allocated_capacity_kw              NUMERIC OPTIONS(description = '自社BG割当容量(kW)：割当方式は制度に依存（R-16）'),
  actual_flow_kw                     NUMERIC OPTIONS(description = '実潮流(kW)'),
  is_congested                       BOOL NOT NULL OPTIONS(description = '混雑フラグ'),
  from_area_price                    NUMERIC OPTIONS(description = '送電元／送電先エリアプライス：転記'),
  to_area_price                      NUMERIC OPTIONS(description = '送電元／送電先エリアプライス：転記'),
  price_spread                       NUMERIC OPTIONS(description = 'エリア間値差：送電先 − 送電元'),
  spread_amount                      NUMERIC OPTIONS(description = '値差影響額：自社潮流分'),
  ftr_contract_id                    STRING OPTIONS(description = '間接送電権契約ID'),
  refund_amount                      NUMERIC OPTIONS(description = '還付額：保有時のみ'),
  bg_code                            STRING OPTIONS(description = 'BGコード'),
  data_status                        STRING NOT NULL OPTIONS(description = 'データ区分：暫定／確定'),
  ingestion_run_id                   STRING OPTIONS(description = 'パイプライン実行ID（命名・運用定義書 11.3）'),
  loaded_at                          TIMESTAMP OPTIONS(description = 'BigQueryへのロード日時UTC'),
  pipeline_version                   STRING OPTIONS(description = '処理コードまたはモデルのバージョン'),
  PRIMARY KEY (allocation_id) NOT ENFORCED
)
PARTITION BY target_date
CLUSTER BY bg_code
OPTIONS (
  require_partition_filter = TRUE,
  description = 'fact_interconnection_allocations'
);

-- FX-09 相対・PPA精算明細
CREATE TABLE IF NOT EXISTS fact_procurement_settlements (
  settlement_id                      INT64 NOT NULL OPTIONS(description = '精算ID'),
  procurement_contract_id            STRING OPTIONS(description = '調達契約ID'),
  target_date                        DATE OPTIONS(description = '対象日／コマ／エリア'),
  slot_number                        INT64 OPTIONS(description = '対象日／コマ／エリア'),
  area_code                          STRING OPTIONS(description = '対象日／コマ／エリア'),
  delivered_kwh                      NUMERIC NOT NULL OPTIONS(description = '受渡量(kWh)'),
  unit_price                         NUMERIC NOT NULL OPTIONS(description = '適用単価(円/kWh)：固定、または市場連動＋差金の結果'),
  settlement_amount                  NUMERIC NOT NULL OPTIONS(description = '精算金額(円)：受領値のまま保持（丸め・税抜換算しない。1.5）'),
  tax_type_received                  STRING NOT NULL OPTIONS(description = '受領時税区分：税抜／税込／不課税。相手先通知の表示区分をそのまま持つ。税込の場合のみ Gold（11.5）で ÷(1+税率) を未丸めで適用（レビューで追加。D-28 の tax_type は契約の課税区分で、受領明細の表示区分とは別）'),
  data_status                        STRING NOT NULL OPTIONS(description = 'データ区分：暫定（自社計算）／確定（相手先通知）'),
  ingestion_run_id                   STRING OPTIONS(description = 'パイプライン実行ID（命名・運用定義書 11.3）'),
  loaded_at                          TIMESTAMP OPTIONS(description = 'BigQueryへのロード日時UTC'),
  pipeline_version                   STRING OPTIONS(description = '処理コードまたはモデルのバージョン'),
  PRIMARY KEY (settlement_id) NOT ENFORCED
)
PARTITION BY target_date
CLUSTER BY area_code, procurement_contract_id
OPTIONS (
  require_partition_filter = TRUE,
  description = 'fact_procurement_settlements'
);

-- FX-10 非化石証書購入
CREATE TABLE IF NOT EXISTS fact_nonfossil_certificate_purchases (
  purchase_id                        INT64 NOT NULL OPTIONS(description = '購入ID'),
  certificate_type                   STRING NOT NULL OPTIONS(description = '証書種別／対象年度：D-33 と同一区分'),
  fiscal_year                        INT64 NOT NULL OPTIONS(description = '証書種別／対象年度：D-33 と同一区分'),
  purchased_kwh                      NUMERIC NOT NULL OPTIONS(description = '購入量(kWh)'),
  unit_price                         NUMERIC NOT NULL OPTIONS(description = '購入単価（税抜）／購入金額：円/kWh ／ 円'),
  purchase_amount                    NUMERIC NOT NULL OPTIONS(description = '購入単価（税抜）／購入金額：円/kWh ／ 円'),
  purchase_date                      DATE NOT NULL OPTIONS(description = '購入日／市場：JEPX_NONFOSSIL／BILATERAL'),
  market                             STRING NOT NULL OPTIONS(description = '購入日／市場：JEPX_NONFOSSIL／BILATERAL'),
  allocation_status                  STRING NOT NULL OPTIONS(description = '割当状態：未割当／割当済／償却済'),
  ingestion_run_id                   STRING OPTIONS(description = 'パイプライン実行ID（命名・運用定義書 11.3）'),
  loaded_at                          TIMESTAMP OPTIONS(description = 'BigQueryへのロード日時UTC'),
  pipeline_version                   STRING OPTIONS(description = '処理コードまたはモデルのバージョン'),
  PRIMARY KEY (purchase_id) NOT ENFORCED
)
PARTITION BY purchase_date
OPTIONS (
  description = 'fact_nonfossil_certificate_purchases'
);

-- FT-01 発電計画
CREATE TABLE IF NOT EXISTS fact_gen_plans (
  gen_plan_id                        INT64 NOT NULL OPTIONS(description = '発電計画ID'),
  supply_point_number                STRING OPTIONS(description = '受給地点番号'),
  gen_bg_code                        STRING OPTIONS(description = '発電BGコード'),
  area_code                          STRING OPTIONS(description = 'エリアコード：非正規化'),
  target_date                        DATE OPTIONS(description = '対象日／コマ'),
  slot_number                        INT64 OPTIONS(description = '対象日／コマ'),
  plan_value_kw                      NUMERIC NOT NULL OPTIONS(description = '計画値(kW)：OCCTO提出値（送電端）'),
  plan_basis                         STRING NOT NULL OPTIONS(description = '計画値の基準：発電は原則 SENDING_END'),
  plan_type                          STRING NOT NULL OPTIONS(description = '計画種別：前日計画(DA)／当日計画(ID)'),
  plan_version                       INT64 NOT NULL OPTIONS(description = '計画バージョン：同一種別内の改訂番号'),
  submitted_at                       TIMESTAMP OPTIONS(description = '提出日時：GC判定'),
  created_at                         TIMESTAMP OPTIONS(description = '作成日時'),
  ingestion_run_id                   STRING OPTIONS(description = 'パイプライン実行ID（命名・運用定義書 11.3）'),
  loaded_at                          TIMESTAMP OPTIONS(description = 'BigQueryへのロード日時UTC'),
  pipeline_version                   STRING OPTIONS(description = '処理コードまたはモデルのバージョン'),
  PRIMARY KEY (gen_plan_id) NOT ENFORCED
)
PARTITION BY target_date
CLUSTER BY area_code, supply_point_number
OPTIONS (
  require_partition_filter = TRUE,
  description = 'fact_gen_plans'
);

-- FT-02 需要計画（需要予測）
CREATE TABLE IF NOT EXISTS fact_dem_plans (
  dem_plan_id                        INT64 NOT NULL OPTIONS(description = '需要計画ID'),
  demand_point_number                STRING OPTIONS(description = '需要地点番号'),
  dem_bg_code                        STRING OPTIONS(description = '需要BGコード'),
  area_code                          STRING OPTIONS(description = 'エリアコード'),
  target_date                        DATE OPTIONS(description = '対象日／コマ'),
  slot_number                        INT64 OPTIONS(description = '対象日／コマ'),
  forecast_value_kw                  NUMERIC NOT NULL OPTIONS(description = '予測需要量(kW)'),
  plan_basis                         STRING NOT NULL OPTIONS(description = '計画値の基準：SENDING_END（送電端：OCCTO提出値）／RECEIVING_END（受電端：予測モデルの生値）。精算対象の計画（plan_type がGC確定）は必ず SENDING_END'),
  plan_type                          STRING NOT NULL OPTIONS(description = '計画種別：前日計画(DA)／当日計画(ID)'),
  plan_version                       INT64 NOT NULL OPTIONS(description = '計画バージョン：同一種別内の改訂番号。上書きせず履歴保持'),
  model_version                      STRING OPTIONS(description = '予測モデルバージョン：精度追跡用'),
  weather_scenario_id                STRING OPTIONS(description = '気象シナリオID'),
  submitted_at                       TIMESTAMP OPTIONS(description = '提出日時：OCCTO への提出日時（GC判定）。予測のみの行は NULL'),
  created_at                         TIMESTAMP OPTIONS(description = '作成日時'),
  ingestion_run_id                   STRING OPTIONS(description = 'パイプライン実行ID（命名・運用定義書 11.3）'),
  loaded_at                          TIMESTAMP OPTIONS(description = 'BigQueryへのロード日時UTC'),
  pipeline_version                   STRING OPTIONS(description = '処理コードまたはモデルのバージョン'),
  PRIMARY KEY (dem_plan_id) NOT ENFORCED
)
PARTITION BY target_date
CLUSTER BY area_code, demand_point_number
OPTIONS (
  require_partition_filter = TRUE,
  description = 'fact_dem_plans'
);

-- FT-03 / FT-06 速報
CREATE TABLE IF NOT EXISTS fact_gen_actuals_stream (
  stream_id                          INT64 NOT NULL OPTIONS(description = 'ID'),
  supply_point_number                STRING OPTIONS(description = '地点番号'),
  area_code                          STRING OPTIONS(description = 'エリアコード'),
  target_date                        DATE OPTIONS(description = '対象日／コマ'),
  slot_number                        INT64 OPTIONS(description = '対象日／コマ'),
  actual_value_kwh                   NUMERIC NOT NULL OPTIONS(description = '実績値(kWh)：未検証の生値'),
  inserted_at                        TIMESTAMP NOT NULL OPTIONS(description = '取込日時：重複時は最新を採用'),
  source_type                        STRING OPTIONS(description = 'ソース区分：スマメ／自社パルス／送配電API'),
  ingestion_run_id                   STRING OPTIONS(description = 'パイプライン実行ID（命名・運用定義書 11.3）'),
  loaded_at                          TIMESTAMP OPTIONS(description = 'BigQueryへのロード日時UTC'),
  pipeline_version                   STRING OPTIONS(description = '処理コードまたはモデルのバージョン'),
  PRIMARY KEY (stream_id) NOT ENFORCED
)
PARTITION BY DATE(inserted_at)
CLUSTER BY area_code, supply_point_number
OPTIONS (
  require_partition_filter = TRUE, partition_expiration_days = 7,
  description = 'fact_gen_actuals_stream'
);

-- (需要側) FT-03 / FT-06 速報
CREATE TABLE IF NOT EXISTS fact_dem_actuals_stream (
  stream_id                          INT64 NOT NULL OPTIONS(description = 'ID'),
  demand_point_number                STRING OPTIONS(description = '地点番号'),
  area_code                          STRING OPTIONS(description = 'エリアコード'),
  target_date                        DATE OPTIONS(description = '対象日／コマ'),
  slot_number                        INT64 OPTIONS(description = '対象日／コマ'),
  actual_value_kwh                   NUMERIC NOT NULL OPTIONS(description = '実績値(kWh)：未検証の生値'),
  inserted_at                        TIMESTAMP NOT NULL OPTIONS(description = '取込日時：重複時は最新を採用'),
  source_type                        STRING OPTIONS(description = 'ソース区分：スマメ／自社パルス／送配電API'),
  ingestion_run_id                   STRING OPTIONS(description = 'パイプライン実行ID（命名・運用定義書 11.3）'),
  loaded_at                          TIMESTAMP OPTIONS(description = 'BigQueryへのロード日時UTC'),
  pipeline_version                   STRING OPTIONS(description = '処理コードまたはモデルのバージョン'),
  PRIMARY KEY (stream_id) NOT ENFORCED
)
PARTITION BY DATE(inserted_at)
CLUSTER BY area_code, demand_point_number
OPTIONS (
  require_partition_filter = TRUE, partition_expiration_days = 7,
  description = 'fact_dem_actuals_stream'
);

-- FT-13 速報最新行キャッシュ
CREATE TABLE IF NOT EXISTS fact_gen_actuals_stream_latest (
  supply_point_number                STRING NOT NULL OPTIONS(description = '地点番号／対象日／コマ：1行に集約'),
  target_date                        DATE NOT NULL OPTIONS(description = '地点番号／対象日／コマ：1行に集約'),
  slot_number                        INT64 NOT NULL OPTIONS(description = '地点番号／対象日／コマ：1行に集約'),
  area_code                          STRING OPTIONS(description = 'エリアコード'),
  actual_value_kwh                   NUMERIC NOT NULL OPTIONS(description = '実績値(kWh)：最新の inserted_at を持つ値'),
  source_inserted_at                 TIMESTAMP NOT NULL OPTIONS(description = '元の取込日時'),
  refreshed_at                       TIMESTAMP NOT NULL OPTIONS(description = '更新日時：マイクロバッチの実行時刻'),
  ingestion_run_id                   STRING OPTIONS(description = 'パイプライン実行ID（命名・運用定義書 11.3）'),
  loaded_at                          TIMESTAMP OPTIONS(description = 'BigQueryへのロード日時UTC'),
  pipeline_version                   STRING OPTIONS(description = '処理コードまたはモデルのバージョン'),
  PRIMARY KEY (supply_point_number, target_date, slot_number) NOT ENFORCED
)
PARTITION BY target_date
CLUSTER BY area_code, supply_point_number
OPTIONS (
  require_partition_filter = TRUE, partition_expiration_days = 7,
  description = 'fact_gen_actuals_stream_latest'
);

-- (需要側) FT-13 速報最新行キャッシュ
CREATE TABLE IF NOT EXISTS fact_dem_actuals_stream_latest (
  demand_point_number                STRING NOT NULL OPTIONS(description = '地点番号／対象日／コマ：1行に集約'),
  target_date                        DATE NOT NULL OPTIONS(description = '地点番号／対象日／コマ：1行に集約'),
  slot_number                        INT64 NOT NULL OPTIONS(description = '地点番号／対象日／コマ：1行に集約'),
  area_code                          STRING OPTIONS(description = 'エリアコード'),
  actual_value_kwh                   NUMERIC NOT NULL OPTIONS(description = '実績値(kWh)：最新の inserted_at を持つ値'),
  source_inserted_at                 TIMESTAMP NOT NULL OPTIONS(description = '元の取込日時'),
  refreshed_at                       TIMESTAMP NOT NULL OPTIONS(description = '更新日時：マイクロバッチの実行時刻'),
  ingestion_run_id                   STRING OPTIONS(description = 'パイプライン実行ID（命名・運用定義書 11.3）'),
  loaded_at                          TIMESTAMP OPTIONS(description = 'BigQueryへのロード日時UTC'),
  pipeline_version                   STRING OPTIONS(description = '処理コードまたはモデルのバージョン'),
  PRIMARY KEY (demand_point_number, target_date, slot_number) NOT ENFORCED
)
PARTITION BY target_date
CLUSTER BY area_code, demand_point_number
OPTIONS (
  require_partition_filter = TRUE, partition_expiration_days = 7,
  description = 'fact_dem_actuals_stream_latest'
);

-- FT-04 / FT-07 確報
CREATE TABLE IF NOT EXISTS fact_gen_actuals_daily (
  supply_point_number                STRING NOT NULL OPTIONS(description = '地点番号／対象日／コマ'),
  target_date                        DATE NOT NULL OPTIONS(description = '地点番号／対象日／コマ'),
  slot_number                        INT64 NOT NULL OPTIONS(description = '地点番号／対象日／コマ'),
  area_code                          STRING OPTIONS(description = 'エリアコード'),
  actual_value_kwh                   NUMERIC NOT NULL OPTIONS(description = '実績値(kWh)：クレンジング後の採用値'),
  raw_value_kwh                      NUMERIC OPTIONS(description = '生値(kWh)：補完前の値（監査用）'),
  cleansing_flag                     INT64 NOT NULL OPTIONS(description = 'クレンジングフラグ：0 正常／1 マイナス補正／2 線形補完／3 前日・前週コピー／4 計画値代替／5 プロファイル配分（訪問検針地点の月間総量を標準負荷曲線で48コマへ配分。B-04b）／6 一送推定検針（通信障害等で一送が推定した確定値。分析時に除外可能）'),
  data_status                        STRING NOT NULL OPTIONS(description = 'データステータス：確報値'),
  updated_at                         TIMESTAMP NOT NULL OPTIONS(description = '更新日時'),
  ingestion_run_id                   STRING OPTIONS(description = 'パイプライン実行ID（命名・運用定義書 11.3）'),
  loaded_at                          TIMESTAMP OPTIONS(description = 'BigQueryへのロード日時UTC'),
  pipeline_version                   STRING OPTIONS(description = '処理コードまたはモデルのバージョン'),
  PRIMARY KEY (supply_point_number, target_date, slot_number) NOT ENFORCED
)
PARTITION BY target_date
CLUSTER BY area_code, supply_point_number
OPTIONS (
  require_partition_filter = TRUE,
  description = 'fact_gen_actuals_daily'
);

-- (需要側) FT-04 / FT-07 確報
CREATE TABLE IF NOT EXISTS fact_dem_actuals_daily (
  demand_point_number                STRING NOT NULL OPTIONS(description = '地点番号／対象日／コマ'),
  target_date                        DATE NOT NULL OPTIONS(description = '地点番号／対象日／コマ'),
  slot_number                        INT64 NOT NULL OPTIONS(description = '地点番号／対象日／コマ'),
  area_code                          STRING OPTIONS(description = 'エリアコード'),
  actual_value_kwh                   NUMERIC NOT NULL OPTIONS(description = '実績値(kWh)：クレンジング後の採用値'),
  raw_value_kwh                      NUMERIC OPTIONS(description = '生値(kWh)：補完前の値（監査用）'),
  cleansing_flag                     INT64 NOT NULL OPTIONS(description = 'クレンジングフラグ：0 正常／1 マイナス補正／2 線形補完／3 前日・前週コピー／4 計画値代替／5 プロファイル配分（訪問検針地点の月間総量を標準負荷曲線で48コマへ配分。B-04b）／6 一送推定検針（通信障害等で一送が推定した確定値。分析時に除外可能）'),
  data_status                        STRING NOT NULL OPTIONS(description = 'データステータス：確報値'),
  updated_at                         TIMESTAMP NOT NULL OPTIONS(description = '更新日時'),
  ingestion_run_id                   STRING OPTIONS(description = 'パイプライン実行ID（命名・運用定義書 11.3）'),
  loaded_at                          TIMESTAMP OPTIONS(description = 'BigQueryへのロード日時UTC'),
  pipeline_version                   STRING OPTIONS(description = '処理コードまたはモデルのバージョン'),
  PRIMARY KEY (demand_point_number, target_date, slot_number) NOT ENFORCED
)
PARTITION BY target_date
CLUSTER BY area_code, demand_point_number
OPTIONS (
  require_partition_filter = TRUE,
  description = 'fact_dem_actuals_daily'
);

-- FT-05 / FT-08 確定
CREATE TABLE IF NOT EXISTS fact_gen_actuals_settled (
  supply_point_number                STRING NOT NULL OPTIONS(description = '地点番号／対象日／コマ'),
  target_date                        DATE NOT NULL OPTIONS(description = '地点番号／対象日／コマ'),
  slot_number                        INT64 NOT NULL OPTIONS(description = '地点番号／対象日／コマ'),
  batch_id                           STRING NOT NULL OPTIONS(description = '取込バッチID：監査証跡。訂正レコードは新しい batch_id を持つため主キーに含める'),
  area_code                          STRING OPTIONS(description = 'エリアコード'),
  actual_value_kwh                   NUMERIC NOT NULL OPTIONS(description = '実績値(kWh)：送配電の公式検針確定値。訂正レコードは差分（符号付き）'),
  record_type                        STRING NOT NULL OPTIONS(description = 'レコード種別：ORIGINAL（初回取込）／CORRECTION（打ち消し・差分）'),
  data_status                        STRING NOT NULL OPTIONS(description = 'データステータス：確定値'),
  settled_received_date              DATE NOT NULL OPTIONS(description = '確定受領日：統合ビューの境界判定は FT-11 で行い、本列は証跡用'),
  ingestion_run_id                   STRING OPTIONS(description = 'パイプライン実行ID（命名・運用定義書 11.3）'),
  loaded_at                          TIMESTAMP OPTIONS(description = 'BigQueryへのロード日時UTC'),
  pipeline_version                   STRING OPTIONS(description = '処理コードまたはモデルのバージョン'),
  PRIMARY KEY (supply_point_number, target_date, slot_number, batch_id) NOT ENFORCED
)
PARTITION BY target_date
CLUSTER BY area_code, supply_point_number
OPTIONS (
  require_partition_filter = TRUE,
  description = 'fact_gen_actuals_settled'
);

-- (需要側) FT-05 / FT-08 確定
CREATE TABLE IF NOT EXISTS fact_dem_actuals_settled (
  demand_point_number                STRING NOT NULL OPTIONS(description = '地点番号／対象日／コマ'),
  target_date                        DATE NOT NULL OPTIONS(description = '地点番号／対象日／コマ'),
  slot_number                        INT64 NOT NULL OPTIONS(description = '地点番号／対象日／コマ'),
  batch_id                           STRING NOT NULL OPTIONS(description = '取込バッチID：監査証跡。訂正レコードは新しい batch_id を持つため主キーに含める'),
  area_code                          STRING OPTIONS(description = 'エリアコード'),
  actual_value_kwh                   NUMERIC NOT NULL OPTIONS(description = '実績値(kWh)：送配電の公式検針確定値。訂正レコードは差分（符号付き）'),
  record_type                        STRING NOT NULL OPTIONS(description = 'レコード種別：ORIGINAL（初回取込）／CORRECTION（打ち消し・差分）'),
  data_status                        STRING NOT NULL OPTIONS(description = 'データステータス：確定値'),
  settled_received_date              DATE NOT NULL OPTIONS(description = '確定受領日：統合ビューの境界判定は FT-11 で行い、本列は証跡用'),
  ingestion_run_id                   STRING OPTIONS(description = 'パイプライン実行ID（命名・運用定義書 11.3）'),
  loaded_at                          TIMESTAMP OPTIONS(description = 'BigQueryへのロード日時UTC'),
  pipeline_version                   STRING OPTIONS(description = '処理コードまたはモデルのバージョン'),
  PRIMARY KEY (demand_point_number, target_date, slot_number, batch_id) NOT ENFORCED
)
PARTITION BY target_date
CLUSTER BY area_code, demand_point_number
OPTIONS (
  require_partition_filter = TRUE,
  description = 'fact_dem_actuals_settled'
);

-- FT-15 月次検針値
CREATE TABLE IF NOT EXISTS fact_monthly_meter_readings (
  demand_point_number                STRING NOT NULL OPTIONS(description = '需要地点番号＋請求月：D-31 と同一キー'),
  billing_month                      STRING NOT NULL OPTIONS(description = '需要地点番号＋請求月：D-31 と同一キー'),
  period_start_date                  DATE NOT NULL OPTIONS(description = '検針期間 開始日／終了日：D-31 と一致すること（13.1 で検証）'),
  period_end_date                    DATE NOT NULL OPTIONS(description = '検針期間 開始日／終了日：D-31 と一致すること（13.1 で検証）'),
  index_prev                         NUMERIC OPTIONS(description = '前回指針／今回指針：指針値（乗率適用前）'),
  index_curr                         NUMERIC OPTIONS(description = '前回指針／今回指針：指針値（乗率適用前）'),
  multiplier                         NUMERIC OPTIONS(description = '乗率：計器の乗率'),
  total_kwh                          NUMERIC NOT NULL OPTIONS(description = '月間電力量(kWh)：一送の検針票の確定総量（受電端）'),
  reading_type                       STRING NOT NULL OPTIONS(description = '検針区分：VISIT／ESTIMATED'),
  received_at                        TIMESTAMP NOT NULL OPTIONS(description = '受領日／取込バッチID'),
  batch_id                           STRING NOT NULL OPTIONS(description = '受領日／取込バッチID'),
  ingestion_run_id                   STRING OPTIONS(description = 'パイプライン実行ID（命名・運用定義書 11.3）'),
  loaded_at                          TIMESTAMP OPTIONS(description = 'BigQueryへのロード日時UTC'),
  pipeline_version                   STRING OPTIONS(description = '処理コードまたはモデルのバージョン'),
  PRIMARY KEY (demand_point_number, billing_month) NOT ENFORCED
)
OPTIONS (
  description = 'fact_monthly_meter_readings'
);

-- FT-12 BG構成員別インバランス
CREATE TABLE IF NOT EXISTS fact_bg_member_imbalance (
  target_date                        DATE NOT NULL OPTIONS(description = '対象日／コマ'),
  slot_number                        INT64 NOT NULL OPTIONS(description = '対象日／コマ'),
  bg_code                            STRING NOT NULL OPTIONS(description = 'BGコード'),
  bg_member_id                       STRING NOT NULL OPTIONS(description = '構成員ID'),
  area_code                          STRING OPTIONS(description = 'エリアコード：非正規化'),
  member_plan_kwh                    NUMERIC NOT NULL OPTIONS(description = '構成員計画量(kWh)：GC時点の計画 × 0.5'),
  member_actual_kwh                  NUMERIC NOT NULL OPTIONS(description = '構成員実績量(kWh)：送電端換算'),
  member_imbalance_kwh               NUMERIC NOT NULL OPTIONS(description = '構成員インバランス量 I_i：符号付き（実績 − 計画）'),
  bg_net_imbalance_kwh               NUMERIC NOT NULL OPTIONS(description = 'BG全体インバランス量 I_bg：同一コマのBG合計。非正規化'),
  is_causer                          BOOL NOT NULL OPTIONS(description = '原因者フラグ：sign(I_i) = sign(I_bg) なら 1'),
  imbalance_price                    NUMERIC NOT NULL OPTIONS(description = '適用単価 P'),
  price_status                       STRING NOT NULL OPTIONS(description = '単価ステータス：暫定／確定'),
  bg_total_amount                    NUMERIC NOT NULL OPTIONS(description = 'BG全体精算額 C_bg'),
  allocation_method_applied          STRING NOT NULL OPTIONS(description = '適用按分方式：算出時点の dim_balancing_groups.allocation_method を固定保持'),
  allocated_amount_raw               NUMERIC NOT NULL OPTIONS(description = '按分額（未丸め）：方式の計算式どおりの値（丸めなし）。監査・再計算用'),
  allocated_amount                   NUMERIC NOT NULL OPTIONS(description = '按分額 A_i：符号付き（受取はマイナス）。BG協定書が1円単位精算を規定するため、規約順守として1円に丸めた値（1.5 の例外）'),
  rounding_adjustment                NUMERIC OPTIONS(description = '端数調整額：rounding_rule により負担者にのみ計上'),
  calculated_at                      TIMESTAMP NOT NULL OPTIONS(description = '算出日時'),
  ingestion_run_id                   STRING OPTIONS(description = 'パイプライン実行ID（命名・運用定義書 11.3）'),
  loaded_at                          TIMESTAMP OPTIONS(description = 'BigQueryへのロード日時UTC'),
  pipeline_version                   STRING OPTIONS(description = '処理コードまたはモデルのバージョン'),
  PRIMARY KEY (target_date, slot_number, bg_code, bg_member_id) NOT ENFORCED
)
PARTITION BY target_date
CLUSTER BY area_code, bg_code
OPTIONS (
  require_partition_filter = TRUE,
  description = 'fact_bg_member_imbalance'
);

-- FT-10 マスタ変更監査ログ
CREATE TABLE IF NOT EXISTS fact_master_change_log (
  log_id                             INT64 NOT NULL OPTIONS(description = 'ログID'),
  table_name                         STRING NOT NULL OPTIONS(description = '対象テーブル'),
  record_key                         STRING NOT NULL OPTIONS(description = '対象キー：主キー値の連結'),
  operation                          STRING NOT NULL OPTIONS(description = '操作種別：INSERT / UPDATE / DELETE / CORRECT'),
  before_json                        JSON OPTIONS(description = '変更前／変更後：変更列のみ'),
  after_json                         JSON OPTIONS(description = '変更前／変更後：変更列のみ'),
  reason                             STRING NOT NULL OPTIONS(description = '変更理由'),
  changed_by                         STRING NOT NULL OPTIONS(description = '実行者／承認者'),
  approved_by                        STRING NOT NULL OPTIONS(description = '実行者／承認者'),
  changed_at                         TIMESTAMP NOT NULL OPTIONS(description = '実行日時'),
  ingestion_run_id                   STRING OPTIONS(description = 'パイプライン実行ID（命名・運用定義書 11.3）'),
  loaded_at                          TIMESTAMP OPTIONS(description = 'BigQueryへのロード日時UTC'),
  pipeline_version                   STRING OPTIONS(description = '処理コードまたはモデルのバージョン'),
  PRIMARY KEY (log_id) NOT ENFORCED
)
PARTITION BY DATE(changed_at)
OPTIONS (
  description = 'fact_master_change_log'
);

-- FT-14 バッチ実行ログ
CREATE TABLE IF NOT EXISTS fact_batch_run_log (
  run_id                             STRING NOT NULL OPTIONS(description = '実行ID'),
  batch_id                           STRING NOT NULL OPTIONS(description = 'バッチID：12.2 の B-nn'),
  target_date                        DATE OPTIONS(description = '対象日：対象日を持たないバッチは NULL'),
  started_at                         TIMESTAMP NOT NULL OPTIONS(description = '開始／終了日時'),
  finished_at                        TIMESTAMP NOT NULL OPTIONS(description = '開始／終了日時'),
  status                             STRING NOT NULL OPTIONS(description = '状態：RUNNING／SUCCESS／FAILED／SKIPPED'),
  result_status                      STRING OPTIONS(description = '戻り値：プロシージャが返した status（例：HOLIDAY_CSV_REJECTED、PUBLISHED）'),
  message                            STRING OPTIONS(description = 'メッセージ：エラー内容・件数'),
  ingestion_run_id                   STRING OPTIONS(description = 'パイプライン実行ID（命名・運用定義書 11.3）'),
  loaded_at                          TIMESTAMP OPTIONS(description = 'BigQueryへのロード日時UTC'),
  pipeline_version                   STRING OPTIONS(description = '処理コードまたはモデルのバージョン'),
  PRIMARY KEY (run_id) NOT ENFORCED
)
PARTITION BY target_date
OPTIONS (
  require_partition_filter = TRUE,
  description = 'fact_batch_run_log'
);

-- FT-11 確定値受領状況
CREATE TABLE IF NOT EXISTS fact_settlement_receipts (
  area_code                          STRING NOT NULL OPTIONS(description = 'エリアコード／対象年月'),
  target_month                       STRING NOT NULL OPTIONS(description = 'エリアコード／対象年月'),
  side                               STRING NOT NULL OPTIONS(description = '側：発電／需要'),
  expected_date                      DATE NOT NULL OPTIONS(description = '期待受領日：検針日（または月末）＋ 一送の N 営業日（TS_BUSINESS ルールで営業日をカウント）。カレンダー日付で固定しない'),
  received_date                      DATE OPTIONS(description = '受領日：NULL＝未受領'),
  received_count                     INT64 OPTIONS(description = '受領件数／期待件数：地点数×日数×48 との突合'),
  expected_count                     INT64 OPTIONS(description = '受領件数／期待件数：地点数×日数×48 との突合'),
  is_loaded                          BOOL NOT NULL OPTIONS(description = '取込完了フラグ：統合ビューの境界判定に使う（4.3）'),
  ingestion_run_id                   STRING OPTIONS(description = 'パイプライン実行ID（命名・運用定義書 11.3）'),
  loaded_at                          TIMESTAMP OPTIONS(description = 'BigQueryへのロード日時UTC'),
  pipeline_version                   STRING OPTIONS(description = '処理コードまたはモデルのバージョン'),
  PRIMARY KEY (area_code, target_month, side) NOT ENFORCED
)
OPTIONS (
  description = 'fact_settlement_receipts'
);



-- ============================================================
-- FILE: sql/ddl/marts.sql
-- ============================================================
-- =============================================================================
-- 電力小売データ分析基盤
-- Gold 層 マート（t_*）DDL
-- 生成元：電力小売データ分析基盤.md（第9章のテーブル定義）
-- 注意：本ファイルは設計書の項目定義から機械生成した骨組み（正本は設計書）。
--       型・NOT NULL は設計書の記載に従い、記載のない列は命名から推定している。
--       デプロイ前に dev 環境で DDL レビュー（13.1／フェーズ1完了条件）を行うこと。
-- =============================================================================

-- T-01 日報損益マート
CREATE TABLE IF NOT EXISTS agg_daily_pnl (
  target_date                        DATE NOT NULL OPTIONS(description = '対象日／コマ'),
  slot_number                        INT64 NOT NULL OPTIONS(description = '対象日／コマ'),
  area_code                          STRING NOT NULL OPTIONS(description = 'エリア／BG：需要BG・発電BG共通'),
  bg_code                            STRING NOT NULL OPTIONS(description = 'エリア／BG：需要BG・発電BG共通'),
  direction                          STRING NOT NULL OPTIONS(description = '流向：INBOUND（需要：系統→需要家）／OUTBOUND（発電：発電所→系統）／STORAGE（蓄電）。行の種類。需要側 INSERT は INBOUND、発電側 INSERT は OUTBOUND、第16章のオプションは STORAGE を固定で書く'),
  segment                            STRING NOT NULL OPTIONS(description = 'セグメント：direction=INBOUND：低圧／高圧／特高、direction=OUTBOUND：発電、direction=STORAGE：蓄電池。direction と segment の組合せは 13.1 ⑬ で検証する'),
  menu_type                          STRING NOT NULL OPTIONS(description = 'メニュー種別：固定単価／市場連動（需要行）、FIP／非FIP（発電行）、蓄電（蓄電行）。同一セグメントに両方が共存するため主キーに含める'),
  demand_kwh                         NUMERIC NOT NULL OPTIONS(description = '需要実績量（受電端）：発電行は 0'),
  demand_kwh_sending_end             NUMERIC NOT NULL OPTIONS(description = '需要実績量（送電端換算）：10.2 の損失補正後'),
  generation_kwh                     NUMERIC NOT NULL OPTIONS(description = '発電実績量（送電端）：放電量を含む。需要行は 0'),
  imbalance_kwh                      NUMERIC NOT NULL OPTIONS(description = 'インバランス量：BGネッティング後を送電端需要比で按分'),
  revenue                            NUMERIC NOT NULL OPTIONS(description = '売上（税抜）：下記 rev_* の和'),
  rev_energy                         NUMERIC NOT NULL OPTIONS(description = '売上内訳：従量電力量料金：固定単価または市場連動単価 × 受電端kWh'),
  rev_fuel_adj                       NUMERIC NOT NULL OPTIONS(description = '売上内訳：燃料費調整額：市場連動は常に 0（13.1 ⑦）'),
  rev_levy_incl_tax                  NUMERIC NOT NULL OPTIONS(description = '売上内訳：再エネ賦課金（税込総額）：需要実績量 × 税込公表単価。税込のまま・未丸めで保持する正の値。月次精算・検算 #2 はこの列の月間合計に D-32 の丸めを適用してから税抜化する（10.7）'),
  rev_levy                           NUMERIC NOT NULL OPTIONS(description = '売上内訳：再エネ賦課金（税抜換算・日次参考値）：rev_levy_incl_tax ÷ (1+税率)、未丸め。日次の revenue・gross_profit の表示にのみ使う参考値。月次確定時に「月間税込総額を丸めてから税抜化した値」との差を settlement_rounding_adjustment に計上する'),
  rev_base_est                       NUMERIC NOT NULL OPTIONS(description = '売上内訳：基本料金（日割試算）：resolved_contract_kw（V-07）または契約kW × base_rate ÷ 月日数 ÷ 48。低圧アンペア契約は dim_ampere_rates.retail_base_rate ÷ 月日数 ÷ 48。月次確定は B-08'),
  rev_market_sales                   NUMERIC NOT NULL OPTIONS(description = '売上内訳：市場売電（発電）：発電量 × エリアプライス。課税。JEPX がマイナス価格のコマは負の売上として残す（10.9）'),
  rev_fip_premium                    NUMERIC NOT NULL OPTIONS(description = '売上内訳：FIPプレミアム：発電量 × GREATEST(0, F−A)。不課税'),
  rev_balancing_premium              NUMERIC NOT NULL OPTIONS(description = '売上内訳：バランシングコスト：発電量 × total_balancing_premium。不課税'),
  procurement_cost                   NUMERIC NOT NULL OPTIONS(description = '調達原価（税抜）：下記 cost_*（cost_gen_charge・cost_levy_passthrough を含む）＋ fixed_fee_* の和'),
  cost_jepx_spot                     NUMERIC NOT NULL OPTIONS(description = '原価内訳：JEPX約定代金：fact_jepx_trades.contracted_amount を BG 内で送電端需要比按分'),
  cost_jepx_fee                      NUMERIC NOT NULL OPTIONS(description = '原価内訳：JEPX従量手数料：取引＋決済代行（買）。発電行は売り手数料'),
  cost_procurement_contract          NUMERIC NOT NULL OPTIONS(description = '原価内訳：相対・PPA・先物：相対・PPA の精算額（FX-09、エリア按分）＋先物差金の割戻し（10.8.3、BG按分）'),
  cost_imbalance                     NUMERIC NOT NULL OPTIONS(description = '原価内訳：インバランス：agg_imbalance_daily.imbalance_amount の按分'),
  cost_wheeling_variable             NUMERIC NOT NULL OPTIONS(description = '原価内訳：託送電力量料金：受電端kWh × demand_variable_rate'),
  cost_wheeling_fixed_est            NUMERIC NOT NULL OPTIONS(description = '原価内訳：託送基本料金（日割試算）：契約kW × demand_fixed_rate ÷ 月日数 ÷ 48。低圧アンペア契約は dim_ampere_rates.wheeling_base_rate ÷ 月日数 ÷ 48。rev_base_est と対で持つ'),
  cost_capacity_contribution         NUMERIC NOT NULL OPTIONS(description = '原価内訳：容量拠出金：受電端kWh × 一律kWh単価（R-6）'),
  cost_nonfossil_certificate         NUMERIC NOT NULL OPTIONS(description = '原価内訳：非化石証書：環境価値付きメニューの受電端kWh × 証書単価（D-33、10.8.5）。付与なしメニューは 0'),
  cost_gen_charge                    NUMERIC NOT NULL OPTIONS(description = '原価内訳：発電側課金：発電行（direction=\'OUTBOUND\'）のみ。契約出力(kW) × 発電側課金単価 × (1−割引率) の月割試算＋従量課金単価分（10.10）。需要行は 0'),
  cost_levy_passthrough              NUMERIC NOT NULL OPTIONS(description = '原価内訳：再エネ賦課金納付（パススルー）：rev_levy と同額。需要家から預かった賦課金を費用負担調整機関へそのまま納付する原価。売上側の rev_levy と相殺され、粗利には影響しない（10.7・利益階層③）。発電行は 0'),
  fixed_fee_provisional              NUMERIC NOT NULL OPTIONS(description = '定額手数料（暫定）：当日約定量（買）× 前月実績ベース単価（10.8.1）'),
  fixed_fee_final                    NUMERIC NOT NULL OPTIONS(description = '定額手数料（月次確定差額）：月末日行以外は 0'),
  settlement_rounding_adjustment     NUMERIC NOT NULL OPTIONS(description = '請求丸め調整：D-32 の丸めとコマ積算の差。月末日行以外は 0'),
  contribution_margin                NUMERIC NOT NULL OPTIONS(description = 'コマ限界利益（利益階層①）：需要行：rev_energy − cost_jepx_spot − cost_jepx_fee − cost_procurement_contract、発電行：rev_market_sales − cost_jepx_fee。市場調達と小売／売電価格の純粋なスプレッド（10.13）'),
  gross_profit                       NUMERIC NOT NULL OPTIONS(description = '粗利（利益階層②＝③）：revenue − procurement_cost。賦課金は売上（rev_levy）と原価（cost_levy_passthrough）の双方に同額計上されるため相殺され、調整後売上総利益（②）と会計上の粗利（③）は同値になる（10.13）'),
  margin_per_kwh                     NUMERIC OPTIONS(description = 'kWhあたり限界利益：gross_profit ÷ (demand_kwh + generation_kwh)。賦課金の影響を受けない。分母 0 は NULL'),
  base_data_status                   STRING NOT NULL OPTIONS(description = '集計時ステータス：速報値／確報値／確定値'),
  applied_rate_refs                  JSON OPTIONS(description = '適用単価参照：使用した単価・パラメータのID群'),
  is_verified                        BOOL NOT NULL OPTIONS(description = '検算フラグ：11.3 の検算 #1〜#3 を全て通過で TRUE'),
  ingestion_run_id                   STRING OPTIONS(description = 'パイプライン実行ID（命名・運用定義書 11.3）'),
  loaded_at                          TIMESTAMP OPTIONS(description = 'BigQueryへのロード日時UTC'),
  pipeline_version                   STRING OPTIONS(description = '処理コードまたはモデルのバージョン'),
  PRIMARY KEY (target_date, slot_number, area_code, bg_code, direction, segment, menu_type) NOT ENFORCED
)
PARTITION BY target_date
CLUSTER BY area_code, direction, segment, bg_code
OPTIONS (
  require_partition_filter = TRUE,
  description = 'agg_daily_pnl'
);

-- T-02 インバランス日次マート
CREATE TABLE IF NOT EXISTS agg_imbalance_daily (
  target_date                        DATE NOT NULL OPTIONS(description = '対象日／コマ／BG'),
  slot_number                        INT64 NOT NULL OPTIONS(description = '対象日／コマ／BG'),
  bg_code                            STRING NOT NULL OPTIONS(description = '対象日／コマ／BG'),
  area_code                          STRING OPTIONS(description = 'エリアコード'),
  plan_kwh                           NUMERIC OPTIONS(description = '計画量／実績量（送電端 kWh）'),
  actual_kwh                         NUMERIC OPTIONS(description = '計画量／実績量（送電端 kWh）'),
  gross_imbalance_kwh                NUMERIC OPTIONS(description = 'ネッティング前／後インバランス量'),
  net_imbalance_kwh                  NUMERIC OPTIONS(description = 'ネッティング前／後インバランス量'),
  imbalance_price                    NUMERIC OPTIONS(description = '適用単価'),
  imbalance_amount                   NUMERIC OPTIONS(description = '精算額'),
  price_status                       STRING OPTIONS(description = '単価ステータス'),
  ingestion_run_id                   STRING OPTIONS(description = 'パイプライン実行ID（命名・運用定義書 11.3）'),
  loaded_at                          TIMESTAMP OPTIONS(description = 'BigQueryへのロード日時UTC'),
  pipeline_version                   STRING OPTIONS(description = '処理コードまたはモデルのバージョン'),
  PRIMARY KEY (target_date, slot_number, bg_code) NOT ENFORCED
)
PARTITION BY target_date
CLUSTER BY area_code, bg_code
OPTIONS (
  require_partition_filter = TRUE,
  description = 'agg_imbalance_daily'
);

-- T-03 コマ別集約マート
CREATE TABLE IF NOT EXISTS agg_slot_summary_active (
  target_date                        DATE NOT NULL OPTIONS(description = '対象日／コマ：Active は対象日から過去2年以内のみ'),
  slot_number                        INT64 NOT NULL OPTIONS(description = '対象日／コマ：Active は対象日から過去2年以内のみ'),
  area_code                          STRING NOT NULL OPTIONS(description = 'エリア／セグメント：低圧／高圧／特高／発電／蓄電池'),
  segment                            STRING NOT NULL OPTIONS(description = 'エリア／セグメント：低圧／高圧／特高／発電／蓄電池'),
  total_demand_kwh                   NUMERIC NOT NULL OPTIONS(description = '需要量（受電端／送電端）'),
  total_demand_sending_kwh           NUMERIC NOT NULL OPTIONS(description = '需要量（受電端／送電端）'),
  total_generation_kwh               NUMERIC NOT NULL OPTIONS(description = '発電量（送電端）'),
  jepx_spot_price                    NUMERIC NOT NULL OPTIONS(description = 'JEPXスポット価格：当該コマのエリアプライス（転記）'),
  imbalance_price                    NUMERIC NOT NULL OPTIONS(description = 'インバランス単価：転記'),
  total_revenue                      NUMERIC NOT NULL OPTIONS(description = '売上／原価／粗利：agg_daily_pnl をセグメントに集約'),
  total_procurement_cost             NUMERIC NOT NULL OPTIONS(description = '売上／原価／粗利：agg_daily_pnl をセグメントに集約'),
  total_gross_profit                 NUMERIC NOT NULL OPTIONS(description = '売上／原価／粗利：agg_daily_pnl をセグメントに集約'),
  ingestion_run_id                   STRING OPTIONS(description = 'パイプライン実行ID（命名・運用定義書 11.3）'),
  loaded_at                          TIMESTAMP OPTIONS(description = 'BigQueryへのロード日時UTC'),
  pipeline_version                   STRING OPTIONS(description = '処理コードまたはモデルのバージョン'),
  PRIMARY KEY (target_date, slot_number, area_code, segment) NOT ENFORCED
)
PARTITION BY target_date
CLUSTER BY area_code, segment
OPTIONS (
  require_partition_filter = TRUE, partition_expiration_days = 737,
  description = 'agg_slot_summary_active'
);

-- T-03b コマ別集約マート（Cold）：Active と同一スキーマ。2年超〜10年。B-13 が bq cp でパーティションコピーする
CREATE TABLE IF NOT EXISTS agg_slot_summary_cold (
  target_date                        DATE NOT NULL OPTIONS(description = '対象日／コマ：Active は対象日から過去2年以内のみ'),
  slot_number                        INT64 NOT NULL OPTIONS(description = '対象日／コマ：Active は対象日から過去2年以内のみ'),
  area_code                          STRING NOT NULL OPTIONS(description = 'エリア／セグメント：低圧／高圧／特高／発電／蓄電池'),
  segment                            STRING NOT NULL OPTIONS(description = 'エリア／セグメント：低圧／高圧／特高／発電／蓄電池'),
  total_demand_kwh                   NUMERIC NOT NULL OPTIONS(description = '需要量（受電端／送電端）'),
  total_demand_sending_kwh           NUMERIC NOT NULL OPTIONS(description = '需要量（受電端／送電端）'),
  total_generation_kwh               NUMERIC NOT NULL OPTIONS(description = '発電量（送電端）'),
  jepx_spot_price                    NUMERIC NOT NULL OPTIONS(description = 'JEPXスポット価格：当該コマのエリアプライス（転記）'),
  imbalance_price                    NUMERIC NOT NULL OPTIONS(description = 'インバランス単価：転記'),
  total_revenue                      NUMERIC NOT NULL OPTIONS(description = '売上／原価／粗利：agg_daily_pnl をセグメントに集約'),
  total_procurement_cost             NUMERIC NOT NULL OPTIONS(description = '売上／原価／粗利：agg_daily_pnl をセグメントに集約'),
  total_gross_profit                 NUMERIC NOT NULL OPTIONS(description = '売上／原価／粗利：agg_daily_pnl をセグメントに集約'),
  ingestion_run_id                   STRING OPTIONS(description = 'パイプライン実行ID（命名・運用定義書 11.3）'),
  loaded_at                          TIMESTAMP OPTIONS(description = 'BigQueryへのロード日時UTC'),
  pipeline_version                   STRING OPTIONS(description = '処理コードまたはモデルのバージョン'),
  PRIMARY KEY (target_date, slot_number, area_code, segment) NOT ENFORCED
)
PARTITION BY target_date
CLUSTER BY area_code, segment
OPTIONS (
  require_partition_filter = TRUE,
  description = 'agg_slot_summary_cold'
);

-- T-04 月次経営サマリ
CREATE TABLE IF NOT EXISTS agg_monthly_summary (
  target_month                       STRING NOT NULL OPTIONS(description = '対象年月：YYYYMM'),
  month_start_date                   DATE NOT NULL OPTIONS(description = '月初日：パーティション列。PARSE_DATE(\'%Y%m01\', target_month)'),
  area_code                          STRING NOT NULL OPTIONS(description = 'エリア／セグメント'),
  segment                            STRING NOT NULL OPTIONS(description = 'エリア／セグメント'),
  key_customer_id                    STRING NOT NULL OPTIONS(description = '主要顧客ID：上位N社は個別、その他は ALL_OTHER'),
  monthly_demand_kwh                 NUMERIC NOT NULL OPTIONS(description = '月間需要量／発電量：受電端／送電端'),
  monthly_generation_kwh             NUMERIC NOT NULL OPTIONS(description = '月間需要量／発電量：受電端／送電端'),
  monthly_revenue                    NUMERIC NOT NULL OPTIONS(description = '月間売上（税抜）：基本料金の確定値を含む。再エネ賦課金は monthly_levy_incl_tax を丸め・税抜化した値で算入する'),
  monthly_levy_incl_tax              NUMERIC NOT NULL OPTIONS(description = '月間再エネ賦課金（税込総額）：Σ rev_levy_incl_tax。請求システムの「税込月額」との突合値（10.7）'),
  monthly_levy_excl_tax              NUMERIC NOT NULL OPTIONS(description = '月間再エネ賦課金（税抜・丸め後）：monthly_levy_incl_tax に D-32 の丸めを適用してから ÷ (1+税率)'),
  monthly_procurement_cost           NUMERIC NOT NULL OPTIONS(description = '月間調達原価（税抜）'),
  fixed_fee_adjustment               NUMERIC NOT NULL OPTIONS(description = '定額手数料 確定差額：日次暫定合計との差（10.8.1）'),
  settlement_rounding_adjustment     NUMERIC NOT NULL OPTIONS(description = '請求丸め調整：D-32'),
  monthly_gross_profit               NUMERIC NOT NULL OPTIONS(description = '月間粗利（税抜）'),
  active_points_count                INT64 NOT NULL OPTIONS(description = '有効地点数：当月中に供給中だった地点数'),
  ingestion_run_id                   STRING OPTIONS(description = 'パイプライン実行ID（命名・運用定義書 11.3）'),
  loaded_at                          TIMESTAMP OPTIONS(description = 'BigQueryへのロード日時UTC'),
  pipeline_version                   STRING OPTIONS(description = '処理コードまたはモデルのバージョン'),
  PRIMARY KEY (target_month, area_code, segment, key_customer_id) NOT ENFORCED
)
PARTITION BY month_start_date
CLUSTER BY area_code, segment
OPTIONS (
  require_partition_filter = TRUE,
  description = 'agg_monthly_summary'
);

-- T-05 データ品質日次
CREATE TABLE IF NOT EXISTS agg_data_quality_daily (
  target_date                        DATE NOT NULL OPTIONS(description = '対象日／エリア／側：side＝発電／需要'),
  area_code                          STRING NOT NULL OPTIONS(description = '対象日／エリア／側：side＝発電／需要'),
  side                               STRING NOT NULL OPTIONS(description = '対象日／エリア／側：side＝発電／需要'),
  total_expected_slots               INT64 NOT NULL OPTIONS(description = '期待総コマ数：有効地点数 × 48'),
  missing_slots_count                INT64 NOT NULL OPTIONS(description = '欠番コマ数：13.1 の欠番検知'),
  cleansing_ratio                    NUMERIC NOT NULL OPTIONS(description = '補完率：(フラグ1〜4の和) ÷ 期待総コマ数。月次KPI'),
  null_rate_count                    INT64 NOT NULL OPTIONS(description = '単価NULL件数：検算 #3。公開可否のゲート'),
  energy_balance_diff_kwh            NUMERIC NOT NULL OPTIONS(description = '電力量突合差：検算 #1'),
  unresolved_area_count              INT64 NOT NULL OPTIONS(description = '未名寄せ件数：12.6 の検疫テーブルへ隔離した行数'),
  is_publishable                     BOOL NOT NULL OPTIONS(description = '日報公開可否：検算を全て通過し、抽出更新（14.10）へ流してよければ 1'),
  ingestion_run_id                   STRING OPTIONS(description = 'パイプライン実行ID（命名・運用定義書 11.3）'),
  loaded_at                          TIMESTAMP OPTIONS(description = 'BigQueryへのロード日時UTC'),
  pipeline_version                   STRING OPTIONS(description = '処理コードまたはモデルのバージョン'),
  PRIMARY KEY (target_date, area_code, side) NOT ENFORCED
)
PARTITION BY target_date
CLUSTER BY area_code, side
OPTIONS (
  require_partition_filter = TRUE,
  description = 'agg_data_quality_daily'
);

-- T-06 需要予測精度日次
CREATE TABLE IF NOT EXISTS agg_forecast_accuracy_daily (
  target_date                        DATE NOT NULL OPTIONS(description = '対象日／地点／モデルバージョン'),
  demand_point_number                STRING NOT NULL OPTIONS(description = '対象日／地点／モデルバージョン'),
  model_version                      STRING NOT NULL OPTIONS(description = '対象日／地点／モデルバージョン'),
  actual_kwh_sending_end             NUMERIC NOT NULL OPTIONS(description = '実績量（送電端）：日合計'),
  plan_kwh_sending_end               NUMERIC NOT NULL OPTIONS(description = '計画量（送電端）：前日提出（DA）の kW × 0.5 の日合計'),
  absolute_error_kwh                 NUMERIC NOT NULL OPTIONS(description = '絶対誤差：Σ'),
  mape                               NUMERIC NOT NULL OPTIONS(description = 'MAPE：コマ平均絶対パーセント誤差'),
  wape                               NUMERIC OPTIONS(description = 'WAPE：Σ'),
  bias_kwh                           NUMERIC NOT NULL OPTIONS(description = 'バイアス：Σ(実績 − 計画)。プラス＝過小予測、マイナス＝過大予測'),
  bias_ratio                         NUMERIC OPTIONS(description = 'バイアス率：bias_kwh ÷ plan_kwh_sending_end。地点規模に依らない登録漏れ判定に使う'),
  slots_evaluated                    INT64 NOT NULL OPTIONS(description = '評価コマ数：実績・計画が揃ったコマ数。48 未満なら計画欠損'),
  is_public_holiday                  BOOL NOT NULL OPTIONS(description = '休日属性：「公的休日＝0 かつ顧客休日＝0（登録なし）なのにバイアス率が大きなマイナス」なら顧客休日の登録漏れの疑い（15.4・Q-13）'),
  is_customer_holiday                BOOL NOT NULL OPTIONS(description = '休日属性：「公的休日＝0 かつ顧客休日＝0（登録なし）なのにバイアス率が大きなマイナス」なら顧客休日の登録漏れの疑い（15.4・Q-13）'),
  expected_load_ratio                NUMERIC OPTIONS(description = '想定稼働率：dim_account_holidays.expected_load_ratio（登録なしは 1.00）。予測モデルがこの値を織り込んでいたかの検証用'),
  snapshot_loaded_at                 TIMESTAMP NOT NULL OPTIONS(description = '生成日時'),
  ingestion_run_id                   STRING OPTIONS(description = 'パイプライン実行ID（命名・運用定義書 11.3）'),
  loaded_at                          TIMESTAMP OPTIONS(description = 'BigQueryへのロード日時UTC'),
  pipeline_version                   STRING OPTIONS(description = '処理コードまたはモデルのバージョン'),
  PRIMARY KEY (target_date, demand_point_number, model_version) NOT ENFORCED
)
PARTITION BY target_date
CLUSTER BY demand_point_number
OPTIONS (
  require_partition_filter = TRUE,
  description = 'agg_forecast_accuracy_daily'
);

-- T-08 BG月次精算
CREATE TABLE IF NOT EXISTS agg_bg_settlement_monthly (
  target_month                       STRING NOT NULL OPTIONS(description = '対象年月／BG／構成員'),
  bg_code                            STRING NOT NULL OPTIONS(description = '対象年月／BG／構成員'),
  bg_member_id                       STRING NOT NULL OPTIONS(description = '対象年月／BG／構成員'),
  month_start_date                   DATE OPTIONS(description = '月初日'),
  member_gross_imbalance_kwh         NUMERIC OPTIONS(description = '構成員インバランス量（絶対値合計）：I_i'),
  member_net_imbalance_kwh           NUMERIC OPTIONS(description = '構成員インバランス量（符号付き合計）'),
  causer_slot_count                  INT64 OPTIONS(description = '原因者コマ数'),
  bg_total_amount                    NUMERIC OPTIONS(description = 'BG全体精算額（月次）'),
  netting_benefit_amount             NUMERIC OPTIONS(description = '相殺効果（月次）'),
  allocated_amount                   NUMERIC OPTIONS(description = '按分額（月次）'),
  admin_fee_amount                   NUMERIC OPTIONS(description = '運営手数料'),
  cap_adjustment                     NUMERIC OPTIONS(description = '責任上限適用額'),
  invoice_reconciliation_amount      NUMERIC OPTIONS(description = '一送請求差額'),
  settlement_amount                  NUMERIC OPTIONS(description = '最終請求・還元額'),
  price_status                       STRING OPTIONS(description = '単価ステータス'),
  settlement_status                  STRING OPTIONS(description = '精算ステータス'),
  notified_amount                    NUMERIC OPTIONS(description = '代表者通知額（参照）'),
  variance_amount                    NUMERIC OPTIONS(description = '差異'),
  ingestion_run_id                   STRING OPTIONS(description = 'パイプライン実行ID（命名・運用定義書 11.3）'),
  loaded_at                          TIMESTAMP OPTIONS(description = 'BigQueryへのロード日時UTC'),
  pipeline_version                   STRING OPTIONS(description = '処理コードまたはモデルのバージョン'),
  PRIMARY KEY (target_month, bg_code, bg_member_id) NOT ENFORCED
)
PARTITION BY month_start_date
CLUSTER BY bg_code
OPTIONS (
  require_partition_filter = TRUE,
  description = 'agg_bg_settlement_monthly'
);

-- T-09 顧客休日スナップショット
CREATE TABLE IF NOT EXISTS snap_customer_holiday (
  target_date                        DATE NOT NULL OPTIONS(description = '対象日／地点'),
  demand_point_number                STRING NOT NULL OPTIONS(description = '対象日／地点'),
  customer_id                        STRING OPTIONS(description = '需要家ID／事業者ID：D-26 の account_id'),
  account_id                         STRING OPTIONS(description = '需要家ID／事業者ID：D-26 の account_id'),
  account_holiday_type               STRING NOT NULL OPTIONS(description = '休日区分：OBON／SHUTDOWN 等'),
  expected_load_ratio                NUMERIC NOT NULL OPTIONS(description = '想定稼働率：予測モデルが直接参照（例：0.15）'),
  snapshot_loaded_at                 TIMESTAMP NOT NULL OPTIONS(description = '書込日時：書き出した過去日は書き換えない（再現性）'),
  ingestion_run_id                   STRING OPTIONS(description = 'パイプライン実行ID（命名・運用定義書 11.3）'),
  loaded_at                          TIMESTAMP OPTIONS(description = 'BigQueryへのロード日時UTC'),
  pipeline_version                   STRING OPTIONS(description = '処理コードまたはモデルのバージョン'),
  PRIMARY KEY (target_date, demand_point_number) NOT ENFORCED
)
PARTITION BY target_date
CLUSTER BY demand_point_number
OPTIONS (
  require_partition_filter = TRUE,
  description = 'snap_customer_holiday'
);



-- ============================================================
-- FILE: sql/function/udf_validate_demand_point_number.sql
-- ============================================================
-- 電力小売データ分析基盤
-- function/udf_validate_demand_point_number.sql
-- 正本：電力小売データ分析基盤.md（該当節の参照実装を抽出）
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


-- ============================================================
-- FILE: sql/view/v_rate_holiday_priority.sql
-- ============================================================
-- 電力小売データ分析基盤
-- sql/view/v_rate_holiday_priority.sql
-- 正本：spec.md 10.5（V-06 料金用休日ビュー）
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


-- ============================================================
-- FILE: sql/view/v_dem_actuals_timeline.sql
-- ============================================================
-- 電力小売データ分析基盤
-- view/v_dem_actuals_timeline.sql
-- 正本：電力小売データ分析基盤.md（該当節の参照実装を抽出）
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


-- ============================================================
-- FILE: sql/view/v_gen_actuals_timeline.sql
-- ============================================================
-- 電力小売データ分析基盤
-- view/v_gen_actuals_timeline.sql
-- 正本：電力小売データ分析基盤.md（該当節の参照実装を抽出）
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


-- ============================================================
-- FILE: sql/view/v_actual_peak_kw_resolver.sql
-- ============================================================
-- 電力小売データ分析基盤
-- view/v_actual_peak_kw_resolver.sql
-- 正本：電力小売データ分析基盤.md（該当節の参照実装を抽出）
-- 注意：${GCP_PROJECT_ID} と ${BQ_DATASET_*} はテンプレート変数。CI/CD で環境別の値へ展開してから実行する
--       （命名・運用定義書 3.2）。未展開のまま実行してはならない。

CREATE OR REPLACE VIEW v_actual_peak_kw_resolver AS
WITH slot_kw_base AS (
  -- STEP 1：コマごとに、個別またはグループ単位で電力量を合算し kW 換算
  SELECT
    a.target_date, a.slot_number, cust.voltage_class,
    COALESCE(c.contract_group_id, a.demand_point_number) AS billing_unit_key,
    SUM(a.actual_value_kwh) * 2                          AS slot_kw,
    MIN(CASE WHEN a.data_status = '確定値' THEN 1 ELSE 0 END) AS all_settled
  FROM v_dem_actuals_timeline a                         -- 確定→確報→速報を1本化した Silver ビュー
  JOIN dim_dem_customers cust      ON a.demand_point_number = cust.demand_point_number
  JOIN dim_customer_contracts c    ON cust.customer_id = c.customer_id
                                AND a.target_date BETWEEN c.start_date AND c.end_date
  WHERE cust.is_actual_kw_based
  GROUP BY 1, 2, 3, 4
),
monthly_max_kw AS (
  -- STEP 2：月ごとの最高 kW（最大需要電力）。実績のある月にしか行が立たない
  SELECT
    EXTRACT(YEAR FROM target_date) * 12 + EXTRACT(MONTH FROM target_date) AS month_index,  -- 年跨ぎで連続する月番号
    billing_unit_key, voltage_class,
    MAX(slot_kw)          AS monthly_max_demand_kw,
    MIN(all_settled)      AS month_settled
  FROM slot_kw_base
  GROUP BY 1, 2, 3
),
unit_span AS (
  SELECT
    COALESCE(c.contract_group_id, cust.demand_point_number)                        AS billing_unit_key,
    ANY_VALUE(cust.voltage_class)                                                  AS voltage_class,
    EXTRACT(YEAR FROM MIN(c.start_date)) * 12 + EXTRACT(MONTH FROM MIN(c.start_date)) AS first_month_index,
    EXTRACT(YEAR FROM CURRENT_DATE('Asia/Tokyo')) * 12 + EXTRACT(MONTH FROM CURRENT_DATE('Asia/Tokyo')) AS last_month_index
  FROM dim_dem_customers cust
  JOIN dim_customer_contracts c ON cust.customer_id = c.customer_id
  WHERE cust.is_actual_kw_based
  GROUP BY 1
),
month_spine AS (
  -- 判定単位 × 暦月（欠損月も1行ずつ生成する）
  SELECT u.billing_unit_key, u.voltage_class, m AS month_index,
         FORMAT('%04d%02d', DIV(m - 1, 12), MOD(m - 1, 12) + 1) AS target_month
  FROM unit_span u, UNNEST(GENERATE_ARRAY(u.first_month_index, u.last_month_index)) AS m
),
filled AS (
  -- 骨格を左に置いて LEFT JOIN。実績のない月は monthly_max_demand_kw = NULL の行として存在させる
  SELECT s.target_month, s.month_index, s.billing_unit_key, s.voltage_class,
         k.monthly_max_demand_kw, k.month_settled,
         CASE WHEN k.month_index IS NULL THEN 1 ELSE 0 END AS is_missing_month
  FROM month_spine s
  LEFT JOIN monthly_max_kw k
    ON s.billing_unit_key = k.billing_unit_key AND s.month_index = k.month_index
)
-- STEP 3：当月を含む過去12ヶ月（暦月）の最大値を契約電力として判定（結合ではなくウィンドウで）
SELECT
  target_month, billing_unit_key, voltage_class,
  monthly_max_demand_kw                                   AS current_month_max_kw,   -- 欠損月は NULL
  MAX(monthly_max_demand_kw) OVER (
    PARTITION BY billing_unit_key
    ORDER BY month_index
    ROWS BETWEEN 11 PRECEDING AND CURRENT ROW)            AS resolved_contract_kw,   -- 骨格が暦月で連続しているので ROWS で12行＝12暦月。NULL は無視される
  COUNT(monthly_max_demand_kw) OVER (
    PARTITION BY billing_unit_key
    ORDER BY month_index
    ROWS BETWEEN 11 PRECEDING AND CURRENT ROW)            AS months_with_actuals,    -- 実績のある月数
  COUNT(*) OVER (
    PARTITION BY billing_unit_key
    ORDER BY month_index
    ROWS BETWEEN 11 PRECEDING AND CURRENT ROW)            AS months_since_contract,  -- 契約開始からの暦月数（12未満なら新規契約）
  SUM(is_missing_month) OVER (
    PARTITION BY billing_unit_key
    ORDER BY month_index
    ROWS BETWEEN 11 PRECEDING AND CURRENT ROW)            AS missing_months_in_window, -- 窓内の欠損月数（1以上ならアラート。13.2）
  CASE WHEN MIN(COALESCE(month_settled, 0)) OVER (
    PARTITION BY billing_unit_key
    ORDER BY month_index
    ROWS BETWEEN 11 PRECEDING AND CURRENT ROW) = 1 THEN 0 ELSE 1 END AS is_provisional   -- 欠損月は未確定扱い
FROM filled;


-- ============================================================
-- FILE: sql/view/v_market_linked_price_resolver.sql
-- ============================================================
-- 電力小売データ分析基盤
-- view/v_market_linked_price_resolver.sql
-- 正本：電力小売データ分析基盤.md（該当節の参照実装を抽出）
-- 注意：${GCP_PROJECT_ID} と ${BQ_DATASET_*} はテンプレート変数。CI/CD で環境別の値へ展開してから実行する
--       （命名・運用定義書 3.2）。未展開のまま実行してはならない。

CREATE OR REPLACE VIEW v_market_linked_price_resolver AS
WITH scored AS (
  SELECT
    dem.target_date, dem.slot_number, dem.area_code, cust.demand_point_number, cust.customer_id, c.rate_menu_code,
    jepx.area_price AS jepx_spot_price, loss.loss_rate,
    CASE   -- D-11 託送従量単価（11.5 prepared と同一ロジック。holiday_day_rate_rule を含む）
      WHEN slot.jepx_time_class = '夜間'                                     THEN COALESCE(whl.variable_rate_night,       whl.demand_variable_rate)
      WHEN rh.is_rate_holiday AND whl.holiday_day_rate_rule = 'STANDARD' THEN whl.demand_variable_rate
      WHEN rh.is_rate_holiday AND cal.power_season = '夏季'              THEN COALESCE(whl.variable_rate_summer_day,  whl.demand_variable_rate)
      WHEN rh.is_rate_holiday AND cal.power_season = '冬季'              THEN COALESCE(whl.variable_rate_winter_day,  whl.demand_variable_rate)
      WHEN rh.is_rate_holiday                                            THEN whl.demand_variable_rate
      WHEN cal.power_season = '夏季' AND slot.is_peak                    THEN COALESCE(whl.variable_rate_summer_peak, whl.demand_variable_rate)
      WHEN cal.power_season = '夏季'                                         THEN COALESCE(whl.variable_rate_summer_day,  whl.demand_variable_rate)
      WHEN cal.power_season = '冬季'                                         THEN COALESCE(whl.variable_rate_winter_day,  whl.demand_variable_rate)
      ELSE whl.demand_variable_rate END AS applied_wheeling_variable_rate,
    p.param_id, p.scope_level, p.procurement_adj_rate, p.retail_margin_rate, p.operation_fee_rate,
    p.capacity_pass_through_rate, p.price_cap, p.price_floor,
    CASE p.scope_level WHEN 'POINT' THEN 1 WHEN 'CUSTOMER' THEN 2 ELSE 3 END AS priority_score
  FROM fact_dem_actuals_daily dem
  JOIN dim_dem_customers cust      ON dem.demand_point_number = cust.demand_point_number
  JOIN dim_customer_contracts c    ON cust.customer_id = c.customer_id AND dem.target_date BETWEEN c.start_date AND c.end_date
  JOIN dim_rate_menus menu         ON c.rate_menu_code = menu.rate_menu_code AND dem.target_date BETWEEN menu.start_date AND menu.end_date
  JOIN dim_date_calendar cal       ON dem.target_date = cal.target_date
  JOIN dim_slot_calendar slot      ON dem.slot_number = slot.slot_number
  JOIN v_rate_holiday_priority rh ON dem.target_date = rh.target_date
  JOIN dim_loss_rates loss         ON dem.area_code = loss.area_code AND cust.voltage_class = loss.voltage_class
                                AND dem.target_date BETWEEN loss.start_date AND loss.end_date
  JOIN dim_wheeling_rates whl      ON dem.area_code = whl.area_code AND cust.voltage_class = whl.voltage_class
                                AND dem.target_date BETWEEN whl.start_date AND whl.end_date
                                AND ((c.wheeling_menu_name IS NOT NULL AND whl.menu_name = c.wheeling_menu_name)
                                     OR (c.wheeling_menu_name IS NULL AND whl.is_default))
  JOIN fact_jepx_spot_prices jepx   ON dem.target_date = jepx.target_date AND dem.slot_number = jepx.slot_number AND dem.area_code = jepx.area_code
  JOIN dim_market_linked_parameters p
                                 ON c.rate_menu_code = p.rate_menu_code AND dem.area_code = p.area_code
                                AND (p.voltage_class IS NULL OR p.voltage_class = cust.voltage_class)     -- D-25 の電圧クラス（NULL＝全電圧）
                                AND dem.target_date BETWEEN p.start_date AND p.end_date
                                AND p.approved_by IS NOT NULL                                            -- 承認済み行のみ（10.4／13.1 ⑫）
                                AND (p.scope_level = 'MENU'
                                     OR (p.scope_level = 'CUSTOMER' AND p.customer_id = cust.customer_id)
                                     OR (p.scope_level = 'POINT'    AND p.demand_point_number = dem.demand_point_number))
  WHERE menu.is_market_linked
),
resolved AS (
  SELECT * FROM scored
  QUALIFY ROW_NUMBER() OVER (PARTITION BY target_date, slot_number, demand_point_number
                             ORDER BY priority_score, param_id DESC) = 1     -- 同順位は改定通番の新しい行（13.1 ⑫ で重複自体を禁止）
),
calc AS (
  SELECT *,
         jepx_spot_price / (1 - loss_rate) + applied_wheeling_variable_rate
           + COALESCE(procurement_adj_rate, 0) + COALESCE(retail_margin_rate, 0)
           + COALESCE(operation_fee_rate, 0) + COALESCE(capacity_pass_through_rate, 0)   AS raw_price
  FROM resolved
)
SELECT target_date, slot_number, area_code, demand_point_number, customer_id, rate_menu_code,
       param_id, scope_level, jepx_spot_price, applied_wheeling_variable_rate, raw_price,
       -- クランプ（NULL 安全：上限・下限が未設定なら生値をそのまま通す。LEAST/GREATEST は NULL を返すため CASE で分岐）
       CASE WHEN price_cap   IS NOT NULL AND raw_price > price_cap   THEN price_cap
            WHEN price_floor IS NOT NULL AND raw_price < price_floor THEN price_floor
            ELSE raw_price END                                                             AS final_market_linked_price,
       CASE WHEN price_cap   IS NOT NULL AND raw_price > price_cap   THEN 'CLAMPED_BY_CAP'
            WHEN price_floor IS NOT NULL AND raw_price < price_floor THEN 'CLAMPED_BY_FLOOR'
            ELSE 'RAW' END                                                                 AS clamp_status
FROM calc;


-- ============================================================
-- FILE: sql/view/v_profit_layers_daily.sql
-- ============================================================
-- 電力小売データ分析基盤
-- view/v_profit_layers_daily.sql
-- 正本：電力小売データ分析基盤.md（該当節の参照実装を抽出）
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


-- ============================================================
-- FILE: sql/view/v_bi_daily_pnl_extract.sql
-- ============================================================
-- 電力小売データ分析基盤
-- view/v_bi_daily_pnl_extract.sql
-- 正本：電力小売データ分析基盤.md（該当節の参照実装を抽出）
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


-- ============================================================
-- FILE: sql/procedure/p_calculate_bg_member_imbalance.sql
-- ============================================================
-- 電力小売データ分析基盤
-- procedure/p_calculate_bg_member_imbalance.sql
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
CREATE OR REPLACE PROCEDURE p_calculate_bg_member_imbalance(IN p_target_date DATE, IN p_run_id STRING, IN p_pipeline_version STRING)
BEGIN
  -- ─────────────────────────────────────────────
  -- STEP 1  地点 → 構成員：計画・実績を送電端に揃えてコマ×構成員で合算（10.3.1）
  -- ─────────────────────────────────────────────
  CREATE OR REPLACE TEMP TABLE tmp_member AS
  SELECT dem.target_date, dem.slot_number, mb.bg_code, dem.area_code, mb.bg_member_id,
         ANY_VALUE(mb.is_exempt)                                                          AS is_exempt,
         ANY_VALUE(mb.share_ratio)                                                        AS share_ratio,
         SUM(dem.actual_value_kwh / (1 - loss.loss_rate))                                 AS member_actual_kwh,   -- 受電端 → 送電端
         SUM(CASE plan.plan_basis
               WHEN 'SENDING_END'   THEN COALESCE(plan.forecast_value_kw, 0) * 0.5
               WHEN 'RECEIVING_END' THEN COALESCE(plan.forecast_value_kw, 0) * 0.5 / (1 - loss.loss_rate)
               ELSE 0 END)                                                                AS member_plan_kwh
  FROM fact_dem_actuals_daily dem
  JOIN dim_dem_customers cust      ON dem.demand_point_number = cust.demand_point_number
  JOIN dim_account pt             ON cust.account_id = pt.account_id
  JOIN dim_customer_contracts c    ON cust.customer_id = c.customer_id
                                AND dem.target_date BETWEEN c.start_date AND c.end_date
  JOIN dim_bg_members mb           ON c.dem_bg_code = mb.bg_code
                                -- 地点と構成員は取引先ID で紐付ける（13.1 ⑨ 網羅）。
                                -- 個人需要家（entity_type='INDIVIDUAL'）は BG 構成員にならないため、
                                -- 自社（ACCOUNT_SELF）が代表する需要として按分する（13.1 ⑯）
                                AND mb.account_id = IF(pt.entity_type = 'INDIVIDUAL', 'ACCOUNT_SELF', cust.account_id)
                                AND dem.target_date BETWEEN mb.start_date AND mb.end_date
  JOIN dim_loss_rates loss         ON dem.area_code = loss.area_code AND cust.voltage_class = loss.voltage_class
                                AND dem.target_date BETWEEN loss.start_date AND loss.end_date
  LEFT JOIN (                                                                                -- GC 時点（ID）の最新版計画
      SELECT demand_point_number, target_date, slot_number, forecast_value_kw, plan_basis   -- FT-02 の列名は forecast_value_kw
      FROM fact_dem_plans
      WHERE target_date = p_target_date AND plan_type = 'ID'
      QUALIFY ROW_NUMBER() OVER (PARTITION BY demand_point_number, slot_number ORDER BY plan_version DESC) = 1
  ) plan                         ON dem.demand_point_number = plan.demand_point_number
                                AND dem.target_date = plan.target_date AND dem.slot_number = plan.slot_number
  WHERE dem.target_date = p_target_date
  GROUP BY 1, 2, 3, 4, 5;

  -- ─────────────────────────────────────────────
  -- STEP 2  BG 集計（I_bg, Σ|I_j|, 原因者側 Σ|I_j|, 有効構成員数）
  -- ─────────────────────────────────────────────
  CREATE OR REPLACE TEMP TABLE tmp_bg AS
  SELECT target_date, slot_number, bg_code, area_code,
         SUM(member_actual_kwh - member_plan_kwh)                                         AS bg_net_imbalance_kwh,
         SUM(CASE WHEN NOT is_exempt THEN ABS(member_actual_kwh - member_plan_kwh) END)   AS bg_gross_abs_kwh,
         SUM(CASE WHEN NOT is_exempt
                   AND SIGN(member_actual_kwh - member_plan_kwh)
                       = SIGN(SUM(member_actual_kwh - member_plan_kwh) OVER (PARTITION BY target_date, slot_number, bg_code))
                  THEN ABS(member_actual_kwh - member_plan_kwh) END)                      AS causer_abs_kwh,
         COUNTIF(NOT is_exempt)                                                           AS active_member_count
  FROM tmp_member
  GROUP BY 1, 2, 3, 4;

  -- ─────────────────────────────────────────────
  -- STEP 3  暫定按分額（方式は dim_balancing_groups.allocation_method）
  -- ─────────────────────────────────────────────
  CREATE OR REPLACE TEMP TABLE tmp_alloc AS
  SELECT m.*,
         m.member_actual_kwh - m.member_plan_kwh                                          AS member_imbalance_kwh,
         b.bg_net_imbalance_kwh, b.bg_gross_abs_kwh, b.causer_abs_kwh, b.active_member_count,
         p.imbalance_price, p.price_status,
         b.bg_net_imbalance_kwh * p.imbalance_price                                       AS bg_total_amount,
         bg.allocation_method,
         CASE WHEN SIGN(m.member_actual_kwh - m.member_plan_kwh) = SIGN(b.bg_net_imbalance_kwh) THEN 1 ELSE 0 END AS is_causer,
         CASE
           WHEN m.is_exempt THEN 'EXEMPT'
           WHEN bg.allocation_method = 'INDIVIDUAL'  THEN 'INDIVIDUAL'
           WHEN bg.allocation_method = 'FIXED_SHARE' THEN 'FIXED_SHARE'
           WHEN bg.allocation_method = 'CAUSER_PAYS' AND COALESCE(b.causer_abs_kwh, 0) > 0  THEN 'CAUSER_PAYS'
           WHEN COALESCE(b.bg_gross_abs_kwh, 0) > 0  THEN 'SIMPLE_RATIO'
           ELSE 'EQUAL_SPLIT'                                                              -- Σ|I_j| = 0：均等按分（0 除算回避）
         END AS method_applied
  FROM tmp_member m
  JOIN tmp_bg b              USING (target_date, slot_number, bg_code, area_code)
  JOIN dim_balancing_groups bg ON m.bg_code = bg.bg_code AND m.target_date BETWEEN bg.start_date AND bg.end_date
  JOIN fact_imbalance_prices p  ON m.target_date = p.target_date AND m.slot_number = p.slot_number AND m.area_code = p.area_code;

  -- ─────────────────────────────────────────────
  -- STEP 4  べき等：対象日パーティションを削除して再作成
  -- ─────────────────────────────────────────────
  DELETE FROM fact_bg_member_imbalance WHERE target_date = p_target_date;

  -- ─────────────────────────────────────────────
  -- STEP 5  端数調整（Σ A_i = C_bg を1円単位で成立）と INSERT
  -- ─────────────────────────────────────────────
  INSERT INTO fact_bg_member_imbalance (
    target_date, slot_number, bg_code, bg_member_id, area_code,
    member_plan_kwh, member_actual_kwh, member_imbalance_kwh, bg_net_imbalance_kwh, is_causer,
    imbalance_price, price_status, bg_total_amount,
    allocation_method_applied, allocated_amount_raw, allocated_amount, rounding_adjustment, calculated_at, ingestion_run_id, loaded_at, pipeline_version)
  WITH raw AS (
    SELECT *,
      CASE method_applied
        WHEN 'EXEMPT'       THEN 0
        WHEN 'INDIVIDUAL'   THEN -member_imbalance_kwh * imbalance_price                             -- ④ A_i = −I_i × P
        WHEN 'FIXED_SHARE'  THEN bg_total_amount * share_ratio                                        -- ② A_i = C_bg × share_i
        WHEN 'CAUSER_PAYS'  THEN CASE WHEN is_causer
                                      THEN bg_total_amount * SAFE_DIVIDE(ABS(member_imbalance_kwh), causer_abs_kwh) ELSE 0 END  -- ③
        WHEN 'SIMPLE_RATIO' THEN bg_total_amount * SAFE_DIVIDE(ABS(member_imbalance_kwh), bg_gross_abs_kwh)              -- ①
        ELSE                     SAFE_DIVIDE(bg_total_amount, active_member_count)                     -- 均等
      END AS raw_amount
    FROM tmp_alloc
  ),
  ranked AS (
    SELECT *,
      ROUND(raw_amount, 0) AS rounded_amount,
      bg_total_amount - SUM(ROUND(raw_amount, 0)) OVER (PARTITION BY target_date, slot_number, bg_code) AS bg_delta,
      -- 端数の負担者：免責でない構成員のうち |I_i| 最大（規約が代表者負担なら member_role = 'REPRESENTATIVE' を先頭に）
      ROW_NUMBER() OVER (PARTITION BY target_date, slot_number, bg_code
                         ORDER BY is_exempt ASC, ABS(member_imbalance_kwh) DESC, bg_member_id) AS rnk
    FROM raw
  )
  SELECT target_date, slot_number, bg_code, bg_member_id, area_code,
         member_plan_kwh, member_actual_kwh, member_imbalance_kwh, bg_net_imbalance_kwh, is_causer,
         imbalance_price, price_status, bg_total_amount,
         method_applied                                                          AS allocation_method_applied,
         raw_amount                                                              AS allocated_amount_raw,
         CASE WHEN rnk = 1 THEN rounded_amount + bg_delta ELSE rounded_amount END AS allocated_amount,
         CASE WHEN rnk = 1 THEN bg_delta ELSE 0 END                               AS rounding_adjustment,
         CURRENT_TIMESTAMP()                                                      AS calculated_at,
         p_run_id, CURRENT_TIMESTAMP(), p_pipeline_version
  FROM ranked;

  -- 検算（13.1 ⑨ 合計一致）：一致しないコマがあれば中断
  IF EXISTS (
    SELECT 1 FROM fact_bg_member_imbalance
    WHERE target_date = p_target_date
    GROUP BY target_date, slot_number, bg_code
    HAVING ABS(SUM(allocated_amount) - ANY_VALUE(ROUND(bg_total_amount, 0))) > 0
  ) THEN
    RAISE USING MESSAGE = FORMAT('BG按分の合計不一致: %t', p_target_date);
  END IF;
END;


-- ============================================================
-- FILE: sql/procedure/p_execute_load_profile_allocation.sql
-- ============================================================
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


-- ============================================================
-- FILE: sql/procedure/p_generate_daily_pnl.sql
-- ============================================================
-- 電力小売データ分析基盤
-- procedure/p_generate_daily_pnl.sql
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
CREATE OR REPLACE PROCEDURE p_generate_daily_pnl(IN p_target_date DATE, IN p_run_id STRING, IN p_pipeline_version STRING)
BEGIN
  DECLARE v_missing_slots INT64;
  DECLARE v_null_rates    INT64;

  -- ───────────────────────────────────────────────────────────
  -- STEP 0  前提チェック（NG なら中断し、中途半端な日報を出さない）
  -- ───────────────────────────────────────────────────────────
  -- 0-1 対象日の48コマが需要実績に揃っているか（地点ごと）
  SET v_missing_slots = (
    SELECT COUNT(*) FROM (
      SELECT demand_point_number, COUNT(DISTINCT slot_number) AS n
      FROM fact_dem_actuals_daily WHERE target_date = p_target_date
      GROUP BY demand_point_number HAVING n < 48));
  IF v_missing_slots > 0 THEN
    RAISE USING MESSAGE = FORMAT('欠番あり: %d 地点', v_missing_slots);
  END IF;

  -- 0-2 対象日の単価が全て引けるか（損失率・託送・JEPX・容量拠出金・賦課金・アンペア料金）
  SET v_null_rates = (
    SELECT COUNT(*)
    FROM fact_dem_actuals_daily dem
    JOIN dim_dem_customers cust USING (demand_point_number)
    LEFT JOIN dim_loss_rates loss
      ON dem.area_code = loss.area_code AND cust.voltage_class = loss.voltage_class
     AND dem.target_date BETWEEN loss.start_date AND loss.end_date
    LEFT JOIN dim_customer_contracts c0
      ON cust.customer_id = c0.customer_id AND dem.target_date BETWEEN c0.start_date AND c0.end_date
    LEFT JOIN dim_wheeling_rates whl
      ON dem.area_code = whl.area_code AND cust.voltage_class = whl.voltage_class
     AND dem.target_date BETWEEN whl.start_date AND whl.end_date
     AND ((c0.wheeling_menu_name IS NOT NULL AND whl.menu_name = c0.wheeling_menu_name)
          OR (c0.wheeling_menu_name IS NULL AND whl.is_default))
    LEFT JOIN fact_jepx_spot_prices jepx
      ON dem.target_date = jepx.target_date AND dem.slot_number = jepx.slot_number
     AND dem.area_code = jepx.area_code
    LEFT JOIN dim_capacity_contribution_rates cap
      ON dem.area_code = cap.area_code
     AND dem.target_date BETWEEN cap.start_date AND cap.end_date
    LEFT JOIN dim_meter_reading_cycles mrc
      ON dem.demand_point_number = mrc.demand_point_number
     AND dem.target_date BETWEEN mrc.period_start_date AND mrc.period_end_date
    LEFT JOIN dim_fit_levy_rates levy
      ON mrc.billing_month BETWEEN levy.start_billing_month AND levy.end_billing_month
    LEFT JOIN dim_ampere_rates amp
      ON c0.contract_ampere IS NOT NULL
     AND c0.rate_menu_code = amp.rate_menu_code AND dem.area_code = amp.area_code
     AND c0.contract_ampere = amp.ampere
     AND dem.target_date BETWEEN amp.start_date AND amp.end_date
    WHERE dem.target_date = p_target_date
      AND (loss.loss_rate IS NULL OR whl.demand_variable_rate IS NULL
           OR jepx.area_price IS NULL OR cap.capacity_kwh_rate IS NULL
           OR mrc.billing_month IS NULL OR levy.fit_levy_rate_incl_tax IS NULL
           OR (c0.contract_ampere IS NOT NULL AND amp.ampere_rate_id IS NULL)));
  IF v_null_rates > 0 THEN
    RAISE USING MESSAGE = FORMAT('単価NULL: %d 行', v_null_rates);
  END IF;

  -- ───────────────────────────────────────────────────────────
  -- STEP 1  べき等性：対象日パーティションを削除
  -- ───────────────────────────────────────────────────────────
  DELETE FROM agg_daily_pnl WHERE target_date = p_target_date;

  -- ───────────────────────────────────────────────────────────
  -- STEP 2  需要側：コマ別の売上・原価
  -- ───────────────────────────────────────────────────────────
  INSERT INTO agg_daily_pnl (
    target_date, slot_number, area_code, bg_code, direction, segment, menu_type,
    demand_kwh, demand_kwh_sending_end, generation_kwh, imbalance_kwh,
    revenue, rev_energy, rev_fuel_adj, rev_levy_incl_tax, rev_levy, rev_base_est,
    rev_market_sales, rev_fip_premium, rev_balancing_premium,
    procurement_cost, cost_jepx_spot, cost_jepx_fee, cost_procurement_contract, cost_imbalance,
    cost_wheeling_variable, cost_wheeling_fixed_est, cost_capacity_contribution, cost_nonfossil_certificate, cost_gen_charge, cost_levy_passthrough,
    fixed_fee_provisional, fixed_fee_final, settlement_rounding_adjustment,
    contribution_margin, gross_profit, margin_per_kwh, base_data_status, applied_rate_refs, is_verified,
    ingestion_run_id, loaded_at, pipeline_version)
  WITH
  -- 2-1 料金用休日（R-12：自社の約款休日を最優先、なければ土日祝）
  rate_holiday AS (
    SELECT c.target_date,
           CASE WHEN self_h.account_holiday_date IS NOT NULL THEN 1
                WHEN pub.holiday_date IS NOT NULL            THEN 1
                ELSE 0 END AS is_rate_holiday
    FROM dim_date_calendar c
    LEFT JOIN dim_account_holidays self_h
      ON c.target_date = self_h.account_holiday_date
     AND self_h.account_id = 'ACCOUNT_SELF'
     AND self_h.demand_point_number IS NULL
     AND self_h.applies_to_tariff
    LEFT JOIN dim_public_holidays pub ON c.target_date = pub.holiday_date
    WHERE c.target_date = p_target_date),

  -- 2-2 従量手数料（買）を対象日で1行に畳む
  fee_buy AS (
    SELECT SUM(unit_rate) AS fee_rate_kwh
    FROM dim_jepx_transaction_fees
    WHERE p_target_date BETWEEN start_date AND end_date
      AND market_type = 'スポット' AND charge_method = 'PER_KWH' AND trade_side = '買'),

  -- 2-3 定額手数料の暫定単価（前月実績 ÷ 前月総約定量。10.8.1）
  fee_fixed_provisional AS (
    SELECT SAFE_DIVIDE(
             (SELECT SUM(unit_rate) FROM dim_jepx_transaction_fees
               WHERE charge_method = 'FIXED_MONTHLY'
                 AND DATE_SUB(DATE_TRUNC(p_target_date, MONTH), INTERVAL 1 DAY) BETWEEN start_date AND end_date),
             (SELECT SUM(contracted_kwh) FROM fact_jepx_trades
               WHERE trade_side = '買'
                 AND target_date BETWEEN DATE_TRUNC(DATE_SUB(p_target_date, INTERVAL 1 MONTH), MONTH)
                                     AND DATE_SUB(DATE_TRUNC(p_target_date, MONTH), INTERVAL 1 DAY))
           ) AS fixed_fee_rate_kwh),

  -- 2-3b 基本料金の日割試算に使う「1コマあたり契約kW」（10.11 / 11.2 STEP 4）
  --      実量制は V-07 の当月値（暫定を含む）、それ以外は契約kW。グループ実量制は地点数で等分（確定按分は月次 B-08）
  base_fee_est AS (
    -- kW × 単価の計算をバイパスする。base_fee_est_slot_yen / wheeling_fixed_est_slot_yen は「1コマあたりの円」
    -- そのものを返し、kW契約は「1コマあたりkW」（kw_per_slot）のまま返して既存の menu.base_rate 乗算に載せる。
    SELECT cust.demand_point_number,
           c.contract_ampere,
           SAFE_DIVIDE(
             CASE WHEN cust.is_actual_kw_based THEN pk.resolved_contract_kw ELSE c.contract_kw END,
             COUNT(*) OVER (PARTITION BY COALESCE(c.contract_group_id, cust.demand_point_number))
               * EXTRACT(DAY FROM LAST_DAY(p_target_date)) * 48) AS kw_per_slot,
           SAFE_DIVIDE(CASE WHEN amp.tax_type = '税込' THEN amp.retail_base_rate / (1 + tx.tax_rate) ELSE amp.retail_base_rate END,   -- 税込公表値は Gold で未丸め税抜化
             COUNT(*) OVER (PARTITION BY COALESCE(c.contract_group_id, cust.demand_point_number))
               * EXTRACT(DAY FROM LAST_DAY(p_target_date)) * 48) AS ampere_retail_slot_yen,
           SAFE_DIVIDE(CASE WHEN amp.tax_type = '税込' THEN amp.wheeling_base_rate / (1 + tx.tax_rate) ELSE amp.wheeling_base_rate END,
             COUNT(*) OVER (PARTITION BY COALESCE(c.contract_group_id, cust.demand_point_number))
               * EXTRACT(DAY FROM LAST_DAY(p_target_date)) * 48) AS ampere_wheeling_slot_yen
    FROM dim_dem_customers cust
    JOIN dim_customer_contracts c ON cust.customer_id = c.customer_id
                               AND p_target_date BETWEEN c.start_date AND c.end_date
    LEFT JOIN v_actual_peak_kw_resolver pk
           ON pk.billing_unit_key = COALESCE(c.contract_group_id, cust.demand_point_number)
          AND pk.target_month     = FORMAT_DATE('%Y%m', p_target_date)
    LEFT JOIN dim_ampere_rates amp
           ON c.contract_ampere IS NOT NULL
          AND c.rate_menu_code = amp.rate_menu_code AND cust.area_code = amp.area_code
          AND c.contract_ampere = amp.ampere
          AND p_target_date BETWEEN amp.start_date AND amp.end_date
    LEFT JOIN dim_tax_rates tx ON p_target_date BETWEEN tx.start_date AND tx.end_date AND NOT tx.is_reduced),

  -- 2-3c 専属調達契約（Dedication）：専属先が設定された契約の精算額は、専属先の需要地点にのみ配分する（10.8.4）。
  --      prepared が参照するため、prepared より前に定義する
  dedicated_contracts AS (
    SELECT DISTINCT c.procurement_contract_id
    FROM dim_customer_contracts c
    WHERE c.procurement_contract_id IS NOT NULL AND p_target_date BETWEEN c.start_date AND c.end_date),
  dedicated_totals AS (   -- 専属契約ごとの配分先合計送電端需要量（コマ単位）
    SELECT c.procurement_contract_id, dem.slot_number,
           SUM(dem.actual_value_kwh / (1 - loss.loss_rate)) AS total_sending_kwh
    FROM dim_customer_contracts c
    JOIN dim_dem_customers cust    ON c.customer_id = cust.customer_id
    JOIN fact_dem_actuals_daily dem ON cust.demand_point_number = dem.demand_point_number AND dem.target_date = p_target_date
    JOIN dim_loss_rates loss       ON dem.area_code = loss.area_code AND cust.voltage_class = loss.voltage_class
                                 AND dem.target_date BETWEEN loss.start_date AND loss.end_date
    WHERE c.procurement_contract_id IS NOT NULL AND p_target_date BETWEEN c.start_date AND c.end_date
    GROUP BY 1,2),
  dedicated_alloc AS (     -- 需要地点ごとの専属契約按分額（コマ単位）
    SELECT cust.demand_point_number, dem.slot_number,
           (CASE WHEN ps.tax_type_received = '税込' THEN ps.settlement_amount / (1 + tx.tax_rate) ELSE ps.settlement_amount END)
             * SAFE_DIVIDE(dem.actual_value_kwh / (1 - loss.loss_rate), dt.total_sending_kwh)   AS dedicated_cost_slot
    FROM dim_customer_contracts c
    JOIN dim_dem_customers cust    ON c.customer_id = cust.customer_id
    JOIN fact_dem_actuals_daily dem ON cust.demand_point_number = dem.demand_point_number AND dem.target_date = p_target_date
    JOIN dim_loss_rates loss       ON dem.area_code = loss.area_code AND cust.voltage_class = loss.voltage_class
                                 AND dem.target_date BETWEEN loss.start_date AND loss.end_date
    JOIN fact_procurement_settlements ps ON ps.procurement_contract_id = c.procurement_contract_id
                                      AND ps.target_date = dem.target_date AND ps.slot_number = dem.slot_number
    JOIN dim_procurement_contracts pc   ON ps.procurement_contract_id = pc.procurement_contract_id
    JOIN dim_tax_rates tx               ON ps.target_date BETWEEN tx.start_date AND tx.end_date AND NOT tx.is_reduced
    JOIN dedicated_totals dt          ON dt.procurement_contract_id = c.procurement_contract_id AND dt.slot_number = dem.slot_number
    WHERE c.procurement_contract_id IS NOT NULL AND p_target_date BETWEEN c.start_date AND c.end_date),

  -- 2-4 需要実績に契約・単価・カレンダーを結合（全て対象日で期間解決）
  prepared AS (
    SELECT
      dem.target_date, dem.slot_number, dem.area_code,
      c.dem_bg_code                               AS bg_code,
      cust.voltage_class                          AS segment,
      menu.is_market_linked,
      dem.actual_value_kwh                        AS demand_kwh,
      dem.actual_value_kwh / (1 - loss.loss_rate) AS demand_kwh_sending_end,     -- 10.2
      levy.fit_levy_rate_incl_tax                 AS levy_rate_incl_tax,         -- 税込の公表単価のまま（D-14・Q-9）検針月基準
      tax.tax_rate                                AS tax_rate,                   -- dim_tax_rates を対象日で解決
      CASE WHEN NOT menu.apply_fuel_adjustment THEN 0
           WHEN fuel.tax_type_published = '税込' THEN fuel.fuel_adj_rate / (1 + tax.tax_rate)   -- Gold で未丸め税抜化（1.5）
           ELSE fuel.fuel_adj_rate END               AS fuel_adj_rate,
      cap.capacity_kwh_rate,
      CASE WHEN menu.env_value_type = 'NONE' THEN 0 ELSE cert.unit_price END AS cert_rate,   -- 非化石証書単価（10.8.5）
      -- D-11 託送従量単価の動的解決（一律／季節別時間帯別の両対応）
      CASE
        WHEN slot.jepx_time_class = '夜間'                   THEN COALESCE(whl.variable_rate_night,       whl.demand_variable_rate)
        WHEN rh.is_rate_holiday AND whl.holiday_day_rate_rule = 'STANDARD' THEN whl.demand_variable_rate
        WHEN rh.is_rate_holiday AND cal.power_season = '夏季'              THEN COALESCE(whl.variable_rate_summer_day,  whl.demand_variable_rate)   -- SEASONAL
        WHEN rh.is_rate_holiday AND cal.power_season = '冬季'              THEN COALESCE(whl.variable_rate_winter_day,  whl.demand_variable_rate)
        WHEN rh.is_rate_holiday                                            THEN whl.demand_variable_rate
        WHEN cal.power_season = '夏季' AND slot.is_peak   THEN COALESCE(whl.variable_rate_summer_peak, whl.demand_variable_rate)
        WHEN cal.power_season = '夏季'                        THEN COALESCE(whl.variable_rate_summer_day,  whl.demand_variable_rate)
        WHEN cal.power_season = '冬季'                        THEN COALESCE(whl.variable_rate_winter_day,  whl.demand_variable_rate)
        ELSE                                                       whl.demand_variable_rate
      END                                         AS applied_wheeling_variable_rate,
      res.final_market_linked_price               AS market_linked_price,        -- V-09（特約解決・クランプ済み）
      -- 基本料金の日割試算：アンペア契約は dim_ampere_rates の固定額、それ以外は kW × 単価（10.11 でアンペア分岐追加）
      CASE WHEN bfe.contract_ampere IS NOT NULL THEN COALESCE(bfe.ampere_retail_slot_yen, 0)
           ELSE COALESCE(bfe.kw_per_slot, 0) * menu.base_rate END          AS base_fee_est_slot,
      CASE WHEN bfe.contract_ampere IS NOT NULL THEN COALESCE(bfe.ampere_wheeling_slot_yen, 0)
           ELSE COALESCE(bfe.kw_per_slot, 0) * whl.demand_fixed_rate END   AS wheeling_fixed_est_slot,
      -- 10.6 固定単価の分岐（rate_priority_rule で夜間／休日の優先を切替）
      CASE
        WHEN menu.rate_priority_rule = 'HOLIDAY_FIRST' AND rh.is_rate_holiday THEN menu.holiday_rate
        WHEN slot.jepx_time_class = '夜間'                                           THEN menu.night_rate
        WHEN rh.is_rate_holiday                                                 THEN menu.holiday_rate
        WHEN cal.power_season = '夏季' AND slot.is_peak                         THEN menu.weekday_summer_peak_rate
        WHEN cal.power_season = '夏季'                                              THEN menu.weekday_summer_day_rate
        ELSE                                                                             menu.weekday_day_rate
      END AS fixed_unit_price,
      menu.rate_menu_code, loss.loss_rate_id, whl.wheeling_rate_id, cap.capacity_rate_id, levy.levy_rate_id,
      COALESCE(ded.dedicated_cost_slot, 0)        AS dedicated_cost_slot      -- 専属調達契約の直接配賦（10.8.4）
    FROM fact_dem_actuals_daily dem
    JOIN dim_dem_customers cust      ON dem.demand_point_number = cust.demand_point_number
    JOIN dim_customer_contracts c    ON cust.customer_id = c.customer_id
                                  AND dem.target_date BETWEEN c.start_date AND c.end_date
    JOIN dim_rate_menus menu         ON c.rate_menu_code = menu.rate_menu_code
                                  AND dem.target_date BETWEEN menu.start_date AND menu.end_date
    JOIN dim_date_calendar cal       ON dem.target_date = cal.target_date
    JOIN dim_slot_calendar slot      ON dem.slot_number = slot.slot_number
    JOIN rate_holiday rh           ON dem.target_date = rh.target_date
    JOIN dim_loss_rates loss         ON dem.area_code = loss.area_code AND cust.voltage_class = loss.voltage_class
                                  AND dem.target_date BETWEEN loss.start_date AND loss.end_date
    JOIN dim_wheeling_rates whl      ON dem.area_code = whl.area_code AND cust.voltage_class = whl.voltage_class
                                  AND dem.target_date BETWEEN whl.start_date AND whl.end_date
                                  AND ((c.wheeling_menu_name IS NOT NULL AND whl.menu_name = c.wheeling_menu_name)
                                       OR (c.wheeling_menu_name IS NULL AND whl.is_default))
    JOIN dim_capacity_contribution_rates cap
                                   ON dem.area_code = cap.area_code
                                  AND dem.target_date BETWEEN cap.start_date AND cap.end_date
    JOIN dim_meter_reading_cycles mrc ON dem.demand_point_number = mrc.demand_point_number
                                  AND dem.target_date BETWEEN mrc.period_start_date AND mrc.period_end_date
    JOIN dim_fit_levy_rates levy     ON mrc.billing_month BETWEEN levy.start_billing_month AND levy.end_billing_month
    JOIN dim_tax_rates tax           ON dem.target_date BETWEEN tax.start_date AND tax.end_date AND NOT tax.is_reduced
    LEFT JOIN dim_nonfossil_certificate_prices cert
                                   ON cert.certificate_type = menu.env_value_type
                                  AND cert.fiscal_year = cal.fiscal_year
                                  AND dem.target_date BETWEEN cert.start_date AND cert.end_date
    LEFT JOIN dim_fuel_adjustments fuel
                                   ON dem.area_code = fuel.area_code AND cust.voltage_class = fuel.voltage_class
                                  AND FORMAT_DATE('%Y%m', dem.target_date) = fuel.target_month
    LEFT JOIN v_market_linked_price_resolver res
                                   ON dem.demand_point_number = res.demand_point_number
                                  AND dem.target_date = res.target_date AND dem.slot_number = res.slot_number   -- V-09（10.4.1）
    LEFT JOIN base_fee_est bfe     ON dem.demand_point_number = bfe.demand_point_number
    LEFT JOIN dedicated_alloc ded  ON dem.demand_point_number = ded.demand_point_number AND dem.slot_number = ded.slot_number
    -- Q-17：特約の優先解決とクランプは V-09 内で完結。この位置での追加処理は不要
    WHERE dem.target_date = p_target_date),

  -- 2-5 BG 単位の市場調達原価（約定明細から。10.8 / 10.8.1）。約定代金と従量手数料は別列に分ける
  bg_procurement AS (
    SELECT t.target_date, t.slot_number, t.area_code, t.bg_code,
           SUM(t.contracted_kwh)                       AS bought_kwh,
           SUM(t.contracted_amount)                    AS market_cost,
           SUM(t.transaction_fee + t.settlement_fee)   AS fee_cost
    FROM fact_jepx_trades t
    WHERE t.target_date = p_target_date AND t.trade_side = '買'
    GROUP BY 1,2,3,4),

  -- 2-6 BG 単位のインバランス精算額（10.3）
  bg_imbalance AS (
    SELECT target_date, slot_number, bg_code,
           SUM(net_imbalance_kwh) AS imbalance_kwh, SUM(imbalance_amount) AS imbalance_cost
    FROM agg_imbalance_daily WHERE target_date = p_target_date
    GROUP BY 1,2,3),

  -- 2-7 先物ヘッジのコマ割戻し（10.8.3：Base は全コマ、Peak は取引所営業日の 17〜40 のみ）
  futures_adj AS (
    SELECT p_target_date AS target_date, s.slot_number, pc.area_code,
           SUM(pc.contract_kw * 0.5 * (pc.contract_price - fp.settlement_price)
               * CASE WHEN pc.delivery_profile = 'ベース' THEN 1
                      WHEN pc.delivery_profile = 'ピーク'
                       AND s.fwd_product_type = 'Base_and_Peak'
                       AND fx_biz.is_business_day THEN 1
                      ELSE 0 END) AS futures_adjustment
    FROM dim_procurement_contracts pc
    JOIN dim_slot_calendar s ON TRUE
    JOIN fact_futures_prices fp
      ON fp.contract_month = FORMAT_DATE('%Y%m', p_target_date) AND fp.area_code = pc.area_code
     AND fp.product_type = CASE pc.delivery_profile WHEN 'ベース' THEN 'Base' ELSE 'Peak' END
     AND fp.trade_date = (SELECT MAX(trade_date) FROM fact_futures_prices WHERE trade_date <= p_target_date)
    JOIN (SELECT c.target_date,
                 CASE WHEN c.day_of_week IN ('Sat','Sun') THEN 0
                      WHEN pub.is_national_holiday THEN 0
                      WHEN d.is_treated_as_holiday THEN 0 ELSE 1 END AS is_business_day
          FROM dim_date_calendar c
          LEFT JOIN dim_public_holidays pub ON c.target_date = pub.holiday_date
          LEFT JOIN dim_holiday_rule_details d ON d.holiday_rule_code = 'FUTURES_PEAK'
                                             AND d.holiday_type = pub.holiday_type
          WHERE c.target_date = p_target_date) fx_biz ON TRUE
    WHERE pc.contract_type = '先物'
      AND p_target_date BETWEEN pc.start_date AND pc.end_date
    GROUP BY 1,2,3),

  -- 2-7b 相対・PPA の精算明細（10.8.4）。専属契約（2-3c）を除いた分をエリア単位で取り、送電端需要比で按分する
  --      バーチャルPPA は unit_price に差金が入っているため、市場原価と二重計上にならない
  bilateral AS (
    SELECT ps.target_date, ps.slot_number, ps.area_code,
           SUM(CASE WHEN ps.tax_type_received = '税込' THEN ps.settlement_amount / (1 + tx.tax_rate)   -- 受領値は Silver に税込のまま。Gold で未丸め税抜化（FX-09）
                    ELSE ps.settlement_amount END) AS bilateral_cost
    FROM fact_procurement_settlements ps
    JOIN dim_procurement_contracts pc ON ps.procurement_contract_id = pc.procurement_contract_id
    JOIN dim_tax_rates tx ON ps.target_date BETWEEN tx.start_date AND tx.end_date AND NOT tx.is_reduced
    WHERE ps.target_date = p_target_date
      AND ps.procurement_contract_id NOT IN (SELECT procurement_contract_id FROM dedicated_contracts)
    GROUP BY 1,2,3),

  -- 2-8 セグメント集計。売上・原価は費目ごとの総額で持ち、合成単価を作らない（1.5 計算順序）
  seg AS (
    SELECT target_date, slot_number, area_code, bg_code,
           'INBOUND' AS direction,                                                          -- T-01 主キー第5軸（流向：需要 ①）
           segment,
           CASE WHEN is_market_linked THEN '市場連動' ELSE '固定単価' END AS menu_type,
           SUM(demand_kwh)             AS demand_kwh,
           SUM(demand_kwh_sending_end) AS demand_kwh_sending_end,
           -- 10.7 売上（税抜）
           SUM(CASE WHEN is_market_linked THEN demand_kwh * market_linked_price
                    ELSE demand_kwh * fixed_unit_price END)                                 AS energy_revenue,
           SUM(CASE WHEN is_market_linked THEN 0 ELSE demand_kwh * fuel_adj_rate END)   AS fuel_adj_revenue,
           SUM(demand_kwh * levy_rate_incl_tax)                                              AS levy_incl_tax,  -- 税込総額（正の値。月次で丸め→税抜化。10.7 ⑥）
           SUM(demand_kwh * levy_rate_incl_tax / (1 + tax_rate))                             AS levy_revenue,   -- 税抜換算の日次参考値（Q-9）
           SUM(base_fee_est_slot)                                                            AS base_fee_revenue,
           -- 10.8 のうち需要量・契約kWに比例する原価
           SUM(demand_kwh * applied_wheeling_variable_rate)                                  AS wheeling_cost,  -- D-11 の時間帯別単価を解決済み
           SUM(wheeling_fixed_est_slot)                                                      AS wheeling_fixed_cost,
           SUM(demand_kwh * capacity_kwh_rate)                                               AS capacity_cost,
           SUM(demand_kwh * COALESCE(cert_rate, 0))                                          AS cert_cost,      -- 非化石証書（10.8.5）
           SUM(dedicated_cost_slot)                                                          AS dedicated_procurement_cost,  -- 専属調達契約（10.8.4）
           ANY_VALUE(fixed_fee_rate_kwh) AS fixed_fee_rate_kwh,
           TO_JSON_STRING(STRUCT(ARRAY_AGG(DISTINCT rate_menu_code) AS menus,
                                 ARRAY_AGG(DISTINCT loss_rate_id) AS loss_ids,
                                 ARRAY_AGG(DISTINCT wheeling_rate_id) AS wheeling_ids,
                                 ARRAY_AGG(DISTINCT capacity_rate_id) AS capacity_ids,
                                 ARRAY_AGG(DISTINCT levy_rate_id) AS levy_ids)) AS applied_rate_refs
    FROM prepared CROSS JOIN fee_fixed_provisional
    GROUP BY 1,2,3,4,5,6,7),

  bg_total AS (
    SELECT target_date, slot_number, area_code, bg_code,
           SUM(demand_kwh_sending_end) AS bg_sending_kwh
    FROM seg GROUP BY 1,2,3,4),

  area_total AS (
    SELECT target_date, slot_number, area_code,
           SUM(demand_kwh_sending_end) AS area_sending_kwh
    FROM seg GROUP BY 1,2,3),

  -- 2-9 BG 単位・エリア単位の原価を送電端需要比でセグメントへ按分し、費目別に確定
  costed AS (
    SELECT s.*,
           SAFE_DIVIDE(s.demand_kwh_sending_end, bt.bg_sending_kwh)   AS bg_share,
           COALESCE(bi.imbalance_kwh, 0)
             * SAFE_DIVIDE(s.demand_kwh_sending_end, bt.bg_sending_kwh)                        AS imbalance_kwh,
           COALESCE(bp.market_cost, 0)
             * SAFE_DIVIDE(s.demand_kwh_sending_end, bt.bg_sending_kwh)                        AS cost_jepx_spot,
           COALESCE(bp.fee_cost, 0)
             * SAFE_DIVIDE(s.demand_kwh_sending_end, bt.bg_sending_kwh)                        AS cost_jepx_fee,
           COALESCE(fa.futures_adjustment, 0)
             * SAFE_DIVIDE(s.demand_kwh_sending_end, bt.bg_sending_kwh)
           + COALESCE(bl.bilateral_cost, 0)
             * SAFE_DIVIDE(s.demand_kwh_sending_end, ar.area_sending_kwh)
           + s.dedicated_procurement_cost                                                      -- 専属調達契約：比率按分せず直接計上
                                                                                                 AS cost_procurement_contract,
           COALESCE(bi.imbalance_cost, 0)
             * SAFE_DIVIDE(s.demand_kwh_sending_end, bt.bg_sending_kwh)                        AS cost_imbalance,
           -- 定額手数料の暫定計上：当日の約定量（買）× 前月実績ベース暫定単価 を需要比で按分（10.8.1）
           COALESCE(bp.bought_kwh, 0) * COALESCE(s.fixed_fee_rate_kwh, 0)
             * SAFE_DIVIDE(s.demand_kwh_sending_end, bt.bg_sending_kwh)                        AS fixed_fee_provisional
    FROM seg s
    JOIN bg_total   bt USING (target_date, slot_number, area_code, bg_code)
    JOIN area_total ar USING (target_date, slot_number, area_code)
    LEFT JOIN bg_procurement bp USING (target_date, slot_number, area_code, bg_code)
    LEFT JOIN bg_imbalance   bi USING (target_date, slot_number, bg_code)
    LEFT JOIN futures_adj    fa USING (target_date, slot_number, area_code)
    LEFT JOIN bilateral      bl USING (target_date, slot_number, area_code))

  SELECT
    target_date, slot_number, area_code, bg_code, direction, segment, menu_type,
    demand_kwh, demand_kwh_sending_end,
    0                                                                                   AS generation_kwh,
    imbalance_kwh,
    -- 売上 ＝ 費目別総額の和（賦課金は税抜換算の参考値 levy_revenue を算入。精算は levy_incl_tax を使う）
    energy_revenue + fuel_adj_revenue + levy_revenue + base_fee_revenue                 AS revenue,
    energy_revenue, fuel_adj_revenue, levy_incl_tax, levy_revenue, base_fee_revenue,
    0, 0, 0,                                        -- rev_market_sales / rev_fip_premium / rev_balancing_premium は発電行のみ
    -- 調達原価 ＝ 費目別総額の和（10.8）
    cost_jepx_spot + cost_jepx_fee + cost_procurement_contract + cost_imbalance
      + wheeling_cost + wheeling_fixed_cost + capacity_cost + cert_cost + levy_revenue + fixed_fee_provisional   AS procurement_cost,
    cost_jepx_spot, cost_jepx_fee, cost_procurement_contract, cost_imbalance,
    wheeling_cost, wheeling_fixed_cost, capacity_cost, cert_cost,
    0                                                                                   AS cost_gen_charge,        -- 需要行は 0（発電側課金は発電行のみ）
    levy_revenue                                                                        AS cost_levy_passthrough,  -- 賦課金の納付原価（売上側 rev_levy と同額で相殺。10.13）
    fixed_fee_provisional,
    0                                                                                   AS fixed_fee_final,               -- 月次確定（B-08）で月末日行にのみ計上
    0                                                                                   AS settlement_rounding_adjustment,-- 同上（D-32）
    energy_revenue - (cost_jepx_spot + cost_jepx_fee + cost_procurement_contract)         AS contribution_margin,  -- 利益階層①（10.13）
    (energy_revenue + fuel_adj_revenue + levy_revenue + base_fee_revenue)
      - (cost_jepx_spot + cost_jepx_fee + cost_procurement_contract + cost_imbalance
         + wheeling_cost + wheeling_fixed_cost + capacity_cost + cert_cost + levy_revenue + fixed_fee_provisional) AS gross_profit,   -- 利益階層②＝③
    SAFE_DIVIDE(
      (energy_revenue + fuel_adj_revenue + base_fee_revenue)
      - (cost_jepx_spot + cost_jepx_fee + cost_procurement_contract + cost_imbalance
         + wheeling_cost + wheeling_fixed_cost + capacity_cost + cert_cost + fixed_fee_provisional),
      demand_kwh)                                                                         AS margin_per_kwh,       -- 賦課金は両側相殺のため含めない
    '確報値'                                                                            AS base_data_status,
    applied_rate_refs,
    FALSE                                                                               AS is_verified,
    p_run_id, CURRENT_TIMESTAMP(), p_pipeline_version
  FROM costed;

  -- ───────────────────────────────────────────────────────────
  -- STEP 3  発電側（FIP 含む）：コマ別の売上（10.9）
  -- ───────────────────────────────────────────────────────────
  INSERT INTO agg_daily_pnl (
    target_date, slot_number, area_code, bg_code, direction, segment, menu_type,
    demand_kwh, demand_kwh_sending_end, generation_kwh, imbalance_kwh,
    revenue, rev_energy, rev_fuel_adj, rev_levy_incl_tax, rev_levy, rev_base_est,
    rev_market_sales, rev_fip_premium, rev_balancing_premium,
    procurement_cost, cost_jepx_spot, cost_jepx_fee, cost_procurement_contract, cost_imbalance,
    cost_wheeling_variable, cost_wheeling_fixed_est, cost_capacity_contribution, cost_nonfossil_certificate, cost_gen_charge, cost_levy_passthrough,
    fixed_fee_provisional, fixed_fee_final, settlement_rounding_adjustment,
    contribution_margin, gross_profit, margin_per_kwh, base_data_status, applied_rate_refs, is_verified,
    ingestion_run_id, loaded_at, pipeline_version)
  WITH fee_sell AS (
    SELECT SUM(unit_rate) AS fee_rate_kwh FROM dim_jepx_transaction_fees
    WHERE p_target_date BETWEEN start_date AND end_date
      AND market_type = 'スポット' AND charge_method = 'PER_KWH' AND trade_side = '売'),
  trial AS (   -- 試運転判定（D-05）。試運転期間は売上計上区分で切り替え、FIP は商業運転開始日以降に限定
    SELECT gen_point_id, supply_point_number,
           (trial_start_date IS NOT NULL
            AND p_target_date >= trial_start_date
            AND (commercial_operation_date IS NULL OR p_target_date < commercial_operation_date)) AS is_trial,
           COALESCE(trial_revenue_treatment, 'EXCLUDE')                                            AS trial_revenue_treatment,
           (commercial_operation_date IS NOT NULL AND p_target_date >= commercial_operation_date)  AS is_commercial
    FROM dim_gen_supply_points
    WHERE p_target_date BETWEEN start_date AND end_date),
  a_value AS (   -- 確定A値があればそれ、なければ暫定（FX-05）
    SELECT fuel_code, area_code, reference_price
    FROM fact_fip_reference_prices
    WHERE target_month = FORMAT_DATE('%Y%m', p_target_date)
    QUALIFY ROW_NUMBER() OVER (PARTITION BY fuel_code, area_code
                               ORDER BY CASE value_status WHEN 'FINAL' THEN 0 ELSE 1 END) = 1)
  SELECT
    gen.target_date, gen.slot_number, gen.area_code, gp.gen_bg_code,
    'OUTBOUND' AS direction,                                                                        -- T-01 主キー第5軸（流向：発電 ①）
    '発電' AS segment,
    CASE WHEN gp.is_fip THEN 'FIP' ELSE '非FIP' END AS menu_type,
    0, 0, SUM(gen.actual_value_kwh), 0,
    -- 売上：市場売電（課税）＋ P値・バランシングコスト（不課税）。売り手数料は原価側（10.9）
    -- 試運転期間（D-05）：市場売電は trial_revenue_treatment で切替、FIP は商業運転開始日以降に限定
    SUM(CASE WHEN tr.is_trial AND tr.trial_revenue_treatment = 'EXCLUDE' THEN 0
             ELSE gen.actual_value_kwh * jepx.area_price END)
      + SUM(CASE WHEN gp.is_fip AND NOT tr.is_trial THEN gen.actual_value_kwh * GREATEST(0, gp.fip_f_price - av.reference_price) ELSE 0 END)
      + SUM(CASE WHEN gp.is_fip AND NOT tr.is_trial THEN gen.actual_value_kwh * COALESCE(bc.total_balancing_premium, 0) ELSE 0 END)   AS revenue,
    0, 0, 0, 0, 0,                                                                                  -- 需要側の内訳（rev_energy / rev_fuel_adj / rev_levy_incl_tax / rev_levy / rev_base_est）は 0
    SUM(CASE WHEN tr.is_trial AND tr.trial_revenue_treatment = 'EXCLUDE' THEN 0
             ELSE gen.actual_value_kwh * jepx.area_price END)                                       AS rev_market_sales,      -- マイナス価格のコマは負のまま
    SUM(CASE WHEN gp.is_fip AND NOT tr.is_trial THEN gen.actual_value_kwh * GREATEST(0, gp.fip_f_price - av.reference_price) ELSE 0 END) AS rev_fip_premium,
    SUM(CASE WHEN gp.is_fip AND NOT tr.is_trial THEN gen.actual_value_kwh * COALESCE(bc.total_balancing_premium, 0) ELSE 0 END)          AS rev_balancing_premium,
    -- 原価：売り手数料 ＋ 発電側課金（10.10）
    SUM(gen.actual_value_kwh * COALESCE(fs.fee_rate_kwh, 0))
      + IF(ANY_VALUE(gcd.gen_charge_start_basis) = 'GRID_CONNECTION' OR ANY_VALUE(tr.is_commercial),   -- 課金起算（D-34・R-29）
           SAFE_DIVIDE(ANY_VALUE(gp.contract_kw) * ANY_VALUE(whl_g.gen_charge_rate) * (1 - COALESCE(ANY_VALUE(gcd.discount_rate), 0)),
                       EXTRACT(DAY FROM LAST_DAY(gen.target_date)) * 48)
           + SUM(gen.actual_value_kwh * COALESCE(whl_g.gen_charge_kwh_rate, 0)), 0)                  AS procurement_cost,
    0, SUM(gen.actual_value_kwh * COALESCE(fs.fee_rate_kwh, 0)), 0, 0, 0, 0, 0, 0,     -- jepx_spot / jepx_fee / procurement_contract / imbalance / wheeling_variable / wheeling_fixed_est / capacity_contribution / nonfossil_certificate（発電行はいずれも0。cost_jepx_feeのみ非0）
    IF(ANY_VALUE(gcd.gen_charge_start_basis) = 'GRID_CONNECTION' OR ANY_VALUE(tr.is_commercial),
       SAFE_DIVIDE(ANY_VALUE(gp.contract_kw) * ANY_VALUE(whl_g.gen_charge_rate) * (1 - COALESCE(ANY_VALUE(gcd.discount_rate), 0)),
                   EXTRACT(DAY FROM LAST_DAY(gen.target_date)) * 48)
       + SUM(gen.actual_value_kwh * COALESCE(whl_g.gen_charge_kwh_rate, 0)), 0)                      AS cost_gen_charge,   -- 10.10・試運転期間は起算基準で切替
    0                                                                                               AS cost_levy_passthrough,
    0, 0, 0,
    SUM(CASE WHEN tr.is_trial AND tr.trial_revenue_treatment = 'EXCLUDE' THEN 0
             ELSE gen.actual_value_kwh * jepx.area_price END)
      - SUM(gen.actual_value_kwh * COALESCE(fs.fee_rate_kwh, 0))                                    AS contribution_margin,  -- 利益階層①（発電）：市場売電 − 売り手数料
    NULL, NULL, '確報値', NULL, FALSE,
    p_run_id, CURRENT_TIMESTAMP(), p_pipeline_version
  FROM fact_gen_actuals_daily gen
  JOIN dim_gen_supply_points gp ON gen.supply_point_number = gp.supply_point_number
                              AND gen.target_date BETWEEN gp.start_date AND gp.end_date
  JOIN trial tr               ON gp.supply_point_number = tr.supply_point_number
  JOIN dim_plants pl            ON gp.plant_id = pl.plant_id
  JOIN dim_date_calendar cal    ON gen.target_date = cal.target_date
  LEFT JOIN dim_wheeling_rates whl_g
                               ON gp.area_code = whl_g.area_code AND gp.voltage_class = whl_g.voltage_class
                              AND gen.target_date BETWEEN whl_g.start_date AND whl_g.end_date AND whl_g.is_default
  LEFT JOIN dim_gen_charge_discount_rates gcd
                               ON gp.area_code = gcd.area_code AND gp.gen_charge_type = gcd.gen_charge_type
                              AND gen.target_date BETWEEN gcd.start_date AND gcd.end_date
  JOIN fact_jepx_spot_prices jepx ON gen.target_date = jepx.target_date AND gen.slot_number = jepx.slot_number
                              AND gen.area_code = jepx.area_code
  LEFT JOIN a_value av        ON pl.fuel_code = av.fuel_code AND gen.area_code = av.area_code
  LEFT JOIN dim_fip_bg_privileges bc
                              ON bc.cert_fiscal_year = gp.fip_cert_fiscal_year
                             AND bc.delivery_fiscal_year = cal.fiscal_year
                             AND bc.fuel_code = pl.fuel_code AND bc.area_code = gen.area_code
  CROSS JOIN fee_sell fs
  WHERE gen.target_date = p_target_date
  GROUP BY 1,2,3,4,5,6,7;

  -- 粗利・限界利益を発電行に設定（行の種類は segment ではなく direction で判定する）
  UPDATE agg_daily_pnl SET gross_profit = revenue - procurement_cost,
                         margin_per_kwh = SAFE_DIVIDE(revenue - procurement_cost, generation_kwh)
  WHERE target_date = p_target_date AND direction = 'OUTBOUND';

  -- ───────────────────────────────────────────────────────────
  -- STEP 4  検算（11.3）→ agg_data_quality_daily。NG は要確認フラグ
  -- ───────────────────────────────────────────────────────────
  CALL p_verify_daily_pnl(p_target_date, p_run_id, p_pipeline_version);   -- 検算 #1〜#3 を実行し is_verified を更新

  -- ───────────────────────────────────────────────────────────
  -- STEP 5 ⭐ 蓄電・揚水（オプション。未導入時は省略）
  -- ───────────────────────────────────────────────────────────
  -- CALL p_generate_battery_pnl(p_target_date, p_run_id, p_pipeline_version);   -- 第16章（Q-18：初期導入ではペンディング。導入時にコメント解除）

  -- ───────────────────────────────────────────────────────────
  -- STEP 6  集約マート（11.2 STEP 9）
  -- ───────────────────────────────────────────────────────────
  CALL p_generate_forecast_accuracy_daily(p_target_date, p_run_id, p_pipeline_version);   -- T-06
  -- CALL p_generate_slot_summary(p_target_date, p_run_id, p_pipeline_version);           -- T-03（別途）
END;


-- ============================================================
-- FILE: sql/procedure/p_generate_forecast_accuracy_daily.sql
-- ============================================================
-- 電力小売データ分析基盤
-- procedure/p_generate_forecast_accuracy_daily.sql
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
CREATE OR REPLACE PROCEDURE p_generate_forecast_accuracy_daily(IN p_target_date DATE, IN p_run_id STRING, IN p_pipeline_version STRING)
BEGIN
  DELETE FROM agg_forecast_accuracy_daily WHERE target_date = p_target_date;   -- べき等（対象日パーティション）

  INSERT INTO agg_forecast_accuracy_daily (
    target_date, demand_point_number, model_version,
    actual_kwh_sending_end, plan_kwh_sending_end, absolute_error_kwh,
    mape, wape, bias_kwh, bias_ratio, slots_evaluated,
    is_public_holiday, is_customer_holiday, expected_load_ratio, snapshot_loaded_at, ingestion_run_id, loaded_at, pipeline_version)
  WITH
  da_plan AS (   -- 前日計画（DA）の最新版。SENDING_END を優先し、なければ RECEIVING_END
    SELECT demand_point_number, slot_number, forecast_value_kw, plan_basis, COALESCE(model_version, 'UNKNOWN') AS model_version
    FROM fact_dem_plans
    WHERE target_date = p_target_date AND plan_type = 'DA'
    QUALIFY ROW_NUMBER() OVER (PARTITION BY demand_point_number, slot_number
                               ORDER BY CASE plan_basis WHEN 'SENDING_END' THEN 0 ELSE 1 END, plan_version DESC) = 1
  ),
  slot_level AS (
    SELECT
      act.target_date, act.demand_point_number, plan.model_version, act.slot_number,
      act.actual_value_kwh / (1 - loss.loss_rate)                                   AS slot_actual_sending_kwh,   -- 10.2
      CASE plan.plan_basis
        WHEN 'SENDING_END'   THEN plan.forecast_value_kw * 0.5
        WHEN 'RECEIVING_END' THEN plan.forecast_value_kw * 0.5 / (1 - loss.loss_rate)
      END                                                                          AS slot_plan_sending_kwh,     -- 10.3.1 基準統一
      cal.is_public_holiday,
      CASE WHEN ch.account_holiday_date IS NOT NULL THEN 1 ELSE 0 END               AS is_customer_holiday,
      COALESCE(ch.expected_load_ratio, 1.0)                                        AS expected_load_ratio
    FROM fact_dem_actuals_daily act
    JOIN dim_dem_customers cust ON act.demand_point_number = cust.demand_point_number
    JOIN da_plan plan         ON act.demand_point_number = plan.demand_point_number AND act.slot_number = plan.slot_number
    JOIN dim_loss_rates loss    ON act.area_code = loss.area_code AND cust.voltage_class = loss.voltage_class
                             AND act.target_date BETWEEN loss.start_date AND loss.end_date
    JOIN dim_date_calendar cal  ON act.target_date = cal.target_date
    LEFT JOIN dim_account_holidays ch
                              ON cust.account_id = ch.account_id AND act.target_date = ch.account_holiday_date
                             AND (ch.demand_point_number IS NULL OR ch.demand_point_number = act.demand_point_number)
    WHERE act.target_date = p_target_date
      -- 実潮流でない値をモデルの実力評価に混ぜない（13.4）。
      --   6 = 一送の推定検針（通信障害等で一送が推定した確定値）
      --   7 = 試運転期間（発電側のみ。需要側には現れないが値域として除外しておく）
      AND act.cleansing_flag NOT IN (6, 7)
  ),
  daily AS (
    SELECT
      target_date, demand_point_number, model_version,
      SUM(slot_actual_sending_kwh)                                        AS actual_kwh_sending_end,
      SUM(slot_plan_sending_kwh)                                          AS plan_kwh_sending_end,
      SUM(ABS(slot_actual_sending_kwh - slot_plan_sending_kwh))           AS absolute_error_kwh,
      -- MAPE：実績 0 のコマは SAFE_DIVIDE → NULL となり AVG から除外される（参考指標）
      AVG(SAFE_DIVIDE(ABS(slot_actual_sending_kwh - slot_plan_sending_kwh), slot_actual_sending_kwh)) * 100 AS mape,
      -- WAPE：日合計で割るため実績 0 コマの影響を受けない（閾値判定の主指標）
      SAFE_DIVIDE(SUM(ABS(slot_actual_sending_kwh - slot_plan_sending_kwh)), SUM(slot_actual_sending_kwh)) * 100 AS wape,
      SUM(slot_actual_sending_kwh - slot_plan_sending_kwh)                AS bias_kwh,
      SAFE_DIVIDE(SUM(slot_actual_sending_kwh - slot_plan_sending_kwh), SUM(slot_plan_sending_kwh)) AS bias_ratio,
      COUNT(*)                                                            AS slots_evaluated,
      MAX(is_public_holiday)                                              AS is_public_holiday,
      MAX(is_customer_holiday)                                            AS is_customer_holiday,
      MIN(expected_load_ratio)                                            AS expected_load_ratio
    FROM slot_level
    GROUP BY 1, 2, 3
  )
  SELECT target_date, demand_point_number, model_version,
         actual_kwh_sending_end, plan_kwh_sending_end, absolute_error_kwh,
         mape, wape, bias_kwh, bias_ratio, slots_evaluated,
         is_public_holiday, is_customer_holiday, expected_load_ratio, CURRENT_TIMESTAMP(),
         p_run_id, CURRENT_TIMESTAMP(), p_pipeline_version
  FROM daily;
END;


-- ============================================================
-- FILE: sql/procedure/p_load_public_holidays.sql
-- ============================================================
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


-- ============================================================
-- FILE: sql/procedure/p_monitor_bi_extract_sync.sql
-- ============================================================
-- 電力小売データ分析基盤
-- procedure/p_monitor_bi_extract_sync.sql
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
CREATE OR REPLACE PROCEDURE p_monitor_bi_extract_sync(IN p_target_date DATE, IN p_datasource_id STRING, IN p_run_id STRING, IN p_pipeline_version STRING)
BEGIN
  DECLARE v_all_verified   INT64;
  DECLARE v_batch_done_at  TIMESTAMP;
  DECLARE v_extract_jobs   INT64;

  -- 1) 品質ゲート：対象日の全行が検算通過
  SET v_all_verified = (SELECT COALESCE(MIN(is_verified), 0) FROM agg_daily_pnl WHERE target_date = p_target_date);
  SET v_batch_done_at = (SELECT MAX(finished_at) FROM fact_batch_run_log WHERE batch_id = 'B-05' AND target_date = p_target_date AND status = 'SUCCESS');

  IF v_all_verified = 0 OR v_batch_done_at IS NULL THEN
    MERGE agg_data_quality_daily t
    USING (SELECT p_target_date AS target_date, 'ALL' AS area_code, 'SYSTEM' AS side) s
    ON t.target_date = s.target_date AND t.area_code = s.area_code AND t.side = s.side
    WHEN MATCHED THEN UPDATE SET NOT is_publishable
    WHEN NOT MATCHED THEN INSERT (target_date, area_code, side, total_expected_slots, missing_slots_count,
                                  cleansed_flag_1_count, cleansed_flag_2_count, cleansed_flag_3_count, cleansed_flag_4_count,
                                  cleansing_ratio, null_rate_count, energy_balance_diff_kwh, unresolved_area_count, is_publishable)
                          VALUES (s.target_date, s.area_code, s.side, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, FALSE);
    SELECT 'BLOCKED_NOT_VERIFIED' AS status, p_target_date AS target_date;
    RETURN;
  END IF;

  -- 2) 抽出更新ジョブの検知（B-05 完了後に、対象データソースが抽出用ビューを読んで正常終了したジョブ）
  SET v_extract_jobs = (
    SELECT COUNT(*)
    FROM `region-asia-northeast1`.INFORMATION_SCHEMA.JOBS_BY_PROJECT j
    WHERE j.creation_time >= v_batch_done_at
      AND j.creation_time >= TIMESTAMP_SUB(CURRENT_TIMESTAMP(), INTERVAL 3 HOUR)   -- パーティション絞り込み（スキャン抑制）
      AND j.state = 'DONE' AND j.error_result IS NULL
      AND EXISTS (SELECT 1 FROM UNNEST(j.labels) l WHERE l.key = 'requestor' AND l.value = 'looker_studio')
      AND EXISTS (SELECT 1 FROM UNNEST(j.labels) l WHERE l.key = 'looker_studio_datasource_id' AND l.value = p_datasource_id)
      AND EXISTS (SELECT 1 FROM UNNEST(j.referenced_tables) r WHERE r.table_id = 'v_bi_daily_pnl_extract'));

  IF v_extract_jobs > 0 THEN
    MERGE agg_data_quality_daily t
    USING (SELECT p_target_date AS target_date, 'ALL' AS area_code, 'SYSTEM' AS side) s
    ON t.target_date = s.target_date AND t.area_code = s.area_code AND t.side = s.side
    WHEN MATCHED THEN UPDATE SET is_publishable
    WHEN NOT MATCHED THEN INSERT (target_date, area_code, side, total_expected_slots, missing_slots_count,
                                  cleansed_flag_1_count, cleansed_flag_2_count, cleansed_flag_3_count, cleansed_flag_4_count,
                                  cleansing_ratio, null_rate_count, energy_balance_diff_kwh, unresolved_area_count, is_publishable)
                          VALUES (s.target_date, s.area_code, s.side, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, TRUE);
    SELECT 'PUBLISHED' AS status, p_target_date AS target_date;
  ELSE
    SELECT 'EXTRACT_NOT_DETECTED' AS status, p_target_date AS target_date;   -- Composer がリトライ。6回目でもこの値ならアラート
  END IF;
END;


-- ============================================================
-- FILE: sql/procedure/p_validate_and_gate_customer_contracts.sql
-- ============================================================
-- 電力小売データ分析基盤
-- procedure/p_validate_and_gate_customer_contracts.sql
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
CREATE OR REPLACE PROCEDURE p_validate_and_gate_customer_contracts(IN p_batch_id STRING, IN p_run_id STRING, IN p_pipeline_version STRING)
BEGIN
  DECLARE v_error_count INT64 DEFAULT 0;
  DECLARE v_alert_msg   STRING;
  DECLARE v_run_id      STRING DEFAULT GENERATE_UUID();
  DECLARE v_started_at  TIMESTAMP DEFAULT CURRENT_TIMESTAMP();

  CREATE OR REPLACE TEMP TABLE tmp_contract_validation_errors AS
  WITH src AS (
    SELECT s.*, cust.voltage_class, cust.is_actual_kw_based, cust.area_code AS cust_area_code
    FROM `${GCP_PROJECT_ID}.${BQ_DATASET_STAGING}.migration_customer_contracts` s
    LEFT JOIN dim_dem_customers cust ON s.customer_id = cust.customer_id
    WHERE s.batch_id = p_batch_id
  ),
  sorted AS (
    SELECT *,
           LEAD(start_date)          OVER (PARTITION BY customer_id ORDER BY start_date, contract_history_id) AS next_start_date,
           LEAD(contract_history_id) OVER (PARTITION BY customer_id ORDER BY start_date, contract_history_id) AS next_contract_history_id
    FROM src
  ),
  flagged AS (
    SELECT customer_id, contract_history_id, start_date, end_date, next_contract_history_id, next_start_date,
      CASE
        WHEN start_date > end_date                                                                       THEN 'ERR_DATE_INVERSION_START_AFTER_END'
        WHEN next_start_date IS NOT NULL AND next_start_date <= end_date                                  THEN 'ERR_SCD2_OVERLAP_DETECTED'
        WHEN end_date <> DATE '9999-12-31' AND next_start_date IS NOT NULL
             AND DATE_ADD(end_date, INTERVAL 1 DAY) <> next_start_date                                    THEN 'ERR_SCD2_GAP_DETECTED'
        WHEN contract_status = '解約' AND end_date = DATE '9999-12-31'                                    THEN 'ERR_TERMINATED_BUT_OPEN'
        WHEN contract_status = '供給中' AND end_date <> DATE '9999-12-31' AND next_start_date IS NULL      THEN 'ERR_ACTIVE_BUT_CLOSED'
        WHEN (contract_kw IS NULL) = (contract_ampere IS NULL)                                            THEN 'ERR_KW_AMPERE_EXCLUSIVITY'      -- 13.1 ⑭
        WHEN contract_ampere IS NOT NULL AND (voltage_class <> '低圧' OR is_actual_kw_based)          THEN 'ERR_AMPERE_ONLY_FOR_LOW_VOLTAGE' -- 13.1 ⑭
        WHEN procurement_contract_id IS NOT NULL AND NOT EXISTS (                                         -- 13.1 ⑮
               SELECT 1 FROM dim_procurement_contracts pc
               WHERE pc.procurement_contract_id = sorted.procurement_contract_id
                 AND pc.area_code = sorted.cust_area_code
                 AND sorted.start_date BETWEEN pc.start_date AND pc.end_date)                              THEN 'ERR_PROCUREMENT_CONTRACT_INVALID'
        WHEN end_date <> DATE '9999-12-31' AND next_start_date IS NULL                                    THEN 'WARN_SCD2_NO_OPEN_RECORD'
        ELSE 'OK'
      END AS error_code
    FROM sorted
  )
  SELECT * FROM flagged WHERE error_code LIKE 'ERR_%';

  SET v_error_count = (SELECT COUNT(*) FROM tmp_contract_validation_errors);

  IF v_error_count > 0 THEN
    SET v_alert_msg = (
      SELECT FORMAT('【移行遮断】batch_id=%s：SCD2不整合 %d 件。例：需要家 %s / %s / 履歴 %s (%s〜%s) / 次履歴 %s (%s)',
                    p_batch_id, v_error_count, customer_id, error_code, contract_history_id,
                    CAST(start_date AS STRING), CAST(end_date AS STRING),
                    COALESCE(next_contract_history_id, '-'), COALESCE(CAST(next_start_date AS STRING), '-'))
      FROM tmp_contract_validation_errors LIMIT 1);
    -- 例外の前に実行ログへ FAILED を記録（RAISE 後の文は実行されない）
    INSERT INTO fact_batch_run_log (run_id, batch_id, target_date, started_at, finished_at, status, result_status, message, ingestion_run_id, loaded_at, pipeline_version)
  VALUES (v_run_id, 'B-09_VAL', CURRENT_DATE('Asia/Tokyo'), v_started_at, CURRENT_TIMESTAMP(), 'FAILED', 'REJECTED_BY_QUALITY_GATE', v_alert_msg, p_run_id, CURRENT_TIMESTAMP(), p_pipeline_version);
    RAISE USING MESSAGE = v_alert_msg;
  END IF;

  INSERT INTO fact_batch_run_log (run_id, batch_id, target_date, started_at, finished_at, status, result_status, message, ingestion_run_id, loaded_at, pipeline_version)
  VALUES (v_run_id, 'B-09_VAL', CURRENT_DATE('Asia/Tokyo'), v_started_at, CURRENT_TIMESTAMP(), 'SUCCESS', 'PASSED',
          FORMAT('batch_id=%s のSCD2検証を通過', p_batch_id), p_run_id, CURRENT_TIMESTAMP(), p_pipeline_version);
END;


-- ============================================================
-- FILE: sql/procedure/p_verify_daily_pnl.sql
-- ============================================================
-- 電力小売データ分析基盤
-- procedure/p_verify_daily_pnl.sql
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
CREATE OR REPLACE PROCEDURE p_verify_daily_pnl(IN p_target_date DATE, IN p_run_id STRING, IN p_pipeline_version STRING)
BEGIN
  DECLARE v_balance_diff NUMERIC;
  DECLARE v_total_demand NUMERIC;
  DECLARE v_amount_errors INT64;
  DECLARE v_pk_dups INT64;
  DECLARE v_direction_errors INT64;
  DECLARE v_null_rate_rows INT64;
  DECLARE v_ok BOOL;

  -- #1 電力量突合（送電端）
  SET (v_total_demand, v_balance_diff) = (
    SELECT AS STRUCT
      SUM(demand_kwh_sending_end),
      SUM(demand_kwh_sending_end) - SUM(generation_kwh) - SUM(imbalance_kwh)
        - (SELECT COALESCE(SUM(CASE trade_side WHEN '買' THEN contracted_kwh ELSE -contracted_kwh END), 0)
           FROM fact_jepx_trades WHERE target_date = p_target_date)
    FROM agg_daily_pnl WHERE target_date = p_target_date);

  -- #2 金額整合（前段）
  SET v_amount_errors = (
    SELECT COUNT(*) FROM agg_daily_pnl
    WHERE target_date = p_target_date
      AND (ABS(revenue - (rev_energy + rev_fuel_adj + rev_levy + rev_base_est + rev_market_sales + rev_fip_premium + rev_balancing_premium)) > 0.000001
        OR ABS(procurement_cost - (cost_jepx_spot + cost_jepx_fee + cost_procurement_contract + cost_imbalance + cost_wheeling_variable
                                   + cost_wheeling_fixed_est + cost_capacity_contribution + cost_nonfossil_certificate + cost_gen_charge
                                   + cost_levy_passthrough + fixed_fee_provisional + fixed_fee_final)) > 0.000001
        OR ABS(gross_profit - (revenue - procurement_cost)) > 0.000001));
  SET v_pk_dups = (
    SELECT COUNT(*) FROM (
      SELECT 1 FROM agg_daily_pnl WHERE target_date = p_target_date
      GROUP BY target_date, slot_number, area_code, bg_code, direction, segment, menu_type HAVING COUNT(*) > 1));
  SET v_direction_errors = (
    SELECT COUNT(*) FROM agg_daily_pnl
    WHERE target_date = p_target_date
      AND NOT ((direction = 'INBOUND'  AND segment IN ('低圧','高圧','特高') AND menu_type IN ('固定単価','市場連動') AND generation_kwh = 0)
            OR (direction = 'OUTBOUND' AND segment = '発電' AND menu_type IN ('FIP','非FIP') AND demand_kwh = 0)
            OR (direction = 'STORAGE'  AND segment = '蓄電池')));

  -- #3 単価網羅（STEP 0 で停止しているはずだが、二重に確認）
  SET v_null_rate_rows = (
    SELECT COUNT(*) FROM agg_daily_pnl
    WHERE target_date = p_target_date AND direction = 'INBOUND'
      AND (JSON_VALUE(applied_rate_refs, '$.loss_ids[0]') IS NULL OR JSON_VALUE(applied_rate_refs, '$.wheeling_ids[0]') IS NULL));

  SET v_ok = (ABS(v_balance_diff) <= v_total_demand * 0.001 AND v_amount_errors = 0 AND v_pk_dups = 0
              AND v_direction_errors = 0 AND v_null_rate_rows = 0);

  UPDATE agg_daily_pnl SET is_verified = v_ok WHERE target_date = p_target_date;

  MERGE agg_data_quality_daily t
  USING (SELECT p_target_date AS target_date, 'ALL' AS area_code, 'SYSTEM' AS side) s
  ON t.target_date = s.target_date AND t.area_code = s.area_code AND t.side = s.side
  WHEN MATCHED THEN UPDATE SET
    energy_balance_diff_kwh = v_balance_diff, null_rate_count = v_null_rate_rows,
    unresolved_area_count = v_amount_errors + v_pk_dups + v_direction_errors, is_publishable = v_ok
  WHEN NOT MATCHED THEN INSERT (target_date, area_code, side, total_expected_slots, missing_slots_count,
                                cleansed_flag_1_count, cleansed_flag_2_count, cleansed_flag_3_count, cleansed_flag_4_count,
                                cleansing_ratio, null_rate_count, energy_balance_diff_kwh, unresolved_area_count, is_publishable)
    VALUES (s.target_date, s.area_code, s.side, 0, 0, 0, 0, 0, 0, 0, v_null_rate_rows, v_balance_diff,
            v_amount_errors + v_pk_dups + v_direction_errors, v_ok);

  INSERT INTO fact_batch_run_log (run_id, batch_id, target_date, started_at, finished_at, status, result_status, message, ingestion_run_id, loaded_at, pipeline_version)
  VALUES (GENERATE_UUID(), 'B-05_VERIFY', p_target_date, CURRENT_TIMESTAMP(), CURRENT_TIMESTAMP(),
          'SUCCESS', IF(v_ok, 'VERIFIED', 'NOT_VERIFIED'),
          FORMAT('balance_diff=%t amount_err=%d pk_dup=%d dir_err=%d null_rate=%d', v_balance_diff, v_amount_errors, v_pk_dups, v_direction_errors, v_null_rate_rows), p_run_id, CURRENT_TIMESTAMP(), p_pipeline_version);
END;
