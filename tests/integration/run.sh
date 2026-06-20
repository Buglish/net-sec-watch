#!/usr/bin/env bash
set -euo pipefail

script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
repo_root="$(cd "$script_dir/../.." && pwd)"
runtime="$repo_root/tests/runtime"
compose_file="$script_dir/compose.integration.yaml"
project="net-sec-watch-integration"

compose() {
  docker compose \
    --project-name "$project" \
    --env-file "$repo_root/.env" \
    --file "$compose_file" \
    "$@"
}

cleanup() {
  compose down --volumes --remove-orphans >/dev/null 2>&1 || true
}

fail() {
  echo "FAIL: $*" >&2
  compose ps >&2 || true
  compose logs --no-color >&2 || true
  exit 1
}

wait_for_log() {
  local service="$1"
  local marker="$2"
  local timeout="${3:-45}"
  local deadline=$((SECONDS + timeout))

  while (( SECONDS < deadline )); do
    if compose logs --no-color "$service" 2>/dev/null | grep -Fq "$marker"; then
      return 0
    fi
    sleep 1
  done

  fail "marker '$marker' was not observed in $service logs"
}

marker_count() {
  local service="$1"
  local marker="$2"
  compose logs --no-color "$service" 2>/dev/null | grep -Foc "$marker" || true
}

prepare_runtime() {
  rm -rf "$runtime"
  mkdir -p \
    "$runtime/logs/text" \
    "$runtime/logs/app" \
    "$runtime/logs/system" \
    "$runtime/logs/containers/demo" \
    "$runtime/logs/zeek" \
    "$runtime/logs/suricata"

  cp "$repo_root/examples/logs/text/service.log" "$runtime/logs/text/service.log"
  cp "$repo_root/examples/logs/app/application.json.log" "$runtime/logs/app/application.json.log"
  cp "$repo_root/examples/logs/system/syslog" "$runtime/logs/system/syslog"
  cp "$repo_root/examples/logs/system/auth.log" "$runtime/logs/system/auth.log"
  cp "$repo_root/examples/logs/containers/demo/demo-json.log" \
    "$runtime/logs/containers/demo/demo-json.log"
  cp "$repo_root/examples/logs/zeek/"*.log "$runtime/logs/zeek/"
  cp "$repo_root/examples/logs/suricata/eve.json" \
    "$runtime/logs/suricata/eve.json"
}

test_initial_collection() {
  local text_marker="phase1-text-$RANDOM-$RANDOM"
  local app_marker="phase1-app-$RANDOM-$RANDOM"
  local system_marker="phase1-system-$RANDOM-$RANDOM"
  local container_marker="phase1-container-$RANDOM-$RANDOM"

  printf '%s INFO %s\n' "$(date --iso-8601=seconds)" "$text_marker" \
    >> "$runtime/logs/text/service.log"
  printf '{"timestamp":"%s","level":"INFO","service":"integration-test","message":"%s"}\n' \
    "$(date --iso-8601=seconds)" "$app_marker" \
    >> "$runtime/logs/app/application.json.log"
  printf '%s test-host phase1[1]: %s\n' "$(date '+%b %d %H:%M:%S')" "$system_marker" \
    >> "$runtime/logs/system/syslog"
  printf '{"log":"%s\\n","stream":"stdout","time":"%s"}\n' \
    "$container_marker" "$(date --utc '+%Y-%m-%dT%H:%M:%S.000000000Z')" \
    >> "$runtime/logs/containers/demo/demo-json.log"

  wait_for_log receiver "$text_marker"
  wait_for_log receiver "$app_marker"
  wait_for_log receiver "$system_marker"
  wait_for_log receiver "$container_marker"
  echo "PASS: all sample source types were collected"
}

