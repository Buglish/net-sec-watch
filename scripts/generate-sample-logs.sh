#!/usr/bin/env bash
set -euo pipefail

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
timestamp="$(date --iso-8601=seconds)"

printf '%s INFO generated plain-text event\n' "$timestamp" \
  >> "$repo_root/examples/logs/text/service.log"

printf '{"timestamp":"%s","level":"INFO","service":"sample-generator","message":"generated JSON event","environment":"demo"}\n' \
  "$timestamp" >> "$repo_root/examples/logs/app/application.json.log"

printf '%s demo-host sample-generator[1]: generated system event\n' \
  "$(date '+%b %d %H:%M:%S')" >> "$repo_root/examples/logs/system/syslog"

printf '{"log":"generated container event\\n","stream":"stdout","time":"%s"}\n' \
  "$(date --utc '+%Y-%m-%dT%H:%M:%S.000000000Z')" \
  >> "$repo_root/examples/logs/containers/demo/demo-json.log"

echo "Generated one event for each sample source."

