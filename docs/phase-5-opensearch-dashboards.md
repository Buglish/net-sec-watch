# Phase 5 OpenSearch Dashboards deployment

OpenSearch Dashboards provides the browser-based search and visualization
interface for Net Sec Watch. Its image is pinned to version 3.7.0 to match the
OpenSearch cluster.

## Start the secured interface

Initialize private configuration and start the stack:

```bash
make init
make up-dashboards-secure
```

Open <https://127.0.0.1:5601> and sign in with:

- username: `admin`
- password: the `OPENSEARCH_INITIAL_ADMIN_PASSWORD` value in the ignored
  `.env` file

For step-by-step query syntax, investigation scenarios, freshness checks, and
evidence handling, use the
[analyst query and investigation guide](phase-5-analyst-workflows.md).
Target-user validation follows the
[Phase 5 usability test plan](phase-5-usability-test-plan.md).
The NFR-03 response-time gate follows the
[seven-day search performance procedure](phase-5-search-performance.md).
Export and clean-restore verification follow the
[saved-object reproducibility procedure](phase-5-saved-object-reproducibility.md).

Startup idempotently imports these approved data views:

| Data view | Index pattern | Time field |
| --- | --- | --- |
| Application | `net-sec-watch-application-*` | `@timestamp` |
| System | `net-sec-watch-system-*` | `@timestamp` |
| Network | `net-sec-watch-network-*` | `@timestamp` |
| Dead letter | `net-sec-watch-dead-letter-*` | `@timestamp` |

Stable saved-object IDs allow the views to be updated and exported
reproducibly. Re-running startup overwrites the managed definitions without
creating duplicates.

## Search examples

In **Discover**, select the relevant data view, set the query language to DQL,
choose a time range, and enter one of these examples.

| Investigation | Data view | DQL query |
| --- | --- | --- |
| Free-text error search | Application | `error` |
| Exact phrase | Application | `message: "connection refused"` |
| Failed authentication | System | `event.action: authentication AND event.outcome: failure` |
| High-severity events | System | `event.severity >= 7` |
| Traffic from one source | Network | `source.ip: "192.168.1.50"` |
| DNS name prefix | Network | `dns.question.name: "*.example.test"` |
| Web traffic to sensitive paths | Network | `http.request.method: "POST" AND url.path: "/admin*"` |
| Possible scanning | Network | `destination.port >= 1 AND destination.port <= 1024 AND source.ip: *` |
| Parser failures | Dead letter | `error.type: parsing_error` |
| Events missing a host name | Any approved view | `NOT host.name: *` |

Fielded string values are quoted, even when a value currently contains no
spaces. Use uppercase `AND`, `OR`, and `NOT` to make analyst intent obvious.
The time picker is the preferred way to constrain `@timestamp`; this keeps the
query reusable across investigations.

The versioned machine-readable catalog is stored in
`config/dashboards/search-examples-v1.json`. Repository checks ensure each
referenced field exists in the canonical OpenSearch mapping and each data-view
identifier is approved.

## Saved investigations

Bootstrap imports four managed saved searches:

| Saved search | Data view | Purpose |
| --- | --- | --- |
| Net Sec Watch - Authentication Failures | System | Review failed authentication activity by host and source |
| Net Sec Watch - Parser Failures | Dead letter | Diagnose malformed or unsupported records |
| Net Sec Watch - Suspicious Network Activity | Network | Triage warnings, denied traffic, and high-severity network events |
| Net Sec Watch - Application Errors | Application | Investigate error-level application events |

Each search uses DQL, sorts newest events first, selects investigation-specific
normalized fields, and includes `event.original`. The searches intentionally
inherit the active Discover time picker instead of embedding a fixed date
range.

Definitions are stored in
`config/dashboards/saved-searches-v1.ndjson` with stable IDs and explicit
references to the managed data views. Startup imports them with overwrite
enabled, making updates reproducible without creating duplicates.

## Investigation dashboards

Bootstrap imports four dashboards:

| Dashboard | Panels |
| --- | --- |
| Net Sec Watch - Infrastructure | Authentication failures and parser failures |
| Net Sec Watch - Application | Application errors |
| Net Sec Watch - Network | Suspicious network activity |
| Net Sec Watch - Security | Authentication failures, suspicious network activity, and parser failures |

Panels embed the versioned saved investigations, inherit the active time
picker, and support direct drill-down into Discover. Empty panels are valid
when no event currently matches the investigation query.

Definitions are stored in `config/dashboards/dashboards-v1.ndjson`. Stable
dashboard IDs, panel references, and grid positions make imports reproducible
and allow the complete analyst experience to be exported or restored.

## Empty, delayed, and error states

Every managed dashboard includes an analyst-state guide:

- **No matching events:** the query completed successfully but found nothing
  in the selected time range. Broaden the time picker or remove filters.
