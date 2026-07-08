# Installation, Administration, and Troubleshooting

Author: SJ du Preez

## Install with Docker Compose

```bash
make init
make gen-tls-certs
make up-identity
make check
```

For a production-style Compose deployment:

```bash
docker compose --env-file .env \
  --file compose.yaml \
  --file compose.opensearch-secure.yaml \
  --file deploy/compose/compose.production.yaml \
  --profile opensearch up -d
```

## Install on Linux VM

```bash
sudo NET_SEC_WATCH_BRANCH=main deploy/linux/install-linux-vm.sh
```

Run preflight first:

```bash
deploy/linux/install-linux-vm.sh --check
```

## Install on Kubernetes

Review `deploy/kubernetes/secret.example.yaml`, create real secrets using your
cluster secret manager, then apply:

```bash
kubectl apply -f deploy/kubernetes/namespace.yaml
kubectl apply -f deploy/kubernetes/
```

## Administration

Useful commands:

```bash
make logs
make logs-opensearch
make logs-dashboards
make test-phase7-operations
make test-phase8-detections
make test-phase9-ml
```

## Troubleshooting

- If collectors stop ingesting, use `docs/runbooks/collector-backlog-and-parser-failure.md`.
- If OpenSearch rejects writes or goes red, use `docs/runbooks/opensearch-failure-disk-mapping.md`.
- If snapshots fail, use `docs/runbooks/backup-restore.md`.
- If TLS or identity breaks, use `docs/runbooks/certificate-and-secret-rotation.md`.
- If deployment validation fails, run `make preflight-deployment`.
