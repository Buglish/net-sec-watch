# Deployment guide

Net Sec Watch supports Docker Compose, Linux VM, and Kubernetes deployment
artifacts.

## Preflight

```bash
make preflight-deployment
make test-deployment
```

## Docker Compose

Development:

```bash
make init
make up
```

Secure/production-style:

```bash
docker compose --env-file .env \
  --file compose.yaml \
  --file compose.opensearch-secure.yaml \
  --file deploy/compose/compose.production.yaml \
  --profile opensearch up -d
```

## Linux VM

```bash
deploy/linux/install-linux-vm.sh --check
sudo NET_SEC_WATCH_BRANCH=main deploy/linux/install-linux-vm.sh
```

## Kubernetes

Manifests live in `deploy/kubernetes/`.

Review `secret.example.yaml`, create real secrets through your cluster secret
manager, then apply:

```bash
kubectl apply -f deploy/kubernetes/namespace.yaml
kubectl apply -f deploy/kubernetes/
```

## Release

The release checklist is in `docs/release-checklist.md`.
The first supported release still requires an explicit tag and publish action.
