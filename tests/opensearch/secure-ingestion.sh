#!/usr/bin/env bash
set -euo pipefail

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
project="net-sec-watch-opensearch-secure-smoke"
admin_credential="Nsw-test-$(openssl rand -hex 12)-A9!"
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
compose up -d opensearch fluent-bit

deadline=$((SECONDS + 180))
until curl --fail --insecure --silent \
  --user "admin:$admin_credential" \
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
      --user "admin:$admin_credential" \
      "https://127.0.0.1:${port}/net-sec-watch-development/_count" |
      python3 -c 'import json,sys; print(json.load(sys.stdin).get("count", 0))' \
      2>/dev/null || echo 0
  )"
  sleep 2
done

echo "PASS: authenticated TLS ingestion indexed $count events"
