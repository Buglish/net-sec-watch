#!/usr/bin/env bash
set -euo pipefail

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
project="net-sec-watch-opensearch-secure-smoke"
admin_credential="Nsw-test-$(openssl rand -hex 12)-A9!"
credentials="$(printf '%s:%s' admin "$admin_credential")"
port=19201

compose() {
  OPENSEARCH_INITIAL_ADMIN_PASSWORD="$admin_credential" \
  OPENSEARCH_USERNAME=admin \
  OPENSEARCH_HTTP_PORT="$port" \
  FLUENT_BIT_HTTP_PORT=12021 \
  SYSLOG_UDP_PORT=15141 \
  SYSLOG_TCP_PORT=15141 \
  SYSLOG_TLS_PORT=16515 \
  FLUENT_BIT_CONFIG_PATH=./config/fluent-bit.opensearch.conf.example \
    docker compose \
      --project-name "$project" \
      --env-file "$repo_root/.env" \
      --file "$repo_root/compose.yaml" \
      --file "$repo_root/compose.opensearch-secure.yaml" \
      --profile opensearch \
      "$@"
}

cleanup() {
  compose down --volumes --remove-orphans >/dev/null 2>&1 || true
}

trap cleanup EXIT
cleanup
compose up -d opensearch-bootstrap fluent-bit

deadline=$((SECONDS + 180))
until curl --fail --insecure --silent \
  --user "$credentials" \
  "https://127.0.0.1:${port}/_cluster/health" >/dev/null; do
  if ((SECONDS >= deadline)); then
    compose logs --no-color >&2 || true
    echo "FAIL: secured OpenSearch did not become ready." >&2
    exit 1
  fi
  sleep 3
done

status="$(
  curl --insecure --silent --output /dev/null --write-out '%{http_code}' \
    "https://127.0.0.1:${port}/_cluster/health"
)"
[[ "$status" == "401" ]] || {
  echo "FAIL: unauthenticated OpenSearch request returned HTTP $status." >&2
  exit 1
}

deadline=$((SECONDS + 30))
until curl --fail --silent \
  http://127.0.0.1:12021/api/v1/health >/dev/null; do
  if ((SECONDS >= deadline)); then
    compose logs --no-color fluent-bit >&2 || true
    echo "FAIL: Fluent Bit did not become ready for test input." >&2
    exit 1
  fi
  sleep 1
done

printf '<134>%s stream-router data-stream-test: network stream marker\n' \
  "$(date '+%b %d %H:%M:%S')" |
  nc -u -w1 127.0.0.1 15141

template="$(
  curl --fail-with-body --insecure --silent --show-error \
    --user "$credentials" \
    "https://127.0.0.1:${port}/_index_template/net-sec-watch-events-v1"
)"
python3 -c '
import json, sys
template = json.load(sys.stdin)["index_templates"][0]["index_template"]
mapping = template["template"]["mappings"]
assert "data_stream" in template
assert mapping["dynamic"] is False
assert mapping["properties"]["source"]["properties"]["ip"]["type"] == "ip"
assert mapping["properties"]["event"]["properties"]["observed"]["type"] == "date"
' <<<"$template"

rollover_policy="$(
  curl --fail --insecure --silent \
    --user "$credentials" \
    "https://127.0.0.1:${port}/_plugins/_ism/policies/net-sec-watch-rollover-v1"
)"
python3 -c '
import json, sys
policy = json.load(sys.stdin)["policy"]
assert policy["default_state"] == "hot"
ism_templates = policy["ism_template"]
if isinstance(ism_templates, dict):
    ism_templates = [ism_templates]
assert ism_templates[0]["index_patterns"] == [".ds-net-sec-watch-*-*"]
action = policy["states"][0]["actions"][0]["rollover"]
assert action["min_index_age"] == "1d"
assert action["min_size"] == "20gb"
' <<<"$rollover_policy"

# Re-run bootstrap against the same cluster to exercise idempotent policy
# updates using the current sequence number and primary term.
compose run --rm opensearch-bootstrap >/dev/null

