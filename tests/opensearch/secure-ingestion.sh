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

dead_letter_marker="DeadLetterRoute001"
printf '<134>%s  deadletter[1234]: %s\n' \
  "$(date '+%b %e %H:%M:%S')" \
  "$dead_letter_marker" |
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
settings = template["template"]["settings"]
assert "data_stream" in template
assert mapping["dynamic"] is False
assert mapping["properties"]["source"]["properties"]["ip"]["type"] == "ip"
assert mapping["properties"]["event"]["properties"]["observed"]["type"] == "date"
index_settings = settings.get("index", settings)
assert index_settings["number_of_replicas"] == "0"
assert index_settings["auto_expand_replicas"] == "0-1"
' <<<"$template"

predictions_template="$(
  curl --fail --insecure --silent \
    --user "$credentials" \
    "https://127.0.0.1:${port}/_index_template/net-sec-watch-predictions-v1"
)"
model_template="$(
  curl --fail --insecure --silent \
    --user "$credentials" \
    "https://127.0.0.1:${port}/_index_template/net-sec-watch-model-metadata-v1"
)"
python3 - "$predictions_template" "$model_template" <<'PY'
import json, sys

prediction = json.loads(sys.argv[1])["index_templates"][0]["index_template"]
model = json.loads(sys.argv[2])["index_templates"][0]["index_template"]
assert "data_stream" in prediction
assert prediction["priority"] == 300
assert "data_stream" not in model
assert model["priority"] == 400
PY

model_stream_lookup="$(
  curl --fail --insecure --silent \
    --user "$credentials" \
    "https://127.0.0.1:${port}/_data_stream/net-sec-watch-model-metadata"
)"
python3 -c '
import json, sys
assert json.load(sys.stdin)["data_streams"] == []
' <<<"$model_stream_lookup"

curl --fail --insecure --silent \
  --user "$credentials" \
  --request PUT \
  "https://127.0.0.1:${port}/_data_stream/net-sec-watch-predictions-development" \
  >/dev/null

curl --fail --insecure --silent \
  --user "$credentials" \
  --header 'Content-Type: application/json' \
  --request PUT \
  --data '{"@timestamp":"2026-06-21T01:00:00Z","record":{"kind":"prediction"},"prediction":{"id":"prediction-test-001","source_event_id":"event-test-001","source_index":"net-sec-watch-network-development","classification":"suspicious_network_activity","threat_level":"medium","score":0.82,"confidence":0.91,"model_id":"network-classifier","model_version":"1.0.0","created_at":"2026-06-21T01:00:00Z","explanation":"Unusual destination and port combination"},"deployment":{"environment":{"name":"development"}}}' \
  "https://127.0.0.1:${port}/net-sec-watch-predictions-development/_create/prediction-test-001?refresh=true" \
  >/dev/null

curl --fail --insecure --silent \
  --user "$credentials" \
  --header 'Content-Type: application/json' \
  --request PUT \
  --data '{"@timestamp":"2026-06-21T01:05:00Z","record":{"kind":"feedback"},"feedback":{"id":"feedback-test-001","prediction_id":"prediction-test-001","analyst_id":"analyst-test","verdict":"true_positive","disposition":"confirmed","comment":"Confirmed during integration verification","created_at":"2026-06-21T01:05:00Z"},"deployment":{"environment":{"name":"development"}}}' \
  "https://127.0.0.1:${port}/net-sec-watch-predictions-development/_create/feedback-test-001?refresh=true" \
  >/dev/null

curl --fail --insecure --silent \
  --user "$credentials" \
  --header 'Content-Type: application/json' \
  --request PUT \
  --data '{"@timestamp":"2026-06-21T00:30:00Z","model":{"id":"network-classifier","version":"1.0.0","name":"Network threat classifier","task":"event_classification","framework":"scikit-learn","status":"candidate","artifact_uri":"models/network-classifier/1.0.0/model.bin","artifact_sha256":"aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa","features":["destination.port","network.transport","event.action"],"owner":"secops-ml","trained_at":"2026-06-20T22:00:00Z","registered_at":"2026-06-21T00:30:00Z","notes":"Integration metadata record"},"training":{"dataset":"net-sec-watch-network-training-v1","schema_version":"1.0.0","event_count":12000,"time_range":{"start":"2026-05-01T00:00:00Z","end":"2026-05-31T23:59:59Z"}},"metrics":{"precision":0.91,"recall":0.88,"f1":0.895,"roc_auc":0.94,"false_positive_rate":0.04}}' \
  "https://127.0.0.1:${port}/net-sec-watch-model-metadata/_doc/network-classifier-1.0.0?refresh=true" \
  >/dev/null

prediction_search="$(
  curl --fail --insecure --silent \
    --user "$credentials" \
    "https://127.0.0.1:${port}/net-sec-watch-predictions-development/_search?q=prediction.id:prediction-test-001"
)"
feedback_search="$(
  curl --fail --insecure --silent \
    --user "$credentials" \
    "https://127.0.0.1:${port}/net-sec-watch-predictions-development/_search?q=feedback.prediction_id:prediction-test-001"
)"
model_search="$(
  curl --fail --insecure --silent \
    --user "$credentials" \
    "https://127.0.0.1:${port}/net-sec-watch-model-metadata/_search?q=model.id:network-classifier"
)"
python3 - "$prediction_search" "$feedback_search" "$model_search" <<'PY'
import json, sys

