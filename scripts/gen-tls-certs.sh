#!/usr/bin/env bash
# Generate a self-signed CA and server certificate for TLS syslog reception.
# Output goes to config/tls/ (git-ignored). Run once; rotate annually.
# Requires: openssl
set -euo pipefail

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
tls_dir="${TLS_CERT_DIR:-$repo_root/config/tls}"

command -v openssl >/dev/null 2>&1 || {
  echo "openssl is required but not found." >&2
  exit 1
}

mkdir -p "$tls_dir"

echo "Generating CA key and self-signed certificate..."
openssl req -x509 -newkey rsa:4096 -days 3650 -nodes \
  -keyout "$tls_dir/ca.key" \
  -out    "$tls_dir/ca.crt" \
  -subj   "/CN=net-sec-watch-ca" \
  2>/dev/null

echo "Generating server key and certificate signing request..."
openssl req -newkey rsa:4096 -nodes \
  -keyout "$tls_dir/server.key" \
  -out    "$tls_dir/server.csr" \
  -subj   "/CN=net-sec-watch-syslog" \
  2>/dev/null

echo "Signing server certificate with CA..."
openssl x509 -req -days 3650 \
  -in           "$tls_dir/server.csr" \
  -CA           "$tls_dir/ca.crt" \
  -CAkey        "$tls_dir/ca.key" \
  -CAcreateserial \
  -out          "$tls_dir/server.crt" \
  2>/dev/null

chmod 600 "$tls_dir"/*.key
rm -f "$tls_dir/server.csr" "$tls_dir/ca.srl"

echo "Done. Certificates written to $tls_dir/"
echo "  CA cert (install on sender devices): $tls_dir/ca.crt"
echo "  Server cert: $tls_dir/server.crt"
echo "  Server key:  $tls_dir/server.key"
echo
echo "Set FLUENT_BIT_CONFIG_PATH=./config/fluent-bit.local.conf in .env,"
echo "uncomment the TLS syslog input block, then: make down && make up"
