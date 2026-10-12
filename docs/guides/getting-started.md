# Install and start Net Sec Watch

Install Git, Docker Engine or Docker Desktop with Compose v2, Python 3, Bash,
curl, and OpenSSL. `make` is optional. On Windows use an Ubuntu WSL2 terminal
with Docker Desktop WSL integration enabled. Start Docker before continuing.
Allow several minutes for the first image download and enough memory for Docker
to run OpenSearch, Dashboards, and the collector together.

```bash
git clone https://github.com/Buglish/net-sec-watch.git
cd net-sec-watch
python3 scripts/setup.py --demo
```

Or use `make dashboard-demo`. Setup checks tools and the Docker daemon, creates
ignored local configuration and secrets, starts the services, waits for readiness,
imports all default dashboards and data views, and generates sample logs.
It prints the dashboard URL using your configured port.

On a Linux Docker host, if setup reports a low `vm.max_map_count`, run:

```bash
sudo sysctl -w vm.max_map_count=262144
```

To retain this setting after reboot, add `vm.max_map_count=262144` to a file
under `/etc/sysctl.d/` on the Docker host. On Docker Desktop the setting belongs
to its Linux VM. Setup reports failures without deleting your existing data;
fix the error and rerun the same command.

## Choose what to start

| Command | Result |
| --- | --- |
| `make doctor` | Check prerequisites without changing configuration |
| `make setup` | Collector, search, and imported dashboards, without sample events |
| `make dashboard-demo` | Same stack, with sample logs |
| `make setup-ml` | Sample logs plus traffic classification dashboard records |
| `make ml-demo` | Offline authentication scoring with readable explanations |
| `make import-dashboards` | Re-import default dashboards into a running stack |
| `make down` | Stop services while retaining stored data |

Without make, use `python3 scripts/setup.py --doctor`, `python3 scripts/setup.py`,
`python3 scripts/setup.py --demo --ml`, or `python3 scripts/ml-demo.py`.
Dashboard import can also run with `bash scripts/import-dashboards.sh`.

Setup preserves local files and secrets and changes the default collector path
in `.env` to `config/fluent-bit.demo.conf` so logs continue reaching OpenSearch
after restarts. Despite its name, that configuration accepts real syslog too.
Custom collector configurations are preserved; setup directs you to the manual
path rather than replacing them. This setup starts the local HTTP profile;
use the [security guide](security.md) for TLS and authentication.

## Open a dashboard

Open the printed URL (default `http://127.0.0.1:5601/app/dashboards`). Choose
**Net Sec Watch - Network**, **Security**, **Application**, or **Infrastructure**.
Set the time picker to **Last 24 hours** and refresh after sample ingestion.
In **Discover**, choose `net-sec-watch-network` and search `NetSecWatchDemo001`.

If imports are missing, run `make import-dashboards`. Imports overwrite the
managed saved object IDs; export changes to managed dashboards before re-importing.
Your own dashboards should use separate IDs.
For a custom Dashboards port, set `OPENSEARCH_DASHBOARDS_ENDPOINT` when importing:

```bash
OPENSEARCH_DASHBOARDS_ENDPOINT=http://127.0.0.1:5602 make import-dashboards
```

To build your own dashboard, start in Discover, save a filtered search, then open
Dashboard and add it. See [search and dashboards](search-and-dashboards.md).

## Add real logs and ML

Run `make setup`, then configure your router/firewall's remote syslog destination
to the Docker host's LAN IP and the `SYSLOG_UDP_PORT` from `.env` (default 514).
Allow that port through your host firewall. See [ingestion](ingestion.md) for
files, Linux hosts, and other sources.

Start with [machine learning](machine-learning.md): it explains what runs, how
to interpret scores, and how to replace fixtures with your own feature data.

## Diagnose startup problems

Run `make doctor`, then `make logs-opensearch`, `make logs-dashboards`, or
`make logs` for the failing service. Port conflicts can be resolved by editing
`.env` and rerunning setup. Check Docker memory allocation if services are killed.
Do not delete volumes to fix ordinary startup errors: they contain your data.