- **Delayed ingestion:** the newest event is older than the approved freshness
  threshold. Treat dashboard results as incomplete and inspect collection.
- **Query error:** Dashboards displays an error banner or failed panel. Review
  DQL syntax, field names, permissions, and OpenSearch health before changing
  the investigation conclusion.

Check stream freshness from the repository without opening containers:

```bash
export OPENSEARCH_PASSWORD='<password-from-.env>'
make ingestion-status
```

The command reports `current`, `empty`, `delayed`, or `query_error` for every
approved log class. It defaults to the `development` environment and a
five-minute freshness threshold. Use `--environment`, `--max-age-seconds`, and
`--json` for automation.

An empty stream means OpenSearch has no events for that class and environment;
it is distinct from a valid dashboard query that happens to return no matches.
The command exits nonzero for delayed or query-error states so monitoring can
consume it. Empty streams are reported clearly but do not fail a fresh
installation.

## Bounded evidence export

Export a selected time range from an approved stream as CSV or JSON Lines:

```bash
export OPENSEARCH_PASSWORD='<password-from-.env>'

./scripts/export-events.py \
  --stream network \
  --start 2026-06-22T00:00:00Z \
  --end 2026-06-23T00:00:00Z \
  --query 'event.action: dropped' \
  --format csv \
  --output network-drops.csv \
  --insecure
```

The exporter accepts only `application`, `system`, `network`, or `dead-letter`
streams. Every request requires explicit UTC start and end timestamps. The
default limit is 1,000 rows, the hard maximum is 5,000 rows, and the maximum
time range is seven days.

Use `--fields` to select mapped fields. The defaults include `@timestamp`,
normalized investigation context, `message`, and `event.original`. CSV values
beginning with spreadsheet formula characters are prefixed with an apostrophe
to prevent formula execution when evidence is opened in office software.

The endpoint defaults to `https://127.0.0.1:9200`. Set `OPENSEARCH_USERNAME`
and `OPENSEARCH_PASSWORD` through the environment; credentials are never
written into the export. `--insecure` is intended only for the local demo
certificate.

## Discover investigation behavior

Bootstrap applies consistent defaults from
`config/dashboards/discover-settings-v1.json`:

- default time range: previous 24 hours through now;
- automatic refresh: paused, preventing surprise query load;
- target histogram density: 50 time buckets;
- maximum displayed sample: 500 events;
- timestamp column: visible in the event table.

The default event table displays:

- `message`;
- `event.dataset`, `event.action`, and `event.outcome`;
- `source.ip` and `destination.ip`;
- `host.name`;
- `event.original`.

Fields that do not apply to a particular event remain empty. Analysts can add,
remove, or reorder columns for an investigation without changing indexed data.
`event.original` is the immutable source record captured before normalization;
compare it with normalized fields when validating parser behavior or preserving
evidence.

Analysts can override the time range or refresh interval for an individual
investigation. Prefer relative ranges such as **Last 15 minutes**, **Last 24
hours**, or **Last 7 days** for repeatable operational work. Use absolute start
and end times when preserving incident evidence.

The Discover histogram groups matching events over `@timestamp`. Drag across a
histogram interval to narrow the time range, or use the time picker to enter an
exact range.

To create a structured filter:

1. Select **Add filter**.
2. Choose a normalized field such as `source.ip`, `event.action`, or
   `log.level`.
3. Select an operator and value.
4. Pin the filter only when it should follow the analyst between views.
5. Disable a filter to compare results without deleting the investigation
   context.

Click the expand control beside an event to inspect the normalized field table
and JSON representation. The expanded view exposes all mapped normalized
fields plus `event.original`, even when they are not table columns. Use the
field-table actions to include or exclude a value as a filter. Expansion does
not alter the indexed event.

Follow startup logs with:

```bash
make logs-dashboards
```

Stop the secured stack with:

```bash
make down-opensearch-secure
```

## Local security boundary

The browser port binds to `127.0.0.1` by default and serves HTTPS using the
ignored local Dashboards certificate. Dashboards connects to OpenSearch using
HTTPS and the built-in `kibanaserver` service identity. The demo OpenSearch
certificate is not verified in this development deployment.

Do not expose port 5601 to a LAN or the internet. Centralized identity,
role-based access, and production certificate verification remain Phase 6
objectives.

## Unsecured development mode

For isolated local development, start Dashboards against the intentionally
unsecured OpenSearch profile:

```bash
make up-dashboards
```

This mode disables both OpenSearch security plugins and remains localhost-only.
Use the secured command for ingestion and analyst testing.

## Verification

Run the isolated secured deployment smoke test:

```bash
make test-opensearch-dashboards
```

The test starts a disposable secured cluster and Dashboards container, waits
for the authenticated Dashboards status API to report `available`, confirms the
browser login page is reachable, verifies all four managed data views, and
removes the test volumes. An unauthenticated status request is rejected by the
secured deployment.
