# Security guide

This guide covers authentication, authorization, TLS, audit logging, redaction,
privacy, and supply-chain evidence.

## TLS

```bash
make gen-tls-certs
make test-tls-config
```

The secure profile enables HTTPS for Dashboards and TLS-capable syslog
ingestion.

## Identity and access control

```bash
make up-identity
make test-oidc
```

The local identity profile uses Keycloak and OpenSearch Security. Roles:

- administrator;
- analyst;
- read-only;
- source-owner;
- service.

Role definitions live in `config/opensearch-security/`.

## Redaction and privacy

Collector-side redaction is implemented in
`config/scripts/sensitive_redaction.lua`. Data classification and onboarding
policy live in `config/security/`.

## Audit logging

OpenSearch audit configuration lives at
`config/opensearch-security/audit-v1.json`.

## Secrets and certificates

Use `docs/phase-6-secret-rotation.md` and
`docs/runbooks/certificate-and-secret-rotation.md`.

## Supply-chain audit

```bash
make security-audit
```

This generates SBOM and vulnerability evidence under `security/audits/`.
