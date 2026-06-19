#!/usr/bin/env bash
set -euo pipefail

script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
repo_root="$(cd "$script_dir/../.." && pwd)"
runtime="$repo_root/tests/runtime"
compose_file="$script_dir/compose.integration.yaml"
project="net-sec-watch-phase1"

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
    "$runtime/logs/containers/demo"

  cp "$repo_root/examples/logs/text/service.log" "$runtime/logs/text/service.log"
  cp "$repo_root/examples/logs/app/application.json.log" "$runtime/logs/app/application.json.log"
  cp "$repo_root/examples/logs/system/syslog" "$runtime/logs/system/syslog"
  cp "$repo_root/examples/logs/system/auth.log" "$runtime/logs/system/auth.log"
  cp "$repo_root/examples/logs/containers/demo/demo-json.log" \
    "$runtime/logs/containers/demo/demo-json.log"
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

  trap cleanup EXIT
  cleanup
  prepare_runtime
  compose config --quiet
  compose up -d
  sleep 5

  test_initial_collection
  test_multiline
  test_rotation
  test_restart_offsets
  test_buffer_recovery

  echo "PASS: all Objective 1 integration tests completed"
}

main "$@"
