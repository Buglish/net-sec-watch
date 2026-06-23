# Phase 6 centralized identity with OIDC

Net Sec Watch integrates OpenSearch and OpenSearch Dashboards with a self-hosted
Keycloak identity provider using OpenID Connect (OIDC). Keycloak can later
federate LDAP or Active Directory without changing the OpenSearch login
protocol.

## Components and trust flow

1. The browser selects **Net Sec Watch SSO** in Dashboards.
2. Dashboards redirects the browser to the `net-sec-watch` Keycloak realm.
3. Keycloak authenticates the user and issues signed ID/access tokens.
4. OpenSearch retrieves OIDC metadata and signing keys from Keycloak.
5. OpenSearch validates issuer, audience, signature, expiry, username, and
   backend-role claims.

Basic authentication remains available for bootstrap, service integrations,
and emergency access. OIDC is non-challenging so API clients can continue using
explicit Basic or Bearer authorization headers.

## Initialize and start

`make init` generates these values only in the ignored `.env` file:

- Keycloak bootstrap administrator password;
- confidential Dashboards client secret;
- local OIDC test-user password.

Start the identity-enabled secured stack:

```bash
make init
make up-identity
```

The start target waits for Keycloak and OpenSearch, applies the OIDC
authentication domain with `securityadmin.sh`, and then starts Dashboards. This
also updates an existing OpenSearch security index; deleting event-data volumes
is not required.

Open:

- Dashboards: <https://127.0.0.1:5601>
- Keycloak administration: <http://127.0.0.1:18080>

The committed realm uses environment placeholders and contains no real
credential. The included `oidc-test-analyst` account exists only to validate
local integration and must not be used in production.

## Versioned configuration

- `compose.identity.yaml` adds the pinned Keycloak container and OIDC settings.
- `config/identity/net-sec-watch-realm.json` defines the realm, confidential
  client, role claim, audience claim, and local integration user.
- `config/opensearch-security/config-oidc.yml` enables both internal Basic and
  OIDC authentication domains.
- `config/dashboards/opensearch_dashboards.identity.yml` enables the
  multi-option login page and consumes its client secret from the environment.

The browser-facing OIDC issuer is
`http://127.0.0.1:18080/realms/net-sec-watch`. Keycloak's dynamic backchannel
allows OpenSearch and Dashboards to retrieve metadata and signing keys through
the private `keycloak:8080` container address while validating the same issuer.
Production must use a stable HTTPS identity hostname and trusted certificate.

## Verify

Run:

```bash
make test-oidc
```

The isolated test verifies discovery, confidential-client token issuance,
OpenSearch JWT validation, backend-role extraction, the Dashboards SSO option,
and the emergency Basic path.

## Production migration

- Replace Keycloak development mode and its embedded database with production
  mode and PostgreSQL.
- Serve Keycloak over HTTPS with a stable DNS name.
- Remove the local integration user.
- Connect Keycloak to the approved identity directory and MFA policy.
- Store client and administrator secrets in the deployment secret manager.
- Restrict Keycloak administration to an operator network.
- Map approved identity groups to the roles implemented in the next Phase 6
  objective.
