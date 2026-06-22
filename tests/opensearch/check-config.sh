#!/usr/bin/env bash
set -euo pipefail

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
cd "$repo_root"

compose_config="$(
  docker compose --env-file .env --profile opensearch config
)"

grep -Fq 'opensearchproject/opensearch:3.7.0' <<<"$compose_config" || {
  echo "OpenSearch image is not pinned to the approved development version." >&2
  exit 1
}
grep -Fq 'DISABLE_SECURITY_PLUGIN: "true"' <<<"$compose_config" || {
  echo "Development OpenSearch security mode is not explicit." >&2
  exit 1
}
grep -Fq '127.0.0.1:9200' <<<"$compose_config" || {
  echo "Development OpenSearch API is not restricted to localhost." >&2
  exit 1
}
grep -Fq 'source: opensearch-data' <<<"$compose_config" || {
  echo "OpenSearch persistent data volume is missing." >&2
  exit 1
}
grep -Fq 'path.repo: /usr/share/opensearch/snapshots' <<<"$compose_config" || {
  echo "OpenSearch snapshot path allow-list is missing." >&2
  exit 1
}
grep -Fq 'source: opensearch-snapshots' <<<"$compose_config" || {
  echo "OpenSearch snapshot volume is missing." >&2
  exit 1
}
grep -Fq 'opensearchproject/opensearch-dashboards:3.7.0' \
  <<<"$compose_config" || {
  echo "OpenSearch Dashboards image is not pinned to the cluster version." >&2
  exit 1
}
grep -A20 -F 'opensearch-dashboards:' <<<"$compose_config" |
  grep -Fq 'host_ip: 127.0.0.1' || {
  echo "OpenSearch Dashboards is not restricted to localhost." >&2
  exit 1
}
grep -Fq 'DISABLE_SECURITY_DASHBOARDS_PLUGIN: "true"' \
  <<<"$compose_config" || {
  echo "Development Dashboards security mode is not explicit." >&2
  exit 1
}
grep -Fq 'opensearch-snapshot-init:' <<<"$compose_config" || {
  echo "OpenSearch snapshot volume initializer is missing." >&2
  exit 1
}

echo "OpenSearch development Compose configuration is valid."

secure_config="$(
  FLUENT_BIT_CONFIG_PATH=./config/fluent-bit.opensearch.conf \
    docker compose \
      --env-file .env \
      --file compose.yaml \
      --file compose.opensearch-secure.yaml \
      --profile opensearch config
)"

grep -Fq 'DISABLE_SECURITY_PLUGIN: "false"' <<<"$secure_config" || {
  echo "Secure OpenSearch override does not enable the Security plugin." >&2
  exit 1
}
grep -Fq 'OPENSEARCH_PASSWORD:' <<<"$secure_config" || {
  echo "Fluent Bit does not receive its ignored OpenSearch credential." >&2
  exit 1
}
grep -Fq 'DEPLOYMENT_ENVIRONMENT: development' <<<"$secure_config" || {
  echo "Fluent Bit does not receive the data-stream environment." >&2
  exit 1
}
grep -Fq 'opensearch-bootstrap:' <<<"$secure_config" || {
  echo "OpenSearch template bootstrap service is missing." >&2
  exit 1
}
grep -Fq 'DISABLE_SECURITY_DASHBOARDS_PLUGIN: "false"' \
  <<<"$secure_config" || {
  echo "Secure Dashboards does not enable the Security plugin." >&2
  exit 1
}
grep -Fq 'OPENSEARCH_SSL_VERIFICATIONMODE: none' <<<"$secure_config" || {
  echo "Secure Dashboards does not declare demo-certificate handling." >&2
  exit 1
}
grep -Fq 'OPENSEARCH_USERNAME: kibanaserver' <<<"$secure_config" || {
  echo "Secure Dashboards service identity is missing." >&2
  exit 1
}
grep -Fq 'opensearch-dashboards-bootstrap:' <<<"$secure_config" || {
  echo "OpenSearch Dashboards data-view bootstrap service is missing." >&2
  exit 1
}
grep -Fq '/dashboards-config/install-data-views.sh' <<<"$secure_config" || {
  echo "OpenSearch Dashboards data-view installer is not mounted." >&2
  exit 1
}
python3 - <<'PY'
import json
from pathlib import Path