assert_canonical_event() {
  local marker="$1"
  local expected_dataset="$2"
  local event
  event="$(compose logs --no-color receiver 2>/dev/null |
    grep -F "$marker" | tail -n 1)"

  grep -Fq '"event.original":' <<<"$event" ||
    fail "$expected_dataset did not preserve event.original"
  grep -Fq '"event.schema_version":"1.0.0"' <<<"$event" ||
    fail "$expected_dataset did not receive the canonical schema version"
  grep -Fq "\"event.dataset\":\"${expected_dataset}\"" <<<"$event" ||
    fail "$expected_dataset dataset was not normalized"
  grep -Fq '"event.parser_version":' <<<"$event" ||
    fail "$expected_dataset parser version was not recorded"
  grep -Fq '"@timestamp":' <<<"$event" ||
    fail "$expected_dataset UTC timestamp was not recorded"
  grep -Fq '"event.observed":' <<<"$event" ||
    fail "$expected_dataset observation time was not recorded"
  grep -Fq '"event.timestamp_inferred":' <<<"$event" ||
    fail "$expected_dataset timestamp inference status was not recorded"
  grep -Fq '"event.clock_skew_seconds":' <<<"$event" ||
    fail "$expected_dataset clock skew was not recorded"
  grep -Fq '"collector.name":"integration-collector"' <<<"$event" ||
    fail "$expected_dataset collector metadata was not recorded"
  grep -Fq '"site.name":"integration-site"' <<<"$event" ||
    fail "$expected_dataset site metadata was not recorded"
}

test_canonical_normalization() {
  local text_marker="phase3-text-$RANDOM-$RANDOM"
  local app_marker="phase3-app-$RANDOM-$RANDOM"
  local system_marker="phase3-system-$RANDOM-$RANDOM"
  local container_marker="phase3-container-$RANDOM-$RANDOM"

  printf '%s WARN %s\n' "$(date --iso-8601=seconds)" "$text_marker" \
    >> "$runtime/logs/text/service.log"
  printf '{"timestamp":"%s","level":"ERROR","service":"phase3-test","environment":"integration","message":"%s"}\n' \
    "$(date --iso-8601=seconds)" "$app_marker" \
    >> "$runtime/logs/app/application.json.log"
  printf '%s phase3-host phase3[1]: %s\n' \
    "$(date '+%b %d %H:%M:%S')" "$system_marker" \
    >> "$runtime/logs/system/syslog"
  printf '{"log":"%s\\n","stream":"stderr","time":"%s"}\n' \
    "$container_marker" "$(date --utc '+%Y-%m-%dT%H:%M:%S.000000000Z')" \
    >> "$runtime/logs/containers/demo/demo-json.log"

  wait_for_log receiver "$text_marker"
  wait_for_log receiver "$app_marker"
  wait_for_log receiver "$system_marker"
  wait_for_log receiver "$container_marker"

  assert_canonical_event "$text_marker" "file.text"
  assert_canonical_event "$app_marker" "application.json"
  assert_canonical_event "$system_marker" "host.system"
  assert_canonical_event "$container_marker" "container.docker"

  local text_event app_event
  text_event="$(compose logs --no-color receiver 2>/dev/null |
    grep -F "$text_marker" | tail -n 1)"
  app_event="$(compose logs --no-color receiver 2>/dev/null |
    grep -F "$app_marker" | tail -n 1)"
  grep -Fq '"event.timestamp_inferred":false' <<<"$text_event" ||
    fail "ISO 8601 text timestamp was not recognized"
  grep -Fq '"log.level":"warn"' <<<"$text_event" ||
    fail "plain-text log level was not normalized"
  grep -Fq '"log.severity.number":13' <<<"$text_event" ||
    fail "plain-text severity was not mapped to OpenTelemetry"
  grep -Fq '"log.level":"error"' <<<"$app_event" ||
    fail "application log level was not normalized"
  grep -Fq '"log.severity.number":17' <<<"$app_event" ||
    fail "application severity was not mapped to OpenTelemetry"
  grep -Fq '"service.name":"phase3-test"' <<<"$app_event" ||
    fail "application service metadata was not normalized"
  grep -Fq '"deployment.environment.name":"integration"' <<<"$app_event" ||
    fail "application environment metadata was not normalized"

  echo "PASS: canonical metadata, timestamps, severity, and raw events were normalized"
}

assert_deadletter_event() {
  local marker="$1"
  local expected_source="$2"
  local event
  event="$(compose logs --no-color receiver 2>/dev/null |
    grep -F "$marker" | tail -n 1)"

  grep -Fq '"event.kind":"pipeline_error"' <<<"$event" ||
    fail "$expected_source parse failure was not marked as a pipeline error"
  grep -Fq '"event.dataset":"pipeline.deadletter"' <<<"$event" ||
    fail "$expected_source parse failure was not assigned to dead-letter"
  grep -Fq '"error.type":"parsing_error"' <<<"$event" ||
    fail "$expected_source parse failure type was not recorded"
  grep -Fq '"error.stage":"source_parser"' <<<"$event" ||
    fail "$expected_source parse failure stage was not recorded"
  grep -Fq "\"error.source_dataset\":\"${expected_source}\"" <<<"$event" ||
    fail "$expected_source source dataset was not retained"
  grep -Fq '"_dead_letter":true' <<<"$event" ||
    fail "$expected_source dead-letter marker was not recorded"
  grep -Fq '"event.original":' <<<"$event" ||
    fail "$expected_source malformed source record was not preserved"
}

