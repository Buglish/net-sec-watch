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
make test-phase6-security
make test-phase7-operations
make test-phase8-detections
make test-phase9-ml
make test-phase10-deployment
make test-phase11-orchestration
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
make test-phase10-deployment
```
