# データ基盤デザイン標準 最終成果物

このパッケージは、データ基盤汎用ガイド、電力小売り個別ガイド、統制実装チェックリスト、ローカル開発環境標準、Conftest / Checkov / GitHub Actionsの実装サンプル、Workload Identity Federation設定ガイド、ローカル検証手順、プレゼンテーションの最終版だけを収録しています。

## INDEX

### ドキュメント

| 日本語名 | 英語名（旧ファイル名） | リンク |
|---|---|---|
| [データ基盤汎用デザインガイド](design-guides/データ基盤汎用デザインガイド.md) | `data-platform-generic-design-guide.md` | [開く](design-guides/データ基盤汎用デザインガイド.md) |
| [電力小売りデータ基盤個別デザインガイド](design-guides/電力小売りデータ基盤個別デザインガイド.md) | `electricity-retail-data-platform-design-guide.md` | [開く](design-guides/電力小売りデータ基盤個別デザインガイド.md) |
| [CI/CD・Terraform自動検証チェックリストと電力小売りアンチパターン集](design-guides/CI_CD_Terraform自動検証チェックリストと電力小売りアンチパターン集.md) | `implementation-control-checklist-and-electricity-antipatterns.md` | [開く](design-guides/CI_CD_Terraform自動検証チェックリストと電力小売りアンチパターン集.md) |
| [GitHub Actions・GCP WIF設定ガイド](design-guides/GitHub_Actions_GCP_WIF設定ガイド.md) | `github-actions-wif-setup-guide.md` | [開く](design-guides/GitHub_Actions_GCP_WIF設定ガイド.md) |
| [Conftest・Checkovローカル実行手順書](design-guides/Conftest_Checkovローカル実行手順書.md) | `local-policy-test-guide.md` | [開く](design-guides/Conftest_Checkovローカル実行手順書.md) |
| [ローカル開発環境標準](design-guides/ローカル開発環境標準.md) | `local-development-environment-standard.md` | [開く](design-guides/ローカル開発環境標準.md) |

### 実装サンプル

| 日本語名 | 英語ファイル名 | リンク |
|---|---|---|
| Terraform統制ポリシー・CI/CDサンプル | `ci-policy-samples/README.md` | [開く](ci-policy-samples/README.md) |
| Terraformセキュリティ・コスト統制Rego | `ci-policy-samples/conftest/terraform_security_cost.rego` | [開く](ci-policy-samples/conftest/terraform_security_cost.rego) |
| BigQueryスキーマ・パーティション統制Rego | `ci-policy-samples/conftest/bigquery_schema.rego` | [開く](ci-policy-samples/conftest/bigquery_schema.rego) |
| Checkovカスタムポリシー | `ci-policy-samples/checkov/custom_policies.py` | [開く](ci-policy-samples/checkov/custom_policies.py) |
| Terraform Controls GitHub Actions | `ci-policy-samples/github-workflows/terraform-controls.yml` | [開く](ci-policy-samples/github-workflows/terraform-controls.yml) |

### プレゼンテーション

| 日本語名 | 英語ファイル名 | リンク |
|---|---|---|
| データ基盤CI/CD自動検証アーキテクチャ | `presentation/` | [プレゼンテーションフォルダ](presentation/) |

## ディレクトリ

- `design-guides/`：日本語ファイル名の最終ガイド・設定手順・ローカル実行手順
- `ci-policy-samples/`：Rego、Checkov、GitHub Actions、実行スクリプト。実装ファイル名はCI参照のため英語を維持
- `presentation/`：完成済みHTMLスライド8枚。スライドIDとの対応を維持するため英語ファイル名を維持

## フォルダツリー

```text
final-deliverable/
├── README.md
├── design-guides/
│   ├── データ基盤汎用デザインガイド.md
│   ├── 電力小売りデータ基盤個別デザインガイド.md
│   ├── CI_CD_Terraform自動検証チェックリストと電力小売りアンチパターン集.md
│   ├── GitHub_Actions_GCP_WIF設定ガイド.md
│   ├── Conftest_Checkovローカル実行手順書.md
│   └── ローカル開発環境標準.md
├── ci-policy-samples/
│   ├── README.md
│   ├── conftest/
│   │   ├── terraform_security_cost.rego
│   │   └── bigquery_schema.rego
│   ├── checkov/
│   │   └── custom_policies.py
│   ├── github-workflows/
│   │   └── terraform-controls.yml
│   └── scripts/
│       ├── local-policy-check.sh
│       ├── sql-static-check.sh
│       ├── bq-dry-run.sh
│       └── staging-access-test.sh
└── presentation/
    ├── overview.html
    ├── control_layers.html
    ├── pipeline.html
    ├── policy_engine.html
    ├── wif.html
    ├── electricity.html
    ├── local_run.html
    └── rollout.html
```

## 開発環境標準

ローカル開発環境は、[ローカル開発環境標準](design-guides/ローカル開発環境標準.md)を正とする。Terraform 1.16.2、Python 3.13.x、Google Cloud SDK 583.0.0を必須基準とし、その他のツールは用途に応じて導入する。

## 注意

`ci-policy-samples/github-workflows/terraform-controls.yml` は実リポジトリの `.github/workflows/` へ配置して使用してください。GCP Project、Repository ID、GitHub Environment、Variablesは実環境に合わせて設定してください。