test_structured_deadletter_routing() {
  local app_marker="bad-app-$RANDOM-$RANDOM"
  local container_marker="bad-container-$RANDOM-$RANDOM"
  local zeek_marker="bad-zeek-$RANDOM-$RANDOM"
  local suricata_marker="bad-suricata-$RANDOM-$RANDOM"

  printf '{"message":"%s"\n' "$app_marker" \
    >> "$runtime/logs/app/application.json.log"
  printf '{"log":"%s\\n","stream":\n' "$container_marker" \
    >> "$runtime/logs/containers/demo/demo-json.log"
  printf '{"uid":"%s"\n' "$zeek_marker" \
    >> "$runtime/logs/zeek/conn.log"
  printf '{"flow_id":"%s"\n' "$suricata_marker" \
    >> "$runtime/logs/suricata/eve.json"

  wait_for_log receiver "$app_marker"
  wait_for_log receiver "$container_marker"
  wait_for_log receiver "$zeek_marker"
  wait_for_log receiver "$suricata_marker"

  assert_deadletter_event "$app_marker" "application.json"
  assert_deadletter_event "$container_marker" "container.docker"
  assert_deadletter_event "$zeek_marker" "zeek.conn"
  assert_deadletter_event "$suricata_marker" "suricata.unknown"

  echo "PASS: malformed structured records were routed to dead-letter"
}

test_mapping_explosion_guard() {
  local marker="mapping-guard-$RANDOM-$RANDOM"

  python3 - "$runtime/logs/app/application.json.log" "$marker" <<'EOF'
import json
import sys

event = {
    "timestamp": "2026-06-20T08:00:00Z",
    "level": "INFO",
    "service": "mapping-guard-test",
    "message": sys.argv[2],
}
for number in range(140):
    event[f"attacker_controlled_{number:03d}"] = number

with open(sys.argv[1], "a", encoding="utf-8") as handle:
    handle.write(json.dumps(event, separators=(",", ":")) + "\n")
EOF

  wait_for_log receiver "$marker"

  local event
  event="$(compose logs --no-color receiver 2>/dev/null |
    grep -F "$marker" | tail -n 1)"
  grep -Fq '"event.kind":"pipeline_error"' <<<"$event" ||
    fail "oversized dynamic event was not marked as a pipeline error"
  grep -Fq '"event.dataset":"pipeline.deadletter"' <<<"$event" ||
    fail "oversized dynamic event was not routed to dead-letter"
  grep -Fq '"error.type":"mapping_guard_error"' <<<"$event" ||
    fail "mapping guard error type was not recorded"
  grep -Fq '"error.stage":"schema_guard"' <<<"$event" ||
    fail "mapping guard stage was not recorded"
  grep -Fq '"error.message":"maximum field count exceeded"' <<<"$event" ||
    fail "mapping guard limit reason was not recorded"
  grep -Fq '"error.source_dataset":"application.json"' <<<"$event" ||
    fail "mapping guard source dataset was not retained"

  echo "PASS: mapping explosion guard rejected an excessive dynamic event"
}

test_rotation() {
  local old_marker="phase1-before-rotation-$RANDOM-$RANDOM"
  local new_marker="phase1-after-rotation-$RANDOM-$RANDOM"
  local log="$runtime/logs/text/service.log"

  printf '%s INFO %s\n' "$(date --iso-8601=seconds)" "$old_marker" >> "$log"
  wait_for_log receiver "$old_marker"

  mv "$log" "$log.1"
  printf '%s INFO %s\n' "$(date --iso-8601=seconds)" "$new_marker" > "$log"
  wait_for_log receiver "$new_marker"
  echo "PASS: collection continued after file rotation"
}

