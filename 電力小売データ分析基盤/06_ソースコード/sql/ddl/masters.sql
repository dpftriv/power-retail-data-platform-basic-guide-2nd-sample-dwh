-- =============================================================================
-- 電力小売データ分析基盤
-- Silver 層 マスタ（dim_*）DDL
-- 根拠：基本設計書 第7章（テーブル定義）・詳細設計書 第1部 2. 基盤・業務マスタ定義詳細、詳細設計書 第1部 3. 日付・カレンダーマスタ駆動設計
-- 注意：型・NOT NULL は設計書の記載に従う。
--       設計書に型の記載がない列は、命名規約から型を定めている。
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
  pii_customer_name                  STRING NOT NULL OPTIONS(description = '需要家名：PII。個人情報。初期はマスキングなし。将来 Policy Tags の対象列（15.3）'),
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
  procurement_contract_id            STRING OPTIONS(description = '専属調達契約ID：特定の相対・PPA契約（例：RE100顧客専用のコーポレートPPA）をこの需要家契約に専属させる場合に設定する。NULL の場合はエリア全体の調達（dim_procurement_contracts の紐付けなし分）から送電端需要比で按分される（10.8.4・13.1 ⑮）'),
  contract_group_id                  STRING OPTIONS(description = '契約グループID：実量制の判定単位を決めるキー。NULL＝地点単体で最大kWを判定（個別判定）。値あり（例：GRP_KAISHA_001）＝同一IDを持つ全地点の同一コマ電力量を合算して判定（グループ実量制）。同一グループは同一 account_id・同一 voltage_class でなければならない（13.1 ⑪）'),
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
  bg_code                            STRING NOT NULL OPTIONS(description = 'BGコード：公的に付与される識別子。期間管理（規約改定・按分方式変更）に対応するため、start_date と組み合わせて主キーとする'),
  bg_name                            STRING NOT NULL OPTIONS(description = 'BG名'),
  bg_type                            STRING NOT NULL OPTIONS(description = 'BG種別：発電 / 需要'),
  bg_structure                       STRING NOT NULL OPTIONS(description = '運営形態：SINGLE（自社単独）／CONSORTIUM（共同運営）'),
  representative_account_id          STRING OPTIONS(description = '代表事業者ID：送配電事業者に対して一括で支払義務を負う者'),
  area_code                          STRING OPTIONS(description = '管轄エリアコード：同一企業でもエリアごとに別BG'),
  is_own_bg                          BOOL NOT NULL OPTIONS(description = '自社BGフラグ：TRUE：自社が代表、FALSE：他社BGに構成員として参加'),
  allocation_method                  STRING NOT NULL OPTIONS(description = '按分方式：SIMPLE_RATIO／FIXED_SHARE／CAUSER_PAYS／HYBRID（10.3.2）。BG規約が唯一の正'),
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
  bg_member_id                       STRING NOT NULL OPTIONS(description = '構成員ID：(bg_code, account_id) の初回登録時に1回だけ発行し、以降の属性変更（シェア変更・免責変更等）では同じ値を維持したまま新しい start_date の行を追加する（安定識別子）。fact_bg_member_imbalance.bg_member_id を軸に同一構成員の履歴を追跡できる'),
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
  scope_level                        STRING NOT NULL OPTIONS(description = '適用スコープ：MENU（メニュー×エリア：標準）／CUSTOMER（顧客単体）／POINT（地点単体）。現時点は MENU のみ運用し、特高の個別特約が確定した時点で CUSTOMER / POINT 行を追加する'),
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
  capacity_kwh_rate                  NUMERIC NOT NULL OPTIONS(description = '電力量一律拠出金単価：円/kWh。日報の調達原価に用いる単価'),
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
  fit_levy_rate_incl_tax             NUMERIC NOT NULL OPTIONS(description = '公表単価（税込）：円/kWh・全国一律。国の公表値をそのまま保持し、計算にもこの税込単価を使う。単価を税抜化した列は持たない（端数ズレの原因になるため）'),
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

