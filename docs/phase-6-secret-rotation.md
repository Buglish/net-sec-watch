# Phase 6 Secret Rotation and Certificate Renewal

Author: SJ du Preez

## Local development secrets

Local secrets live in `.env`, which is ignored by Git. Create or refresh it
with:

```bash
make init
```

The command generates:

- `OPENSEARCH_INITIAL_ADMIN_PASSWORD`
- `KEYCLOAK_ADMIN_PASSWORD`
- `OIDC_CLIENT_SECRET`
- OIDC demo-user passwords

## Rotate OpenSearch administrator password

1. Stop the secure stack:

   ```bash
   make down-identity
   ```

2. Replace `OPENSEARCH_INITIAL_ADMIN_PASSWORD` in the ignored `.env` file.
3. Start and reapply security configuration:

   ```bash
   make up-identity
   ```

4. Run:

   ```bash
   make test-oidc
   make test-phase6-security
   ```

## Rotate OIDC client secret

1. Replace `OIDC_CLIENT_SECRET` in `.env`.
2. Restart the identity profile:

   ```bash
   make down-identity
   make up-identity
   ```

3. Confirm Dashboards redirects to the identity provider and Basic emergency
   access still works:

   ```bash
   make test-oidc
   ```

## Renew local TLS certificates

The local CA and certificates are generated under `config/tls/`, which is
ignored by Git.

```bash
make gen-tls-certs
```

If you intentionally need to replace a still-valid local CA, remove the local
ignored files first, regenerate them, and reinstall `ca.crt` in browsers or
TLS-capable syslog senders.

## Production expectation

Production deployments should use an external secret manager or platform-native
secret storage. Do not commit production credentials, private keys, customer
certificates, or exported identity-provider secrets.
