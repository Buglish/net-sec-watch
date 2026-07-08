# Supported Versions and Compatibility

Author: SJ du Preez

## Runtime components

| Component | Supported version | License/runtime posture |
|-----------|-------------------|-------------------------|
| Fluent Bit | 4.0 | Open source, self-hostable |
| OpenSearch | 3.7.0 | Open source, self-hostable |
| OpenSearch Dashboards | 3.7.0 | Open source, self-hostable |
| Keycloak | 26.2.5 | Open source, self-hostable |
| Zeek | LTS image | Open source, self-hostable |
| Suricata | 8.0.5 | Open source, self-hostable |
| Syft | 1.45.1 | Open source audit tooling |
| Grype | 0.114.0 | Open source vulnerability scanning |

## Compatibility policy

- Patch upgrades should pass `make check`.
- Minor upgrades require smoke, dashboard, integration, security, operations,
  detection, ML, and deployment contract tests.
- Major upgrades require migration notes, rollback plan, snapshot validation,
  and production-readiness review.

## Support policy

The first supported release is prepared as `0.1.0-rc.1`. The final supported
release tag is created only after review, commit, and push approval.
