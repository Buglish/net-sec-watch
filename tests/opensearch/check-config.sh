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
for stream in application system network pipeline; do
  grep -Fq "Index                net-sec-watch-${stream}-\${DEPLOYMENT_ENVIRONMENT}" \
    config/fluent-bit.opensearch.conf.example || {
    echo "Missing OpenSearch data-stream route for class: $stream" >&2
    exit 1
  }
done
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
assert template["version"] == 2
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
assert template["_meta"]["schema_version"] == "1.0.0"

rollover_policy = rollover["policy"]
assert rollover_policy["default_state"] == "hot"
assert rollover_policy["ism_template"]["index_patterns"] == [
    ".ds-net-sec-watch-*-*"
]
assert rollover_policy["ism_template"]["priority"] == 200
rollover_action = rollover_policy["states"][0]["actions"][0]["rollover"]
assert rollover_action["min_index_age"] == "1d"
assert rollover_action["min_size"] == "20gb"

print("OpenSearch explicit mapping contract is valid.")
print("OpenSearch age-and-size rollover policy is valid.")
PY
