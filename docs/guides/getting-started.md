# Install and start Net Sec Watch

This guide takes a fresh checkout to a running stack with dashboards, sample
logs, and the machine-learning (ML) demo. It takes about 10 minutes on the
first run, mostly for image downloads.

## Step 1: Install prerequisites

Install Git, Docker Engine or Docker Desktop with Compose v2, Python 3, Bash,
curl, and OpenSSL. `make` is optional.

- **Windows:** use an Ubuntu WSL2 terminal with Docker Desktop WSL integration
  turned on.
- **Memory:** give Docker at least 4 GB so OpenSearch, Dashboards, and the
  collector can run together.

Start Docker, then check everything is ready:

```bash
git clone https://github.com/Buglish/net-sec-watch.git
cd net-sec-watch
python3 scripts/setup.py --doctor        # or: make doctor
```

If it reports a low `vm.max_map_count` on a Linux Docker host, run:

```bash
sudo sysctl -w vm.max_map_count=262144
```

To keep the setting after a reboot, add `vm.max_map_count=262144` to a file
under `/etc/sysctl.d/`. On Docker Desktop the setting belongs to Docker's Linux
VM.

## Step 2: Run setup

One command starts everything, including the ML demo:

```bash
python3 scripts/setup.py --demo --ml     # or: make setup-ml
```

This command:

1. creates local config and secrets (ignored by Git, never overwritten);
2. starts the collector (Fluent Bit), OpenSearch, and OpenSearch Dashboards;
3. imports the default dashboards and data views;
4. sends sample logs and confirms they reached OpenSearch;
5. runs the traffic classification demo and stores its results in OpenSearch.

If a step fails, setup prints the reason. Fix it and run the same command
again. Your existing data is kept.

Leave out the flags you don't want:

| Command | What you get |
| --- | --- |
| `make setup-ml` | Stack, dashboards, sample logs, and the ML demo (recommended first run) |
| `make dashboard-demo` | Stack, dashboards, and sample logs, without ML |
| `make setup` | Stack and dashboards only, for real log sources |

Without `make`, use `python3 scripts/setup.py` and add `--demo` and `--ml` as
needed.

## Step 3: Check the dashboards

Open the URL setup prints (default <http://127.0.0.1:5601/app/dashboards>) and
set the time picker to **Last 24 hours**.

| Dashboard | Shows |
| --- | --- |
| Net Sec Watch - Network | Router, firewall, denied traffic, and suspicious network records |
| Net Sec Watch - Security | Authentication, network, and parser triage |
| Net Sec Watch - Application | Application errors and failed outcomes |
| Net Sec Watch - Infrastructure | Authentication failures and collection quality |
| Net Sec Watch - Traffic Classification | ML demo results (needs `--ml`) |

To check a single event, open **Discover**, select the `net-sec-watch-network`
data view, and search `NetSecWatchDemo001`. If it appears, logs are flowing from
syslog into OpenSearch.

## Step 4: Check the ML results

Open **Net Sec Watch - Traffic Classification**. In Discover
(`net-sec-watch-network`), search:

```text
event.dataset:"traffic.classification.demo"
```

To check the second ML feature, which needs no Docker, run:

```bash
python3 scripts/ml-demo.py               # or: make ml-demo
```

It prints authentication anomaly scores with plain-language explanations. The
[machine learning guide](machine-learning.md) explains both features, what
they do and don't do, and how to score your own data.

## Step 5: Next steps

- **Real router or firewall logs:** set the device's remote syslog destination
  to the Docker host's LAN IP and `SYSLOG_UDP_PORT` from `.env` (default 514).
  Allow that port through the host firewall. See [ingestion](ingestion.md) for
  files, Linux hosts, and other sources.
- **Your own dashboards:** save a filtered search in Discover, then add it to a
  dashboard. See [search and dashboards](search-and-dashboards.md).
- **TLS and login:** setup starts the local HTTP stack only. See the
  [security guide](security.md).

## Everyday commands

| Command | Purpose |
| --- | --- |
| `make doctor` | Check prerequisites without changing anything |
| `make import-dashboards` | Re-import default dashboards into a running stack |
| `make traffic-classification-demo` | Add the ML demo to a stack that is already running |
| `make ml-demo` | Offline authentication scoring (no Docker) |
| `make ingestion-status` | Check how recently each log stream was indexed |
| `make down` | Stop services and keep stored data |

## Notes on setup behaviour

- Setup sets `FLUENT_BIT_CONFIG_PATH=./config/fluent-bit.demo.conf` in `.env`
  so logs keep reaching OpenSearch after restarts. Despite the name, this config
  also accepts real syslog.
- If you already use a custom collector config, setup leaves it alone and stops.
  It then points you to the manual path.
- Re-importing dashboards overwrites the managed dashboards. Export any changes
  first, and give your own dashboards separate IDs.
- For a custom Dashboards port:
  `OPENSEARCH_DASHBOARDS_ENDPOINT=http://127.0.0.1:5602 make import-dashboards`.

## Troubleshooting

| Problem | Fix |
| --- | --- |
| Setup times out | Run `make logs-opensearch` or `make logs-dashboards`, fix the error, and rerun setup. Services that get killed usually need more Docker memory. |
| Port already in use | Change the port in `.env` and rerun setup. |
| Dashboards empty | Set the time picker to **Last 24 hours**, select the `net-sec-watch-network` data view, and run `make import-dashboards`. |
| Traffic Classification dashboard empty | Run `make traffic-classification-demo`, then refresh. |
| `@timestamp` or saved-object errors | Run `make import-dashboards`, then close old Dashboards tabs. |
| Router logs don't arrive | Use the LAN IP of the machine running Docker, not a container or WSL internal IP. Check the published port with `docker compose --env-file .env port fluent-bit 5514/udp`. On Windows, allow inbound UDP/TCP 514 on the Private firewall profile. |

Don't delete Docker volumes to fix ordinary startup errors, because they hold
your data. To wipe everything on purpose, run
`docker compose --env-file .env --profile opensearch down --volumes`, then run
`make setup-ml` again.
