# Phase 10 - Deployment Portability and Production Release

Author: SJ du Preez

## Outcome

Net Sec Watch can be deployed and maintained consistently on supported Linux,
Docker, and Kubernetes environments without proprietary runtime dependencies.

## Deployment options

| Target | Automation | Notes |
|--------|------------|-------|
| Docker Compose development | `make init && make up` | Local development and parser validation. |
| Docker Compose secure/production-style | `compose.yaml` + `compose.opensearch-secure.yaml` + `deploy/compose/compose.production.yaml` | Uses TLS/security profiles and resource guardrails. |
| Linux VM | `deploy/linux/install-linux-vm.sh` | Clones the repo, initializes ignored config, runs preflight, starts Compose. |
| Kubernetes | `deploy/kubernetes/*.yaml` | Namespace, service accounts, RBAC, config, secrets example, PVCs, deployments, services, network policies. |

## Environment separation

Environment examples live in `deploy/environments/`:

- `development.env.example`
- `test.env.example`
- `staging.env.example`
- `production.env.example`

Real environment files must be ignored or provided by the deployment platform.

## Preflight

Run:

```bash
make preflight-deployment
make test-phase10-deployment
```

The file-only preflight is also used by CI:

```bash
./scripts/preflight-deployment.sh --check-files-only
```

## Release status

`VERSION` currently contains the prepared release candidate version. The final
release task remains open until the repository is committed, tagged, and pushed
using the approved release procedure.
