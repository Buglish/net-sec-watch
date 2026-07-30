# Fresh install to ML processing

This guide takes a clean Net Sec Watch checkout from nothing running to:

- log collection;
- OpenSearch storage;
- OpenSearch Dashboards;
- sample router/firewall-style ingestion;
- traffic classification;
- model orchestration records visible in Dashboards.

Use this when you want the full local demo path, including the ML/self-learning
capabilities, without jumping between multiple guides.

## 1. Prerequisites

Install:

- Git
- Docker Engine or Docker Desktop with Compose v2
- `make`
- `python3`
- `openssl`
- WSL2 when running on Windows

On Windows, run the commands inside the Ubuntu WSL terminal from the project
directory.

## 2. Clone and start the dashboard demo

```bash
git clone git@github.com:Buglish/net-sec-watch.git
cd net-sec-watch
make dashboard-demo
```

This creates local ignored config, starts Fluent Bit, OpenSearch, and
OpenSearch Dashboards, imports managed saved objects, generates sample logs,
and sends a known syslog marker.

Open:

```text
http://127.0.0.1:5601
```

## 3. Confirm ingestion is working

Check the collector:

```bash
curl http://127.0.0.1:2020/api/v1/health
```

Check indexed stream freshness:

```bash
make ingestion-status
```

If application or system streams are delayed in a local demo, refresh sample
logs and check again:

```bash
make generate
make ingestion-status
```

In **Discover**:

1. Select the `net-sec-watch-network` data view.
2. Search for:

   ```text
   NetSecWatchDemo001
   ```

If the event appears, the collection path from syslog to OpenSearch is working.

## 4. Open the base dashboards

In OpenSearch Dashboards, open **Dashboards** and try:

| Dashboard | What to inspect |
| --- | --- |
| `Net Sec Watch - Network` | Router/firewall, denied traffic, and suspicious network records |
| `Net Sec Watch - Security` | Cross-domain authentication, network, and parser triage |
| `Net Sec Watch - Application` | Application errors and failed outcomes |
| `Net Sec Watch - Infrastructure` | Authentication failures and collection quality |

If dashboards or data views are missing:

```bash
make import-dashboards
```

## 5. Send a router or firewall test message

UDP syslog test:

```bash
printf '<134>%s demo-router firewall: action=deny srcip=192.0.2.10 dstip=198.51.100.20 proto=6 srcport=51515 dstport=443 policyid=42 vendor=DemoFirewall\n' \
  "$(date '+%b %e %H:%M:%S')" |
  nc -u -w1 127.0.0.1 514
```

TCP syslog test:

```bash
printf '<134>%s demo-router firewall: action=deny srcip=192.0.2.10 dstip=198.51.100.20 proto=6 srcport=51515 dstport=443 policyid=42 vendor=DemoFirewall\n' \
  "$(date '+%b %e %H:%M:%S')" |
  nc -w1 127.0.0.1 514
```

In Discover, use `net-sec-watch-network` and search:

```text
vendor=DemoFirewall
```

The normalized event should use:

```text
event.dataset: enterprise.firewall
network.transport: tcp
event.action: deny
```

For a real router/firewall, configure the device to send remote syslog to:

```text
<net-sec-watch-host-ip>:514
```

ASUS stock firmware usually accepts only the host IP in the remote log field
and sends UDP 514 automatically. More device detail is in
[network-device-syslog-collection.md](../network-device-syslog-collection.md).

## 6. Run deterministic security detections

The detection engine can be tested offline:

```bash
make test-detections
```

Detection config lives under:

```text
config/detections/
```

Use deterministic detections as the trusted baseline before acting on ML
output.

## 7. Run ML shadow scoring

Run the governed ML contract and shadow scoring checks:

```bash
make test-ml
```

The ML configuration lives under:

```text
config/ml/
```

Important concept: ML output is advisory until reviewed. The expected flow is:

```text
ML suggests -> analyst reviews -> rule/model is tuned -> promotion is approved
```

## 8. Run traffic classification and model orchestration

Populate the ML/self-learning demo records:

```bash
make traffic-classification-demo
make import-dashboards
```

The command:

1. classifies fixture network events;
2. creates unknown-traffic candidate model decisions;
3. writes local demo files under `runtime/demos/traffic-classification/`;
4. indexes prediction records into OpenSearch when it is running;
5. indexes model orchestration records showing staged and rejected candidates.

Generated local files:

| File | Purpose |
| --- | --- |
| `runtime/demos/traffic-classification/predictions.jsonl` | Classification predictions |
| `runtime/demos/traffic-classification/candidates.json` | Candidate model staging/rejection decisions |
| `runtime/demos/traffic-classification/summary.md` | Human-readable summary |
| `runtime/demos/traffic-classification/opensearch-bulk.ndjson` | Records sent to OpenSearch |

## 9. View ML and orchestration in Dashboards

Open:

```text
Net Sec Watch - Traffic Classification
```

This dashboard includes:

- all traffic classification demo events;
- unknown/high-interest classifications;
- model orchestration events;
- suspicious network activity.

In Discover, select `net-sec-watch-network`.

Traffic classification records:

```text
event.dataset:"traffic.classification.demo"
```

Model orchestration records:

```text
event.dataset:"traffic.model_orchestration.demo"
```

Useful fields:

| Field | Meaning |
| --- | --- |
| `event.classification` | Predicted class such as `expected` or `unknown` |
| `event.ml_confidence` | Confidence score |
| `event.threat_level` | Normalized threat level |
| `event.threat_score` | Numeric threat score |
| `event.ml_model_id` | Active model or candidate model identifier |
| `event.action` | Candidate state such as `staged_shadow` or `rejected` |
| `event.outcome` | Whether the orchestration decision succeeded or failed |
| `message` | Human-readable explanation |
| `event.original` | Original prediction/candidate payload |

## 10. Validate the full local capability

Run:

```bash
./scripts/check-repository.sh
make test-integration
make test-orchestration
```

For a faster day-to-day check:

```bash
make check
```

## 11. Stop the stack

```bash
make down
```

Only remove volumes when you intentionally want to clear local OpenSearch and
Dashboards state:

```bash
docker compose --env-file .env --profile opensearch down --volumes
```

Then recreate everything with:

```bash
make dashboard-demo
make traffic-classification-demo
```

## Troubleshooting

### No data in Discover

Use the correct data view:

```text
net-sec-watch-network
```

Set the time picker to **Last 24 hours**, then run:

```bash
make generate
make traffic-classification-demo
make ingestion-status
```

### Dashboard or `@timestamp` field errors

Re-import managed saved objects:

```bash
make import-dashboards
```

Close old tabs and open:

```text
http://127.0.0.1:5601/app/dashboards#/view/net-sec-watch-traffic-classification
```

### Router cannot send logs

Use the Windows/LAN IP of the machine running Docker, not a container IP or WSL
internal IP. Confirm Docker publishes the syslog port:

```bash
docker compose --env-file .env port fluent-bit 5514/udp
docker compose --env-file .env port fluent-bit 5514/tcp
```

If using Windows, allow inbound UDP/TCP 514 on the Private firewall profile.
