# Runbook: Rolling Upgrade and Rollback

Author: SJ du Preez

## Pre-checks

1. Confirm recent snapshot exists.
2. Run `make check`.
3. Review image version changes in `.env.example` and deployment values.
4. Confirm disk capacity and cluster health.

## Upgrade

1. Upgrade one component class at a time: collector, OpenSearch, Dashboards,
   sensors, then identity provider.
2. Run the relevant smoke test after each component.
3. Monitor rejected writes, buffer pressure, shard health, and parser errors.

## Rollback

1. Stop the upgraded component.
2. Restore the previous image version.
3. Restart the component.
4. Run the smoke test and check alert recovery.
5. If data compatibility changed, restore from snapshot only after approval.

## Evidence

Record old/new versions, checks run, alert state, rollback decision, and final
health status.
