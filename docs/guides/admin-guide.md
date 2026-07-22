# Administrator guide

This is the canonical, ordered walkthrough for standing up Net Sec Watch as
an administrator or operator. It replaces piecing the process together from
the README, the quick-start, and the configuration guide: start here, then
follow the links out for depth on a specific topic.

If you just want the fastest path with no explanation, see the quick start
in [getting-started.md](getting-started.md). Come back here when something
doesn't work, or before you decide which optional profile to enable.

For a first-time local install where the goal is simply "show me data in a
dashboard", run:

```bash
make dashboard-demo
```

Then open `http://127.0.0.1:5601`, go to **Discover**, select the Net Sec
Watch data view, and search for `NetSecWatchDemo001`.

## 1. Prerequisites

Required:

- Docker Engine or Docker Desktop, with the Docker Compose **v2** plugin
  (`docker compose version`, not the standalone `docker-compose` v1 binary).
- `make`, `bash`, `openssl`, `python3`.
- Linux, or Windows with WSL2 and Docker Desktop's WSL integration enabled.
- Enough local disk for OpenSearch data, snapshots, and collector buffers —
  a few GB is enough for local/lab use.

Verify them before you start:

```bash
docker compose version
make --version
openssl version
python3 --version
```

`make init` (next step) also checks for `docker`, `docker compose`, and
`openssl` itself and fails with a specific message if one is missing, so you
don't need to do this by hand — it's here so you know what's being checked
and can fix it yourself if `make init` stops you.

## 2. Clone and initialize local configuration

```bash
git clone git@github.com:Buglish/net-sec-watch.git
cd net-sec-watch
make init
```

`make init` (`scripts/init-local-config.sh`) copies committed `*.example`
files into git-ignored local files and generates random local secrets. It
never overwrites a file that already exists, so it's safe to re-run.

| Generated file | From | Purpose |
| --- | --- | --- |
| `.env` | `.env.example` | Ports, image tags, generated passwords, host paths |
| `config/fluent-bit.local.conf` | `config/fluent-bit.local.conf.example` | Local collector overrides (e.g. TLS syslog input) |
| `config/fluent-bit.opensearch.conf` | `config/fluent-bit.opensearch.conf.example` | Collector config used by the secure OpenSearch profile |
| `config/traffic-telemetry-policy.yaml` | `config/traffic-telemetry-policy.example.yaml` | Traffic analysis and telemetry policy |

It also generates `OPENSEARCH_INITIAL_ADMIN_PASSWORD`, `KEYCLOAK_ADMIN_PASSWORD`,
and the `OIDC_*` user passwords directly into the ignored `.env` — these are
strong random values, not the committed example's blanks. Review `.env`
before continuing; it is never committed.

## 3. Validate the repository

```bash
make check
```

This runs the full local validation suite: required-file checks, shell
syntax and `shellcheck`, `yamllint`, a secrets scan, and the schema,
dashboard, detection, ML, and orchestration contract tests. It doesn't
require Docker to be running. Treat a clean `make check` as the gate before
starting services or opening a pull request — see
[developer-testing.md](developer-testing.md) for focused subsets.

## 4. Choose a profile and start the stack

Net Sec Watch layers optional Docker Compose **profiles** on top of the base
collector. Start with the smallest profile that answers your question — you
can layer more on later without redoing steps 1-3.

| You want to... | Command | What starts |
| --- | --- | --- |
| Get a working dashboard with visible sample data | `make dashboard-demo` | Fluent Bit + OpenSearch + Dashboards, imports saved objects, generates sample events, sends a demo syslog marker |
| Confirm the collector parses/normalizes events, no search backend | `make up` | Fluent Bit only; output goes to `stdout` (`make logs`) |
| Search events via the OpenSearch API only, no UI | `make up-opensearch` | + OpenSearch (binds `127.0.0.1:9200`) — does **not** start Dashboards |
| Search and dashboard events in the UI, security plugin disabled | `make up-dashboards` | + OpenSearch + Dashboards (binds `127.0.0.1:9200` and `127.0.0.1:5601`) |
| Exercise TLS + authenticated OpenSearch (still self-signed local certs) | `make gen-tls-certs`<br>`make up-opensearch-secure` | + TLS on the collector and OpenSearch, security plugin enabled |
| Exercise SSO / OIDC login through Keycloak | `make gen-tls-certs`<br>`make up-identity` | + Keycloak, secure OpenSearch, Dashboards SSO |
| Add network metadata from a mirrored/tapped interface | `make up-zeek` (set `ZEEK_INTERFACE` in `.env` first) | + Zeek, requires host networking and packet-capture capabilities |
| Add passive IDS/flow alerts | `make up-suricata` (set `SURICATA_INTERFACE` in `.env` first) | + Suricata, same networking requirements as Zeek |
| Generate SBOMs and scan for vulnerabilities | see [security guide](security.md) | `syft`/`grype` one-shot containers under the `audit` profile |

