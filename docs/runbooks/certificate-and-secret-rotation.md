# Runbook: Certificate and Secret Rotation

Author: SJ du Preez

## Certificate rotation

Use the Phase 6 rotation procedure:

```bash
make gen-tls-certs
make test-tls-config
```

For production, replace local development certificates with the approved CA or
platform certificate issuer. Alert at 30 days before expiry and treat 7 days as
critical.

## Secret rotation

Use the Phase 6 procedure in `docs/phase-6-secret-rotation.md`.

After rotating secrets:

```bash
make up-identity
make test-oidc
make test-phase6-security
```

## Emergency handling

If a secret is suspected leaked:

1. revoke the secret at the identity provider or secret manager;
2. rotate dependent services;
3. search audit logs for privileged use;
4. open a security review finding and document closure.
