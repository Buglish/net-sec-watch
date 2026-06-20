#!/usr/bin/env bash
set -euo pipefail

script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
repo_root="$(cd "$script_dir/../.." && pwd)"
checker="$repo_root/scripts/check-telemetry-readiness.sh"

if "$checker" "$repo_root/config/traffic-telemetry-policy.example.yaml" \
    >/dev/null 2>&1; then
  echo "FAIL: draft telemetry policy unexpectedly passed" >&2
  exit 1
fi

"$checker" "$script_dir/approved-policy.yaml" >/dev/null
echo "PASS: telemetry readiness gate rejects drafts and accepts approved policy"
