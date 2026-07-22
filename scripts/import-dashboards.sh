#!/usr/bin/env bash
set -euo pipefail

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$repo_root"

endpoint="${OPENSEARCH_DASHBOARDS_ENDPOINT:-http://127.0.0.1:5601}"
bundle="${DASHBOARDS_BUNDLE:-config/dashboards/managed-saved-objects-v1.ndjson}"
settings="${DASHBOARDS_DISCOVER_SETTINGS:-config/dashboards/discover-settings-v1.json}"
ca_file="${OPENSEARCH_DASHBOARDS_CA_FILE:-}"
username="${OPENSEARCH_DASHBOARDS_USERNAME:-${OPENSEARCH_USERNAME:-}}"
auth_value="${OPENSEARCH_DASHBOARDS_PASSWORD:-${OPENSEARCH_INITIAL_ADMIN_PASSWORD:-}}"
attempt=0

curl_args=(--fail --silent --show-error)

if [[ -n "$ca_file" ]]; then
  curl_args+=(--cacert "$ca_file")
elif [[ "$endpoint" == https://* ]]; then
  curl_args+=(--insecure)
fi

if [[ -n "$username" || -n "$auth_value" ]]; then
  if [[ -z "$username" || -z "$auth_value" ]]; then
    echo "Set both OPENSEARCH_DASHBOARDS_USERNAME and OPENSEARCH_DASHBOARDS_PASSWORD." >&2
    echo "Alternatively set OPENSEARCH_USERNAME and OPENSEARCH_INITIAL_ADMIN_PASSWORD." >&2
    exit 1
  fi
  curl_args+=(--user "$(printf '%s:%s' "$username" "$auth_value")")
fi

if [[ ! -s "$bundle" ]]; then
  echo "Dashboard bundle not found: $bundle" >&2
  echo "Run: make dashboards-bundle" >&2
  exit 1
fi

if [[ ! -s "$settings" ]]; then
  echo "Discover settings file not found: $settings" >&2
  exit 1
fi

echo "Waiting for OpenSearch Dashboards at $endpoint ..."
until curl "${curl_args[@]}" "${endpoint%/}/api/status" >/dev/null; do
  attempt=$((attempt + 1))
  if [[ "$attempt" -ge 80 ]]; then
    echo "OpenSearch Dashboards did not become ready." >&2
    exit 1
  fi
  sleep 3
done

echo "Importing Net Sec Watch data views, saved searches, and dashboards ..."
curl "${curl_args[@]}" \
  --header "osd-xsrf: true" \
  --form "file=@${bundle};type=application/ndjson" \
  "${endpoint%/}/api/saved_objects/_import?overwrite=true" >/dev/null

echo "Applying Discover defaults ..."
curl "${curl_args[@]}" \
  --header "Content-Type: application/json" \
  --header "osd-xsrf: true" \
  --request POST \
  --data-binary "@${settings}" \
  "${endpoint%/}/api/opensearch-dashboards/settings" >/dev/null

echo "Dashboards are installed."
echo "Open ${endpoint} and go to Discover."
