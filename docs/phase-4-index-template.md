# OpenSearch index template and mappings

The secure OpenSearch profile installs
`config/opensearch/index-template-v1.json` before Fluent Bit starts.
`opensearch-bootstrap` is a one-shot service, and Fluent Bit waits for it to
complete successfully. This prevents early documents from creating accidental
dynamic mappings.

The template applies to `net-sec-watch-*` indexes and defines:

- UTC event and observation timestamps as `date`;
- source and destination addresses as `ip`;
- ports, byte counts, packet counts, and severity values as numeric fields;
- identifiers, datasets, actions, protocols, and metadata as `keyword`;
- analyst-facing messages as `text`;
- URL paths as `wildcard`;
- explicit DNS, HTTP, TLS, rule, error, device, and collector objects.

Dynamic mapping is disabled. Unknown source-native fields remain in `_source`
for evidence and future reprocessing, but OpenSearch does not index them or add
them to the field mapping.

## Updating the template

Mapping changes must:

1. agree with `config/schema/canonical-event-schema-v1.json`;
2. preserve existing field types within a schema major version;
3. increment the template `version`;
4. update `_meta.schema_version` when the canonical schema changes;
5. pass `make check` and `make test-opensearch-secure`.

Existing field types cannot be changed in place. A breaking mapping change
requires a new index or data stream generation and a controlled reindex or
dual-write migration.
