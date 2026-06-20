# Network event correlation and duplicate observations

ASUS firewall logs, Zeek metadata, and Suricata EVE events can describe the
same connection. Net Sec Watch preserves each source record because the
records provide different evidence; it does not discard them as byte-for-byte
duplicates.

After source-specific parsing, the collector adds these common fields:

- `event.schema_version`: version of the shared network schema.
- `event.parser_version`: version of the source parser.
- `event.observation_id`: source-specific identity for the observation.
- `event.correlation_key`: transport, source endpoint, destination endpoint,
  and five-minute collector-ingest-time bucket.
- `event.correlation_time_basis`: `collector_ingest_time`.
- `event.deduplication.strategy`: `correlate-preserve`.
- `event.deduplication.window_seconds`: the correlation window.

Detections and dashboards should group records by `event.correlation_key` when
building an incident or connection view. They should retain
`event.observation_id` and `event.dataset` so an analyst can see which devices
and sensors supplied evidence.

The correlation key is intentionally transparent and deterministic. It is not
an event identifier, and two records sharing it are related observations—not
proof that their payloads are identical. NAT, asymmetric routing, missing
ports, or delivery outside the five-minute window can prevent otherwise
related records from sharing a key. Collector ingest time is used because RFC
3164 syslog does not carry a timezone and embedded device clocks may differ.
Original source timestamps remain available for analysis. Later storage and
detection phases may add Community ID or source-specific correlation where
available.
