#!/usr/bin/env bash
set -euo pipefail

target_host="${SYSLOG_LOAD_TEST_HOST:-127.0.0.1}"
target_port="${SYSLOG_LOAD_TEST_PORT:-514}"
expected_peak_eps="${EXPECTED_PEAK_EPS:-250}"
multiplier="${LOAD_TEST_MULTIPLIER:-1.5}"
duration_seconds="${LOAD_TEST_DURATION_SECONDS:-900}"

test_eps="$(
  awk -v peak="$expected_peak_eps" -v multiplier="$multiplier" \
    'BEGIN { printf "%d", peak * multiplier }'
)"

command -v nc >/dev/null 2>&1 || {
  echo "nc is required for the syslog load test." >&2
  exit 2
}

echo "Sending UDP syslog load test to ${target_host}:${target_port}"
echo "Expected peak EPS: ${expected_peak_eps}"
echo "Multiplier: ${multiplier}"
echo "Test EPS: ${test_eps}"
echo "Duration seconds: ${duration_seconds}"

end_time=$((SECONDS + duration_seconds))
sequence=0

while [[ "$SECONDS" -lt "$end_time" ]]; do
  batch_start="$SECONDS"
  for _ in $(seq 1 "$test_eps"); do
    sequence=$((sequence + 1))
    printf '<134>%s net-sec-watch-loadtest app: operations_load_test sequence=%s\n' \
      "$(date '+%b %e %H:%M:%S')" "$sequence" |
      nc -u -w1 "$target_host" "$target_port"
  done
  while [[ "$SECONDS" -eq "$batch_start" ]]; do
    sleep 0.05
  done
done

echo "Load test complete. Sent ${sequence} events."
