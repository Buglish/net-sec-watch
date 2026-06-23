# Phase 6 TLS coverage

The secure profile encrypts every required traffic class:

| Traffic | Endpoint | Protection |
| --- | --- | --- |
| Browser to Dashboards | `https://127.0.0.1:5601` | Project development CA and Dashboards server certificate |
| API clients to OpenSearch | `https://127.0.0.1:9200` | OpenSearch Security plugin HTTPS |
| Fluent Bit to OpenSearch | `https://opensearch:9200` | Authenticated TLS output |
| Device to collector | TCP/6514 | TLS-protected RFC 5424 syslog |
| OpenSearch node transport | TCP/9300 internally | Security plugin transport TLS |

Generate or validate the ignored local certificates:

```bash
make gen-tls-certs
```

The command preserves certificates that chain to the current local CA and have
at least 30 days remaining. It creates:

- `ca.crt` and private `ca.key`;
- `dashboards.crt` and `dashboards.key`;
- `server.crt` and `server.key` for TLS syslog.

Start the secured browser and ingestion stack:

```bash
make init
make up-dashboards-secure
```

Open <https://127.0.0.1:5601>. Install `config/tls/ca.crt` as a local trusted
development CA to remove browser warnings. Never install `ca.key`, copy it to
devices, or commit any generated certificate material.

TLS-capable routers and firewalls should trust `ca.crt` and send RFC 5424
syslog to TCP/6514. UDP/514 and TCP/514 remain compatibility paths for devices
that cannot use TLS and must be documented as plaintext sources.

## Verification

Run:

```bash
make test-tls-config
make test-opensearch-dashboards
make test-opensearch-secure
```

These tests validate certificate generation, CA-verified browser HTTPS,
OpenSearch HTTPS, authenticated Fluent Bit ingestion, and TLS syslog
configuration.

## Current development limitation

OpenSearch 3.7.0's bundled development Security-plugin certificates currently
protect the REST and node-transport layers. Dashboards and Fluent Bit encrypt
their connections to OpenSearch but explicitly use the demo-certificate trust
exception. Replacing the demo CA, enabling hostname verification, certificate
renewal, and trust rotation belongs to the later Phase 6 certificate-renewal
objective. The secure profile remains localhost-only until centralized
identity and role controls are implemented.
