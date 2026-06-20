# Mapping explosion protection

Untrusted JSON can create thousands of unique field names and exhaust
OpenSearch mapping resources. Net Sec Watch uses two layers of protection.

The collector rejects an event to `pipeline.deadletter` when it exceeds:

- 128 total fields, including nested fields and array entries;
- eight levels of nesting;
- 128 characters in a field name.

Rejected events retain `event.original` and receive
`error.type=mapping_guard_error`, `error.stage=schema_guard`, and a bounded
reason in `error.message`. Limits are defined in
`config/schema/mapping-policy-v1.json` and contract-tested against the
collector implementation.

Phase 4 OpenSearch templates must use explicit canonical mappings with
`dynamic: false`. Source-native fields remain in `_source` for evidence but
are not dynamically indexed. The template must also set conservative total
field, nesting, and field-name limits from the mapping policy.

Adding a searchable field requires:

1. documenting its stable meaning and type;
2. adding it to the canonical schema or an approved source mapping;
3. updating the OpenSearch template and schema contract tests;
4. versioning the parser when its output changes.

Operators should monitor `mapping_guard_error` volume. A sudden increase can
indicate a source upgrade, parser regression, or deliberate field-flooding
attempt.
