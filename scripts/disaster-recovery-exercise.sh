#!/usr/bin/env bash
set -euo pipefail

mode="${1:---dry-run}"

if [[ "$mode" != "--dry-run" && "$mode" != "--execute" ]]; then
  echo "Usage: $0 [--dry-run|--execute]" >&2
  exit 2
fi

required_files=(
  config/opensearch/snapshot-repository-v1.json
  docs/runbooks/backup-restore.md
  docs/runbooks/disaster-recovery-exercise.md
  docs/runbooks/opensearch-failure-disk-mapping.md
  config/operations/service-levels-v1.json
)

for file in "${required_files[@]}"; do
  [[ -s "$file" ]] || {
    echo "Missing DR exercise prerequisite: $file" >&2
    exit 1
  }
done

if [[ "$mode" == "--dry-run" ]]; then
  echo "DR dry run passed. Required runbooks and snapshot configuration exist."
  exit 0
fi

echo "Execute mode is intentionally operator-driven."
echo "Follow docs/runbooks/disaster-recovery-exercise.md and record evidence."