settings = json.loads(
    Path("config/dashboards/discover-settings-v1.json").read_text(
        encoding="utf-8"
    )
)["changes"]
assert json.loads(settings["timepicker:timeDefaults"]) == {
    "from": "now-24h",
    "to": "now",
}
assert json.loads(settings["timepicker:refreshIntervalDefaults"]) == {
    "pause": True,
    "value": 0,
}
assert settings["histogram:barTarget"] == 50
assert settings["discover:sampleSize"] == 500
assert settings["doc_table:hideTimeColumn"] is False
expected_columns = [
    "message",
    "event.dataset",
    "event.action",
    "event.outcome",
    "source.ip",
    "destination.ip",
    "host.name",
    "event.original",
]
assert settings["defaultColumns"] == expected_columns

template = json.loads(
    Path("config/opensearch/index-template-v1.json").read_text(
        encoding="utf-8"
    )
)

def mapped_fields(properties, prefix=""):
    fields = set()
    for name, definition in properties.items():
        path = f"{prefix}.{name}" if prefix else name
        fields.add(path)
        if "properties" in definition:
            fields.update(mapped_fields(definition["properties"], path))
    return fields

properties = template["template"]["mappings"]["properties"]
assert set(expected_columns) <= mapped_fields(properties)
assert properties["event"]["properties"]["original"]["type"] == (
    "match_only_text"
)
PY
python3 - <<'PY'
import json
from pathlib import Path

objects = [
    json.loads(line)
    for line in Path("config/dashboards/data-views-v1.ndjson")
    .read_text(encoding="utf-8")
    .splitlines()
    if line
]
expected = {"application", "system", "network", "dead-letter"}
assert {
    item["id"].removeprefix("net-sec-watch-")
    for item in objects
} == expected
for item in objects:
    view = item["id"].removeprefix("net-sec-watch-")
    assert item["type"] == "index-pattern"
    assert item["attributes"]["title"] == f"net-sec-watch-{view}-*"
    assert item["attributes"]["timeFieldName"] == "@timestamp"
    assert item["references"] == []
PY
grep -Fq "HTTP_User            \${OPENSEARCH_USERNAME}" \
  config/fluent-bit.opensearch.conf.example || {
  echo "OpenSearch HTTP authentication is missing from the Fluent Bit example." >&2
  exit 1
}
grep -Fq 'tls                  On' \
  config/fluent-bit.opensearch.conf.example || {
  echo "TLS is not enabled in the Fluent Bit OpenSearch output." >&2
  exit 1
}
for stream in application system network dead-letter; do
  grep -Fq "Index                net-sec-watch-${stream}-\${DEPLOYMENT_ENVIRONMENT}" \
    config/fluent-bit.opensearch.conf.example || {
    echo "Missing OpenSearch data-stream route for class: $stream" >&2
    exit 1
  }
done
grep -A4 -F 'Match        net.syslog.deadletter' config/fluent-bit.conf |
  grep -Fq 'pipeline.deadletter' || {
  echo "Malformed syslog is not retagged for the dead-letter stream." >&2
  exit 1
}
write_operation_count="$(
  grep -Fc 'Write_Operation      create' \
    config/fluent-bit.opensearch.conf.example
)"
[[ "$write_operation_count" -eq 6 ]] || {
  echo "Every OpenSearch route must use create operations for data streams." >&2
  exit 1
}
grep -Fq '/config/fluent-bit.opensearch.conf' <<<"$secure_config" || {
  echo "Secure Fluent Bit configuration is not mounted." >&2
  exit 1
}
for private_file in .env config/fluent-bit.opensearch.conf; do
  git check-ignore --quiet "$private_file" || {
    echo "Private OpenSearch file is not ignored by Git: $private_file" >&2
    exit 1
  }
done

echo "Authenticated TLS ingestion configuration is valid."

python3 - <<'PY'
import json
from pathlib import Path

template = json.loads(
    Path("config/opensearch/index-template-v1.json").read_text(encoding="utf-8")
)
canonical = json.loads(
    Path("config/schema/canonical-event-schema-v1.json").read_text(
        encoding="utf-8"
    )
)
policy = json.loads(
    Path("config/schema/mapping-policy-v1.json").read_text(encoding="utf-8")
)
rollover = json.loads(
    Path("config/opensearch/rollover-policy-v1.json").read_text(
        encoding="utf-8"
    )
)
cluster_settings = json.loads(
    Path("config/opensearch/cluster-settings-v1.json").read_text(
        encoding="utf-8"
    )
)
snapshot_repository = json.loads(
    Path("config/opensearch/snapshot-repository-v1.json").read_text(
        encoding="utf-8"
    )
)
predictions_template = json.loads(
    Path("config/opensearch/predictions-template-v1.json").read_text(
        encoding="utf-8"
    )
)
model_template = json.loads(
    Path("config/opensearch/model-metadata-template-v1.json").read_text(
        encoding="utf-8"
    )
)
mapping = template["template"]["mappings"]
settings = template["template"]["settings"]

