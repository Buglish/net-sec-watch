#!/usr/bin/env bash
set -euo pipefail

rollback_ref="${1:-}"
if [[ -z "$rollback_ref" ]]; then
  echo "Usage: $0 <previous-git-tag-or-branch>" >&2
  exit 2
fi

git fetch --tags origin
git checkout "$rollback_ref"
./scripts/preflight-deployment.sh

echo "Rollback preflight passed for ${rollback_ref}."
echo "Restart services using the documented deployment procedure."