test_multiline() {
  local header_marker="phase1-multiline-header-$RANDOM-$RANDOM"
  local detail_marker="phase1-multiline-detail-$RANDOM-$RANDOM"
  local log="$runtime/logs/text/service.log"

  {
    printf '%s ERROR %s\n' "$(date '+%Y-%m-%d %H:%M:%S')" "$header_marker"
    printf 'java.lang.IllegalStateException: %s\n' "$detail_marker"
    printf '    at com.example.IntegrationTest.run(IntegrationTest.java:42)\n'
  } >> "$log"

  wait_for_log receiver "$detail_marker"

  if ! compose logs --no-color receiver 2>/dev/null |
      grep -F "$header_marker" |
      grep -Fq "$detail_marker"; then
    fail "multiline stack trace was not assembled into one event"
  fi

  echo "PASS: multiline stack trace was assembled into one event"
}

test_restart_offsets() {
  local marker="phase1-restart-offset-$RANDOM-$RANDOM"

  printf '%s INFO %s\n' "$(date --iso-8601=seconds)" "$marker" \
    >> "$runtime/logs/text/service.log"
  wait_for_log receiver "$marker"

  local before
  before="$(marker_count receiver "$marker")"
  [[ "$before" -eq 1 ]] || fail "expected marker once before restart, observed $before"

  compose restart collector >/dev/null
  sleep 5

  local after
  after="$(marker_count receiver "$marker")"
  [[ "$after" -eq 1 ]] || fail "offset replay detected after restart: marker count is $after"
  echo "PASS: persisted offsets prevented replay after collector restart"
}

test_buffer_recovery() {
  local marker="phase1-buffer-recovery-$RANDOM-$RANDOM"

  compose stop receiver >/dev/null
  printf '%s INFO %s\n' "$(date --iso-8601=seconds)" "$marker" \
    >> "$runtime/logs/text/service.log"

  sleep 5
  compose start receiver >/dev/null
  wait_for_log receiver "$marker" 60
  echo "PASS: filesystem buffering recovered after receiver interruption"
}

send_udp() {
  local host="$1" port="$2" message="$3"
  python3 - "$host" "$port" "$message" <<'EOF'
import sys, socket
s = socket.socket(socket.AF_INET, socket.SOCK_DGRAM)
s.sendto(sys.argv[3].encode(), (sys.argv[1], int(sys.argv[2])))
s.close()
EOF
}

send_tcp() {
  local host="$1" port="$2" message="$3"
  printf '%s\n' "$message" | timeout 5 bash -c "cat >/dev/tcp/$1/$2" 2>/dev/null
}

test_syslog_udp() {
  local marker="phase2-syslog-udp-$RANDOM-$RANDOM"
  local ts
  ts="$(date '+%b %e %H:%M:%S')"
  send_udp 127.0.0.1 15514 "<134>${ts} testhost sshd[1234]: ${marker}"
  wait_for_log receiver "$marker"

  local event
  event="$(compose logs --no-color receiver 2>/dev/null |
    grep -F "$marker" | tail -n 1)"
  grep -Fq '"event.dataset":"syslog.rfc3164"' <<<"$event" ||
    fail "generic syslog dataset was not normalized"
  grep -Fq '"event.parser_version":"syslog-rfc3164-1"' <<<"$event" ||
    fail "generic syslog parser version was not recorded"
  grep -Fq '"log.level":"info"' <<<"$event" ||
    fail "syslog severity text was not normalized"
  grep -Fq '"log.severity.number":9' <<<"$event" ||
    fail "syslog severity was not mapped to OpenTelemetry"
  grep -Fq '"host.name":"testhost"' <<<"$event" ||
    fail "syslog host metadata was not normalized"
  echo "PASS: UDP syslog was collected"
}

test_syslog_tcp() {
  local marker="phase2-syslog-tcp-$RANDOM-$RANDOM"
  local ts
  ts="$(date '+%b %e %H:%M:%S')"
  send_tcp 127.0.0.1 15514 "<134>${ts} testhost sshd[1234]: ${marker}" || {
    echo "SKIP: TCP syslog test skipped (/dev/tcp not available)" >&2
    return 0
  }
  wait_for_log receiver "$marker"
  echo "PASS: TCP syslog was collected"
}

