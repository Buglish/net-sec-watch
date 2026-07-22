# Developer testing guide

Use this guide when changing parsers, dashboards, detections, ML contracts, or
deployment automation.

## Full repository check

```bash
make check
```

## Focused checks

```bash
make verify
make test-integration
make test-opensearch-secure
make test-security
make test-operations
make test-detections
make test-ml
make test-deployment
make test-orchestration
```

## Parser changes

Add or update fixtures and run:

```bash
make test-integration
python3 tests/golden/verify.py --help
```

## Dashboard changes

```bash
make dashboards-bundle
make test-dashboards-reproducibility
```

## Deployment changes

```bash
make preflight-deployment
make test-deployment
```
