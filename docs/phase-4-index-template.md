# OpenSearch index template and mappings

The secure OpenSearch profile installs
`config/opensearch/index-template-v1.json` before Fluent Bit starts.
`opensearch-bootstrap` is a one-shot service, and Fluent Bit waits for it to
complete successfully. This prevents early documents from creating accidental
dynamic mappings.

The template applies to `net-sec-watch-*-*` data streams and defines:

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

## Data-stream routing

Fluent Bit routes normalized records into data streams named:

`net-sec-watch-<log-class>-<environment>`

The committed routes are:

| Log class | Fluent Bit tags | Example development stream |
| --- | --- | --- |
| `application` | `file.*`, `container.*` | `net-sec-watch-application-development` |
| `system` | `host.*` | `net-sec-watch-system-development` |
| `network` | `sensor.*`, `net.*` | `net-sec-watch-network-development` |
| `dead-letter` | `pipeline.*` | `net-sec-watch-dead-letter-development` |

Set `DEPLOYMENT_ENVIRONMENT` in the ignored `.env` file to a lowercase,
hyphen-safe environment name such as `development`, `test`, or `production`.
The detailed source and record type remain in `event.dataset`; they are not
encoded into the stream name, which avoids unbounded stream creation.

Parser and schema failures use the dedicated `dead-letter` class. They are
excluded from their normal source stream while preserving `event.original`,
the intended source dataset, and a bounded error reason for investigation and
safe reprocessing.

Data streams require create-only writes, so every Fluent Bit OpenSearch output
uses `Write_Operation create` and generated document IDs. OpenSearch owns the
hidden backing-index names and future rollover generations.

## Rollover policy

The bootstrap installs the `net-sec-watch-rollover-v1` Index State Management
policy from `config/opensearch/rollover-policy-v1.json` before installing the
data-stream template. The policy automatically applies to Net Sec Watch backing
indexes and rolls the write index when either threshold is reached:

- backing-index age of 24 hours;
- backing-index size of 20 GB.

These limits bound shard size and the time range affected by recovery or
reindexing. Each stream currently has one primary shard, so backing-index size
and primary-shard size are equivalent. They do not delete data. Retention and
hot/warm/archive transitions are separate lifecycle tasks so they can be
reviewed without changing the rollover safety boundary.

Run `make test-opensearch-secure` to verify that the installed policy contains
both thresholds and that OpenSearch accepts those conditions for a dry-run
rollover of a real Net Sec Watch data stream.

## Retention lifecycle

The same ISM policy moves each rolled backing index through these states:

| State | Index age | Action |
| --- | ---: | --- |
| `hot` | 0–7 days | Accept writes and roll over at 24 hours or 20 GB. |
| `warm` | 7–30 days | Force-merge each shard to one segment. |
| `archive` | 30–90 days | Mark the backing index read-only. |
| `delete` | 90 days | Permanently delete the backing index. |

Transitions use backing-index age, measured from index creation. The hot state
does not transition until its rollover action has completed, so the active
data-stream write index remains writable.

The archive state is compact, read-only storage on the OpenSearch cluster. It
is not a backup and does not replace snapshots. Snapshot-backed recovery and
off-cluster archive storage are configured and tested in later Phase 4 tasks.

Changing these retention periods affects evidence availability and storage
cost. Production changes should be reviewed against legal, contractual, and
incident-response retention requirements.

## Replicas and disk protection

Each data-stream backing index starts with one primary shard and zero replicas
on the single-node development cluster. `index.auto_expand_replicas` is set to
`0-1`, so OpenSearch automatically creates one replica when another eligible
data node joins. A production cluster should have at least two data nodes
before relying on this replica for availability.

The bootstrap installs persistent disk-allocation safeguards:

| Watermark | Disk used | OpenSearch behavior |
| --- | ---: | --- |
| Low | 75% | Avoid allocating more shards to the node. |
| High | 85% | Relocate shards away from the node where possible. |
| Flood stage | 90% | Protect affected indexes with a read-only block. |

OpenSearch refreshes disk information every 30 seconds. Operators should alert
well before the low watermark; the watermarks are emergency protections, not a
capacity-planning substitute. On a single-node cluster, relocation is
impossible, so additional disk space or another data node must be supplied
before the flood stage is reached.

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
