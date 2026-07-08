# Ingestion guide

Net Sec Watch collects files, application logs, container logs, Linux system
logs, syslog, and optional network sensor telemetry.

## File, application, container, and host logs

Configure source roots in `.env`:

```text
HOST_LOG_ROOT=./examples/logs/system
CONTAINER_LOG_ROOT=./examples/logs/containers
```

Supported inputs include:

- plain-text files;
- JSON application logs;
- multiline Java stack traces;
- Linux `syslog`, `messages`, and `auth.log`;
- Docker JSON container logs.

For new file sources, use `docs/onboarding-file-source.md`.

## Syslog routers and firewalls

The collector listens on:

| Protocol | Default host port | Use |
| --- | --- | --- |
| UDP | 514 | Consumer routers, including stock ASUS RT-AC68U |
| TCP | 514 | Reliable plain syslog |
| TLS/TCP | 6514 | TLS-capable routers/firewalls |

Test UDP locally:

```bash
printf '<134>%s myhost app: test message\n' "$(date '+%b %d %H:%M:%S')" |
  nc -u -w1 127.0.0.1 514
```

ASUS RT-AC68U remote logging uses the host IP only, not `:514/UDP`.

## Zeek and Suricata sensors

Optional sensors provide traffic metadata beyond router syslog:

```bash
make up-zeek
make up-suricata
```

Use a managed switch SPAN/mirror port, network TAP, or gateway deployment.
Router syslog alone is not complete network-flow telemetry.

## Dead-letter and parser errors

Malformed records route to the dead-letter stream. Use:

- `docs/parser-errors-and-dead-letter.md`
- `docs/golden-parser-tests.md`
- `tests/golden/verify.py`

## Normalization

Events are normalized to the canonical schema in
`docs/canonical-event-schema.md`. Network correlation behavior is documented in
`docs/network-event-correlation.md`.
