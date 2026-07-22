# Security contract test results

Author: SJ du Preez

## Result

Pass.

The security repository contract validates:

- all five required roles exist;
- identity-provider backend roles map to OpenSearch roles;
- service identities can ingest but cannot search;
- read-only and source-owner roles are restricted;
- field-level and document-level restrictions are declared where required;
- audit logging covers REST, transport, compliance, watched fields, and watched
  indices;
- collector-side redaction is wired before outputs;
- data-classification and onboarding policy exists;
- secret-rotation procedures exist;
- Syft and Grype audit services are configured;
- SBOM and vulnerability reports are retained under `security/audits/`;
- approved-license policy exists;
- no production credentials or private keys are expected in Git.

## Command

```bash
make test-security
```
