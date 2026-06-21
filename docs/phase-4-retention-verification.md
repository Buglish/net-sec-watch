# Automatic retention lifecycle verification

The Phase 4 retention gate proves that OpenSearch Index State Management (ISM)
executes rollover and deletion without an operator calling the rollover or
delete APIs.

Run the isolated test with:

```bash
make test-opensearch-retention
```

The test starts a secured OpenSearch cluster on a dedicated Compose project and
installs a test-only ISM policy. The policy uses the same rollover and delete
actions as the production lifecycle, but shortens the scheduler interval and
rolls over after one document so the check can finish in minutes rather than
waiting through the production 1-day and 90-day thresholds.

The initial backing index is explicitly enrolled in the disposable test policy
so the test does not wait for OpenSearch's coordinator sweep. Policy actions
are still executed only by the ISM scheduler.

The test then:

1. Creates a dedicated data stream and records its first backing index.
2. Indexes one uniquely marked event.
3. Waits for ISM to create the second backing index automatically.
4. Waits for ISM to delete the retired first backing index automatically.
5. Confirms the new write index remains attached to the data stream.

The script does not call `_rollover`, delete an index, or manually change a
managed index's state. A failure prints the data-stream definition, ISM explain
output, matching indexes, and OpenSearch logs.

The production policy remains unchanged:

- rollover after 1 day or 20 GB;
- warm transition after 7 days;
- archive transition after 30 days;
- deletion after 90 days.

The short-lived policy is created only inside the disposable test cluster and
has a narrowly scoped pattern matching the test data stream.

## Baseline result

The test passed on June 21, 2026 with OpenSearch 3.7.0. ISM created generation
`000002`, removed retired generation `000001`, and preserved `000002` as the
active write index. The complete isolated run took approximately five minutes.