deadline=$((SECONDS + 90))
count=0
until ((count > 0)); do
  if ((SECONDS >= deadline)); then
    compose logs --no-color fluent-bit >&2 || true
    echo "FAIL: Fluent Bit did not index events over authenticated TLS." >&2
    exit 1
  fi
  count="$(
    curl --fail --insecure --silent \
      --user "$credentials" \
      "https://127.0.0.1:${port}/net-sec-watch-*-development/_count" |
      python3 -c 'import json,sys; print(json.load(sys.stdin).get("count", 0))' \
      2>/dev/null || echo 0
  )"
  sleep 2
done

required_streams=(
  net-sec-watch-application-development
  net-sec-watch-system-development
  net-sec-watch-network-development
)
deadline=$((SECONDS + 90))
while true; do
  streams="$(
    curl --fail --insecure --silent \
      --user "$credentials" \
      "https://127.0.0.1:${port}/_data_stream/net-sec-watch-*-development"
  )"
  if python3 - "$streams" "${required_streams[@]}" <<'PY'
import json, sys
names = {
    stream["name"]
    for stream in json.loads(sys.argv[1])["data_streams"]
}
required = set(sys.argv[2:])
raise SystemExit(0 if required <= names else 1)
PY
  then
    break
  fi
  if ((SECONDS >= deadline)); then
    compose logs --no-color fluent-bit >&2 || true
    echo "Observed data streams: $streams" >&2
    echo "FAIL: expected log-class data streams were not created." >&2
    exit 1
  fi
  sleep 2
done

curl --fail --insecure --silent \
  --user "$credentials" \
  --header 'Content-Type: application/json' \
  --request PUT \
  --data '{"@timestamp":"2026-06-20T00:00:00Z","event":{"dataset":"mapping-test"},"unknown_attacker_field":"retained"}' \
  "https://127.0.0.1:${port}/net-sec-watch-application-development/_create/mapping-test?refresh=true" \
  >/dev/null

source_value="$(
  curl --fail --insecure --silent \
    --user "$credentials" \
    "https://127.0.0.1:${port}/net-sec-watch-application-development/_search?q=event.dataset:mapping-test" |
    python3 -c 'import json,sys; print(json.load(sys.stdin)["hits"]["hits"][0]["_source"]["unknown_attacker_field"])'
)"
[[ "$source_value" == "retained" ]] || {
  echo "FAIL: unknown field was not retained in _source." >&2
  exit 1
}

field_caps="$(
  curl --fail --insecure --silent \
    --user "$credentials" \
    "https://127.0.0.1:${port}/net-sec-watch-application-development/_field_caps?fields=unknown_attacker_field"
)"
python3 -c '
import json, sys
assert "unknown_attacker_field" not in json.load(sys.stdin)["fields"]
' <<<"$field_caps"

rollover_response="/tmp/net-sec-watch-rollover-check.json"
rollover_status="$(
  curl --insecure --silent --show-error \
    --user "$credentials" \
    --header 'Content-Type: application/json' \
    --request POST \
    --data '{"conditions":{"max_age":"1d","max_size":"20gb"}}' \
    --output "$rollover_response" \
    --write-out '%{http_code}' \
    "https://127.0.0.1:${port}/net-sec-watch-application-development/_rollover?dry_run"
)"
if [[ "$rollover_status" != "200" ]]; then
  cat "$rollover_response" >&2
  echo "FAIL: data-stream rollover API returned HTTP $rollover_status." >&2
  exit 1
fi
rollover_check="$(cat "$rollover_response")"
python3 -c '
import json, sys
result = json.load(sys.stdin)
assert result["dry_run"] is True
assert result["old_index"].startswith(
    ".ds-net-sec-watch-application-development-"
)
assert result["new_index"].startswith(
    ".ds-net-sec-watch-application-development-"
)
assert set(result["conditions"]) == {
    "[max_age: 1d]",
    "[max_size: 20gb]",
}
' <<<"$rollover_check"

echo "PASS: authenticated TLS ingestion indexed $count events into class data streams"
echo "PASS: explicit mappings installed and dynamic fields stayed unindexed"
echo "PASS: age-and-size rollover policy and data-stream rollover are valid"
