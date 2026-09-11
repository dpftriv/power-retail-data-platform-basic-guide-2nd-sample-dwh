from __future__ import annotations

from typing import Any, Dict, List, Tuple

from checkov.common.models.enums import CheckResult
from checkov.terraform.checks.resource.base_resource_check import BaseResourceCheck
from checkov.terraform.checks.resource.registry import resource_registry


class BigQueryDatasetRequiresControls(BaseResourceCheck):
    def __init__(self) -> None:
        super().__init__(
            name="Ensure production BigQuery datasets have labels, retention, and encryption controls",
            id="CKV_GCP_CUSTOM_001",
            categories=("general-security", "cost"),
            supported_resources=("google_bigquery_dataset",),
        )

    def scan_resource_conf(self, conf: Dict[str, Any]) -> Tuple[CheckResult, List[str]]:
        labels = conf.get("labels", [{}])[0] if conf.get("labels") else {}
        if labels.get("environment") != "prod":
            return CheckResult.PASSED, []
        failures: List[str] = []
        if not labels.get("owner"):
            failures.append("missing owner label")
        if not labels.get("cost_center"):
            failures.append("missing cost_center label")
        if labels.get("data_classification") not in {"permanent", "audit"}:
            expiration = conf.get("default_partition_expiration_ms", [0])[0]
            if not expiration:
                failures.append("default_partition_expiration_ms is required")
        if labels.get("data_classification") in {"restricted", "pii", "confidential"}:
            encryption = conf.get("default_encryption_configuration", [])
            if not encryption or not encryption[0].get("kms_key_name"):
                failures.append("CMEK kms_key_name is required for restricted data")
        return (CheckResult.PASSED, []) if not failures else (CheckResult.FAILED, failures)


class BigQueryTableRequiresPartitionFilter(BaseResourceCheck):
    def __init__(self) -> None:
        super().__init__(
            name="Ensure production Silver/Gold/Serving BigQuery tables require partition filters",
            id="CKV_GCP_CUSTOM_002",
            categories=("cost", "general-security"),
            supported_resources=("google_bigquery_table",),
        )

    def scan_resource_conf(self, conf: Dict[str, Any]) -> Tuple[CheckResult, List[str]]:
        labels = conf.get("labels", [{}])[0] if conf.get("labels") else {}
        if labels.get("environment") != "prod" or labels.get("layer") not in {"silver", "gold", "serving"}:
            return CheckResult.PASSED, []
        partitioning = conf.get("time_partitioning", [])
        if not partitioning:
            return CheckResult.FAILED, ["time_partitioning is required"]
        if partitioning[0].get("require_partition_filter") is not True:
            return CheckResult.FAILED, ["require_partition_filter must be true"]
        return CheckResult.PASSED, []


class NoPublicBigQueryIam(BaseResourceCheck):
    def __init__(self) -> None:
        super().__init__(
            name="Ensure production BigQuery IAM does not grant public access",
            id="CKV_GCP_CUSTOM_003",
            categories=("general-security",),
            supported_resources=("google_bigquery_dataset_iam_member", "google_bigquery_table_iam_member"),
        )

    def scan_resource_conf(self, conf: Dict[str, Any]) -> Tuple[CheckResult, List[str]]:
        member = conf.get("member", [""])[0] if isinstance(conf.get("member"), list) else conf.get("member", "")
        if member in {"allUsers", "allAuthenticatedUsers"}:
            return CheckResult.FAILED, [f"public principal {member} is prohibited"]
        return CheckResult.PASSED, []


resource_registry.register(BigQueryDatasetRequiresControls())
resource_registry.register(BigQueryTableRequiresPartitionFilter())
resource_registry.register(NoPublicBigQueryIam())
