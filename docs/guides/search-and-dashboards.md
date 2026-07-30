# Search and dashboards guide

Net Sec Watch uses OpenSearch for event storage and OpenSearch Dashboards for
search, investigation, saved searches, filters, and dashboards.

## Fastest working path

Run:

```bash
make dashboard-demo
```

Open:

```text
http://127.0.0.1:5601
```

Then open **Discover**, select the `net-sec-watch-network` data view, and
search for:

```text
NetSecWatchDemo001
```

If you see that event, the dashboard stack is working and data is being
inserted.

## What the demo command does

`make dashboard-demo` is intentionally opinionated for first-time users:

| Step | What happens | Why it matters |
| --- | --- | --- |
| `make init` | Creates `.env` and local config from examples | Avoids missing config/secrets |
| `docker compose ... up` | Starts Fluent Bit, OpenSearch, and Dashboards | Gives you collector + storage + UI |
| `make import-dashboards` | Imports `managed-saved-objects-v1.ndjson` | Creates the data view and starter dashboards |
| `make generate` | Writes bundled sample logs | Creates file-based sample events |
| `scripts/send-demo-syslog.sh` | Sends `NetSecWatchDemo001` over UDP syslog | Gives you a known search marker |

## Manual dashboard setup

If you already initialized the repo and want to do it step by step:

```bash
make up
make up-dashboards
make import-dashboards
make generate
./scripts/send-demo-syslog.sh
```

Open `http://127.0.0.1:5601`, then use **Discover** to search for
`NetSecWatchDemo001`.

## Re-import saved objects

If Dashboards opens but you cannot select a Net Sec Watch data view, run:

```bash
make import-dashboards
```

This imports:

```text
config/dashboards/managed-saved-objects-v1.ndjson
```

with overwrite enabled. It is safe to re-run when dashboard files change.

The managed bundle is generated from these source files:

| File | Purpose |
| --- | --- |
| `config/dashboards/data-views-v1.ndjson` | Data views/index patterns |
| `config/dashboards/saved-searches-v1.ndjson` | Saved searches for analysts |
| `config/dashboards/dashboards-v1.ndjson` | Dashboard layouts |
| `config/dashboards/analyst-states-v1.ndjson` | Analyst workflow objects |
| `config/dashboards/discover-settings-v1.json` | Discover defaults |

The managed data views include a saved field cache generated from the
OpenSearch mapping. This lets visualizations resolve fields such as
`@timestamp`, `event.dataset`, `event.classification`, and
`event.ml_confidence` without relying on a browser-side refresh.

If you change the source files, rebuild the bundle:

```bash
make dashboards-bundle
make import-dashboards
```

## Traffic classification dashboard

To populate the self-learning traffic classification demo, make sure the local
dashboard stack is running, then run:

```bash
make traffic-classification-demo
```

Open **Dashboards** and choose:

```text
Net Sec Watch - Traffic Classification
```

That dashboard is backed by the `net-sec-watch-network` data view and filters
for:

```text
event.dataset:"traffic.classification.demo"
```

If it is missing from the dashboard list, re-import the saved objects:

```bash
make import-dashboards
```

If the dashboard opens but shows no rows, refresh demo classification events:

```bash
make traffic-classification-demo
```

The same dashboard also includes the saved search
**Net Sec Watch - Model Orchestration Events**. It shows candidate models that
were staged for shadow mode or rejected by governance. In Discover, use:

```text
event.dataset:"traffic.model_orchestration.demo"
```

## Add a filter in Discover

1. Open **Discover**.
2. Select the **Net Sec Watch** data view.
3. Use the query bar or field list to filter events.

Useful starter filters:

```text
NetSecWatchDemo001
```

```text
log.syslog.severity.name:(warning OR error)
```

```text
event.kind:alert
```

```text
net.src_ip:192.168.*
```

Common fields:

| Field | Use |
| --- | --- |
| `event.original` | Raw original event |
| `event.dataset` | Source family or stream |
| `host` | Device or host name |
| `net.src_ip` | Source IP |
| `net.dst_ip` | Destination IP |
| `net.transport` | TCP/UDP/etc. |
| `log.syslog.severity.name` | Syslog severity |
| `event.kind` | Event category such as event/alert |

## Troubleshooting stale dashboard objects

If Dashboards shows an error like:

```text
Could not locate that dashboard
```

or:

```text
Could not locate that index-pattern-field (id: @timestamp)
```

the browser may still be on an old saved-object URL, or the local Dashboards
container may contain stale saved objects from an earlier import.

Use the stable dashboard URLs from the dashboard list, or re-import managed
objects:

```bash
make import-dashboards
```

Then close old tabs and open one of the managed dashboard IDs, for example:

```text
http://127.0.0.1:5601/app/dashboards#/view/net-sec-watch-traffic-classification
```

If the problem persists in a local demo stack, reset local Dashboards/OpenSearch
state and recreate the demo:

```bash
make down
docker compose --env-file .env --profile opensearch down --volumes
make dashboard-demo
make traffic-classification-demo
```

## Add a dashboard

1. Build a useful search in **Discover**.
2. Click **Save** and give the search a clear name.
3. Go to **Dashboard → Create dashboard**.
4. Add the saved search or create visualizations.
5. Save the dashboard.

To keep the dashboard in Git:

1. Go to **Management → Dashboards Management → Saved Objects**.
2. Select your new dashboard and related searches/visualizations.
3. Export them as NDJSON.
4. Add the exported object to the correct file under `config/dashboards/`.
5. Run:

   ```bash
   make dashboards-bundle
   make test-opensearch-dashboards
   make test-dashboards-reproducibility
   ```

## Secure profile notes

For the secure or identity profiles:

```bash
make gen-tls-certs
make up-identity
```

Dashboards uses HTTPS:

```text
https://127.0.0.1:5601
```

The secure bootstrap imports saved objects automatically. To manually import
against HTTPS, provide the endpoint and credentials:

```bash
OPENSEARCH_DASHBOARDS_ENDPOINT=https://127.0.0.1:5601 \
OPENSEARCH_DASHBOARDS_USERNAME=admin \
OPENSEARCH_DASHBOARDS_PASSWORD="$OPENSEARCH_INITIAL_ADMIN_PASSWORD" \
OPENSEARCH_DASHBOARDS_CA_FILE=config/tls/ca.crt \
make import-dashboards
```

## Troubleshooting

| Symptom | Fix |
| --- | --- |
| `http://127.0.0.1:5601` does not open | Run `make up-dashboards`, then `make logs-dashboards` |
| Dashboards opens but no Net Sec Watch data view exists | Run `make import-dashboards` |
| Data view exists but no events appear | Run `make generate`, then `./scripts/send-demo-syslog.sh`, then search for `NetSecWatchDemo001` |
| Collector health fails | Check Docker is running, then run `make logs` |
| Router/firewall data does not appear | Confirm the device remote syslog target is `<host-ip>:514/UDP`; on WSL2 also check port forwarding |
| Dashboard panels look broken or missing | Re-run `make import-dashboards`; if you manually imported files, use only `managed-saved-objects-v1.ndjson` |

## Reference material

Detailed background remains in:

- `docs/opensearch-dashboards.md`
- `docs/analyst-workflows.md`
- `docs/search-performance.md`
- `docs/saved-object-reproducibility.md`
