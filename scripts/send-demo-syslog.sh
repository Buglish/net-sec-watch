#!/usr/bin/env bash
set -euo pipefail

host="${SYSLOG_TEST_HOST:-127.0.0.1}"
port="${SYSLOG_TEST_PORT:-514}"
marker="${SYSLOG_TEST_MARKER:-NetSecWatchDemo001}"
timestamp="$(date '+%b %d %H:%M:%S')"

printf '<134>%s demo-host net-sec-watch-demo: %s dashboard smoke event\n' \
  "$timestamp" "$marker" >"/dev/udp/${host}/${port}"

echo "Sent demo syslog marker '${marker}' to ${host}:${port}/UDP."
