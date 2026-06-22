#!/usr/bin/env bash
set -euo pipefail

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
project="net-sec-watch-dashboards-smoke"
admin_credential="Nsw-test-$(openssl rand -hex 12)-A9!"
opensearch_port=19206
dashboards_port=15601

compose() {
  OPENSEARCH_INITIAL_ADMIN_PASSWORD="$admin_credential" \
  OPENSEARCH_USERNAME=admin \
  OPENSEARCH_HTTP_PORT="$opensearch_port" \
  OPENSEARCH_DASHBOARDS_PORT="$dashboards_port" \
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

diagnostics() {
  compose ps >&2 || true
  compose logs --no-color opensearch opensearch-bootstrap \
    opensearch-dashboards opensearch-dashboards-bootstrap >&2 || true
}

trap cleanup EXIT
cleanup
if ! compose up -d opensearch-dashboards-bootstrap; then
  diagnostics
  echo "FAIL: Dashboards data-view bootstrap did not complete." >&2
  exit 1
fi
if ! compose wait opensearch-dashboards-bootstrap; then
  diagnostics
  echo "FAIL: Dashboards data-view bootstrap exited unsuccessfully." >&2
  exit 1
fi

deadline=$((SECONDS + 240))
status=""
until status="$(
  curl --fail --silent \
    --user "admin:${admin_credential}" \
    "http://127.0.0.1:${dashboards_port}/api/status"
)"; do
  if ((SECONDS >= deadline)); then
    diagnostics
    echo "FAIL: OpenSearch Dashboards did not become reachable." >&2
    exit 1
  fi
  sleep 3
done

python3 - "$status" <<'PY'
import json
import sys

payload = json.loads(sys.argv[1])
overall = payload.get("status", {}).get("overall", {})
level = overall.get("level") or overall.get("state")
if level not in {"available", "green"}:
    raise SystemExit(f"Dashboards status is not available: {level!r}")
PY

anonymous_status="$(
  curl --silent \
    --output /dev/null \
    --write-out '%{http_code}' \
    "http://127.0.0.1:${dashboards_port}/api/status"
)"
[[ "$anonymous_status" == "401" ]] || {
  diagnostics
  echo "FAIL: anonymous status access returned HTTP ${anonymous_status}." >&2
  exit 1
}

login_status="$(
  curl --silent \
    --output /dev/null \
    --write-out '%{http_code}' \
    "http://127.0.0.1:${dashboards_port}/app/login"
)"
[[ "$login_status" =~ ^(200|302)$ ]] || {
  diagnostics
  echo "FAIL: Dashboards login returned HTTP ${login_status}." >&2
  exit 1
}

for view in application system network dead-letter; do
  saved_object="$(
    curl --fail --silent \
      --user "admin:${admin_credential}" \
      "http://127.0.0.1:${dashboards_port}/api/saved_objects/index-pattern/net-sec-watch-${view}"
  )"
  python3 - "$saved_object" "$view" <<'PY'
import json
import sys

payload = json.loads(sys.argv[1])
view = sys.argv[2]
assert payload["id"] == f"net-sec-watch-{view}"
assert payload["type"] == "index-pattern"
assert payload["attributes"]["title"] == f"net-sec-watch-{view}-*"
assert payload["attributes"]["timeFieldName"] == "@timestamp"
PY
done

echo "PASS: secured OpenSearch Dashboards status is available"
echo "PASS: anonymous status access is rejected"
echo "PASS: browser login endpoint is reachable on localhost"
echo "PASS: approved application, system, network, and dead-letter data views exist"
