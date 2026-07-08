# Operations guide

Operational controls are grouped into monitoring, runbooks, load testing,
failure testing, backup/restore, and disaster recovery.

## Monitoring and alerts

Configuration lives in `config/operations/`:

- `monitoring-thresholds-v1.json`
- `alert-rules-v1.json`
- `service-levels-v1.json`

Validate:

```bash
make test-phase7-operations
```

## Runbooks

Runbooks live under `docs/runbooks/` and cover:

- collector backlog and parser failure;
- OpenSearch node failure, disk pressure, and mapping conflicts;
- backup and restore;
- certificate and secret rotation;
- load testing;
- failure testing;
- rolling upgrade and rollback;
- disaster recovery.

## Load testing

```bash
make load-test-syslog
```

## Disaster-recovery dry run

```bash
make dr-exercise
```
