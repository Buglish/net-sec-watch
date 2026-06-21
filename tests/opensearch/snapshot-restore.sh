#!/usr/bin/env bash
set -euo pipefail

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
project="net-sec-watch-opensearch-restore"
admin_credential="Nsw-test-$(openssl rand -hex 12)-A9!"
credentials="$(printf '%s:%s' admin "$admin_credential")"
port=19202
repository="net-sec-watch-local"
snapshot="net-sec-watch-restore-test"
stream="net-sec-watch-restore-development"
marker="SnapshotRestoreMarker001"
data_volume="${project}_opensearch-data"

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

cleanup() {
  compose down --volumes --remove-orphans >/dev/null 2>&1 || true
}

wait_for_cluster() {
  local deadline=$((SECONDS + 180))
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
}

wait_for_repository() {
  local deadline=$((SECONDS + 60))
  until curl --fail --insecure --silent \
    --user "$credentials" \
    "https://127.0.0.1:${port}/_snapshot/${repository}" >/dev/null; do
    if ((SECONDS >= deadline)); then
      compose logs --no-color opensearch-bootstrap >&2 || true
      echo "FAIL: snapshot repository was not registered." >&2
      exit 1
    fi
    sleep 2
  done
}

trap cleanup EXIT
cleanup

compose up -d opensearch-bootstrap
wait_for_cluster
wait_for_repository

curl --fail --insecure --silent \
  --user "$credentials" \
  --request PUT \
  "https://127.0.0.1:${port}/_data_stream/${stream}" >/dev/null

curl --fail --insecure --silent \
  --user "$credentials" \
  --header 'Content-Type: application/json' \
  --request PUT \
  --data "{\"@timestamp\":\"2026-06-21T00:00:00Z\",\"message\":\"${marker}\",\"event\":{\"dataset\":\"snapshot.restore.test\"}}" \
  "https://127.0.0.1:${port}/${stream}/_create/restore-marker?refresh=true" \
  >/dev/null

snapshot_result="$(
  curl --fail --insecure --silent \
    --user "$credentials" \
    --header 'Content-Type: application/json' \
    --request PUT \
    --data "{\"indices\":\"${stream}\",\"include_global_state\":false}" \
    "https://127.0.0.1:${port}/_snapshot/${repository}/${snapshot}?wait_for_completion=true"
)"
python3 - "$snapshot_result" "$stream" <<'PY'
import json, sys
snapshot = json.loads(sys.argv[1])["snapshot"]
assert snapshot["state"] == "SUCCESS"
assert any(
    index.startswith(f".ds-{sys.argv[2]}-")
    for index in snapshot["indices"]
)
assert snapshot["shards"]["failed"] == 0
PY

compose down --remove-orphans

docker volume inspect "$data_volume" >/dev/null
docker volume rm "$data_volume" >/dev/null

compose up -d opensearch-bootstrap
wait_for_cluster
wait_for_repository

status="$(
  curl --insecure --silent \
    --user "$credentials" \
    --output /dev/null \
    --write-out '%{http_code}' \
    "https://127.0.0.1:${port}/_data_stream/${stream}"
)"
[[ "$status" == "404" ]] || {
  echo "FAIL: clean cluster unexpectedly retained data stream (HTTP $status)." >&2
  exit 1
}

restore_response="/tmp/net-sec-watch-restore-result.json"
restore_status="$(
  curl --insecure --silent --show-error \
    --user "$credentials" \
    --header 'Content-Type: application/json' \
    --request POST \
    --data '{"include_global_state":false}' \
    --output "$restore_response" \
    --write-out '%{http_code}' \
    "https://127.0.0.1:${port}/_snapshot/${repository}/${snapshot}/_restore?wait_for_completion=true"
)"
if [[ "$restore_status" != "200" ]]; then
  cat "$restore_response" >&2
  echo "FAIL: snapshot restore returned HTTP $restore_status." >&2
  exit 1
fi
restore_result="$(cat "$restore_response")"
python3 - "$restore_result" <<'PY'
import json, sys
shards = json.loads(sys.argv[1])["snapshot"]["shards"]
assert shards["failed"] == 0
assert shards["successful"] == shards["total"]
PY

restored_event="$(
  curl --fail --insecure --silent \
    --user "$credentials" \
    "https://127.0.0.1:${port}/${stream}/_search?q=${marker}"
)"
python3 - "$restored_event" "$marker" <<'PY'
import json, sys
hits = json.loads(sys.argv[1])["hits"]["hits"]
assert len(hits) == 1
assert hits[0]["_source"]["message"] == sys.argv[2]
assert hits[0]["_source"]["event"]["dataset"] == "snapshot.restore.test"
PY

echo "PASS: snapshot completed successfully"
echo "PASS: live data volume was removed and a clean cluster was started"
echo "PASS: snapshot restored the expected data stream and marker event"
