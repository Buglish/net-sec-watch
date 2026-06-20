# Authenticated TLS ingestion

The secure development override enables the bundled OpenSearch Security plugin
and sends Fluent Bit bulk requests over HTTPS with HTTP basic authentication.

Initialize private files and start the secured stack:

```bash
make init
make up-opensearch-secure
```

`make init` creates or preserves these Git-ignored files:

- `.env`
- `config/fluent-bit.opensearch.conf`

It generates a strong `OPENSEARCH_INITIAL_ADMIN_PASSWORD` in `.env` when one
does not already exist. Never copy that value into `.env.example`, Compose
files, documentation, issues, or CI logs.

Verify authenticated access:

```bash
source .env
OPENSEARCH_CREDENTIALS="$(
  printf '%s:%s' "$OPENSEARCH_USERNAME" "$OPENSEARCH_INITIAL_ADMIN_PASSWORD"
)"
curl --fail --insecure \
  --user "$OPENSEARCH_CREDENTIALS" \
  https://127.0.0.1:9200/_cluster/health
```

Run the isolated end-to-end test:

```bash
make test-opensearch-secure
```

The test proves unauthenticated requests are rejected and waits for Fluent Bit
documents to appear in `net-sec-watch-development`.

The OpenSearch-specific collector configuration removes redundant source
aliases such as `log`, `service`, `host`, `environment`, and `level` before
indexing. These scalar names conflict with canonical object paths such as
`log.file.path` and `service.name`. Their evidence remains available through
`event.original`, `message`, and the canonical fields.

## Certificate trust

The secure development profile uses the demo Security-plugin certificates.
Traffic is encrypted, but Fluent Bit sets `tls.verify Off` because the demo CA
is not a project-managed trust anchor. This is development-only.

Production deployment must replace the demo certificates, mount the approved
CA into Fluent Bit, set `tls.verify On`, enable hostname verification, and use
a least-privilege ingestion service account rather than `admin`.
