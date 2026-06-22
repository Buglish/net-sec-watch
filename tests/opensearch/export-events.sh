#!/usr/bin/env bash
set -euo pipefail

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
project="net-sec-watch-event-export"
admin_credential="Nsw-test-$(openssl rand -hex 12)-A9!"
credentials="$(printf '%s:%s' admin "$admin_credential")"
port=19207
stream="net-sec-watch-network-exporttest"
csv_output="/tmp/net-sec-watch-export-test.csv"
json_output="/tmp/net-sec-watch-export-test.jsonl"

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
  rm -f "$csv_output" "$json_output"
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
    echo "FAIL: OpenSearch export test stack did not become ready." >&2
    exit 1
  fi
  sleep 3
done

api --request PUT \
  "https://127.0.0.1:${port}/_data_stream/${stream}" >/dev/null

for number in 1 2 3; do
  api \
    --header 'Content-Type: application/json' \
    --request PUT \
    --data "{
      \"@timestamp\":\"2026-06-22T00:00:0${number}Z\",
      \"message\":\"=export marker ${number}\",
      \"event\":{
        \"dataset\":\"export.test\",
        \"action\":\"dropped\",
        \"original\":\"<4> export marker ${number}\"
      },
      \"source\":{\"ip\":\"192.0.2.${number}\"},
      \"destination\":{\"ip\":\"198.51.100.${number}\"}
    }" \
    "https://127.0.0.1:${port}/${stream}/_create/export-${number}" \
    >/dev/null
done

api --request POST \
  "https://127.0.0.1:${port}/${stream}/_refresh" >/dev/null

OPENSEARCH_PASSWORD="$admin_credential" \
  "$repo_root/scripts/export-events.py" \
    --endpoint "https://127.0.0.1:${port}" \
    --stream network \
    --start 2026-06-22T00:00:00Z \
    --end 2026-06-22T00:01:00Z \
    --query 'event.action:dropped' \
    --format csv \
    --limit 2 \
    --output "$csv_output" \
    --insecure

OPENSEARCH_PASSWORD="$admin_credential" \
  "$repo_root/scripts/export-events.py" \
    --endpoint "https://127.0.0.1:${port}" \
    --stream network \
    --start 2026-06-22T00:00:00Z \
    --end 2026-06-22T00:01:00Z \
    --format jsonl \
    --limit 3 \
    --output "$json_output" \
    --insecure

python3 - "$csv_output" "$json_output" <<'PY'
import csv
import json
import sys
from pathlib import Path

with Path(sys.argv[1]).open(encoding="utf-8", newline="") as source:
    rows = list(csv.DictReader(source))
assert len(rows) == 2
assert all(row["message"].startswith("'=export marker") for row in rows)
assert all(row["event.original"].startswith("<4> export marker") for row in rows)

records = [
    json.loads(line)
    for line in Path(sys.argv[2]).read_text(encoding="utf-8").splitlines()
]
assert len(records) == 3
assert {record["source.ip"] for record in records} == {
    "192.0.2.1", "192.0.2.2", "192.0.2.3"
}
assert all("event.original" in record for record in records)
PY

python3 "$repo_root/tests/dashboards/test-export-events.py"

echo "PASS: bounded CSV export enforced its row limit and neutralized formulas"
echo "PASS: bounded JSONL export preserved selected normalized and original fields"
