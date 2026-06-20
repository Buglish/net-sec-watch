#!/usr/bin/env bash
set -euo pipefail

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
policy="${1:-$repo_root/config/traffic-telemetry-policy.yaml}"

[[ -s "$policy" ]] || {
  echo "Missing telemetry policy: $policy" >&2
  echo "Run 'make init', complete the policy, then retry." >&2
  exit 1
}

failures=0

require_pattern() {
  local pattern="$1"
  local message="$2"
  if ! grep -Eq "$pattern" "$policy"; then
    echo "FAIL: $message" >&2
    failures=$((failures + 1))
  fi
}

reject_pattern() {
  local pattern="$1"
  local message="$2"
  if grep -Eiq "$pattern" "$policy"; then
    echo "FAIL: $message" >&2
    failures=$((failures + 1))
  fi
}

reject_pattern 'replace-with|YYYY-MM-DD' \
  "replace all placeholder values"
require_pattern '^[[:space:]]*status:[[:space:]]*"approved"[[:space:]]*$' \
  "policy.status must be approved"
require_pattern '^[[:space:]]*measured_sample_hours:[[:space:]]*[1-9][0-9]*' \
  "record at least one measured sample hour"
require_pattern '^[[:space:]]*measured_bytes:[[:space:]]*[1-9][0-9]*' \
  "record measured telemetry bytes"
require_pattern '^[[:space:]]*estimated_daily_bytes:[[:space:]]*[1-9][0-9]*' \
  "record estimated daily bytes"
require_pattern '^[[:space:]]*peak_events_per_second:[[:space:]]*[1-9][0-9]*' \
  "record peak events per second"
require_pattern '^[[:space:]]*free_storage_bytes:[[:space:]]*[1-9][0-9]*' \
  "record available storage"
require_pattern '^[[:space:]]*raw_packet_capture:[[:space:]]*0[[:space:]]*$' \
  "raw packet capture retention must remain zero"
require_pattern '^[[:space:]]*payload_capture_enabled:[[:space:]]*false[[:space:]]*$' \
  "payload capture must remain disabled"
require_pattern '^[[:space:]]*tls_decryption_enabled:[[:space:]]*false[[:space:]]*$' \
  "TLS decryption must remain disabled"

for gate in \
  privacy_review_complete \
  capacity_review_complete \
  retention_review_complete \
  security_review_complete \
  test_capture_complete; do
  require_pattern "^[[:space:]]*${gate}:[[:space:]]*true[[:space:]]*$" \
    "${gate} must be true"
done

for dataset in \
  ids_alerts \
  connection_flows \
  dns \
  http_metadata \
  tls_metadata \
  dhcp \
  sensor_health; do
  require_pattern "^[[:space:]]*${dataset}:[[:space:]]*[1-9][0-9]*" \
    "set a positive retention period for ${dataset}"
done

if (( failures > 0 )); then
  echo "Telemetry readiness failed with $failures issue(s)." >&2
  exit 1
fi

echo "Telemetry policy is approved and passes readiness checks."