Zeek and Suricata need real (or mirrored/tapped) network traffic and
elevated capabilities — test them in a lab before pointing them at a
production network.

Check the collector came up:

```bash
curl http://127.0.0.1:2020/api/v1/health
```

## 5. Verify ingestion

If you used `make dashboard-demo`, it already generated sample logs and sent
the `NetSecWatchDemo001` syslog marker.

To send another test syslog message:

```bash
./scripts/send-demo-syslog.sh
make logs
```

Or generate a full set of sample logs across every source type:

```bash
make generate
make logs
```

If you're pointing a real router or firewall at this host, see
[ingestion.md](ingestion.md) for device-specific notes, and
[docs/network-device-syslog-collection.md](../network-device-syslog-collection.md) if you're on
WSL2 and need the UDP/TCP port forwarding procedure — Windows does not
forward privileged ports into WSL2 automatically.

### Link a real input source

There is no UI step for this — every input is wired by pointing a device or
host path at the collector, not by clicking "add source" anywhere:

| Source | How to link it |
| --- | --- |
| Router/firewall syslog | In the device's admin UI, set remote syslog server to this host's IP on UDP/TCP 514 (or 6514 for TLS). For an ASUS RT-AC68U: **System Log → General Log → Remote Log Server**. See [ingestion.md](ingestion.md) for other vendors (Meraki, pfSense, OPNsense, Fortinet, Ubiquiti). |
| Linux host logs | Set `HOST_LOG_ROOT` in `.env` to the real path (e.g. `/var/log`) instead of the bundled example logs, then restart the collector. |
| Docker container logs | Set `CONTAINER_LOG_ROOT` in `.env` to the real Docker log root (e.g. `/var/lib/docker/containers`), then restart the collector. |
| Plain-text or JSON app log files | Drop new files under the paths matched by `config/fluent-bit.conf`'s `file.text`/`file.application` inputs, or add a new `[INPUT]` block — see `docs/onboarding-file-source.md`. |
| Zeek / Suricata | `make up-zeek` / `make up-suricata` with `ZEEK_INTERFACE`/`SURICATA_INTERFACE` set to a mirrored/tapped interface (step 4). |

## 6. Open OpenSearch Dashboards

Requires `make up-dashboards` (or `up-opensearch-secure`/`up-identity`, which
both start Dashboards too) — plain `make up-opensearch` does not start the
Dashboards container, so there is nothing listening on 5601 until you run one
of these (step 4):

```text
http://127.0.0.1:5601        (insecure/dev profile)
https://127.0.0.1:5601       (opensearch-secure or identity profile)
```

In **Discover**, select the Net Sec Watch data view and search for your test
marker (for example `NetSecWatchDemo001`).

If the Net Sec Watch data view is missing in the local/insecure profile, import
the managed saved objects:

```bash
make import-dashboards
```

