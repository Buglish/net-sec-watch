#!/usr/bin/env bash
set -euo pipefail

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
project="net-sec-watch-oidc-integration"
admin_credential="Nsw-test-$(openssl rand -hex 12)-A9!"
identity_admin_credential="Idp-test-$(openssl rand -hex 12)-B7!"
client_credential="Oidc-client-$(openssl rand -hex 16)-C8!"
analyst_credential="Oidc-user-$(openssl rand -hex 12)-D6!"
opensearch_port=19209
dashboards_port=15604
keycloak_port=18080

compose() {
  OPENSEARCH_INITIAL_ADMIN_PASSWORD="$admin_credential" \
  OPENSEARCH_USERNAME=admin \
  OPENSEARCH_HTTP_PORT="$opensearch_port" \
  OPENSEARCH_DASHBOARDS_PORT="$dashboards_port" \
  KEYCLOAK_PORT="$keycloak_port" \
  KEYCLOAK_ADMIN_PASSWORD="$identity_admin_credential" \
  OIDC_CLIENT_SECRET="$client_credential" \
  OIDC_TEST_USER_PASSWORD="$analyst_credential" \
    docker compose \
      --project-name "$project" \
      --env-file "$repo_root/.env" \
      --file "$repo_root/compose.yaml" \
      --file "$repo_root/compose.opensearch-secure.yaml" \
      --file "$repo_root/compose.identity.yaml" \
      --profile opensearch \
      --profile identity \
      "$@"
}

cleanup() {
  compose down --volumes --remove-orphans >/dev/null 2>&1 || true
}

diagnostics() {
  compose ps >&2 || true
  compose logs --no-color keycloak opensearch opensearch-dashboards >&2 || true
}

trap cleanup EXIT
cleanup
"$repo_root/scripts/gen-tls-certs.sh"

if ! compose up -d opensearch-dashboards-bootstrap; then
  diagnostics
  echo "FAIL: OIDC integration stack did not start." >&2
  exit 1
fi
if ! compose wait opensearch-dashboards-bootstrap; then
  diagnostics
  echo "FAIL: Dashboards bootstrap failed with OIDC enabled." >&2
  exit 1
fi

# Reapply the authentication domain to prove existing security indexes can be
# updated without deleting event-data volumes.
compose exec -T opensearch \
  /usr/share/opensearch/plugins/opensearch-security/tools/securityadmin.sh \
  -f /usr/share/opensearch/config/opensearch-security/config.yml \
  -t config -icl -nhnv \
  -cacert /usr/share/opensearch/config/root-ca.pem \
  -cert /usr/share/opensearch/config/kirk.pem \
  -key /usr/share/opensearch/config/kirk-key.pem >/dev/null

discovery_url="http://127.0.0.1:${keycloak_port}/realms/net-sec-watch/.well-known/openid-configuration"
deadline=$((SECONDS + 240))
discovery=""
until discovery="$(curl --fail --silent "$discovery_url")"; do
  if ((SECONDS >= deadline)); then
    diagnostics
    echo "FAIL: Keycloak OIDC discovery did not become available." >&2
    exit 1
  fi
  sleep 3
done

python3 - "$discovery" "$keycloak_port" <<'PY'
import json
import sys

payload = json.loads(sys.argv[1])
issuer = (
    f"http://127.0.0.1:{sys.argv[2]}/realms/net-sec-watch"
)
assert payload["issuer"] == issuer
assert payload["authorization_endpoint"].startswith(issuer)
assert payload["token_endpoint"].startswith(issuer)
assert payload["jwks_uri"].startswith(issuer)
PY

token_response="$(
  curl --fail --silent --show-error \
    --request POST \
    --data-urlencode "grant_type=password" \
    --data-urlencode "client_id=net-sec-watch-dashboards" \
    --data-urlencode "client_secret=${client_credential}" \
    --data-urlencode "username=oidc-test-analyst" \
    --data-urlencode "password=${analyst_credential}" \
    "http://127.0.0.1:${keycloak_port}/realms/net-sec-watch/protocol/openid-connect/token"
)"
access_token="$(
  python3 - "$token_response" <<'PY'
import json
import sys

payload = json.loads(sys.argv[1])
assert payload["token_type"] == "Bearer"
assert payload["access_token"]
print(payload["access_token"])
PY
)"

auth_info="$(
  curl --fail --insecure --silent --show-error \
    --header "Authorization: Bearer ${access_token}" \
    "https://127.0.0.1:${opensearch_port}/_plugins/_security/authinfo"
)"
python3 - "$auth_info" <<'PY'
import json
import sys

payload = json.loads(sys.argv[1])
assert payload["user_name"] == "oidc-test-analyst"
assert "net-sec-watch-analyst" in payload["backend_roles"]
PY

oidc_headers="$(
  curl --silent --show-error \
    --cacert "$repo_root/config/tls/ca.crt" \
    --dump-header - \
    --output /dev/null \
    "https://127.0.0.1:${dashboards_port}/auth/openid/login"
)"
grep -Eqi '^location: http://127\.0\.0\.1:18080/realms/net-sec-watch/protocol/openid-connect/auth' \
  <<<"$oidc_headers" || {
  echo "$oidc_headers" >&2
  diagnostics
  echo "FAIL: Dashboards OIDC login did not redirect to Keycloak." >&2
  exit 1
}

basic_status="$(
  curl --silent \
    --cacert "$repo_root/config/tls/ca.crt" \
    --user "admin:${admin_credential}" \
    --output /dev/null \
    --write-out '%{http_code}' \
    "https://127.0.0.1:${dashboards_port}/api/status"
)"
[[ "$basic_status" == "200" ]] || {
  echo "FAIL: emergency basic login path returned HTTP ${basic_status}." >&2
  exit 1
}

echo "PASS: Keycloak published the Net Sec Watch OIDC discovery document"
echo "PASS: the confidential Dashboards client issued a signed analyst token"
echo "PASS: OpenSearch authenticated the OIDC user and extracted its backend role"
echo "PASS: Dashboards exposed OIDC and retained emergency basic authentication"
echo "PASS: the OIDC authentication domain reapplied without deleting data volumes"
