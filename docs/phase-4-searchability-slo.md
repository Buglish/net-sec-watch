# Event searchability service-level objective

The Phase 4 ingestion gate requires at least 95% of accepted events to become
searchable in OpenSearch within 10 seconds under normal load.

Run the isolated end-to-end test with:

```bash
make test-opensearch-searchability
```

The test starts secured OpenSearch and Fluent Bit, writes 100 unique RFC 3164
events over TCP syslog, and records the send time after each socket write
succeeds. It polls the normal network data stream and records the first search
time for each unique marker.

An event counts as accepted when its complete TCP frame is successfully
written. Events that never appear in search count as failures. The test passes
only when at least 95 of 100 events are observed within 10 seconds of their
individual acceptance time.

The result reports:

- accepted and searchable event counts;
- the number and percentage visible within the deadline;
- p50, p95, and maximum observed search latency;
- markers missing at the end of the deadline.

This is a normal-load correctness gate, not a maximum-throughput benchmark.
Capacity and load tests should repeat the same measurement at expected peak
event rates and alert when sustained production performance falls below the
same 95% within 10 seconds objective.

## Baseline result

Measured on June 21, 2026 with the pinned OpenSearch and Fluent Bit images:

| Measurement | Result |
| --- | ---: |
| Accepted events | 100 |
| Searchable within 10 seconds | 100 |
| Success rate | 100% |
| p50 searchability latency | 1.845 seconds |
| p95 searchability latency | 1.846 seconds |
| Maximum latency | 1.846 seconds |
| Missing events | 0 |

The result satisfies the Phase 4 completion gate. It should be rerun after
changes to buffering, flush intervals, index refresh behavior, mappings,
OpenSearch resources, or the ingestion topology.
