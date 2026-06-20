# Net Sec Watch

**Author:** Salomon du Preez

**License:** [Apache License 2.0](LICENSE)

Net Sec Watch is a fully self-hosted, free and open-source platform for collecting,
searching, visualizing, and analyzing logs from servers, applications, routers,
firewalls, switches, and other network devices.

The reference architecture uses:

- Fluent Bit for file tailing, syslog reception, parsing, buffering, and forwarding.
- OpenSearch for indexed storage, full-text search, lifecycle management, and snapshots.
- OpenSearch Dashboards for Discover-style searching, filtering, dashboards, and alerts.
- OpenSearch Anomaly Detection, scikit-learn, River, MLflow, and optional PyTorch for
  later security machine-learning capabilities.

All required production components and libraries must be self-hostable and use
approved OSI open-source licenses. The platform must not depend on paid APIs,
proprietary cloud services, license keys, or feature-gated enterprise modules.

## Objectives

The detailed, tickable delivery plan is maintained in
[OBJECTIVES.md](OBJECTIVES.md).

The full product and technical specification is available at
[docs/specification/net-sec-watch-project-specification.md](docs/specification/net-sec-watch-project-specification.md).

1. Collect logs from text files, rotated files, applications, containers, and
   operating systems.
2. Receive syslog over TCP, UDP, or TLS from routers, firewalls, switches, and
   other network appliances.
3. Normalize vendor-specific logs into a consistent, searchable event schema
   while retaining each original event.
4. Provide a Kibana-like experience with free-text search, field filters,
   time-range analysis, histograms, saved searches, dashboards, and exports.
5. Protect log data through TLS, centralized authentication, role-based access,
   tenant isolation, audit logging, retention policies, and sensitive-data redaction.
6. Support reliable buffering, lifecycle management, snapshots, health monitoring,
   disaster recovery, and horizontal scaling.
7. Add a governed machine-learning phase for security anomaly detection, transparent
   risk scoring, analyst feedback, explainability, and model-drift monitoring.
8. Run on Linux virtual machines, bare metal, Docker, or Kubernetes without a
   mandatory proprietary service.
9. Provide a live adaptive traffic intelligence layer that continuously improves itself. Stream network and syslog events through a self-hosted classification and threat-scoring pipeline. When the pipeline encounters unknown or low-confidence traffic, an autonomous orchestration loop clusters the new patterns, trains candidate models, evaluates them against quality thresholds, stages them in shadow mode, and promotes approved models to the live serving pipeline — no manual retraining required. A self-hosted large language model (Ollama / Llama 3 or equivalent, open-source licensed) optionally enriches analyst-facing explanations of new patterns but is never required for the automation loop itself. The platform grows progressively smarter while analysts retain full override authority and observability at every step.

## Architecture

![OpenLog architecture](docs/images/openlog-architecture.png)

The event flow is:

1. Fluent Bit agents tail log files, while redundant receivers accept network
   device syslog.
2. Processing pipelines parse, normalize, enrich, redact, and classify events.
3. OpenSearch stores events in managed data streams and provides indexed search.
4. OpenSearch Dashboards provides exploration, dashboards, alerts, and analyst workflows.
5. A later security ML phase consumes governed event features and returns anomaly
   scores and supporting evidence without performing automatic enforcement.
6. A live adaptive intelligence layer streams events through a self-updating
   classification and threat-scoring pipeline, autonomously discovers unknown
   traffic patterns, trains and promotes new models, and optionally uses a
   self-hosted LLM to generate analyst-readable explanations of new patterns.

## Current implementation status

Net Sec Watch is being developed into a SIEM. The runnable platform currently
implements collection and normalization plus an optional single-node
OpenSearch development deployment. OpenSearch production security and
lifecycle controls, Dashboards, detections, alerting, and machine learning are
tracked in [OBJECTIVES.md](OBJECTIVES.md).

The current collector supports:

- Plain text files and multiline Java stack traces.
- Structured JSON application logs.
- Linux system and authentication logs.
- Docker JSON container logs.
- File rotation, persisted offsets, and filesystem buffering.

