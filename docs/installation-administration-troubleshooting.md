# Installation, Administration, and Troubleshooting

Author: SJ du Preez

## Install and administer

For local Docker Compose install (prerequisites, profile selection,
environment variables, verifying ingestion, stopping/cleanup), see the
[administrator guide](guides/admin-guide.md).

For a production-style Compose deployment, the Linux VM installer, or
Kubernetes manifests, see the [deployment guide](guides/deployment.md).

Day-to-day administration commands (logs, health checks, focused validation)
are also listed in the [administrator guide](guides/admin-guide.md) and
[developer-testing.md](guides/developer-testing.md); operations-specific
commands are in the [operations guide](guides/operations.md).

## Troubleshooting

- If collectors stop ingesting, use `docs/runbooks/collector-backlog-and-parser-failure.md`.
- If OpenSearch rejects writes or goes red, use `docs/runbooks/opensearch-failure-disk-mapping.md`.
- If snapshots fail, use `docs/runbooks/backup-restore.md`.
- If TLS or identity breaks, use `docs/runbooks/certificate-and-secret-rotation.md`.
- If deployment validation fails, run `make preflight-deployment`.
