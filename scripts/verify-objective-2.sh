#!/usr/bin/env bash
set -euo pipefail

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$repo_root"

required=(
  config/scripts/syslog_metadata.lua
  examples/logs/network/asus-router-rfc3164.log
  examples/logs/network/generic-rfc5424.log
  scripts/gen-tls-certs.sh
  docs/phase-2-network-syslog.md
  tests/failover/compose.failover.yaml
  tests/failover/config/syslog-receiver.conf
  tests/failover/run-failover.sh
  config/scripts/zeek_metadata.lua
  docs/phase-2-zeek-sensor.md
  examples/logs/zeek/conn.log
  examples/logs/zeek/dns.log
  config/scripts/suricata_metadata.lua
  docs/phase-2-suricata-sensor.md
  examples/logs/suricata/eve.json
  config/traffic-telemetry-policy.example.yaml
  docs/traffic-telemetry-governance.md
  scripts/check-telemetry-readiness.sh
  tests/telemetry-policy/approved-policy.yaml
  tests/telemetry-policy/run.sh
)

for file in "${required[@]}"; do
  test -s "$file" || {
    echo "Missing or empty required file: $file" >&2
    exit 1
  }
done

grep -q 'Name.*syslog'             config/fluent-bit.conf
grep -q 'Mode.*udp'                config/fluent-bit.conf
grep -q 'Mode.*tcp'                config/fluent-bit.conf
grep -q 'Source_Address_Key'       config/fluent-bit.conf
grep -q 'net\.transport'           config/fluent-bit.conf
grep -q 'net\.syslog\.deadletter'  config/fluent-bit.conf
grep -q 'syslog_metadata'          config/fluent-bit.conf

grep -q '5514'                     compose.yaml
grep -q 'config/scripts'           compose.yaml
grep -q 'SYSLOG'                   .env.example

grep -q 'test_syslog_udp'          tests/integration/run.sh
grep -q 'test_syslog_tcp'          tests/integration/run.sh
grep -q 'test_syslog_deadletter'   tests/integration/run.sh
grep -q 'test_syslog_src_ip'       tests/integration/run.sh
grep -q 'test_asus_firewall_parsing' tests/integration/run.sh
grep -q 'event.action'              config/scripts/syslog_metadata.lua
grep -q 'source.ip'                 config/scripts/syslog_metadata.lua
grep -q 'destination.ip'            config/scripts/syslog_metadata.lua
grep -q 'RT-AC68U-TEST kernel: DROP' examples/logs/network/asus-router-rfc3164.log
grep -q 'send_udp_dual_target'      tests/failover/run-failover.sh
grep -q 'send_tcp_with_failover'    tests/failover/run-failover.sh
grep -q 'syslog-primary'            tests/failover/compose.failover.yaml
grep -q 'syslog-secondary'          tests/failover/compose.failover.yaml
grep -q 'sensor.zeek'               config/fluent-bit.conf
grep -q 'profiles.*zeek'            compose.yaml
grep -q 'test_zeek_collection'      tests/integration/run.sh
grep -q 'event.dataset'             config/scripts/zeek_metadata.lua
grep -q 'sensor.suricata'           config/fluent-bit.conf
grep -q 'profiles.*suricata'        compose.yaml
grep -q 'test_suricata_collection'  tests/integration/run.sh
grep -q 'event.dataset'             config/scripts/suricata_metadata.lua
grep -q 'suricata-update'           compose.yaml
grep -q 'update-suricata-rules'     Makefile
grep -q 'telemetry-readiness'       Makefile
grep -q 'raw_packet_capture'        config/traffic-telemetry-policy.example.yaml
grep -q 'Packet-loss'               docs/traffic-telemetry-governance.md
grep -q 'test-telemetry-policy'     Makefile

git check-ignore -q config/traffic-telemetry-policy.yaml || {
  echo "Real telemetry policy must be ignored by Git." >&2
  exit 1
}

grep -q 'Mode.*udp'                tests/integration/config/collector.conf
grep -q 'Mode.*tcp'                tests/integration/config/collector.conf

bash -n scripts/gen-tls-certs.sh

echo "Objective 2 configuration checks passed."