test_syslog_deadletter() {
  local marker="phase2-syslog-dl-$RANDOM-$RANDOM"
  local ts
  ts="$(date '+%b %e %H:%M:%S')"
  # Two spaces after the timestamp produce an empty host field, triggering dead-letter.
  send_udp 127.0.0.1 15514 "<134>${ts}  sshd[1234]: ${marker}"
  wait_for_log receiver "$marker"
  local event
  event="$(compose logs --no-color receiver 2>/dev/null |
    grep -F "$marker" | tail -n 1)"
  grep -Fq '"_dead_letter":true' <<<"$event" ||
    fail "malformed syslog record was not routed to dead-letter stream"
  grep -Fq '"event.kind":"pipeline_error"' <<<"$event" ||
    fail "malformed syslog record was not marked as a pipeline error"
  grep -Fq '"error.stage":"syslog_input"' <<<"$event" ||
    fail "malformed syslog error stage was not recorded"
  echo "PASS: malformed syslog record was routed to dead-letter stream"
}

test_syslog_src_ip() {
  local marker="phase2-syslog-ip-$RANDOM-$RANDOM"
  local ts
  ts="$(date '+%b %e %H:%M:%S')"
  send_udp 127.0.0.1 15514 "<134>${ts} testhost sshd[1234]: ${marker}"
  wait_for_log receiver "$marker"
  if ! compose logs --no-color receiver 2>/dev/null |
      grep -F "$marker" | grep -Fq '"net.src_ip"'; then
    fail "sender IP was not preserved in syslog record"
  fi
  echo "PASS: sender IP was preserved in syslog record"
}

test_asus_firewall_parsing() {
  local source_port=$((20000 + RANDOM % 30000))
  local message
  message="<4>$(date '+%b %e %H:%M:%S') RT-AC68U-TEST kernel: DROP IN=eth0 OUT= MAC=00:11:22:33:44:55 SRC=192.0.2.45 DST=198.51.100.7 LEN=216 PROTO=UDP SPT=${source_port} DPT=6667"

  send_udp 127.0.0.1 15514 "$message"
  wait_for_log receiver "\"source.port\":${source_port}"

  local event
  event="$(compose logs --no-color receiver 2>/dev/null |
    grep -F "\"source.port\":${source_port}" | tail -n 1)"

  grep -Fq '"event.action":"drop"' <<<"$event" ||
    fail "ASUS firewall action was not normalized"
  grep -Fq '"event.outcome":"failure"' <<<"$event" ||
    fail "ASUS firewall outcome was not normalized"
  grep -Fq '"source.ip":"192.0.2.45"' <<<"$event" ||
    fail "ASUS firewall source IP was not parsed"
  grep -Fq '"destination.ip":"198.51.100.7"' <<<"$event" ||
    fail "ASUS firewall destination IP was not parsed"
  grep -Fq '"destination.port":6667' <<<"$event" ||
    fail "ASUS firewall destination port was not parsed"
  grep -Fq '"network.transport":"udp"' <<<"$event" ||
    fail "ASUS firewall transport was not normalized"
  grep -Fq '"observer.ingress.interface.name":"eth0"' <<<"$event" ||
    fail "ASUS firewall ingress interface was not parsed"
  grep -Fq '"observer.vendor":"ASUS"' <<<"$event" ||
    fail "ASUS observer metadata was not added"
  grep -Fq '"event.original":' <<<"$event" ||
    fail "ASUS original event was not preserved"

  echo "PASS: ASUS firewall event was normalized"
}

