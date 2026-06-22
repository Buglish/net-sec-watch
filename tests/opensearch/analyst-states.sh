#!/usr/bin/env bash
set -euo pipefail

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
project="net-sec-watch-analyst-states"
admin_credential="Nsw-test-$(openssl rand -hex 12)-A9!"
credentials="$(printf '%s:%s' admin "$admin_credential")"
port=19208
environment="state-test"
result="/tmp/net-sec-watch-analyst-states.json"
error_result="/tmp/net-sec-watch-query-error.json"

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
  curl --fail --insecure --silent --show-error \
    --user "$credentials" \
    "$@"
}

cleanup() {
  compose down --volumes --remove-orphans >/dev/null 2>&1 || true
  rm -f "$result" "$error_result"
}

trap cleanup EXIT
cleanup
compose up -d opensearch-bootstrap

deadline=$((SECONDS + 180))
until api \
  "https://127.0.0.1:${port}/_index_template/net-sec-watch-events-v1" \
  >/dev/null 2>&1; do
  if ((SECONDS >= deadline)); then
    compose logs --no-color >&2 || true
    echo "FAIL: analyst-state test stack did not become ready." >&2
    exit 1
  fi
  sleep 3
done

for stream in network system; do
  api --request PUT \
    "https://127.0.0.1:${port}/_data_stream/net-sec-watch-${stream}-${environment}" \
    >/dev/null
done

api \
  --header 'Content-Type: application/json' \
  --request PUT \
  --data '{
    "@timestamp":"2026-06-23T00:09:00Z",
    "message":"current network marker",
    "event":{"dataset":"state.test"}
  }' \
  "https://127.0.0.1:${port}/net-sec-watch-network-${environment}/_create/current" \
  >/dev/null

api \
  --header 'Content-Type: application/json' \
  --request PUT \
  --data '{
    "@timestamp":"2026-06-23T00:00:00Z",
    "message":"delayed system marker",
    "event":{"dataset":"state.test"}
  }' \
  "https://127.0.0.1:${port}/net-sec-watch-system-${environment}/_create/delayed" \
  >/dev/null

api --request POST \
  "https://127.0.0.1:${port}/net-sec-watch-*-${environment}/_refresh" \
  >/dev/null

set +e
OPENSEARCH_PASSWORD="$admin_credential" \
  "$repo_root/scripts/check-ingestion-status.py" \
    --endpoint "https://127.0.0.1:${port}" \
    --environment "$environment" \
    --max-age-seconds 300 \
    --now 2026-06-23T00:10:00Z \
    --insecure \
    --json >"$result"
status_code=$?
set -e
[[ "$status_code" -eq 1 ]] || {
  echo "FAIL: delayed stream did not produce a nonzero status." >&2
  exit 1
}

python3 - "$result" <<'PY'
import json
import sys

streams = {
    item["stream"]: item
    for item in json.load(open(sys.argv[1], encoding="utf-8"))["streams"]
}
assert streams["network"]["state"] == "current"
assert streams["network"]["age_seconds"] == 60
assert streams["system"]["state"] == "delayed"
assert streams["system"]["age_seconds"] == 600
assert streams["application"]["state"] == "empty"
assert streams["dead-letter"]["state"] == "empty"
PY

set +e
OPENSEARCH_PASSWORD="incorrect-password" \
  "$repo_root/scripts/check-ingestion-status.py" \
    --endpoint "https://127.0.0.1:${port}" \
    --environment "$environment" \
    --insecure \
    --json >"$error_result"
error_code=$?
set -e
[[ "$error_code" -eq 1 ]] || {
  echo "FAIL: query errors did not produce a nonzero status." >&2
  exit 1
}

python3 - "$error_result" <<'PY'
import json
import sys

states = {
    item["state"]
    for item in json.load(open(sys.argv[1], encoding="utf-8"))["streams"]
}
assert states == {"query_error"}
PY

python3 "$repo_root/tests/dashboards/test-ingestion-status.py"

echo "PASS: freshness check distinguished current, empty, and delayed streams"
echo "PASS: authentication failure was reported as query_error"