## Configure, build, and run

### 1. Prerequisites

Install:

- Git
- GNU Make
- Docker Engine with Docker Compose v2, or Docker Desktop
- `curl` for health checks

For Windows with WSL 2:

1. Install an Ubuntu WSL distribution.
2. Install and start Docker Desktop.
3. Open **Docker Desktop → Settings → Resources → WSL Integration**.
4. Enable integration for the Ubuntu distribution containing this repository.
5. From Ubuntu, verify:

```bash
docker version
docker compose version
```

Both commands must display a client and a reachable Docker engine.

### 2. Clone the repository

Using SSH:

```bash
git clone git@github.com:Buglish/net-sec-watch.git
cd net-sec-watch
```

Using HTTPS:

```bash
git clone https://github.com/Buglish/net-sec-watch.git
cd net-sec-watch
```

If you already have the repository:

```bash
cd ~/SecOps/net-sec-watch
git pull --ff-only
```

### 3. Create private runtime configuration

```bash
make init
```

This creates:

- `.env` from `.env.example`
- `config/fluent-bit.local.conf` from
  `config/fluent-bit.local.conf.example`

These real files are excluded by `.gitignore`. Do not commit credentials,
tokens, private keys, internal paths, or production endpoints.

The initial `.env` uses safe sample-log directories. Review it:

```bash
sed -n '1,200p' .env
```

Important options:

```dotenv
FLUENT_BIT_IMAGE=fluent/fluent-bit:4.0
FLUENT_BIT_CONFIG_PATH=./config/fluent-bit.conf
HOST_LOG_ROOT=./examples/logs/system
CONTAINER_LOG_ROOT=./examples/logs/containers
FLUENT_BIT_HTTP_BIND=127.0.0.1
FLUENT_BIT_HTTP_PORT=2020
```

### 4. Validate the repository and configuration

```bash
make check
make verify
```

These commands check formatting, shell syntax, secrets, required files, Git
ignore rules, Fluent Bit settings, and the resolved Docker Compose
configuration.

Before enabling high-volume Zeek or Suricata telemetry, complete the private
traffic policy created by `make init`, then run:

```bash
make telemetry-readiness
```

See [docs/traffic-telemetry-governance.md](docs/traffic-telemetry-governance.md)
for capacity measurement, privacy, packet-loss monitoring and retention rules.

### 5. Build or obtain the runtime

Phase 1 uses the official open-source Fluent Bit container image; there is no
custom image build yet. Pull the pinned image and validate the deployment:

```bash
docker compose --env-file .env pull
docker compose --env-file .env config
```

### 5.1 Generate a dependency and vulnerability audit

Generate an inventory of all libraries/packages discovered in the runtime
image and repository, then scan both inventories for known vulnerabilities:

```bash
make security-audit
```

The Docker Compose `audit` profile uses:

- Syft to generate SPDX JSON software bills of materials and license inventory.
- Grype to scan the SBOMs for known vulnerabilities.

Reports are written beneath:

```text
security/audits/<year>/<YYYYMMDDTHHMMSSZ>/
```

Artifact names follow this security-evidence convention:

```text
<project>_<scope>_<artifact>_<UTC timestamp>.<format>
```

Each run includes SBOMs, vulnerability reports, a Markdown summary, and a
SHA-256 manifest. Generated reports are ignored by Git because they can contain
environment and vulnerability details. See
[security/audits/README.md](security/audits/README.md).

To make the command fail when findings meet a severity threshold, set this in
the private `.env`:

```dotenv
AUDIT_FAIL_ON=high
```

Leave it empty for report-only mode.

### 6. Start the collector

```bash
make up
docker compose --env-file .env ps
```

To also start the OpenSearch development node:

```bash
make up-opensearch
curl --fail http://127.0.0.1:9200/_cluster/health
```

The current OpenSearch profile is localhost-only and intentionally unsecured
for development. See
[docs/phase-4-opensearch-development.md](docs/phase-4-opensearch-development.md)
before enabling it.

