#!/usr/bin/env bash
set -euo pipefail

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
test_dir="$(mktemp -d)"

cleanup() {
  rm -rf "$test_dir"
}
trap cleanup EXIT

TLS_CERT_DIR="$test_dir" "$repo_root/scripts/gen-tls-certs.sh"

for file in ca.crt ca.key server.crt server.key dashboards.crt dashboards.key; do
  [[ -s "$test_dir/$file" ]] || {
    echo "Missing generated TLS file: $file" >&2
    exit 1
  }
done

openssl verify -CAfile "$test_dir/ca.crt" \
  "$test_dir/server.crt" "$test_dir/dashboards.crt" >/dev/null

openssl x509 -in "$test_dir/dashboards.crt" -noout -ext subjectAltName |
  grep -Fq 'DNS:localhost' || {
  echo "Dashboards certificate is missing the localhost SAN." >&2
  exit 1
}
openssl x509 -in "$test_dir/dashboards.crt" -noout -ext subjectAltName |
  grep -Fq 'IP Address:127.0.0.1' || {
  echo "Dashboards certificate is missing the loopback IP SAN." >&2
  exit 1
}
openssl x509 -in "$test_dir/server.crt" -noout -ext extendedKeyUsage |
  grep -Fq 'TLS Web Server Authentication' || {
  echo "Syslog certificate is missing server authentication usage." >&2
  exit 1
}

echo "PASS: local CA issues valid Dashboards and syslog server certificates"
