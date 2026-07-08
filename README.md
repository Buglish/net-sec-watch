# Net Sec Watch

Net Sec Watch is an open-source, self-hostable SIEM-style platform for
collecting, normalizing, searching, and analyzing security-relevant logs from
files, workloads, routers, firewalls, and optional network sensors.

Author: SJ du Preez

![Net Sec Watch architecture](docs/images/openlog-architecture.png)

## What it provides

- Fluent Bit log collection for files, applications, containers, Linux system
  logs, UDP/TCP/TLS syslog, Zeek, and Suricata.
- Canonical event normalization with original-event retention and dead-letter
  routing.
- OpenSearch storage, lifecycle, snapshots, mappings, and dashboards.
- OpenSearch Dashboards saved searches, data views, dashboards, and analyst
  workflow examples.
- TLS, OIDC identity, role-based access control, audit logging, redaction, and
  data-classification policy.
- Operations runbooks, service-level targets, load testing, backup/restore, and
  disaster-recovery procedures.
- Deterministic detection rules and source-agnostic alert schema.
- Governed shadow-mode ML contracts and adaptive traffic-orchestration
  simulation.
- Docker Compose, Linux VM, and Kubernetes deployment artifacts.

Current feature status and remaining work are tracked in
[docs/features-and-roadmap.md](docs/features-and-roadmap.md).

## Documentation

Start with the documentation index:

- [Documentation index](docs/index.md)
- [Getting started](docs/guides/getting-started.md)
- [Configuration](docs/guides/configuration.md)
- [Ingestion](docs/guides/ingestion.md)
- [Search and dashboards](docs/guides/search-and-dashboards.md)
- [Security](docs/guides/security.md)
- [Operations](docs/guides/operations.md)
- [Deployment](docs/guides/deployment.md)
- [Add-ons and special features](docs/guides/addons-and-special-features.md)
- [Developer testing](docs/guides/developer-testing.md)

Detailed historical implementation notes remain under `docs/phase-*` and
`docs/test-results/` for traceability, but day-to-day users should use the
guides above.

## Quick start

```bash
git clone git@github.com:Buglish/net-sec-watch.git
cd net-sec-watch
make init
make check
make up
```

Check collector health:

```bash
curl http://127.0.0.1:2020/api/v1/health
```

Generate sample events:

```bash
make generate
make logs
```

Stop:

```bash
make down
```

## Secure profile

```bash
make gen-tls-certs
make up-identity
make test-oidc
```

## Optional features

```bash
make up-zeek
make up-suricata
make test-phase8-detections
make test-phase9-ml
make test-phase11-orchestration
```

See [Add-ons and special features](docs/guides/addons-and-special-features.md)
before enabling optional sensors, ML, or adaptive orchestration in a real
environment.

## Deployment

Development:

```bash
make init
make up
```

Production-style Compose:

```bash
docker compose --env-file .env \
  --file compose.yaml \
  --file compose.opensearch-secure.yaml \
  --file deploy/compose/compose.production.yaml \
  --profile opensearch up -d
```

Kubernetes manifests live in `deploy/kubernetes/`.

## Validation

Run all repository checks:

```bash
make check
```

Focused checks:

```bash
make test-phase6-security
make test-phase7-operations
make test-phase8-detections
make test-phase9-ml
make test-phase10-deployment
make test-phase11-orchestration
```

## Production readiness

The application is usable today for local development, lab validation, syslog
collection, OpenSearch search/dashboards, deterministic detection testing, and
simulated ML/adaptive workflows.

Before production release, complete the remaining real-world evidence listed in
[docs/features-and-roadmap.md](docs/features-and-roadmap.md), including live
source validation, target-user usability testing, performance/resilience
evidence, clean-environment deployment evidence, and release tagging.

## License

MIT. See [LICENSE](LICENSE).
