#!/usr/bin/env bash
set -euo pipefail

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
project="net-sec-watch-opensearch-storage"
admin_credential="Nsw-test-$(openssl rand -hex 12)-A9!"
credentials="$(printf '%s:%s' admin "$admin_credential")"
port=19203
stream="net-sec-watch-capacity-development"
document_count="${STORAGE_BENCHMARK_DOCUMENTS:-12000}"
bulk_file="/tmp/net-sec-watch-storage-benchmark.ndjson"
metadata_file="/tmp/net-sec-watch-storage-benchmark.json"
bulk_response="/tmp/net-sec-watch-storage-bulk-response.json"

compose() {
  OPENSEARCH_INITIAL_ADMIN_PASSWORD="$admin_credential" \
  OPENSEARCH_USERNAME=admin \
  OPENSEARCH_HTTP_PORT="$port" \
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
  rm -f "$bulk_file" "$metadata_file" "$bulk_response"
}

trap cleanup EXIT
cleanup
compose up -d opensearch-bootstrap

deadline=$((SECONDS + 180))
until curl --fail --insecure --silent \
  --user "$credentials" \
  "https://127.0.0.1:${port}/_cluster/health" >/dev/null; do
  if ((SECONDS >= deadline)); then
    compose logs --no-color >&2 || true
    echo "FAIL: secured OpenSearch did not become ready." >&2
    exit 1
  fi
  sleep 3
done

python3 - "$bulk_file" "$metadata_file" "$stream" "$document_count" <<'PY'
import datetime
import ipaddress
import json
import sys

bulk_path, metadata_path, stream, requested_count = sys.argv[1:]
count = int(requested_count)
if count < 600 or count % 6:
    raise SystemExit("STORAGE_BENCHMARK_DOCUMENTS must be >= 600 and divisible by 6")

base_time = datetime.datetime(2026, 6, 21, tzinfo=datetime.timezone.utc)
raw_bytes = 0
datasets = {}

def address(network, number):
    return str(ipaddress.ip_address(int(ipaddress.ip_address(network)) + number))

def application(number, timestamp):
    return {
        "@timestamp": timestamp,
        "message": f"checkout request completed benchmark={number}",
        "event": {
            "dataset": "application.json",
            "kind": "event",
            "schema_version": "1.0.0",
            "parser_version": "application-json-1",
            "original": (
                f'{{"level":"INFO","service":"checkout","request_id":'
                f'"bench-{number:08d}","duration_ms":{20 + number % 900}}}'
            ),
        },
        "service": {"name": "checkout"},
        "deployment": {"environment": {"name": "benchmark"}},
        "log": {"level": "info", "severity": {"number": 9}},
    }

def system(number, timestamp):
    host = f"host-{number % 80:03d}"
    return {
        "@timestamp": timestamp,
        "message": f"systemd service health check completed benchmark={number}",
        "event": {
            "dataset": "host.system",
            "kind": "event",
            "schema_version": "1.0.0",
            "parser_version": "host-system-1",
            "original": (
                f"Jun 21 12:00:00 {host} systemd[1]: "
                f"service health check completed benchmark={number}"
            ),
        },
        "host": {"name": host},
        "service": {"name": "systemd"},
        "log": {"level": "info", "severity": {"number": 9}},
    }

def firewall(number, timestamp):
    source = address("192.0.2.0", 1 + number % 200)
    destination = address("198.51.100.0", 1 + number % 200)
    source_port = 1024 + number % 50000
    destination_port = [22, 53, 80, 443, 3389][number % 5]
    return {
        "@timestamp": timestamp,
        "message": (
            f"DROP SRC={source} DST={destination} SPT={source_port} "
            f"DPT={destination_port} PROTO=TCP"
        ),
        "event": {
            "dataset": "asuswrt.firewall",
            "kind": "event",
            "category": "network",
            "type": "denied",
            "action": "drop",
            "outcome": "failure",
            "schema_version": "1.0.0",
            "parser_version": "asuswrt-firewall-1",
            "original": (
                f"<4> Jun 21 12:00:00 benchmark-router kernel: DROP "
                f"SRC={source} DST={destination} SPT={source_port} "
                f"DPT={destination_port} PROTO=TCP"
            ),
        },
        "source": {"ip": source, "port": source_port},
        "destination": {"ip": destination, "port": destination_port},
        "network": {"transport": "tcp"},
        "observer": {"vendor": "ASUS", "product": "RT-AC68U"},
        "log": {"level": "warning", "severity": {"number": 13}},
    }

def zeek(number, timestamp):
    source = address("192.0.2.0", 1 + number % 200)
    destination = address("198.51.100.0", 1 + number % 200)
    query = f"asset-{number % 400:03d}.benchmark.example"
    return {
        "@timestamp": timestamp,
        "message": f"Zeek DNS query {query}",
        "event": {
            "id": f"CZeekBenchmark{number:08d}",
            "dataset": "zeek.dns",
            "kind": "event",
            "schema_version": "1.0.0",
            "parser_version": "zeek-network-1",
            "original": (
                f'{{"uid":"CZeekBenchmark{number:08d}","query":"{query}",'
                f'"id.orig_h":"{source}","id.resp_h":"{destination}"}}'
            ),
        },
        "source": {"ip": source, "port": 40000 + number % 20000},
        "destination": {"ip": destination, "port": 53},
        "network": {"transport": "udp", "protocol": "dns"},
        "dns": {"question": {"name": query, "type": "A"}},
        "observer": {"vendor": "Zeek", "product": "Zeek Network Security Monitor"},
    }

