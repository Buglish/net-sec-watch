# Reliability, operations, and disaster recovery

Author: SJ du Preez

## Outcome

Operators can observe, scale, recover, upgrade, and support Net Sec Watch in a
predictable way.

## Monitoring coverage

`config/operations/monitoring-thresholds-v1.json` defines thresholds for:

- accepted events;
- dropped events;
- retried events;
- buffered events;
- failed events;
- collector silence;
- source-volume change;
- queue depth;
- rejected writes;
- shard health;
- disk watermarks;
- snapshot failure;
- certificate expiry.

`config/operations/alert-rules-v1.json` maps critical signals to runbooks and
owners.

## Runbook index

- [Collector backlog and parser failure](runbooks/collector-backlog-and-parser-failure.md)
- [OpenSearch failure, disk pressure, and mapping conflicts](runbooks/opensearch-failure-disk-mapping.md)
- [Backup and restore](runbooks/backup-restore.md)
- [Certificate and secret rotation](runbooks/certificate-and-secret-rotation.md)
- [Load testing](runbooks/load-testing.md)
- [Failure testing](runbooks/failure-testing.md)
- [Rolling upgrade and rollback](runbooks/rolling-upgrade-and-rollback.md)
- [Disaster recovery exercise](runbooks/disaster-recovery-exercise.md)

## Service levels

Operational targets and escalation ownership are defined in
`config/operations/service-levels-v1.json`.

## Commands

```bash
make test-operations
make load-test-syslog
make dr-exercise
```

## Production gates

The operations repository implementation is complete, but the production
completion gates remain dependent on live environment evidence:

- production service-level targets met under agreed load;
- documented recovery exercise meeting approved RTO and RPO;
- operators confirm they can diagnose all critical alerts using maintained
  runbooks.
