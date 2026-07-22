#!/usr/bin/env bash
set -euo pipefail

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$repo_root"

require_command() {
  local command_name="$1"
  local hint="$2"
  command -v "$command_name" >/dev/null 2>&1 || {
    echo "Missing required tool: $command_name" >&2
    echo "  $hint" >&2
    exit 1
  }
}

require_command docker "Install Docker Engine or Docker Desktop: https://docs.docker.com/get-docker/"
require_command openssl "Install OpenSSL (needed to generate local secrets)."
require_command python3 "Install Python 3 (used by repository checks and tooling)."

docker compose version >/dev/null 2>&1 || {
  echo "Missing required tool: the Docker Compose v2 plugin" >&2
  echo "  'docker compose version' failed. Install/upgrade Docker so 'docker compose' works," >&2
  echo "  as opposed to the older standalone 'docker-compose' v1 binary." >&2
  exit 1
}

created_files=()
kept_files=()

copy_if_missing() {
  local example="$1"
  local target="$2"

  if [[ -e "$target" ]]; then
    echo "Keeping existing $target"
    kept_files+=("$target")
    return
  fi

  cp "$example" "$target"
  echo "Created $target from $example"
  created_files+=("$target")
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
if [[ ${#created_files[@]} -gt 0 ]]; then
  echo "Created: ${created_files[*]}"
fi
if [[ ${#kept_files[@]} -gt 0 ]]; then
  echo "Kept existing: ${kept_files[*]}"
fi
echo "Local files are Git-ignored. Review .env before running Docker Compose."
echo
echo "Next: make check, then make up (see docs/guides/admin-guide.md)."
