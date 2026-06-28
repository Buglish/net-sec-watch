# Phase 6 - Security, Privacy, and Access Control

Author: SJ du Preez

## Outcome

Phase 6 protects collected logs with authentication, authorization, encryption,
audit logging, sensitive-field redaction, data-classification controls, and
repeatable supply-chain audit evidence.

## Access-control model

Net Sec Watch defines five first-class roles in
`config/opensearch-security/roles-v1.json` and maps identity-provider backend
roles in `config/opensearch-security/roles-mapping-v1.json`.

| Persona | Backend role | Intended use |
|---------|--------------|--------------|
| Administrator | `net-sec-watch-admin` | Full platform, security, index, and tenant administration. |
| Analyst | `net-sec-watch-analyst` | Search approved streams, save investigations, and export approved results. |
| Read-only | `net-sec-watch-read-only` | View dashboards/search results without writing saved objects or exporting. |
| Source owner | `net-sec-watch-source-owner` | View only source-owned data through document and field restrictions. |
| Service | `net-sec-watch-service` | Collector and automation ingestion without search or security administration. |

The Keycloak development realm includes matching test users so that the local
identity profile can exercise the same backend-role names used by OpenSearch.

## Data restrictions

The role model restricts access by:

- data stream/index pattern (`net-sec-watch-application-*`,
  `net-sec-watch-system-*`, `net-sec-watch-network-*`,
  `net-sec-watch-dead-letter-*`, and `net-sec-watch-audit-*`);
- Dashboards tenant permissions (`kibana_all_read` and `kibana_all_write`);
- field-level exclusions for raw messages and sensitive headers;
- masked fields for usernames, email addresses, credentials, tokens, cookies,
  API keys, and secrets;
- document-level filtering for source-owner access with the
  `source.owner` field and the user's `source_owner` identity attribute.

## Audit logging

`config/opensearch-security/audit-v1.json` enables REST and transport audit
logging, compliance logging, watched fields, and watched indices. The audit
scope includes privileged searches, exports, Dashboards saved-object writes,
security configuration changes, and index/template changes.

## Collector-side redaction

`config/scripts/sensitive_redaction.lua` runs before any output receives the
event. Approved sensitive fields are replaced with `[REDACTED]` and a stable
hash companion field is added where correlation remains useful.

The redaction policy covers keys containing:

- authorization
- cookie
- password/passwd/pwd
- secret
- token
- API key/access key
- private key

## Classification and onboarding

`config/security/data-classification-v1.json` defines public, internal,
confidential, and restricted log classes. Production source onboarding requires
source ownership, environment, datasets, classification, sensitive-field list,
retention policy, access roles, redaction approval, and legal/privacy review.

## Rotation and renewal

Secrets and certificates are generated into ignored local files by `make init`
and `make gen-tls-certs`. Rotation procedures are documented in
`docs/phase-6-secret-rotation.md`.

## Supply-chain audit

`make security-audit` uses the audit Compose profile to generate:

- runtime SPDX SBOM;
- source SPDX SBOM;
- runtime vulnerability report;
- source vulnerability report;
- SHA-256 manifest;
- markdown summary.

Evidence is retained under:

```text
security/audits/<year>/<timestamp>/
```

The approved-license policy is defined in
`config/security/approved-licenses-v1.json`.

## Verification

Run:

```bash
make test-phase6-security
make check
```

The Phase 6 contract test validates role coverage, role mappings, data
restriction controls, audit configuration, redaction wiring, local secret
handling, SBOM/vulnerability tooling, license policy, and objective completion.