test_zeek_collection() {
  local conn_marker="CZeekIntegration001"
  local dns_marker="zeek-integration.example"
  local http_marker="example.test"
  local tls_marker="secure.example.test"
  local dhcp_marker="demo-client"
  local notice_marker="Sanitized example scan notice"

  wait_for_log receiver "$conn_marker"
  wait_for_log receiver "$dns_marker"
  wait_for_log receiver "$http_marker"
  wait_for_log receiver "$tls_marker"
  wait_for_log receiver "$dhcp_marker"
  wait_for_log receiver "$notice_marker"

  local conn_event dns_event all_logs
  all_logs="$(compose logs --no-color receiver 2>/dev/null)"
  conn_event="$(compose logs --no-color receiver 2>/dev/null |
    grep -F "$conn_marker" | tail -n 1)"
  dns_event="$(compose logs --no-color receiver 2>/dev/null |
    grep -F "$dns_marker" | tail -n 1)"

  grep -Fq '"event.dataset":"zeek.conn"' <<<"$conn_event" ||
    fail "Zeek conn dataset was not identified"
  grep -Fq '"source.ip":"192.0.2.10"' <<<"$conn_event" ||
    fail "Zeek source IP was not normalized"
  grep -Fq '"destination.port":443' <<<"$conn_event" ||
    fail "Zeek destination port was not normalized"
  grep -Fq '"network.transport":"tcp"' <<<"$conn_event" ||
    fail "Zeek transport was not normalized"
  grep -Fq '"event.dataset":"zeek.dns"' <<<"$dns_event" ||
    fail "Zeek DNS dataset was not identified"
  grep -Fq '"dns.question.name":"zeek-integration.example"' <<<"$dns_event" ||
    fail "Zeek DNS question was not normalized"
  grep -F "$http_marker" <<<"$all_logs" |
    grep -Fq '"event.dataset":"zeek.http"' ||
    fail "Zeek HTTP dataset was not collected"
  grep -F "$tls_marker" <<<"$all_logs" |
    grep -Fq '"event.dataset":"zeek.ssl"' ||
    fail "Zeek TLS dataset was not collected"
  grep -F "$dhcp_marker" <<<"$all_logs" |
    grep -Fq '"event.dataset":"zeek.dhcp"' ||
    fail "Zeek DHCP dataset was not collected"
  grep -F "$notice_marker" <<<"$all_logs" |
    grep -Fq '"event.dataset":"zeek.notice"' ||
    fail "Zeek notice dataset was not collected"

  echo "PASS: Zeek conn, DNS, HTTP, TLS, DHCP, and notice logs were collected"
}

test_suricata_collection() {
  local alert_marker="Sanitized test IDS signature"
  local flow_marker="987654321001"
  local dns_marker="suricata-integration.example"
  local http_marker="suricata-http.example"
  local tls_marker="suricata-tls.example"

  wait_for_log receiver "$alert_marker"
  wait_for_log receiver "$flow_marker"
  wait_for_log receiver "$dns_marker"
  wait_for_log receiver "$http_marker"
  wait_for_log receiver "$tls_marker"

  local logs alert_event flow_event
  logs="$(compose logs --no-color receiver 2>/dev/null)"
  alert_event="$(grep -F "$alert_marker" <<<"$logs" | tail -n 1)"
  flow_event="$(grep -F "$flow_marker" <<<"$logs" | tail -n 1)"

  grep -Fq '"event.dataset":"suricata.alert"' <<<"$alert_event" ||
    fail "Suricata alert dataset was not identified"
  grep -Fq '"rule.id":9000001' <<<"$alert_event" ||
    fail "Suricata signature ID was not normalized"
  grep -Fq '"source.ip":"192.0.2.60"' <<<"$alert_event" ||
    fail "Suricata alert source IP was not normalized"
  grep -Fq '"destination.port":22' <<<"$alert_event" ||
    fail "Suricata alert destination port was not normalized"
  grep -Fq '"event.dataset":"suricata.flow"' <<<"$flow_event" ||
    fail "Suricata flow dataset was not identified"
  grep -Fq '"source.bytes":640' <<<"$flow_event" ||
    fail "Suricata flow source bytes were not normalized"
  grep -F "$dns_marker" <<<"$logs" |
    grep -Fq '"event.dataset":"suricata.dns"' ||
    fail "Suricata DNS event was not collected"
  grep -F "$http_marker" <<<"$logs" |
    grep -Fq '"event.dataset":"suricata.http"' ||
    fail "Suricata HTTP event was not collected"
  grep -F "$tls_marker" <<<"$logs" |
    grep -Fq '"event.dataset":"suricata.tls"' ||
    fail "Suricata TLS event was not collected"

  echo "PASS: Suricata alert, flow, DNS, HTTP, and TLS events were collected"
}

correlation_key_from_event() {
  sed -n 's/.*"event.correlation_key":"\([^"]*\)".*/\1/p' <<<"$1"
}

