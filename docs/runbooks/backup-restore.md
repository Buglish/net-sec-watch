# Runbook: Backup and Restore

Author: SJ du Preez

## Backup policy

OpenSearch snapshots use the configured filesystem repository in
`config/opensearch/snapshot-repository-v1.json`.

Minimum target:

- snapshot frequency: daily;
- RPO: 24 hours;
- RTO: 4 hours.

## Verify repository

```bash
curl --insecure --user "$OPENSEARCH_USERNAME:$OPENSEARCH_INITIAL_ADMIN_PASSWORD" \
  -X POST https://127.0.0.1:9200/_snapshot/net-sec-watch-fs/_verify
```

## Create snapshot

```bash
snapshot="manual-$(date --utc '+%Y%m%dT%H%M%SZ')"
curl --insecure --user "$OPENSEARCH_USERNAME:$OPENSEARCH_INITIAL_ADMIN_PASSWORD" \
  -X PUT "https://127.0.0.1:9200/_snapshot/net-sec-watch-fs/${snapshot}?wait_for_completion=true"
```

## Restore test

Use the existing restore test:

```bash
make test-opensearch-restore
```

Record the result in `docs/test-results/`.

## Failure handling

If snapshots fail twice consecutively:

1. verify repository availability and permissions;
2. check disk capacity;
3. confirm cluster health is not red;
4. escalate to DevOps platform on-call.
