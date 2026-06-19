#!/usr/bin/env bash
set -euo pipefail

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
log="$repo_root/examples/logs/text/service.log"
rotated="$repo_root/examples/logs/text/service.log.1"

mv "$log" "$rotated"
printf '%s INFO first event after rotation\n' "$(date --iso-8601=seconds)" > "$log"

echo "Rotated service.log to service.log.1 and created a replacement file."

