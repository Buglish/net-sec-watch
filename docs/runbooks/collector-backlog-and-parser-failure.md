# Runbook: Collector Backlog and Parser Failure

Author: SJ du Preez

## Alerts

- `collector-dropped-events`
- `collector-output-retries`
- `collector-buffer-pressure`
- `collector-source-silence`
- `source-volume-anomaly`

## First checks

```bash
docker compose --env-file .env ps
docker compose --env-file .env logs --no-color fluent-bit
curl --fail --silent http://127.0.0.1:2020/api/v1/metrics
```

## Diagnose backlog

1. Check Fluent Bit output retries and filesystem buffer growth.
2. Confirm OpenSearch is healthy and accepts writes.
3. Check disk space for the collector state volume.
4. Confirm the affected source is not sending an unexpected event spike.
5. If backlog is growing, reduce non-critical source volume before restarting.

## Diagnose parser failure

1. Search for `pipeline.deadletter` and `_dead_letter`.
2. Compare `event.original` with parser fixtures.
3. Add or update a sanitized fixture before changing parser code.
4. Run integration and golden parser tests.

## Recovery

- Restart the collector only after confirming buffered data will not be lost.
- Increase `Mem_Buf_Limit` and filesystem storage only with a matching disk
  capacity check.
- Route malformed records to the dead-letter stream instead of dropping them.

## Escalation

Escalate to DevOps platform on-call if retries or buffer pressure remain
critical for 30 minutes. Escalate to the source owner if a single source causes
unexpected volume or malformed records.