test_cross_source_correlation() {
  local source_port=$((20000 + RANDOM % 30000))
  local marker="cross-source-$RANDOM-$RANDOM"
  local epoch
  epoch="$(date +%s)"

  printf '{"ts":%s,"uid":"%s-zeek","id.orig_h":"192.0.2.90","id.orig_p":%s,"id.resp_h":"198.51.100.90","id.resp_p":443,"proto":"tcp","service":"ssl"}\n' \
    "$epoch" "$marker" "$source_port" >> "$runtime/logs/zeek/conn.log"
  printf '{"timestamp":"%s","flow_id":"%s-suricata","event_type":"flow","src_ip":"192.0.2.90","src_port":%s,"dest_ip":"198.51.100.90","dest_port":443,"proto":"TCP","app_proto":"tls"}\n' \
    "$(date --utc '+%Y-%m-%dT%H:%M:%S.000000+0000')" "$marker" "$source_port" \
    >> "$runtime/logs/suricata/eve.json"
  send_udp 127.0.0.1 15514 \
    "<4>$(date '+%b %e %H:%M:%S') RT-AC68U-TEST kernel: DROP IN=eth0 OUT= SRC=192.0.2.90 DST=198.51.100.90 PROTO=TCP SPT=${source_port} DPT=443 MARKER=${marker}-asus"

  wait_for_log receiver "$marker-zeek"
  wait_for_log receiver "$marker-suricata"
  wait_for_log receiver "$marker-asus"

  local logs zeek_event suricata_event asus_event
  local zeek_key suricata_key asus_key
  logs="$(compose logs --no-color receiver 2>/dev/null)"
  zeek_event="$(grep -F "$marker-zeek" <<<"$logs" | tail -n 1)"
  suricata_event="$(grep -F "$marker-suricata" <<<"$logs" | tail -n 1)"
  asus_event="$(grep -F "$marker-asus" <<<"$logs" | tail -n 1)"
  zeek_key="$(correlation_key_from_event "$zeek_event")"
  suricata_key="$(correlation_key_from_event "$suricata_event")"
  asus_key="$(correlation_key_from_event "$asus_event")"

  [[ -n "$zeek_key" ]] || fail "Zeek correlation key was not generated"
  [[ "$zeek_key" == "$suricata_key" ]] ||
    fail "Zeek and Suricata observations did not share a correlation key"
  [[ "$zeek_key" == "$asus_key" ]] ||
    fail "ASUS and sensor observations did not share a correlation key"

  grep -Fq '"event.deduplication.strategy":"correlate-preserve"' <<<"$zeek_event" ||
    fail "cross-source duplicate strategy was not recorded"
  grep -Fq '"event.schema_version":"1.0.0"' <<<"$asus_event" ||
    fail "shared network schema version was not recorded"
  [[ "$zeek_event" != "$suricata_event" && "$zeek_event" != "$asus_event" ]] ||
    fail "source observations were collapsed instead of preserved"

  echo "PASS: related ASUS, Zeek, and Suricata observations were correlated without data loss"
}

test_golden_parser_outputs() {
  local ts
  ts="$(date '+%b %e %H:%M:%S')"

  send_udp 127.0.0.1 15514 \
    "<134>${ts} golden-router golden[42]: golden-rfc3164-event"
  send_udp 127.0.0.1 15514 \
    "<4>${ts} RT-AC68U-GOLDEN kernel: DROP IN=eth0 OUT= SRC=192.0.2.45 DST=198.51.100.7 PROTO=UDP SPT=45001 DPT=6667 GOLDEN=asus-firewall"

  wait_for_log receiver "golden-rfc3164-event"
  wait_for_log receiver "GOLDEN=asus-firewall"

  local output="$runtime/golden-output.log"
  compose logs --no-color receiver > "$output"
  python3 "$repo_root/tests/golden/verify.py" --logs "$output"
}

main() {
  command -v docker >/dev/null 2>&1 || {
    echo "Docker is required. Enable Docker Desktop WSL integration for Ubuntu." >&2
    exit 2
  }
  docker compose version >/dev/null
  [[ -f "$repo_root/.env" ]] || {
    echo "Run 'make init' before integration tests." >&2
    exit 2
  }
  command -v python3 >/dev/null 2>&1 || {
    echo "python3 is required for syslog integration tests." >&2
    exit 2
  }

  trap cleanup EXIT
  cleanup
  prepare_runtime
  compose config --quiet
  compose up -d
  sleep 5

  test_initial_collection
  test_canonical_normalization
  test_structured_deadletter_routing
  test_mapping_explosion_guard
  test_multiline
  test_rotation
  test_restart_offsets

  test_syslog_udp
  test_syslog_tcp
  test_syslog_deadletter
  test_syslog_src_ip
  test_asus_firewall_parsing
  test_zeek_collection
  test_suricata_collection
  test_cross_source_correlation
  test_golden_parser_outputs
  test_buffer_recovery

  echo "PASS: all integration tests completed"
}

main "$@"
