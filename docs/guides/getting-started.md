# Getting started

Use this guide to build, configure, run, and verify Net Sec Watch as a whole.

## Prerequisites

- Linux or WSL2 with Docker Desktop integration.
- Docker Compose v2.
- `make`, `bash`, `openssl`, and `python3`.
- Enough local disk for OpenSearch data, snapshots, and collector buffers.

## First run

```bash
git clone git@github.com:Buglish/net-sec-watch.git
cd net-sec-watch
make init
make check
make up
```

Open collector health:

```bash
curl http://127.0.0.1:2020/api/v1/health
```

Follow collector logs:

```bash
make logs
```

Generate sample events:

```bash
make generate
make logs
```

## Secure OpenSearch and Dashboards

```bash
make gen-tls-certs
make up-identity
make test-oidc
```

Dashboards is served over HTTPS in the secure profile. Use the local CA created
under `config/tls/` for browser trust in development.

## Verify everything

```bash
make check
```

This runs repository checks, parser contracts, dashboard contracts, security
contracts, operations contracts, detections, ML contracts, deployment checks,
and adaptive-orchestration checks.

## Stop

```bash
make down
make down-identity
```

Use `docker compose down --volumes` only when you intentionally want to remove
local data volumes.
