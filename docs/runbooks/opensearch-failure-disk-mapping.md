# Runbook: OpenSearch Failure, Disk Pressure, and Mapping Conflicts

Author: SJ du Preez

## Alerts

- `opensearch-rejected-writes`
- `opensearch-shard-health-red`
- `opensearch-disk-watermark`

## First checks

```bash
curl --insecure --user "$OPENSEARCH_USERNAME:$OPENSEARCH_INITIAL_ADMIN_PASSWORD" \
  https://127.0.0.1:9200/_cluster/health?pretty

curl --insecure --user "$OPENSEARCH_USERNAME:$OPENSEARCH_INITIAL_ADMIN_PASSWORD" \
  https://127.0.0.1:9200/_cat/thread_pool/write?v

curl --insecure --user "$OPENSEARCH_USERNAME:$OPENSEARCH_INITIAL_ADMIN_PASSWORD" \
  https://127.0.0.1:9200/_cat/allocation?v
```

## Disk pressure

1. Confirm the node is above low, high, or flood-stage watermark.
2. Stop high-volume optional sensors if ingestion threatens availability.
3. Verify retention policy execution.
4. Expand storage or add nodes before clearing flood-stage blocks.
5. After capacity is restored, clear read-only blocks only for affected indices.

## Rejected writes

1. Check write queue and bulk rejection counts.
2. Confirm index templates and mappings are valid.
3. Reduce collector concurrency or high-volume sources if the cluster is
   saturated.
4. Keep collector filesystem buffering enabled until the cluster recovers.

## Mapping conflicts

1. Identify the index and field conflict from OpenSearch errors.
2. Compare the event with `docs/canonical-event-schema.md`.
3. Fix normalization or index template mapping.
4. Reindex only after preserving the original event.

## Escalation

Escalate to DevOps platform on-call immediately for red cluster health or
flood-stage disk blocks.
