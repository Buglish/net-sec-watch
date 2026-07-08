# Configuration guide

Net Sec Watch separates committed examples from private runtime files.

## Local initialization

```bash
make init
```

This creates ignored local files from examples:

- `.env`
- `config/fluent-bit.local.conf`
- `config/fluent-bit.opensearch.conf`
- `config/traffic-telemetry-policy.yaml`

Do not commit generated `.env`, private keys, certificates, passwords, tokens,
or source-specific secrets.

## Environment variables

Start from `.env.example`. Important values:

- `DEPLOYMENT_ENVIRONMENT`
- `FLUENT_BIT_CONFIG_PATH`
- `HOST_LOG_ROOT`
- `CONTAINER_LOG_ROOT`
- `SYSLOG_BIND`
- `SYSLOG_UDP_PORT`
- `SYSLOG_TCP_PORT`
- `SYSLOG_TLS_PORT`
- `OPENSEARCH_INITIAL_ADMIN_PASSWORD`
- `OIDC_CLIENT_SECRET`
- `TLS_CERT_DIR`

Environment-specific examples live in `deploy/environments/`:

- `development.env.example`
- `test.env.example`
- `staging.env.example`
- `production.env.example`

## TLS material

```bash
make gen-tls-certs
```

Generated files under `config/tls/` are local-only and ignored by Git.

## Safe customization

Prefer local ignored override files for machine-specific settings. For shared
changes, update the committed `.example` file and add a validation test.
