# Objective 1: file and workload log collection

This implementation provides the first vertical slice of Net Sec Watch:
reliable collection from files, applications, containers, and Linux
operating-system logs.

## Supported inputs

| Source | Fluent Bit tag | Default demo path |
|---|---|---|
| Plain text and Java stack traces | `file.text` | `/logs/text/*.log` |
| JSON application logs | `file.application` | `/logs/app/*.json.log` |
| Linux system and authentication logs | `host.system` | `/host/var/log` |
| Docker JSON logs | `container.docker` | `/host/var/lib/docker/containers/*/*.log` |

Each input has its own SQLite offset database. Fluent Bit therefore remembers
the last collected position after restart. Filesystem buffering is enabled to
protect collection during downstream interruption.

## Quick start

Docker Desktop must have integration enabled for the Ubuntu WSL distribution.

```bash
make init
make verify
make up
make logs
```

`make init` creates these private runtime files from committed examples:

- `.env` from `.env.example`
- `config/fluent-bit.local.conf` from
  `config/fluent-bit.local.conf.example`

The real files are ignored by Git. Never add credentials, tokens, private keys,
internal host paths, or production endpoints to an example file.

The default `.env` continues to use safe sample log directories. To use a
private collector configuration, change:

```dotenv
FLUENT_BIT_CONFIG_PATH=./config/fluent-bit.local.conf
```

In another terminal:

```bash
make generate
make rotate
```

The generated records should appear in `make logs`. The rotation test renames
`service.log` and creates a new file; Fluent Bit should finish reading the old
file and continue with the replacement.

Stop the collector with:

```bash
make down
```

## Automated integration tests

After Docker Desktop WSL integration is enabled:

```bash
make test-smoke
make test-integration
```

The smoke test validates the top-level production-style Compose configuration,
health endpoint, multiline assembly, and empty-line suppression.

The isolated integration harness starts a collector and a downstream Fluent Bit
receiver. It verifies:

- Plain-text, JSON application, system, and Docker log collection.
- Collection continuing after file rotation.
- SQLite offsets preventing replay after a collector restart.
- Filesystem buffering recovering after the receiver is stopped and restarted.

The harness uses `tests/runtime/`, which is ignored by Git, and removes its
containers and volumes after the test.

New sources should follow
[the file-source onboarding checklist](onboarding-file-source.md).

The latest recorded execution is available in
[the Phase 1 integration test result](test-results/phase-1-integration.md).

## Collect real host logs

Edit the private `.env` file for Linux system logs:

```dotenv
HOST_LOG_ROOT=/var/log
```

For Docker Engine JSON logs:

```dotenv
CONTAINER_LOG_ROOT=/var/lib/docker/containers
```

Then run `make up`. Both paths may be supplied together. The user running
Docker must have permission to read the selected paths.

## Configuration policy

| File | Committed | Purpose |
|---|---:|---|
| `.env.example` | Yes | Documents supported runtime variables with safe values |
| `.env` | No | Real machine paths, ports, image choice, and active config path |
| `config/fluent-bit.conf` | Yes | Shared baseline collector configuration |
| `config/fluent-bit.local.conf.example` | Yes | Template for private overrides |
| `config/fluent-bit.local.conf` | No | Real host-specific filters and outputs |

When OpenSearch credentials are introduced, they must be provided through
environment variables or mounted files under the ignored `secrets/` directory.
They must never be committed to Git.

## Health endpoint

The Fluent Bit HTTP server is bound to localhost:

```bash
curl http://127.0.0.1:2020/api/v1/health
curl http://127.0.0.1:2020/api/v1/metrics/prometheus
```

## Scope boundary

The current output is JSON Lines on collector stdout. This makes collection,
rotation, parsing, and offset behavior independently testable. OpenSearch
indexing and the common searchable schema are introduced by later objectives.
