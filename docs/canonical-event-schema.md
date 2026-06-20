# Canonical event schema

Net Sec Watch normalizes accepted records to schema version `1.0.0`. The
machine-readable contract is
`config/schema/canonical-event-schema-v1.json`.

## Naming rules

- Use lowercase dotted field names, for example `source.ip`.
- Use singular nouns unless the value is an array.
- Do not encode units in values; include the unit in the field name when the
  field is not covered by a standard convention.
- Keep source-native fields only when they add evidence that has no canonical
  equivalent. They must not overwrite canonical fields.
- Parser-specific changes require a new `event.parser_version`.
- Breaking canonical changes require a new major schema version.

## Required fields

Every normalized event must contain:

| Field | Meaning |
| --- | --- |
| `@timestamp` | Event time normalized to UTC |
| `event.observed` | Time the collector first observed the record |
| `event.dataset` | Stable source and record class, such as `zeek.conn` |
| `event.kind` | High-level record kind |
| `event.original` | Original or best-effort reconstructed source record |
| `event.parser_version` | Parser implementation version |
| `event.schema_version` | Canonical schema version |

If a required value cannot be derived, the record goes to the dead-letter
stream with `event.kind=pipeline_error`, `error.type`, `error.message`, and
`error.stage`. A parser must not invent a security-relevant value merely to
satisfy the schema.

## OpenTelemetry alignment

The schema follows the OpenTelemetry Logs Data Model while keeping field names
suited to JSON and OpenSearch:

| OpenTelemetry concept | Net Sec Watch field |
| --- | --- |
| Timestamp | `@timestamp` |
| ObservedTimestamp | `event.observed` |
| Body | `message` |
| SeverityText | `log.level` |
| SeverityNumber | `log.severity.number` |
| EventName | `event.dataset` |
| Resource attributes | `service.*`, `host.*`, `device.*`, `collector.*` |
| Attributes | Remaining canonical and approved source-native fields |

OpenTelemetry severity numbers use `0` for unspecified and `1` through `24`
from trace through fatal. Original syslog severity remains available under
`log.syslog.severity.*`.

## Security fields

Network and security records use `source.*`, `destination.*`,
`network.transport`, `network.protocol`, `event.action`, `event.outcome`, and
`event.severity`. `event.outcome` is limited to `success`, `failure`, or
`unknown`; it describes the result of the action, not whether the event is
malicious.

## Reserved ML namespace

These fields are reserved now but remain absent until an approved model writes
them:

- `event.classification`
- `event.threat_level`
- `event.threat_score`
- `event.ml_model_id`
- `event.ml_confidence`

The ingestion parser must not populate placeholder values. This prevents
ordinary collection from being mistaken for an ML decision.

## Compatibility and migration

Patch releases clarify documentation or constraints without changing accepted
records. Minor releases add optional fields. Major releases remove fields,
change meaning or type, or add required fields.

During a major migration, producers write the old schema until the new index
template and consumers are ready. A controlled dual-write or reindex migration
then runs for a documented period. Dashboards and detections must declare the
schema major versions they support. Rollback retains the previous parser and
index template until migration acceptance evidence is recorded.

The schema currently permits additional source-native properties. Phase 3
mapping controls will replace that transition allowance with explicit dynamic
templates and field-count limits before OpenSearch production ingestion.