To test authenticated HTTPS ingestion instead:

```bash
make init
make up-opensearch-secure
```

This uses the ignored `.env` password and
`config/fluent-bit.opensearch.conf`. See
[docs/phase-4-authenticated-ingestion.md](docs/phase-4-authenticated-ingestion.md).

The service should report `Up`. Follow its output:

```bash
make logs
```

Press `Ctrl+C` to stop following logs; the collector continues running.

### 7. Confirm health and metrics

In another terminal:

```bash
curl --fail http://127.0.0.1:2020/api/v1/health
curl --fail http://127.0.0.1:2020/api/v1/metrics/prometheus
```

The health response should identify Fluent Bit Community Edition.

### 8. Generate and observe sample events

With `make logs` running:

```bash
make generate
make rotate
```

You should see events from:

- Plain-text application logs
- Structured JSON application logs
- Linux-style system logs
- Docker JSON container logs

The rotation command verifies that collection continues when `service.log` is
renamed and replaced.

### 9. Run Phase 1 automated tests

```bash
make test-smoke
make test-integration
```

The test suite verifies:

- Every supported sample source
- Multiline stack-trace assembly
- File rotation
- Offset persistence after collector restart
- Filesystem-buffer recovery after downstream interruption

Temporary test containers, networks, volumes, and logs are cleaned up
automatically.

### 10. Collect real host logs

Edit the private `.env` file:

```dotenv
HOST_LOG_ROOT=/var/log
CONTAINER_LOG_ROOT=/var/lib/docker/containers
```

The Docker engine must be able to read those host paths. Restart the collector
after changing `.env`:

```bash
make down
make up
make logs
```

For a new source, follow
[the file-source onboarding checklist](docs/onboarding-file-source.md).

### 11. Stop or reset the collector

Stop the service while preserving its offset and buffer volume:

```bash
make down
```

Start it again with:

```bash
make up
```

To intentionally remove the persisted collector state and force a clean
demonstration start:

```bash
docker compose --env-file .env down --volumes
```

Removing the volume discards saved offsets and buffered records. Do not use
that reset command casually in a real deployment.

### Troubleshooting

**`docker: command not found` in WSL**

Enable Docker Desktop WSL integration for the correct Ubuntu distribution,
restart Docker Desktop, and reopen the terminal.

**Port 2020 is already in use**

Change this private `.env` setting:

```dotenv
FLUENT_BIT_HTTP_PORT=2021
```

Then restart with `make down && make up`.

**Permission denied reading real host logs**

Confirm the selected paths exist from the Docker engine’s host context and
that Docker is permitted to mount them. Start with the bundled sample paths
before granting access to real logs.

**Collector exits during startup**

Inspect:

```bash
docker compose --env-file .env ps
docker compose --env-file .env logs fluent-bit
docker compose --env-file .env config
```

See
[Objective 1: file and workload log collection](docs/objective-1-file-collection.md)
for implementation detail and the recorded test evidence.

Contribution and review requirements are documented in
[CONTRIBUTING.md](CONTRIBUTING.md).

## Planned delivery phases

The full phase-by-phase delivery plan with tickable items is maintained in
[OBJECTIVES.md](OBJECTIVES.md). Summary:

1. Project foundation and collection infrastructure (Phases 0–2)
2. Event normalization, storage, search, and dashboards (Phases 3–5)
3. Security hardening, reliability, and disaster recovery (Phases 6–7)
4. Deterministic security detections and alerting (Phase 8)
5. Governed security machine learning and anomaly detection (Phase 9)
6. Deployment portability and production release (Phase 10)
7. Live adaptive traffic intelligence and self-updating model orchestration (Phase 11)

## Repository status

Phases 0 and 1 are complete. The repository contains the project foundation,
Fluent Bit collector, configuration examples, parsers, test fixtures, automated
tests, project specification, and operational documentation. The remaining
SIEM capabilities will be implemented according to
[OBJECTIVES.md](OBJECTIVES.md).
