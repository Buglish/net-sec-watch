#!/usr/bin/env bash
# Generate a local CA and service certificates for encrypted development traffic.
set -euo pipefail

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
tls_dir="${TLS_CERT_DIR:-$repo_root/config/tls}"

command -v openssl >/dev/null 2>&1 || {
  echo "openssl is required but not found." >&2
  exit 1
}

mkdir -p "$tls_dir"

if [[ ! -s "$tls_dir/ca.crt" || ! -s "$tls_dir/ca.key" ]]; then
  echo "Generating Net Sec Watch development CA..."
  openssl req -x509 -newkey rsa:4096 -sha256 -days 3650 -nodes \
    -keyout "$tls_dir/ca.key" \
    -out "$tls_dir/ca.crt" \
    -subj "/CN=Net Sec Watch Development CA" \
    -addext "basicConstraints=critical,CA:TRUE" \
    -addext "keyUsage=critical,keyCertSign,cRLSign" \
    2>/dev/null
else
  echo "Keeping existing Net Sec Watch development CA."
fi

issue_certificate() {
  local name="$1"
  local common_name="$2"
  local subject_alt_name="$3"
  local key="$tls_dir/${name}.key"
  local certificate="$tls_dir/${name}.crt"
  local request="$tls_dir/${name}.csr"
  local extensions="$tls_dir/${name}.ext"

  if [[ -s "$key" && -s "$certificate" ]] &&
    openssl verify -CAfile "$tls_dir/ca.crt" "$certificate" >/dev/null 2>&1 &&
    openssl x509 -checkend 2592000 -noout -in "$certificate" >/dev/null; then
    echo "Keeping valid ${name} certificate."
    return
  fi

  echo "Generating ${name} certificate..."
  openssl req -newkey rsa:3072 -sha256 -nodes \
    -keyout "$key" \
    -out "$request" \
    -subj "/CN=${common_name}" \
    2>/dev/null
  {
    echo "basicConstraints=critical,CA:FALSE"
    echo "keyUsage=critical,digitalSignature,keyEncipherment"
    echo "extendedKeyUsage=serverAuth"
    echo "subjectAltName=${subject_alt_name}"
  } >"$extensions"
  openssl x509 -req -sha256 -days 825 \
    -in "$request" \
    -CA "$tls_dir/ca.crt" \
    -CAkey "$tls_dir/ca.key" \
    -CAcreateserial \
    -out "$certificate" \
    -extfile "$extensions" \
    2>/dev/null
  rm -f "$request" "$extensions" "$tls_dir/ca.srl"
}

# Keep server.crt/server.key for compatibility with the existing TLS syslog
# example and device documentation.
issue_certificate \
  server \
  net-sec-watch-syslog \
  "DNS:net-sec-watch-syslog,DNS:localhost,IP:127.0.0.1"
issue_certificate \
  dashboards \
  opensearch-dashboards \
  "DNS:opensearch-dashboards,DNS:localhost,IP:127.0.0.1"

chmod 600 "$tls_dir"/*.key
chmod 644 "$tls_dir"/*.crt

for certificate in server dashboards; do
  openssl verify \
    -CAfile "$tls_dir/ca.crt" \
    "$tls_dir/${certificate}.crt" >/dev/null
done

echo "TLS material is ready in $tls_dir/"
echo "Install ca.crt in browsers and TLS-capable syslog senders."
