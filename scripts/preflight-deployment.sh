#!/usr/bin/env bash
set -euo pipefail

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$repo_root"

check_files_only=false
if [[ "${1:-}" == "--check-files-only" ]]; then
  check_files_only=true
fi

required_files=(
  compose.yaml
  compose.opensearch-secure.yaml
  deploy/compose/compose.production.yaml
  deploy/environments/development.env.example
  deploy/environments/test.env.example
  deploy/environments/staging.env.example
  deploy/environments/production.env.example
  deploy/linux/install-linux-vm.sh
  deploy/kubernetes/namespace.yaml
  deploy/kubernetes/serviceaccount.yaml
  deploy/kubernetes/rbac.yaml
  deploy/kubernetes/configmap.yaml
  deploy/kubernetes/secret.example.yaml
  deploy/kubernetes/persistentvolumeclaims.yaml
  deploy/kubernetes/deployment.yaml
  deploy/kubernetes/services.yaml
  deploy/kubernetes/networkpolicy.yaml
  docs/deployment-portability.md
  docs/installation-administration-troubleshooting.md
  docs/supported-versions.md
  docs/production-readiness-review.md
)

for file in "${required_files[@]}"; do
  [[ -s "$file" ]] || {
    echo "Missing deployment prerequisite: $file" >&2
    exit 1
  }
done

if "$check_files_only"; then
  echo "Deployment file preflight passed."
  exit 0
fi

command -v docker >/dev/null 2>&1 || {
  echo "Docker is required for Compose deployment." >&2
  exit 1
}
docker compose version >/dev/null

if command -v kubectl >/dev/null 2>&1; then
  kubectl version --client=true >/dev/null
else
  echo "kubectl not found; Kubernetes deployment validation skipped." >&2
fi

docker compose --env-file .env config >/dev/null
echo "Deployment preflight passed."