**What the `config/dashboards/*.ndjson` files actually are**: exported
*saved-object definitions* (index patterns, searches, dashboard layouts) —
not log data. Nothing in OpenSearch changes until you import them into
Dashboards through `make import-dashboards`, the secure bootstrap container,
or the Dashboards UI; they're inert files sitting in the repo until then.
`data-views-v1.ndjson`, `saved-searches-v1.ndjson`, `dashboards-v1.ndjson`,
and `analyst-states-v1.ndjson` are the hand-edited source files; `make
dashboards-bundle` (`scripts/build-dashboards-bundle.py`) combines them into
`managed-saved-objects-v1.ndjson`, which is the one you actually import. See
[search-and-dashboards.md](search-and-dashboards.md#re-import-saved-objects).

**Pre-built data views, saved searches, and dashboards**: the
`opensearch-secure`/`identity` profiles load these automatically (the
`opensearch-dashboards-bootstrap` container imports them on startup) — a
one-time script action, not something you do by hand. The plain `opensearch`
profile (`make up-opensearch`/`make up-dashboards`) uses the host-side
`make import-dashboards` command. If you prefer the UI, import them manually:

1. Click the **menu** in the top-left corner of Dashboards, then
   **Management → Dashboards Management**. This opens a landing page that
   says "Welcome to Dashboards Management" and looks empty at first — the
   actual sections (**Index Patterns**, **Saved Objects**, **Advanced
   Settings**) are links in the **second, narrower menu on the left side of
   that page**, not the ☰ menu you just used. It's easy to miss because
   there are two separate left-hand menus stacked next to each other.
2. Click **Saved Objects** in that left-hand list.
3. Click the **Import** button (top-right of the Saved Objects table).
4. A file picker opens — select **`config/dashboards/managed-saved-objects-v1.ndjson`**
   from your local checkout (not the individual `data-views-v1.ndjson` /
   `saved-searches-v1.ndjson` / `dashboards-v1.ndjson` / `analyst-states-v1.ndjson`
   files — `managed-saved-objects-v1.ndjson` is the pre-combined bundle of all
   four, and it's what the automated bootstrap script actually imports too,
   so it's the tested path). Tick **"Automatically overwrite conflicts"**
   before confirming — safe to re-run any time, and required if you already
   imported an older/partial set.
5. Go to **Discover** (back via the ☰ menu) and confirm the **Net Sec Watch**
   data view now appears in the dropdown in the top-left — that confirms the
   import worked.

Importing the individual files instead of the combined bundle is why a
dashboard can fail to load with an error like `Could not locate that
visualization (id: net-sec-watch-analyst-state-guide)`: that visualization
only exists in `analyst-states-v1.ndjson`, which `dashboards-v1.ndjson`
references but doesn't include. If you already hit that, re-import
`managed-saved-objects-v1.ndjson` with overwrite enabled to fix it — no need
to remove anything first.

**If you skip the "Automatically overwrite conflicts" checkbox** and an
object with the same ID already exists, Dashboards doesn't skip it — it
silently creates a *new copy under a random UUID* instead. Every dashboard
panel and saved search is wired to the others by ID, so these random-UUID
copies are broken (missing panels/references) and also leave orphaned
duplicates cluttering the data-view/dashboard pickers. If that happens,
delete the stray random-ID objects in **Saved Objects** and reimport with
overwrite ticked.

**Verify the import actually worked**, against your real running instance
(no Docker/test harness needed):

```bash
for d in infrastructure application network security; do
  curl -s -o /dev/null -w "dashboard/%{http_code} " \
    "http://127.0.0.1:5601/api/saved_objects/dashboard/net-sec-watch-${d}"
done; echo
curl -s -o /dev/null -w "visualization/%{http_code}\n" \
  "http://127.0.0.1:5601/api/saved_objects/visualization/net-sec-watch-analyst-state-guide"
```

All five should return `200`. `404` means that object isn't present under its
expected ID (import didn't happen, or overwrite wasn't ticked and it landed
under a random UUID instead — check for orphans as above). Use
`https://127.0.0.1:5601` with `--cacert config/tls/ca.crt --user
admin:$OPENSEARCH_INITIAL_ADMIN_PASSWORD` instead if you're on the
`opensearch-secure`/`identity` profile.

This only checks your live instance's saved objects, not the correctness of
the committed bundle file — for that, see the isolated tests below:

```bash
make test-opensearch-dashboards        # fresh install: imports the bundle, asserts every object's shape
make test-dashboards-reproducibility   # export -> delete -> reimport -> export, must match exactly
```

Both spin up their own throwaway Compose project on different ports and tear
it down after, so they never touch the instance you're developing against.

**Building your own search, filter, or dashboard** (UI steps, once data views
exist):

1. Open **Discover**, pick the data view, build a query (e.g.
   `event.kind:alert OR log.syslog.severity.name:(warning OR error)`), and
   **Save** it as a saved search.
2. Open **Dashboard → Create dashboard**, then **Add** your saved search or
   new visualizations, and save the dashboard.
3. If you want it version-controlled instead of only living in this
   OpenSearch instance: **☰ menu → Management → Dashboards Management →
   Saved Objects**, tick the checkbox next to your new saved objects, click
   **Export**, and commit the downloaded `.ndjson` under `config/dashboards/`
   (see
   [search-and-dashboards.md](search-and-dashboards.md) for the managed
   object files and their validation commands).

## 7. What's next: detections, ML, sensors, and security

Once ingestion and Dashboards work, the platform's other features are
config/script layers on top of this same stack — none of them require
redoing steps 1-6. Each one lists what it actually needs before you touch it:

| Feature | Needs | Where |
| --- | --- | --- |
| Detections and alerts | Nothing running — `scripts/run-detections.py` evaluates a JSONL events file directly | [README detections section](../../README.md#3-use-detections-and-alerts) |
| ML shadow scoring | Nothing running — `scripts/ml-shadow-score.py` scores a JSONL events file against a model file | [README ML section](../../README.md#4-use-machine-learning-features) |
| Self-learning traffic/orchestration | Nothing running for the scripts themselves; the `orchestration` Compose profile needs OpenSearch when running continuously | [README self-learning section](../../README.md#5-use-the-self-learning-traffic-features) |
| Zeek / Suricata sensors | `ZEEK_INTERFACE`/`SURICATA_INTERFACE` set in `.env` to a real mirrored/tapped interface (step 4) | [README sensors section](../../README.md#6-optional-sensors-zeek-and-suricata) |
| TLS + OIDC security profile | `make gen-tls-certs`, then `make up-identity` (step 4) | [README security section](../../README.md#7-security-profile) |
| SBOM/vulnerability audits | Nothing running — one-shot `audit`-profile containers | [README audit section](../../README.md#8-audit-open-source-libraries-and-images) |

Detections and ML/orchestration in particular don't need Docker at all to
try out — they're plain Python scripts against fixture or exported event
files, which is the fastest way to see what they produce before wiring them
into a live stack.

## 8. Environment variable reference

Full documented defaults live in `.env.example`; this groups them by what
they control. Environment-specific starting points for non-local deployments
are in `deploy/environments/` (`development`, `test`, `staging`,
`production`).

| Group | Key variables | Notes |
| --- | --- | --- |
| Collector core | `FLUENT_BIT_IMAGE`, `FLUENT_BIT_CONFIG_PATH`, `COLLECTOR_NAME`, `SITE_NAME`, `DEPLOYMENT_ENVIRONMENT`, `HOST_LOG_ROOT`, `CONTAINER_LOG_ROOT` | `HOST_LOG_ROOT`/`CONTAINER_LOG_ROOT` default to bundled example logs so the project is safe to start without granting access to real host paths |
| Network listeners | `FLUENT_BIT_HTTP_BIND`, `FLUENT_BIT_HTTP_PORT`, `SYSLOG_BIND`, `SYSLOG_UDP_PORT`, `SYSLOG_TCP_PORT`, `SYSLOG_TLS_PORT` | Standard ports (514/514/6514) need no firewall exception on most Linux hosts |
| OpenSearch & Dashboards | `OPENSEARCH_IMAGE`, `OPENSEARCH_HTTP_BIND`, `OPENSEARCH_HTTP_PORT`, `OPENSEARCH_JAVA_OPTS`, `OPENSEARCH_DASHBOARDS_IMAGE`, `OPENSEARCH_DASHBOARDS_BIND`, `OPENSEARCH_DASHBOARDS_PORT`, `OPENSEARCH_USERNAME`, `OPENSEARCH_INITIAL_ADMIN_PASSWORD` | Password is generated by `make init`, never left blank in the real `.env` |
| TLS & identity | `TLS_CERT_DIR`, `KEYCLOAK_IMAGE`, `KEYCLOAK_BIND`, `KEYCLOAK_PORT`, `KEYCLOAK_ADMIN_USERNAME`, `KEYCLOAK_ADMIN_PASSWORD`, `OIDC_CLIENT_SECRET`, `OIDC_*_USER_PASSWORD` | All secrets generated by `make init`; certs generated by `make gen-tls-certs` |
| Sensors | `ZEEK_IMAGE`, `ZEEK_INTERFACE`, `ZEEK_LOG_VOLUME`, `SURICATA_IMAGE`, `SURICATA_INTERFACE`, `SURICATA_LOG_VOLUME` | Interface must see mirrored, tapped, or gateway traffic |
| Audit/SBOM | `SYFT_IMAGE`, `GRYPE_IMAGE`, `AUDIT_TARGET_IMAGE`, `AUDIT_FAIL_ON`, `AUDIT_APPROVED_LICENSES` | See [security guide](security.md) |

For parser/filter/detection/ML/dashboard configuration (as opposed to
runtime environment), see [configuration.md](configuration.md) and the
per-topic guides linked from [the documentation index](../index.md).

## 9. Stop and clean up

```bash
make down
make down-opensearch-secure   # if you started the secure profile
make down-identity            # if you started the identity profile
```

This stops containers but **keeps** data volumes (OpenSearch indices,
Keycloak data, collector state). Only remove them intentionally:

```bash
docker compose down --volumes
```

## 10. Beyond local Docker Compose

For a production-style Compose profile, a Linux VM installer, or Kubernetes
manifests, see the [deployment guide](deployment.md) — the commands live
there so they don't drift out of sync with this guide.

## 11. Troubleshooting

| Symptom | Where to look |
| --- | --- |
| `make init` stops with "X is required" | Install the missing prerequisite (step 1) and re-run — it's safe to re-run |
| Collector stops ingesting or falls behind | `docs/runbooks/collector-backlog-and-parser-failure.md` |
| OpenSearch rejects writes or the cluster goes red | `docs/runbooks/opensearch-failure-disk-mapping.md` |
| Snapshots fail | `docs/runbooks/backup-restore.md` |
| TLS or OIDC/identity breaks | `docs/runbooks/certificate-and-secret-rotation.md` |
| No router/firewall events arrive on WSL2 | [network-device-syslog-collection.md](../network-device-syslog-collection.md) (port forwarding) |
| Deployment validation fails | `make preflight-deployment` |
| Anything else | `make check` first to rule out a config-level problem, then the relevant guide in [docs/index.md](../index.md) |
