# Phase 5 analyst query and investigation guide

This guide is the operating playbook for analysts using Net Sec Watch without
direct server access. It covers Dashboards Query Language (DQL), the managed
saved investigations, stream-health checks, and bounded evidence export.

## Before starting an investigation

1. Start the secured interface with `make up-dashboards-secure`.
2. Open <http://127.0.0.1:5601> and sign in.
3. Open **Dashboards > Discover**.
4. Confirm that the query language is **DQL**.
5. Select the data view named in the workflow.
6. Set the time picker before interpreting the results.

Use a relative time range for live triage. Use an absolute UTC start and end
time when recording incident evidence. If results appear stale or unexpectedly
empty, run the freshness check before concluding that no activity occurred:

```bash
export OPENSEARCH_PASSWORD='<password-from-.env>'
make ingestion-status
```

The result distinguishes `current`, `empty`, `delayed`, and `query_error`
streams. Treat delayed or query-error results as incomplete evidence.

## DQL quick reference

The Discover search bar uses DQL. DQL filters events; it does not transform or
aggregate them.

| Intent | DQL example |
| --- | --- |
| Search all searchable fields | `error` |
| Match a field value | `event.action: authentication` |
| Match an exact phrase | `message: "connection refused"` |
| Require two conditions | `event.action: authentication AND event.outcome: failure` |
| Accept either condition | `event.action: denied OR event.action: dropped` |
| Exclude a condition | `NOT source.ip: "192.168.1.1"` |
| Group Boolean conditions | `event.action: (denied OR blocked OR dropped)` |
| Compare a number | `event.severity >= 7` |
| Match a numeric range | `destination.port >= 1 AND destination.port <= 1024 AND source.ip: *` |
| Match a wildcard | `url.path: "/admin*"` |
| Require a populated field | `source.ip: *` |
| Require a missing field | `NOT host.name: *` |

Quote string values to make boundaries obvious. Use uppercase `AND`, `OR`, and
`NOT`, and use parentheses whenever expressions mix operators. Prefer the time
picker over an `@timestamp` clause so a query can be reused safely.

Wildcards can make broad queries expensive. Add a field, time range, or another
condition instead of beginning a search with an unrestricted wildcard.
Field names and values are based on the normalized mapping; inspect
`event.original` when a normalized value looks unexpected.

The `--query` option in `scripts/export-events.py` is sent to the OpenSearch
`query_string` query. The examples in this guide use syntax shared by that
query and DQL, but complex Discover-only expressions should be simplified and
tested before evidence export.

## Common investigation controls

- Use **Add filter** for a structured include or exclude condition.
- Pin a filter only when it should follow you between views.
- Expand an event to inspect all normalized fields and `event.original`.
- Use the histogram to identify bursts, then select a narrower time range.
- Record the data view, query, filters, time range, and relevant event times.
- Clear or disable inherited filters before starting an unrelated case.

## Workflow 1: failed authentication triage

**Goal:** identify repeated authentication failures and the affected systems.

1. In Discover, open the saved search
   **Net Sec Watch - Authentication Failures**.
2. Use the **System** data view and start with **Last 24 hours**.
3. Confirm the query:
   `event.action: authentication AND event.outcome: failure`.
4. Group observations by `source.ip` and `host.name`.
5. Narrow the time range around any burst in the histogram.
6. Expand representative events and compare `message` with `event.original`.
7. Add a filter for a suspicious source or affected host to test its scope.

Record the source IPs, target hosts, first and last observed times, event count,
and whether successful authentication followed the failures.

## Workflow 2: router or firewall DROP investigation

**Goal:** determine who generated denied traffic and where it was headed.

1. Open **Net Sec Watch - Suspicious Network Activity**.
2. Use the **Network** data view and a time range covering the reported event.
3. Begin with:
   `event.action: (denied OR blocked OR dropped) OR event.severity >= 7 OR
   log.level: (warning OR error)`.
4. Filter on `source.ip`, then inspect `destination.ip`,
   `destination.port`, and `network.transport`.
5. Compare repeated events to distinguish a single failed connection from a
   scan or broadcast pattern.
6. Expand the event and verify the router or firewall record in
   `event.original`.

For an ASUS router record that has not yet normalized its action, search the
raw message with `message: "DROP IN="`, then capture the source, destination,
protocol, source port, and destination port from `event.original`.

Record the device, source and destination tuple, action, event frequency, time
range, and whether the traffic is expected for the network.

## Workflow 3: parser and dead-letter investigation

**Goal:** determine why an event did not enter its expected stream.

1. Open **Net Sec Watch - Parser Failures**.
2. Use the **Dead letter** data view.
3. Confirm the query `error.type: parsing_error`.
4. Filter on `error.source_dataset` to isolate the affected source.
5. Inspect `error.stage`, `message`, and `event.original`.
6. Compare multiple failures to identify a timestamp, framing, or source-format
   pattern.
7. Check stream health with `make ingestion-status` after correcting and
   retesting the source.

Record the source dataset, failed stage, representative original record, first
and last occurrence, and the parser or collector change required.

## Workflow 4: application incident investigation

**Goal:** correlate application failures with a service, host, and time window.

1. Open **Net Sec Watch - Application Errors**.
2. Use the **Application** data view and the incident time range.
3. Confirm the query `log.level: error OR event.outcome: failure`.
4. Filter on `service.name` and `host.name`.
5. Search an exact symptom when known, such as
   `message: "connection refused"`.
6. Expand events to compare normalized fields with `event.original`.
7. Move backward in time to find the first related warning or failure.

Record the service, hosts, first error, repeated error pattern, outcome, and
the event immediately preceding the incident.

## Export bounded evidence

Use an absolute UTC interval copied from the investigation. Never place
credentials in the command or repository.

```bash
export OPENSEARCH_PASSWORD='<password-from-.env>'

./scripts/export-events.py \
  --stream network \
  --start 2026-06-22T00:00:00Z \
  --end 2026-06-23T00:00:00Z \
  --query 'event.action: dropped' \
  --fields @timestamp,source.ip,destination.ip,destination.port,event.original \
  --format csv \
  --output network-drops.csv \
  --insecure
```

The exporter permits only approved streams, requires an explicit interval,
limits the interval to seven days, and caps output at 5,000 events. Store
exports according to the incident evidence policy; generated evidence files
should not be committed.

## Investigation completion checklist

- The selected data view and time range are recorded.
- The final DQL query and structured filters are recorded.
- Stream freshness is current, or its limitation is documented.
- Relevant normalized fields were compared with `event.original`.
- Empty results were not confused with delayed ingestion or a query error.
- Any export used an absolute UTC range and the minimum necessary fields.
- The conclusion separates observed facts from analyst interpretation.

For the full deployment and saved-object design, see
[phase-5-opensearch-dashboards.md](phase-5-opensearch-dashboards.md).
The upstream syntax reference is the
[OpenSearch DQL documentation](https://docs.opensearch.org/latest/dashboards/dql/).