def mapped_fields(properties, prefix=""):
    fields = set()
    for name, definition in properties.items():
        path = f"{prefix}.{name}" if prefix else name
        if "properties" in definition:
            fields.update(mapped_fields(definition["properties"], path))
        else:
            fields.add(path)
    return fields

assert mapping["dynamic"] is False
assert mapping["date_detection"] is False
assert template["data_stream"] == {}
assert template["index_patterns"] == ["net-sec-watch-*-*"]
assert template["version"] == 3
assert mapping["properties"]["@timestamp"]["type"] == "date"
assert mapping["properties"]["source"]["properties"]["ip"]["type"] == "ip"
assert mapping["properties"]["message"]["type"] == "text"
assert set(canonical["properties"]) <= mapped_fields(mapping["properties"])
assert settings["index.mapping.total_fields.limit"] == policy[
    "opensearch_defaults"
]["index.mapping.total_fields.limit"]
assert settings["index.mapping.depth.limit"] == policy[
    "opensearch_defaults"
]["index.mapping.depth.limit"]
assert settings["index.mapping.field_name_length.limit"] == policy[
    "opensearch_defaults"
]["index.mapping.field_name_length.limit"]
assert settings["index.number_of_replicas"] == 0
assert settings["index.auto_expand_replicas"] == "0-1"
assert template["_meta"]["schema_version"] == "1.0.0"

persistent = cluster_settings["persistent"]
assert persistent["cluster.routing.allocation.disk.threshold_enabled"] is True
assert persistent["cluster.routing.allocation.disk.watermark.low"] == "75%"
assert persistent["cluster.routing.allocation.disk.watermark.high"] == "85%"
assert persistent[
    "cluster.routing.allocation.disk.watermark.flood_stage"
] == "90%"
assert persistent["cluster.info.update.interval"] == "30s"
assert snapshot_repository == {
    "type": "fs",
    "settings": {
        "location": "/usr/share/opensearch/snapshots/net-sec-watch",
        "compress": True,
    },
}

assert predictions_template["index_patterns"] == [
    "net-sec-watch-predictions-*"
]
assert predictions_template["priority"] > template["priority"]
assert predictions_template["data_stream"] == {}
prediction_properties = predictions_template["template"]["mappings"][
    "properties"
]
assert prediction_properties["prediction"]["properties"]["score"]["type"] == (
    "float"
)
assert prediction_properties["feedback"]["properties"]["verdict"]["type"] == (
    "keyword"
)
assert prediction_properties["record"]["properties"]["kind"]["type"] == (
    "keyword"
)

assert model_template["index_patterns"] == ["net-sec-watch-model-metadata"]
assert model_template["priority"] > predictions_template["priority"]
assert "data_stream" not in model_template
model_properties = model_template["template"]["mappings"]["properties"]
assert model_properties["model"]["properties"]["artifact_sha256"]["type"] == (
    "keyword"
)
assert model_properties["metrics"]["properties"]["f1"]["type"] == "float"
assert model_properties["training"]["properties"]["event_count"]["type"] == (
    "long"
)

rollover_policy = rollover["policy"]
assert rollover_policy["default_state"] == "hot"
assert rollover_policy["ism_template"]["index_patterns"] == [
    ".ds-net-sec-watch-*-*"
]
assert rollover_policy["ism_template"]["priority"] == 200
rollover_action = rollover_policy["states"][0]["actions"][0]["rollover"]
states = {state["name"]: state for state in rollover_policy["states"]}
assert set(states) == {"hot", "warm", "archive", "delete"}
assert rollover_action["min_index_age"] == "1d"
assert rollover_action["min_size"] == "20gb"
assert states["hot"]["transitions"] == [
    {"state_name": "warm", "conditions": {"min_index_age": "7d"}}
]
assert states["warm"]["actions"] == [
    {"force_merge": {"max_num_segments": 1}}
]
assert states["warm"]["transitions"] == [
    {"state_name": "archive", "conditions": {"min_index_age": "30d"}}
]
assert states["archive"]["actions"] == [{"read_only": {}}]
assert states["archive"]["transitions"] == [
    {"state_name": "delete", "conditions": {"min_index_age": "90d"}}
]
assert states["delete"]["actions"] == [{"delete": {}}]

print("OpenSearch explicit mapping contract is valid.")
print("OpenSearch hot-warm-archive-delete lifecycle policy is valid.")
print("OpenSearch replica and disk watermark configuration is valid.")
print("OpenSearch filesystem snapshot repository configuration is valid.")
print("OpenSearch Phase 11 prediction and model registry templates are valid.")
PY
