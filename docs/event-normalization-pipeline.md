# Event normalization pipeline

Every accepted event passes through source parsing, source-specific enrichment,
and a final canonical normalization filter.

Structured inputs retain their exact source line in `event.original` before
JSON or Docker parsing. Plain text and system records copy their raw `log`
value. Syslog retains the best available reconstructed wire representation
because the Fluent Bit syslog input parses the datagram before filters run.

The canonical filter adds:

- schema and parser versions;
- `@timestamp`, `event.observed`, `event.ingested`, and source timezone;
- timestamp inference and collector/source clock-skew indicators;
- normalized OpenTelemetry severity number and source severity text;
- dataset, host, service, device, environment, site, and collector metadata.

`@timestamp` uses an explicit source timestamp when one is available. Epoch
timestamps are treated as UTC. ISO 8601 offsets are preserved in
`event.timezone` and converted to UTC. If no trustworthy source timestamp is
available, the Fluent Bit event timestamp is used and
`event.timestamp_inferred` is `true`.

Clock skew is `event.observed - @timestamp` in seconds. Large positive or
negative values are evidence for investigation; normalization does not silently
replace the source time.

Syslog severity is mapped to OpenTelemetry severity numbers while preserving
`log.syslog.severity.code` and `log.syslog.severity.name`. Text levels are
normalized to lowercase in `log.level`.

Deployment metadata is configured through ignored `.env` values:

```dotenv
COLLECTOR_NAME=net-sec-watch-fluent-bit
SITE_NAME=default
```

Source-provided `service`, `host`, `environment`, and observer names map to
`service.name`, `host.name`, `deployment.environment.name`, and `device.name`.
