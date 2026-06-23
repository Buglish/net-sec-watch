# Phase 6 OIDC integration result

**Test date:** June 23, 2026  
**Result:** PASS

The isolated Keycloak, OpenSearch, and OpenSearch Dashboards integration test
verified:

- Keycloak imported the versioned `net-sec-watch` realm;
- OIDC discovery published issuer, authorization, token, and JWKS endpoints;
- the confidential Dashboards client issued a signed token;
- OpenSearch validated the token and identified `oidc-test-analyst`;
- the `net-sec-watch-analyst` backend role was extracted from the JWT;
- Dashboards redirected its OpenID login endpoint to Keycloak; and
- emergency Basic authentication remained available.

Reproduce with:

```bash
make test-oidc
```
