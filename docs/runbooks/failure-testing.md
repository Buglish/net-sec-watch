# Runbook: Failure Testing

Author: SJ du Preez

## Scope

Exercise collector, network, and OpenSearch failure modes without losing all
supported ingestion.

## Scenarios

1. Stop one syslog receiver and confirm redundant receiver failover.
2. Block OpenSearch temporarily and confirm collector buffering/retries.
3. Restore OpenSearch and confirm buffered events drain.
4. Send malformed events and confirm dead-letter routing.
5. Stop optional Zeek or Suricata and confirm core syslog ingestion continues.

## Commands

```bash
make test-failover
make test-opensearch-secure
make test-integration
```

## Evidence

Record event counts before, during, and after the failure. Capture the alert
that fired and the runbook followed.
