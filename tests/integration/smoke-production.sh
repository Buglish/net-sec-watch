#!/usr/bin/env bash
set -euo pipefail

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
project="net-sec-watch-smoke"
marker="production-smoke-$RANDOM-$RANDOM"
runtime="$repo_root/tests/runtime-smoke"
override="$repo_root/tests/integration/compose.smoke.yaml"
export FLUENT_BIT_HTTP_PORT=12020
export SYSLOG_UDP_PORT=15140
export SYSLOG_TCP_PORT=15140
export SYSLOG_TLS_PORT=16514

compose() {
  docker compose \
    --project-name "$project" \
    --env-file "$repo_root/.env" \
    --file "$repo_root/compose.yaml" \
    --file "$override" \
    "$@"
}

cleanup() {
  compose down --volumes --remove-orphans >/dev/null 2>&1 || true
  if [[ "$(realpath -m "$runtime")" == "$repo_root/tests/runtime-smoke" ]]; then
    rm -rf "$runtime"
  fi
}

trap cleanup EXIT
cleanup

mkdir -p "$runtime/logs/text"
printf '%s ERROR %s\n' "$(date '+%Y-%m-%d %H:%M:%S')" "$marker" \
  > "$runtime/logs/text/service.log"
printf 'java.lang.IllegalStateException: smoke detail\n' \
  >> "$runtime/logs/text/service.log"

compose up -d

deadline=$((SECONDS + 45))
logs=""
while (( SECONDS < deadline )); do
  logs="$(compose logs --no-color fluent-bit 2>/dev/null || true)"
  if grep -Fq "$marker" <<<"$logs" &&
      curl --fail --silent http://127.0.0.1:12020/api/v1/health >/dev/null; then
    break
  fi
  sleep 1
done

if ! grep -F "$marker" <<<"$logs" |
    grep -Fq "IllegalStateException"; then
  echo "Dedicated multiline smoke event was not collected." >&2
  compose logs --no-color >&2 || true
  exit 1
fi

if printf '%s\n' "$logs" | grep -Fq '"log":""'; then
  echo "Empty log record detected in production smoke output." >&2
  exit 1
fi

curl --fail --silent http://127.0.0.1:12020/api/v1/health >/dev/null
echo "PASS: production Compose smoke test"
