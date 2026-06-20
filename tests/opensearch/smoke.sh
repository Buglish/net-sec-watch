#!/usr/bin/env bash
set -euo pipefail

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
project="net-sec-watch-opensearch-smoke"

compose() {
  docker compose \
    --project-name "$project" \
    --env-file "$repo_root/.env" \
    --file "$repo_root/compose.yaml" \
    --profile opensearch \
    "$@"
}

cleanup() {
  compose down --volumes --remove-orphans >/dev/null 2>&1 || true
}

trap cleanup EXIT
cleanup

OPENSEARCH_HTTP_PORT=19200 compose up -d opensearch

deadline=$((SECONDS + 120))
until curl --fail --silent http://127.0.0.1:19200/_cluster/health > /tmp/net-sec-watch-opensearch-health.json; do
  if ((SECONDS >= deadline)); then
    compose logs --no-color opensearch >&2 || true
    echo "FAIL: OpenSearch did not become healthy within 120 seconds." >&2
    exit 1
  fi
  sleep 2
done

python3 - /tmp/net-sec-watch-opensearch-health.json <<'PY'
import json
import sys

with open(sys.argv[1], encoding="utf-8") as handle:
    health = json.load(handle)

assert health["number_of_nodes"] == 1, health
assert health["status"] in {"green", "yellow"}, health
print("PASS: OpenSearch single-node development deployment is healthy")
PY
