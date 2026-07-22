# Getting started

This is the shortest path to a working Net Sec Watch dashboard with visible
data.

For prerequisites, optional profiles, real device ingestion, and
troubleshooting, use the [administrator guide](admin-guide.md).

## One-command dashboard demo

```bash
git clone git@github.com:Buglish/net-sec-watch.git
cd net-sec-watch
make dashboard-demo
```

`make dashboard-demo` runs the first-use flow:

1. `make init` creates ignored local config files from the committed examples.
2. Docker Compose starts Fluent Bit, OpenSearch, and OpenSearch Dashboards.
3. `make import-dashboards` imports the Net Sec Watch data view, saved
   searches, dashboards, and Discover defaults.
4. `make generate` creates sample log events.
5. `scripts/send-demo-syslog.sh` sends a UDP syslog marker named
   `NetSecWatchDemo001`.

Open:

```text
http://127.0.0.1:5601
```

Then:

1. Open **Discover**.
2. Select the **Net Sec Watch** data view.
3. Search for:

   ```text
   NetSecWatchDemo001
   ```

If the marker appears, the collector, OpenSearch index, dashboard saved
objects, and ingestion path are working.

## Manual first run

Use this if you want each step separated:

```bash
make init
make check
make up
make up-dashboards
make import-dashboards
make generate
./scripts/send-demo-syslog.sh
```

Open `http://127.0.0.1:5601`, go to **Discover**, select the Net Sec Watch
data view, and search for `NetSecWatchDemo001`.

## Check the collector

```bash
curl http://127.0.0.1:2020/api/v1/health
make logs
```

## Re-import dashboards

If Dashboards opens but the Net Sec Watch data view or dashboards are missing:

```bash
make import-dashboards
```

This imports `config/dashboards/managed-saved-objects-v1.ndjson` with
overwrite enabled, which is safe to re-run.

## Real router or firewall ingestion

After the demo works, point your router or firewall remote syslog setting to:

```text
<net-sec-watch-host-ip>:514/UDP
```

Example:

```text
192.168.1.209:514/UDP
```

More detail is in [ingestion.md](ingestion.md).

## Secure OpenSearch and Dashboards

```bash
make gen-tls-certs
make up-identity
make test-oidc
```

Dashboards is served over HTTPS in the secure profile. Use the local CA
created under `config/tls/` for browser trust in development. See the
[admin guide's profile table](admin-guide.md#4-choose-a-profile-and-start-the-stack)
for what each profile adds.

## Stop

```bash
make down
make down-identity
```

Use `docker compose down --volumes` only when you intentionally want to remove
local data volumes. See the [admin guide](admin-guide.md#9-stop-and-clean-up).
