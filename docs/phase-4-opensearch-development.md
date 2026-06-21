# Phase 4 OpenSearch development deployment

The optional `opensearch` Compose profile starts a persistent, single-node
OpenSearch development cluster.

```bash
make init
make up-opensearch
curl --fail http://127.0.0.1:9200/_cluster/health
```

View logs or stop the platform with:

```bash
make logs-opensearch
make down
```

OpenSearch data is stored in the `opensearch-data` Docker volume. `make down`
retains it. To intentionally delete development data, use:

```bash
docker compose --env-file .env --profile opensearch down --volumes
```

## Snapshot repository

The OpenSearch profile provisions a separate `opensearch-snapshots` Docker
volume and allows it through `path.repo`. Secure bootstrap registers the
filesystem repository as `net-sec-watch-local` at:

`/usr/share/opensearch/snapshots/net-sec-watch`

Repository registration verifies that every eligible OpenSearch node can write
to and read from the shared path. Check it manually with:

```bash
credentials="admin:<password-from-.env>"
curl --fail --insecure --user "$credentials" \
  --request POST \
  https://127.0.0.1:9200/_snapshot/net-sec-watch-local/_verify
```

The snapshot volume is separate from live index data but remains on the same
Docker host. For production disaster recovery, use supported remote storage or
replicate snapshot files off-host. Snapshot creation and restoration are
tested in the following Phase 4 objective.

## Development security boundary

This first Phase 4 profile follows the official single-node Docker pattern and
explicitly disables the demo security configuration and Security plugin. The
API is therefore bound to `127.0.0.1` by default and must not be exposed to a
LAN, WAN, shared host, or production environment.

Authenticated TLS ingestion and ignored or mounted credentials are separate
Phase 4 tasks. Do not change `OPENSEARCH_HTTP_BIND` to `0.0.0.0` while this
development profile is unsecured.

## Resources

The default JVM heap is 512 MiB minimum and maximum. Docker must have enough
memory for OpenSearch plus Fluent Bit and any optional sensors. Override the
heap privately in `.env` only after measuring available host memory:

```dotenv
OPENSEARCH_JAVA_OPTS=-Xms1g -Xmx1g
```

Run the isolated deployment test with:

```bash
make test-opensearch
```
