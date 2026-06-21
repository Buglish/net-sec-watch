#!/usr/bin/env bash
set -euo pipefail

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
project="net-sec-watch-opensearch-searchability"
admin_credential="Nsw-test-$(openssl rand -hex 12)-A9!"
port=19204
syslog_port=15144
health_port=12024

compose() {
  OPENSEARCH_INITIAL_ADMIN_PASSWORD="$admin_credential" \
  OPENSEARCH_USERNAME=admin \
  OPENSEARCH_HTTP_PORT="$port" \
  FLUENT_BIT_HTTP_PORT="$health_port" \
  SYSLOG_UDP_PORT="$syslog_port" \
  SYSLOG_TCP_PORT="$syslog_port" \
  SYSLOG_TLS_PORT=16518 \
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
until curl --fail --silent \
  "http://127.0.0.1:${health_port}/api/v1/health" >/dev/null; do
  if ((SECONDS >= deadline)); then
    compose logs --no-color >&2 || true
    echo "FAIL: searchability test stack did not become ready." >&2
    exit 1
  fi
  sleep 3
done

python3 "$repo_root/tests/opensearch/searchability-slo.py" \
  --syslog-port "$syslog_port" \
  --endpoint "https://127.0.0.1:${port}" \
  --username admin \
  --password "$admin_credential" \
  --events 100 \
  --deadline-seconds 10 \
  --required-percent 95
