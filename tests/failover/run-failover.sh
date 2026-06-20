#!/usr/bin/env bash
set -euo pipefail

script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
repo_root="$(cd "$script_dir/../.." && pwd)"
project="net-sec-watch-failover"

compose() {
  docker compose \
    --project-name "$project" \
    --env-file "$repo_root/.env" \
    --file "$script_dir/compose.failover.yaml" \
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
  local deadline=$((SECONDS + 30))

  while (( SECONDS < deadline )); do
    if compose logs --no-color "$service" 2>/dev/null |
        grep -Fq "$marker"; then
      return 0
    fi
    sleep 1
  done

  fail "marker '$marker' was not observed in $service logs"
}

send_udp_dual_target() {
  local message="$1"
  python3 - "$message" <<'PY'
import socket
import sys

message = sys.argv[1].encode()
with socket.socket(socket.AF_INET, socket.SOCK_DGRAM) as sock:
    for port in (15515, 15516):
        sock.sendto(message, ("127.0.0.1", port))
PY
}

send_tcp_with_failover() {
  local message="$1"
  python3 - "$message" <<'PY'
import socket
import sys

message = (sys.argv[1] + "\n").encode()
for port in (15515, 15516):
    try:
        with socket.create_connection(("127.0.0.1", port), timeout=2) as sock:
            sock.sendall(message)
        print(port)
        raise SystemExit(0)
    except OSError:
        continue
raise SystemExit("no syslog receiver was reachable")
PY
}

main() {
  command -v docker >/dev/null 2>&1 ||
    fail "Docker is required"
  command -v python3 >/dev/null 2>&1 ||
    fail "python3 is required"
  [[ -f "$repo_root/.env" ]] ||
    fail "run 'make init' before failover tests"

  trap cleanup EXIT
  cleanup
  compose config --quiet
  compose up -d
  sleep 4

  local timestamp udp_marker udp_message
  timestamp="$(date '+%b %e %H:%M:%S')"
  udp_marker="phase2-dual-udp-$RANDOM-$RANDOM"
  udp_message="<134>${timestamp} test-router app: ${udp_marker}"
  send_udp_dual_target "$udp_message"
  wait_for_log syslog-primary "$udp_marker"
  wait_for_log syslog-secondary "$udp_marker"
  echo "PASS: dual-target UDP reached both independent receivers"

  local primary_marker primary_message selected
  primary_marker="phase2-primary-tcp-$RANDOM-$RANDOM"
  primary_message="<134>${timestamp} test-firewall app: ${primary_marker}"
  selected="$(send_tcp_with_failover "$primary_message")"
  [[ "$selected" == "15515" ]] ||
    fail "expected healthy primary on port 15515, selected $selected"
  wait_for_log syslog-primary "$primary_marker"
  echo "PASS: TCP sender selected the healthy primary receiver"

  compose stop syslog-primary >/dev/null

  local failover_marker failover_message
  failover_marker="phase2-failover-tcp-$RANDOM-$RANDOM"
  failover_message="<134>${timestamp} test-firewall app: ${failover_marker}"
  selected="$(send_tcp_with_failover "$failover_message")"
  [[ "$selected" == "15516" ]] ||
    fail "expected failover to secondary port 15516, selected $selected"
  wait_for_log syslog-secondary "$failover_marker"
  echo "PASS: TCP sender failed over to the secondary receiver"

  compose start syslog-primary >/dev/null
  sleep 3
  compose ps --status running | grep -q 'syslog-primary' ||
    fail "primary receiver did not recover"
  compose ps --status running | grep -q 'syslog-secondary' ||
    fail "secondary receiver is not running"
  echo "PASS: both receivers are healthy after primary recovery"
}

main "$@"
