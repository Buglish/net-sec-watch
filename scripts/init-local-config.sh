#!/usr/bin/env bash
set -euo pipefail

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$repo_root"

copy_if_missing() {
  local example="$1"
  local target="$2"

  if [[ -e "$target" ]]; then
    echo "Keeping existing $target"
    return
  fi

  cp "$example" "$target"
  echo "Created $target from $example"
}

copy_if_missing .env.example .env
copy_if_missing config/fluent-bit.local.conf.example config/fluent-bit.local.conf
copy_if_missing \
  config/fluent-bit.opensearch.conf.example \
  config/fluent-bit.opensearch.conf
copy_if_missing \
  config/traffic-telemetry-policy.example.yaml \
  config/traffic-telemetry-policy.yaml

mkdir -p runtime/zeek

if ! grep -Eq '^OPENSEARCH_INITIAL_ADMIN_PASSWORD=.+$' .env; then
  command -v openssl >/dev/null 2>&1 || {
    echo "OpenSSL is required to generate the local OpenSearch password." >&2
    exit 1
  }
  generated_value="Nsw-$(openssl rand -hex 16)-A9!"
  if grep -q '^OPENSEARCH_INITIAL_ADMIN_PASSWORD=' .env; then
    sed -i \
      "s|^OPENSEARCH_INITIAL_ADMIN_PASSWORD=.*|OPENSEARCH_INITIAL_ADMIN_PASSWORD=$generated_value|" \
      .env
  else
    printf '\nOPENSEARCH_INITIAL_ADMIN_PASSWORD=%s\n' "$generated_value" >> .env
  fi
  echo "Generated OPENSEARCH_INITIAL_ADMIN_PASSWORD in ignored .env"
fi

generate_if_missing() {
  local name="$1"
  local prefix="$2"
  if grep -Eq "^${name}=.+$" .env; then
    return
  fi
  local generated_value
  generated_value="${prefix}-$(openssl rand -hex 16)-A9!"
  if grep -q "^${name}=" .env; then
    sed -i "s|^${name}=.*|${name}=${generated_value}|" .env
  else
    printf '\n%s=%s\n' "$name" "$generated_value" >>.env
  fi
  echo "Generated ${name} in ignored .env"
}

generate_if_missing KEYCLOAK_ADMIN_PASSWORD Nsw-idp-admin
generate_if_missing OIDC_CLIENT_SECRET Nsw-oidc-client
generate_if_missing OIDC_ADMIN_USER_PASSWORD Nsw-oidc-admin
generate_if_missing OIDC_TEST_USER_PASSWORD Nsw-oidc-user
generate_if_missing OIDC_READ_ONLY_USER_PASSWORD Nsw-oidc-read
generate_if_missing OIDC_SOURCE_OWNER_USER_PASSWORD Nsw-oidc-owner
generate_if_missing OIDC_SERVICE_USER_PASSWORD Nsw-oidc-service

echo
echo "Local files are Git-ignored. Review .env before running Docker Compose."
