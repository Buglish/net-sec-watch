# Runbook: Load Testing

Author: SJ du Preez

## Goal

Validate ingestion at 1.5 times the agreed expected peak rate.

The default operations profile uses:

- expected peak: 250 events/second;
- test multiplier: 1.5;
- target rate: 375 events/second;
- default duration: 15 minutes.

## Run

```bash
EXPECTED_PEAK_EPS=250 \
LOAD_TEST_MULTIPLIER=1.5 \
LOAD_TEST_DURATION_SECONDS=900 \
make load-test-syslog
```

## Pass criteria

- collector accepts the expected event count;
- dropped events remain below 1%;
- retries do not remain elevated after the test;
- OpenSearch has no sustained write rejections;
- cluster health remains green or accepted yellow for single-node development;
- searchability SLO remains within the agreed target after ingestion.

## Evidence

Record command output, collector metrics, OpenSearch health, rejected writes,
and searchability results in `docs/test-results/`.
