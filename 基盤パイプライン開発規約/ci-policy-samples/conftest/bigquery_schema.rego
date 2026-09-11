package terraform.bigquery_schema

resource_changes[r] {
  r := input.resource_changes[_]
  r.mode == "managed"
  r.change.after != null
}

publish_layers := {"silver", "gold", "serving"}

deny[msg] {
  r := resource_changes[_]
  r.type == "google_bigquery_table"
  labels := object.get(r.change.after, "labels", {})
  environment := object.get(labels, "environment", "")
  layer := object.get(labels, "layer", "")
  environment == "prod"
  publish_layers[layer]
  partitioning := object.get(r.change.after, "time_partitioning", [])
  count(partitioning) == 0
  msg := sprintf("%s: production table must define time_partitioning", [r.address])
}

deny[msg] {
  r := resource_changes[_]
  r.type == "google_bigquery_table"
  labels := object.get(r.change.after, "labels", {})
  environment := object.get(labels, "environment", "")
  layer := object.get(labels, "layer", "")
  environment == "prod"
  publish_layers[layer]
  partitioning := object.get(r.change.after, "time_partitioning", [])
  count(partitioning) > 0
  p := partitioning[0]
  object.get(p, "require_partition_filter", false) != true
  msg := sprintf("%s: production table must set require_partition_filter=true", [r.address])
}

required_table_labels := {"environment", "layer", "domain", "data_product", "owner", "cost_center"}

deny[msg] {
  r := resource_changes[_]
  r.type == "google_bigquery_table"
  labels := object.get(r.change.after, "labels", {})
  missing := required_table_labels - {k | labels[k] != null}
  count(missing) > 0
  msg := sprintf("%s: missing table labels %v", [r.address, missing])
}

warn[msg] {
  r := resource_changes[_]
  r.type == "google_bigquery_table"
  object.get(r.change.after, "description", "") == ""
  msg := sprintf("%s: table description is missing", [r.address])
}
