package terraform.security_cost

is_exception(resource) {
  resource.change.after.metadata.control_exception == true
  resource.change.after.metadata.exception_expiry != ""
}

resource_changes[r] {
  r := input.resource_changes[_]
  r.mode == "managed"
  r.change.after != null
}

public_principals := {"allUsers", "allAuthenticatedUsers"}
broad_roles := {"roles/owner", "roles/editor", "roles/viewer"}
restricted_classes := {"restricted", "pii", "confidential"}

public_member(r) {
  r.type == "google_project_iam_member"
  public_principals[r.change.after.member]
}
public_member(r) {
  r.type == "google_bigquery_dataset_iam_member"
  public_principals[r.change.after.member]
}
public_member(r) {
  r.type == "google_storage_bucket_iam_member"
  public_principals[r.change.after.member]
}
public_member(r) {
  r.type == "google_project_iam_binding"
  member := r.change.after.members[_]
  public_principals[member]
}

deny[msg] {
  r := resource_changes[_]
  public_member(r)
  not is_exception(r)
  msg := sprintf("%s: public principal is prohibited", [r.address])
}

deny[msg] {
  r := resource_changes[_]
  r.type == "google_project_iam_member"
  broad_roles[r.change.after.role]
  not is_exception(r)
  msg := sprintf("%s: broad project role %s is prohibited", [r.address, r.change.after.role])
}

deny[msg] {
  r := resource_changes[_]
  r.type == "google_project_iam_binding"
  broad_roles[r.change.after.role]
  not is_exception(r)
  msg := sprintf("%s: broad project role %s is prohibited", [r.address, r.change.after.role])
}

deny[msg] {
  r := resource_changes[_]
  r.type == "google_service_account_key"
  not is_exception(r)
  msg := sprintf("%s: long-lived service account keys are prohibited", [r.address])
}

deny[msg] {
  r := resource_changes[_]
  r.type == "google_bigquery_dataset"
  env := object.get(r.change.after.labels, "environment", "")
  classification := object.get(r.change.after.labels, "data_classification", "")
  env == "prod"
  not classification == "permanent"
  not classification == "audit"
  object.get(r.change.after, "default_partition_expiration_ms", 0) == 0
  not is_exception(r)
  msg := sprintf("%s: production dataset has no default partition expiration", [r.address])
}

required_labels := {"environment", "domain", "data_product", "owner", "cost_center"}

deny[msg] {
  r := resource_changes[_]
  r.type == "google_bigquery_dataset"
  missing := required_labels - {k | r.change.after.labels[k] != null}
  count(missing) > 0
  not is_exception(r)
  msg := sprintf("%s: missing required cost labels %v", [r.address, missing])
}

deny[msg] {
  r := resource_changes[_]
  r.type == "google_storage_bucket"
  missing := required_labels - {k | r.change.after.labels[k] != null}
  count(missing) > 0
  not is_exception(r)
  msg := sprintf("%s: missing required cost labels %v", [r.address, missing])
}

deny[msg] {
  r := resource_changes[_]
  r.type == "google_bigquery_dataset"
  restricted_classes[object.get(r.change.after.labels, "data_classification", "")]
  object.get(r.change.after, "default_encryption_configuration", null) == null
  not is_exception(r)
  msg := sprintf("%s: restricted dataset must declare CMEK configuration", [r.address])
}

allowed_locations := {"asia-northeast1", "asia-northeast2", "US", "EU"}

deny[msg] {
  r := resource_changes[_]
  r.type == "google_bigquery_dataset"
  env := object.get(r.change.after.labels, "environment", "")
  env == "prod"
  location := object.get(r.change.after, "location", "")
  location != ""
  not allowed_locations[location]
  not is_exception(r)
  msg := sprintf("%s: unapproved production location %s", [r.address, location])
}

deny[msg] {
  r := resource_changes[_]
  r.type == "google_cloud_run_v2_service"
  env := object.get(r.change.after.labels, "environment", "")
  env == "prod"
  object.get(r.change.after, "ingress", "") == "INGRESS_TRAFFIC_ALL"
  not is_exception(r)
  msg := sprintf("%s: unrestricted Cloud Run ingress in production", [r.address])
}

warn[msg] {
  r := resource_changes[_]
  r.type == "google_bigquery_dataset"
  object.get(r.change.after, "description", "") == ""
  msg := sprintf("%s: dataset description is missing", [r.address])
}
