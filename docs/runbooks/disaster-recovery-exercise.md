# Runbook: Disaster Recovery Exercise

Author: SJ du Preez

## Goal

Prove that Net Sec Watch can restore service within the approved targets:

- RTO: 4 hours;
- RPO: 24 hours.

## Dry run

```bash
make dr-exercise
```

## Full exercise

1. Record starting time, current commit, image versions, and latest snapshot.
2. Stop the OpenSearch and Dashboards stack.
3. Start a clean recovery environment.
4. Register the snapshot repository.
5. Restore the latest approved snapshot.
6. Start Dashboards and collector services.
7. Verify searchable data, dashboards, and new ingestion.
8. Record elapsed time and newest restored event timestamp.

## Pass criteria

- restored data is searchable;
- dashboards load;
- new ingestion works;
- recovery time is less than RTO;
- restored data age is within RPO.

## Evidence

Record the exercise in `docs/test-results/phase-7-dr-exercise-<date>.md`.
