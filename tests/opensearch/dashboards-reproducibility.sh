#!/usr/bin/env bash
set -euo pipefail

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
project="net-sec-watch-dashboards-reproducibility"
admin_credential="Nsw-test-$(openssl rand -hex 12)-A9!"
opensearch_port=19208
dashboards_port=15603
bundle="$repo_root/config/dashboards/managed-saved-objects-v1.ndjson"
request_file="/tmp/net-sec-watch-saved-object-export-request.json"
initial_export="/tmp/net-sec-watch-saved-objects-initial.ndjson"
restored_export="/tmp/net-sec-watch-saved-objects-restored.ndjson"

compose() {
  OPENSEARCH_INITIAL_ADMIN_PASSWORD="$admin_credential" \
  OPENSEARCH_USERNAME=admin \
  OPENSEARCH_HTTP_PORT="$opensearch_port" \
  OPENSEARCH_DASHBOARDS_PORT="$dashboards_port" \
    docker compose \
      --project-name "$project" \
      --env-file "$repo_root/.env" \
      --file "$repo_root/compose.yaml" \
      --file "$repo_root/compose.opensearch-secure.yaml" \
      --profile opensearch \
      "$@"
}

cleanup() {
  compose down --volumes --remove-orphans >/dev/null 2>&1 || true
  rm -f "$request_file" "$initial_export" "$restored_export"
}

diagnostics() {
  compose ps >&2 || true
  compose logs --no-color opensearch opensearch-bootstrap \
    opensearch-dashboards opensearch-dashboards-bootstrap >&2 || true
}

export_objects() {
  local output="$1"
  curl --fail --silent --show-error \
    --cacert "$repo_root/config/tls/ca.crt" \
    --user "admin:${admin_credential}" \
    --header "Content-Type: application/json" \
    --header "osd-xsrf: true" \
    --request POST \
    --data-binary "@${request_file}" \
    "https://127.0.0.1:${dashboards_port}/api/saved_objects/_export" \
    --output "$output"
}

import_bundle() {
  curl --fail --silent --show-error \
    --cacert "$repo_root/config/tls/ca.crt" \
    --user "admin:${admin_credential}" \
    --header "osd-xsrf: true" \
    --form "file=@${bundle};type=application/ndjson" \
    "https://127.0.0.1:${dashboards_port}/api/saved_objects/_import?overwrite=true"
}

trap cleanup EXIT
cleanup
"$repo_root/scripts/gen-tls-certs.sh"

"$repo_root/scripts/build-dashboards-bundle.py" --check

python3 - "$bundle" "$request_file" <<'PY'
import json
import sys
from pathlib import Path

objects = []
for line in Path(sys.argv[1]).read_text(encoding="utf-8").splitlines():
    if line:
        item = json.loads(line)
        objects.append({"type": item["type"], "id": item["id"]})
Path(sys.argv[2]).write_text(
    json.dumps({
        "objects": objects,
        "includeReferencesDeep": False,
        "excludeExportDetails": False,
    }),
    encoding="utf-8",
)
PY

if ! compose up -d opensearch-dashboards-bootstrap; then
  diagnostics
  echo "FAIL: Dashboards bootstrap did not complete." >&2
  exit 1
fi
if ! compose wait opensearch-dashboards-bootstrap; then
  diagnostics
  echo "FAIL: Dashboards bootstrap exited unsuccessfully." >&2
  exit 1
fi

deadline=$((SECONDS + 240))
until curl --fail --silent \
  --cacert "$repo_root/config/tls/ca.crt" \
  --user "admin:${admin_credential}" \
  "https://127.0.0.1:${dashboards_port}/api/status" >/dev/null; do
  if ((SECONDS >= deadline)); then
    diagnostics
    echo "FAIL: OpenSearch Dashboards did not become reachable." >&2
    exit 1
  fi
  sleep 3
done

export_objects "$initial_export"
"$repo_root/scripts/compare-dashboards-export.py" "$initial_export"

while IFS=$'\t' read -r type object_id; do
  curl --fail --silent --show-error \
    --cacert "$repo_root/config/tls/ca.crt" \
    --user "admin:${admin_credential}" \
    --header "osd-xsrf: true" \
    --request DELETE \
    "https://127.0.0.1:${dashboards_port}/api/saved_objects/${type}/${object_id}" \
    >/dev/null
done < <(
  python3 - "$bundle" <<'PY'
import json
import sys
from pathlib import Path

for line in Path(sys.argv[1]).read_text(encoding="utf-8").splitlines():
    if line:
        item = json.loads(line)
        print(f"{item['type']}\t{item['id']}")
PY
)

while IFS=$'\t' read -r type object_id; do
  status="$(
    curl --silent \
      --cacert "$repo_root/config/tls/ca.crt" \
      --user "admin:${admin_credential}" \
      --output /dev/null \
      --write-out '%{http_code}' \
      "https://127.0.0.1:${dashboards_port}/api/saved_objects/${type}/${object_id}"
  )"
  [[ "$status" == "404" ]] || {
    echo "FAIL: ${type}/${object_id} remained after clean-up." >&2
    exit 1
  }
done < <(
  python3 - "$bundle" <<'PY'
import json
import sys
from pathlib import Path

for line in Path(sys.argv[1]).read_text(encoding="utf-8").splitlines():
    if line:
        item = json.loads(line)
        print(f"{item['type']}\t{item['id']}")
PY
)

import_result="$(import_bundle)"
python3 - "$import_result" <<'PY'
import json
import sys

result = json.loads(sys.argv[1])
assert result["success"] is True
assert result["successCount"] == 13
assert not result.get("errors")
PY

export_objects "$restored_export"
"$repo_root/scripts/compare-dashboards-export.py" "$restored_export"

echo "PASS: managed saved objects export with canonical source content"
echo "PASS: all managed saved objects were removed before restore"
echo "PASS: the versioned bundle restored 13 objects into a clean saved-object set"
echo "PASS: the restored export exactly matches the versioned object graph"
