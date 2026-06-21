#!/usr/bin/env bash
set -euo pipefail

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
project="net-sec-watch-opensearch-retention"
admin_credential="Nsw-test-$(openssl rand -hex 12)-A9!"
credentials="$(printf '%s:%s' admin "$admin_credential")"
port=19205
policy_id="net-sec-watch-retention-test-v1"
stream="net-sec-watch-retention-test-development"
marker="RetentionLifecycleMarker001"

compose() {
  OPENSEARCH_INITIAL_ADMIN_PASSWORD="$admin_credential" \
  OPENSEARCH_USERNAME=admin \
  OPENSEARCH_HTTP_PORT="$port" \
    docker compose \
      --project-name "$project" \
      --env-file "$repo_root/.env" \
      --file "$repo_root/compose.yaml" \
      --file "$repo_root/compose.opensearch-secure.yaml" \
      --profile opensearch \
      "$@"
}

api() {
  curl --fail-with-body --insecure --silent --show-error \
    --user "$credentials" \
    "$@"
}

cleanup() {
  compose down --volumes --remove-orphans >/dev/null 2>&1 || true
}

diagnostics() {
  echo "--- retention lifecycle diagnostics ---" >&2
  api "https://127.0.0.1:${port}/_data_stream/${stream}?pretty" >&2 || true
  api "https://127.0.0.1:${port}/_plugins/_ism/explain/.ds-${stream}-*?show_policy=true&pretty" \
    >&2 || true
  api "https://127.0.0.1:${port}/_cat/indices/.ds-${stream}-*?v&expand_wildcards=all" \
    >&2 || true
  compose logs --no-color opensearch >&2 || true
}

fail() {
  echo "FAIL: $*" >&2
  diagnostics
  exit 1
}

wait_for_cluster() {
  local deadline=$((SECONDS + 180))
  until api "https://127.0.0.1:${port}/_cluster/health" >/dev/null; do
    if ((SECONDS >= deadline)); then
      fail "secured OpenSearch did not become ready."
    fi
    sleep 3
  done
}

wait_for_bootstrap() {
  local deadline=$((SECONDS + 60))
  until api \
    "https://127.0.0.1:${port}/_index_template/net-sec-watch-events-v1" \
    >/dev/null 2>&1; do
    if ((SECONDS >= deadline)); then
      fail "OpenSearch lifecycle bootstrap did not install the event template."
    fi
    sleep 2
  done
}

backing_indices() {
  api "https://127.0.0.1:${port}/_data_stream/${stream}" |
    python3 -c '
import json
import sys

payload = json.load(sys.stdin)
for stream in payload.get("data_streams", []):
    for index in stream.get("indices", []):
        print(index["index_name"])
'
}

trap cleanup EXIT
cleanup

compose up -d opensearch-bootstrap
wait_for_cluster
wait_for_bootstrap

api \
  --header 'Content-Type: application/json' \
  --request PUT \
  --data '{
    "persistent": {
      "plugins.index_state_management.job_interval": 1,
      "plugins.index_state_management.jitter": 0
    }
  }' \
  "https://127.0.0.1:${port}/_cluster/settings" >/dev/null

api \
  --header 'Content-Type: application/json' \
  --request PUT \
  --data "{
    \"policy\": {
      \"description\": \"Short-lived automatic rollover and deletion verification policy\",
      \"default_state\": \"hot\",
      \"schema_version\": 1,
      \"states\": [
        {
          \"name\": \"hot\",
          \"actions\": [
            {
              \"rollover\": {
                \"min_doc_count\": 1
              }
            }
          ],
          \"transitions\": [
            {
              \"state_name\": \"delete\"
            }
          ]
        },
        {
          \"name\": \"delete\",
          \"actions\": [
            {
              \"delete\": {}
            }
          ],
          \"transitions\": []
        }
      ],
      \"ism_template\": {
        \"index_patterns\": [
          \".ds-${stream}-*\"
        ],
        \"priority\": 1000
      }
    }
  }" \
  "https://127.0.0.1:${port}/_plugins/_ism/policies/${policy_id}" >/dev/null

api \
  --request PUT \
  "https://127.0.0.1:${port}/_data_stream/${stream}" >/dev/null

initial_index="$(backing_indices)"
[[ "$initial_index" == ".ds-${stream}-000001" ]] ||
  fail "unexpected initial backing index: ${initial_index:-none}"

api \
  --header 'Content-Type: application/json' \
  --request POST \
  --data "{\"policy_id\":\"${policy_id}\"}" \
  "https://127.0.0.1:${port}/_plugins/_ism/add/${initial_index}" >/dev/null

managed_deadline=$((SECONDS + 30))
while ((SECONDS < managed_deadline)); do
  managed_policy="$(
    api \
      "https://127.0.0.1:${port}/_plugins/_ism/explain/${initial_index}" |
      python3 -c '
import json
import sys

payload = json.load(sys.stdin)
for name, details in payload.items():
    if name != "total_managed_indices":
        print(details.get("policy_id") or "")
'
  )"
  [[ "$managed_policy" == "$policy_id" ]] && break
  sleep 2
done
[[ "$managed_policy" == "$policy_id" ]] ||
  fail "test backing index was not enrolled in ${policy_id}."

api \
  --header 'Content-Type: application/json' \
  --request PUT \
  --data "{\"@timestamp\":\"2026-06-21T00:00:00Z\",\"message\":\"${marker}\",\"event\":{\"dataset\":\"retention.lifecycle.test\"}}" \
  "https://127.0.0.1:${port}/${stream}/_create/retention-marker?refresh=true" \
  >/dev/null

rollover_deadline=$((SECONDS + 240))
rolled_index=""
while ((SECONDS < rollover_deadline)); do
  mapfile -t current_indices < <(backing_indices)
  if ((${#current_indices[@]} >= 2)); then
    for index in "${current_indices[@]}"; do
      if [[ "$index" != "$initial_index" ]]; then
        rolled_index="$index"
      fi
    done
    [[ -n "$rolled_index" ]] && break
  fi
  sleep 5
done

[[ -n "$rolled_index" ]] ||
  fail "ISM did not automatically roll over the data stream within 240 seconds."

delete_deadline=$((SECONDS + 240))
while ((SECONDS < delete_deadline)); do
  status="$(
    curl --insecure --silent \
      --user "$credentials" \
      --output /dev/null \
      --write-out '%{http_code}' \
      "https://127.0.0.1:${port}/${initial_index}"
  )"
  [[ "$status" == "404" ]] && break
  sleep 5
done

[[ "$status" == "404" ]] ||
  fail "ISM did not automatically delete retired index ${initial_index}."

mapfile -t retained_indices < <(backing_indices)
[[ "${#retained_indices[@]}" -eq 1 ]] ||
  fail "expected one active backing index after retention cleanup."
[[ "${retained_indices[0]}" == "$rolled_index" ]] ||
  fail "the rolled write index was not retained."

echo "PASS: ISM automatically rolled over ${initial_index}"
echo "PASS: ISM automatically deleted the retired backing index"
echo "PASS: active write index ${rolled_index} remains attached to ${stream}"
