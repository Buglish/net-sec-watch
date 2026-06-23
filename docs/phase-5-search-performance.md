# Phase 5 seven-day search performance

Net Sec Watch NFR-03 requires 95% of standard seven-day searches to return the
first page within three seconds at the agreed design load.

## Standard queries

The benchmark reads the four managed saved searches directly from
`config/dashboards/saved-searches-v1.ndjson`:

- authentication failures;
- parser failures;
- suspicious network activity;
- application errors.

Each request uses the saved query and displayed fields, a seven-day
`@timestamp` filter, newest-first sorting, and a 50-event first page.
`track_total_hits` is disabled because Discover does not need an exact full
count to return the first evidence page.

## Reference design load

The versioned benchmark profile is
`config/dashboards/search-performance-v1.json`. Until measured production
source inventory replaces it, the reference rate is the capacity-planning
default of 100 events per second:

```text
100 EPS × 604,800 seconds = 60,480,000 events over seven days
```

The benchmark refuses to pass unless the selected seven-day window contains at
least 60,480,000 events in total and at least 1,000 events in every approved
stream. This prevents an empty or tiny development index from producing a
misleading performance pass.

Update the versioned profile after recording measured average and peak source
rates. Do not lower the design load merely to make a test pass.

## Run the benchmark

Start the secured platform and provide the password through the environment:

```bash
make up-dashboards-secure
export OPENSEARCH_PASSWORD='<password-from-.env>'
make test-seven-day-searches
```

To preserve machine-readable evidence:

```bash
./scripts/benchmark-seven-day-searches.py \
  --insecure \
  --output docs/test-results/phase-5-search-performance.json
```

Use `--end` with an absolute timestamp to repeat a historical measurement:

```bash
./scripts/benchmark-seven-day-searches.py \
  --end 2026-06-23T00:00:00Z \
  --insecure
```

The local demo certificate requires `--insecure`. Production measurements must
use a trusted certificate and omit that option.

## Measurement and pass criteria

The runner performs two warm-up requests and twenty measured requests for each
saved search. It records client-observed wall-clock latency, including network,
TLS, OpenSearch processing, and response transfer time.

A result passes only when:

- the seven-day corpus meets the configured total and per-stream design load;
- every request completes without a transport or response error;
- each saved search returns at least 95% of measured first pages in three
  seconds or less; and
- each saved search has a client-observed p95 of no more than three seconds.

The JSON result includes the exact time window, document counts, target,
per-query p50/p95/maximum latency, errors, and final gate status.

## Interpreting a failure

- **Corpus too small:** load representative retained data or measure the
  production-like environment; do not mark the Phase 5 gate complete.
- **One query is slow:** inspect its mapped fields, wildcard use, shard count,
  and time filtering before changing the target.
- **All queries are slow:** inspect node CPU, heap, disk latency, shard layout,
  and concurrent ingestion.
- **Requests time out or error:** treat the run as failed even if successful
  requests were fast.

The Phase 5 objective remains open until a committed benchmark artifact records
`"passed": true` at the approved design load.