prediction = json.loads(sys.argv[1])["hits"]["hits"][0]["_source"]
feedback = json.loads(sys.argv[2])["hits"]["hits"][0]["_source"]
model = json.loads(sys.argv[3])["hits"]["hits"][0]["_source"]
assert prediction["record"]["kind"] == "prediction"
assert prediction["prediction"]["score"] == 0.82
assert feedback["record"]["kind"] == "feedback"
assert feedback["feedback"]["verdict"] == "true_positive"
assert model["model"]["version"] == "1.0.0"
assert model["metrics"]["f1"] == 0.895
PY

cluster_settings="$(
  curl --fail --insecure --silent \
    --user "$credentials" \
    "https://127.0.0.1:${port}/_cluster/settings?flat_settings=true"
)"
python3 -c '
import json, sys
persistent = json.load(sys.stdin)["persistent"]
assert persistent["cluster.routing.allocation.disk.threshold_enabled"] == "true"
assert persistent["cluster.routing.allocation.disk.watermark.low"] == "75%"
assert persistent["cluster.routing.allocation.disk.watermark.high"] == "85%"
assert persistent[
    "cluster.routing.allocation.disk.watermark.flood_stage"
] == "90%"
assert persistent["cluster.info.update.interval"] == "30s"
' <<<"$cluster_settings"

snapshot_repository="$(
  curl --fail --insecure --silent \
    --user "$credentials" \
    "https://127.0.0.1:${port}/_snapshot/net-sec-watch-local"
)"
python3 -c '
import json, sys
repository = json.load(sys.stdin)["net-sec-watch-local"]
assert repository["type"] == "fs"
assert repository["settings"]["location"] == (
    "/usr/share/opensearch/snapshots/net-sec-watch"
)
assert repository["settings"]["compress"] == "true"
' <<<"$snapshot_repository"

snapshot_verification="$(
  curl --fail --insecure --silent \
    --user "$credentials" \
    --request POST \
    "https://127.0.0.1:${port}/_snapshot/net-sec-watch-local/_verify"
)"
python3 -c '
import json, sys
nodes = json.load(sys.stdin)["nodes"]
assert nodes
' <<<"$snapshot_verification"

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
states = {state["name"]: state for state in policy["states"]}
assert set(states) == {"hot", "warm", "archive", "delete"}

def get_action(state_name, action_name):
    return next(
        item[action_name]
        for item in states[state_name]["actions"]
        if action_name in item
    )

rollover_action = get_action("hot", "rollover")
assert rollover_action["min_index_age"] == "1d"
assert rollover_action["min_size"] == "20gb"
assert states["hot"]["transitions"][0] == {
    "state_name": "warm",
    "conditions": {"min_index_age": "7d"},
}
assert get_action("warm", "force_merge")["max_num_segments"] == 1
assert states["warm"]["transitions"][0] == {
    "state_name": "archive",
    "conditions": {"min_index_age": "30d"},
}
assert get_action("archive", "read_only") == {}
assert states["archive"]["transitions"][0] == {
    "state_name": "delete",
    "conditions": {"min_index_age": "90d"},
}
assert get_action("delete", "delete") == {}
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
  net-sec-watch-dead-letter-development
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

deadline=$((SECONDS + 60))
dead_letter_event=""
until [[ -n "$dead_letter_event" ]]; do
  dead_letter_event="$(
    curl --fail --insecure --silent \
      --user "$credentials" \
      "https://127.0.0.1:${port}/net-sec-watch-dead-letter-development/_search?q=${dead_letter_marker}" |
      python3 -c '
import json, sys
hits = json.load(sys.stdin)["hits"]["hits"]
print(json.dumps(hits[0]["_source"]) if hits else "")
' 2>/dev/null || true
  )"
  if ((SECONDS >= deadline)); then
    compose logs --no-color fluent-bit >&2 || true
    echo "FAIL: malformed event did not reach the dead-letter stream." >&2
    exit 1
  fi
  sleep 2
done
python3 - "$dead_letter_event" "$dead_letter_marker" <<'PY'
import json, sys
event = json.loads(sys.argv[1])
assert sys.argv[2] in event["event.original"]
assert event["event.dataset"] == "pipeline.deadletter"
assert event["event.kind"] == "pipeline_error"
assert event["error.type"] == "parsing_error"
assert event["error.stage"] == "syslog_input"
assert event["error.source_dataset"] == "syslog"
PY

network_copy_count="$(
  curl --fail --insecure --silent \
    --user "$credentials" \
    "https://127.0.0.1:${port}/net-sec-watch-network-development/_count?q=${dead_letter_marker}" |
    python3 -c 'import json,sys; print(json.load(sys.stdin)["count"])'
)"
[[ "$network_copy_count" -eq 0 ]] || {
  echo "FAIL: malformed event was duplicated into the network stream." >&2
  exit 1
}

backing_index="$(
  python3 - "$streams" <<'PY'
import json, sys
streams = json.loads(sys.argv[1])["data_streams"]
application = next(
    stream
    for stream in streams
    if stream["name"] == "net-sec-watch-application-development"
)
print(application["indices"][-1]["index_name"])
PY
)"
backing_settings="$(
  curl --fail --insecure --silent \
    --user "$credentials" \
    "https://127.0.0.1:${port}/${backing_index}/_settings?flat_settings=true"
)"
python3 - "$backing_settings" "$backing_index" <<'PY'
import json, sys
settings = json.loads(sys.argv[1])[sys.argv[2]]["settings"]
assert settings["index.number_of_replicas"] == "0"
assert settings["index.auto_expand_replicas"] == "0-1"
PY

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
echo "PASS: hot-warm-archive-delete lifecycle and data-stream rollover are valid"
echo "PASS: adaptive replicas and disk allocation watermarks are active"
echo "PASS: malformed events are isolated in the dedicated dead-letter stream"
echo "PASS: filesystem snapshot repository is registered and writable"
echo "PASS: prediction, analyst feedback, and model registry storage are queryable"
