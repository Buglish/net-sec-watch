#!/usr/bin/env bash
set -euo pipefail

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
project="net-sec-watch-smoke"

compose() {
  docker compose \
    --project-name "$project" \
    --env-file "$repo_root/.env" \
    --file "$repo_root/compose.yaml" \
    "$@"
}

cleanup() {
  compose down --volumes --remove-orphans >/dev/null 2>&1 || true
}

trap cleanup EXIT
cleanup
compose up -d
sleep 5

logs="$(compose logs --no-color fluent-bit)"

printf '%s\n' "$logs" |
  grep -F "request processing failed" |
  grep -Fq "IllegalStateException"

if printf '%s\n' "$logs" | grep -Fq '"log":""'; then
  echo "Empty log record detected in production smoke output." >&2
  exit 1
fi

curl --fail --silent http://127.0.0.1:2020/api/v1/health >/dev/null
echo "PASS: production Compose smoke test"