def suricata(number, timestamp):
    source = address("192.0.2.0", 1 + number % 200)
    destination = address("198.51.100.0", 1 + number % 200)
    signature = f"Benchmark suspicious connection class {number % 12}"
    return {
        "@timestamp": timestamp,
        "message": signature,
        "event": {
            "id": f"98765{number:08d}",
            "dataset": "suricata.alert",
            "kind": "alert",
            "category": "intrusion_detection",
            "severity": 2 + number % 3,
            "schema_version": "1.0.0",
            "parser_version": "suricata-network-1",
            "original": (
                f'{{"flow_id":98765{number:08d},"event_type":"alert",'
                f'"src_ip":"{source}","dest_ip":"{destination}",'
                f'"signature":"{signature}"}}'
            ),
        },
        "source": {"ip": source, "port": 1024 + number % 50000},
        "destination": {"ip": destination, "port": [22, 443][number % 2]},
        "network": {"transport": "tcp"},
        "rule": {
            "id": f"9{number % 1000000:06d}",
            "name": signature,
            "category": "Potentially Bad Traffic",
        },
        "observer": {"vendor": "OISF", "product": "Suricata"},
    }

def container(number, timestamp):
    return {
        "@timestamp": timestamp,
        "message": f"worker processed queue item benchmark={number}",
        "event": {
            "dataset": "container.docker",
            "kind": "event",
            "schema_version": "1.0.0",
            "parser_version": "docker-json-1",
            "original": (
                f'{{"log":"worker processed queue item benchmark={number}\\n",'
                f'"stream":"stdout","time":"{timestamp}"}}'
            ),
        },
        "service": {"name": f"worker-{number % 20:02d}"},
        "log": {
            "level": "info",
            "severity": {"number": 9},
            "file": {"path": f"/containers/{number % 20:02d}/container-json.log"},
        },
    }

factories = [application, system, firewall, zeek, suricata, container]
with open(bulk_path, "w", encoding="utf-8", newline="\n") as bulk:
    for number in range(count):
        timestamp = (
            base_time + datetime.timedelta(seconds=number)
        ).isoformat().replace("+00:00", "Z")
        event = factories[number % len(factories)](number, timestamp)
        dataset = event["event"]["dataset"]
        datasets[dataset] = datasets.get(dataset, 0) + 1
        source = json.dumps(event, separators=(",", ":"), sort_keys=True)
        raw_bytes += len(source.encode("utf-8")) + 1
        action = {"create": {"_index": stream, "_id": f"bench-{number:08d}"}}
        bulk.write(json.dumps(action, separators=(",", ":")) + "\n")
        bulk.write(source + "\n")

with open(metadata_path, "w", encoding="utf-8") as metadata:
    json.dump(
        {"document_count": count, "raw_bytes": raw_bytes, "datasets": datasets},
        metadata,
        sort_keys=True,
    )
PY

curl --fail --insecure --silent --show-error \
  --user "$credentials" \
  --header 'Content-Type: application/x-ndjson' \
  --request POST \
  --data-binary "@${bulk_file}" \
  --output "$bulk_response" \
  "https://127.0.0.1:${port}/_bulk?refresh=true"

python3 - "$bulk_response" "$document_count" <<'PY'
import json, sys
response = json.load(open(sys.argv[1], encoding="utf-8"))
assert response["errors"] is False
assert len(response["items"]) == int(sys.argv[2])
PY

curl --fail --insecure --silent \
  --user "$credentials" \
  --request POST \
  "https://127.0.0.1:${port}/${stream}/_flush" >/dev/null
curl --fail --insecure --silent \
  --user "$credentials" \
  --request POST \
  "https://127.0.0.1:${port}/${stream}/_forcemerge?max_num_segments=1&flush=true" \
  >/dev/null

stats="$(
  curl --fail --insecure --silent \
    --user "$credentials" \
    "https://127.0.0.1:${port}/${stream}/_stats/docs,store"
)"
python3 - "$metadata_file" "$stats" <<'PY'
import json
import sys

metadata = json.load(open(sys.argv[1], encoding="utf-8"))
stats = json.loads(sys.argv[2])["_all"]["primaries"]
raw_bytes = metadata["raw_bytes"]
indexed_bytes = stats["store"]["size_in_bytes"]
documents = stats["docs"]["count"]
assert documents == metadata["document_count"], (documents, metadata)
ratio = indexed_bytes / raw_bytes

print(f"documents={documents}")
print(f"raw_bytes={raw_bytes}")
print(f"indexed_primary_bytes={indexed_bytes}")
print(f"expansion_ratio={ratio:.4f}")
print(f"raw_bytes_per_event={raw_bytes / documents:.2f}")
print(f"indexed_bytes_per_event={indexed_bytes / documents:.2f}")
print("datasets=" + json.dumps(metadata["datasets"], sort_keys=True))
PY
