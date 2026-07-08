#!/usr/bin/env bash
set -euo pipefail

target_version="${1:-}"
if [[ -z "$target_version" ]]; then
  echo "Usage: $0 <git-tag-or-branch>" >&2
  exit 2
fi

git fetch --tags origin
git checkout "$target_version"
./scripts/preflight-deployment.sh
make check

echo "Upgrade preflight passed for ${target_version}."
echo "Apply with your deployment automation after snapshot verification."
