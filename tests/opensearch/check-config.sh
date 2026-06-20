#!/usr/bin/env bash
set -euo pipefail

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
cd "$repo_root"

compose_config="$(
  docker compose --env-file .env --profile opensearch config
)"

grep -Fq 'opensearchproject/opensearch:3.7.0' <<<"$compose_config" || {
  echo "OpenSearch image is not pinned to the approved development version." >&2
  exit 1
}
grep -Fq 'DISABLE_SECURITY_PLUGIN: "true"' <<<"$compose_config" || {
  echo "Development OpenSearch security mode is not explicit." >&2
  exit 1
}
grep -Fq '127.0.0.1:9200' <<<"$compose_config" || {
  echo "Development OpenSearch API is not restricted to localhost." >&2
  exit 1
}
grep -Fq 'source: opensearch-data' <<<"$compose_config" || {
  echo "OpenSearch persistent data volume is missing." >&2
  exit 1
}

echo "OpenSearch development Compose configuration is valid."

secure_config="$(
  FLUENT_BIT_CONFIG_PATH=./config/fluent-bit.opensearch.conf \
    docker compose \
      --env-file .env \
      --file compose.yaml \
      --file compose.opensearch-secure.yaml \
      --profile opensearch config
)"

grep -Fq 'DISABLE_SECURITY_PLUGIN: "false"' <<<"$secure_config" || {
  echo "Secure OpenSearch override does not enable the Security plugin." >&2
  exit 1
}
grep -Fq 'OPENSEARCH_PASSWORD:' <<<"$secure_config" || {
  echo "Fluent Bit does not receive its ignored OpenSearch credential." >&2
  exit 1
}
grep -Fq "HTTP_User            \${OPENSEARCH_USERNAME}" \
  config/fluent-bit.opensearch.conf.example || {
  echo "OpenSearch HTTP authentication is missing from the Fluent Bit example." >&2
  exit 1
}
grep -Fq 'tls                  On' \
  config/fluent-bit.opensearch.conf.example || {
  echo "TLS is not enabled in the Fluent Bit OpenSearch output." >&2
  exit 1
}
grep -Fq '/config/fluent-bit.opensearch.conf' <<<"$secure_config" || {
  echo "Secure Fluent Bit configuration is not mounted." >&2
  exit 1
}
for private_file in .env config/fluent-bit.opensearch.conf; do
  git check-ignore --quiet "$private_file" || {
    echo "Private OpenSearch file is not ignored by Git: $private_file" >&2
    exit 1
  }
done

echo "Authenticated TLS ingestion configuration is valid."
