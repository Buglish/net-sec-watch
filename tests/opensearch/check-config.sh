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
