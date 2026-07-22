# OpenSearch storage-expansion measurement

Net Sec Watch measures the relationship between compact normalized event JSON
and the primary OpenSearch store created from those events.

Run the reproducible benchmark with:

```bash
make measure-opensearch-storage
```

The benchmark:

- generates 12,000 events evenly across application JSON, host system,
  ASUS-style firewall, Zeek DNS, Suricata alert, and Docker container classes;
- writes compact source JSON through the OpenSearch bulk API;
- uses the production explicit mapping and a single primary shard;
- excludes bulk action metadata and replicas from byte counts;
- flushes and force-merges the backing index to one segment;
- reports primary store bytes and the raw-to-indexed ratio;
- runs in an isolated Compose project and removes all benchmark volumes.

Override the sample count with `STORAGE_BENCHMARK_DOCUMENTS`. The value must be
at least 600 and divisible by six.

## Baseline

Baseline measured on June 21, 2026 using the pinned
`opensearchproject/opensearch:3.7.0` image:

| Measurement | Result |
| --- | ---: |
| Documents | 12,000 |
| Raw compact JSON | 6,731,923 bytes |
| Primary indexed store | 4,077,258 bytes |
| Raw bytes per event | 560.99 bytes |
| Indexed primary bytes per event | 339.77 bytes |
| Primary-store ratio | 0.6057× |

Each of the six datasets contributed 2,000 documents. The ratio below 1.0
reflects Lucene compression, repeated field names and values, force-merging,
and the explicit mapping policy, which retains unknown fields in `_source`
without dynamically indexing them.

This result excludes replicas, translog, snapshots, container filesystem
overhead, and free-space safety margins. With one replica, the indexed shard
store component is approximately doubled before those additional allowances.

Results vary with event mix, field cardinality, segment merging,
OpenSearch/Lucene versions, and document count. Small samples overstate storage
because fixed segment metadata is amortized over fewer events. Capacity plans
should rerun this benchmark using representative production events and use a
conservative ratio rather than assuming this synthetic baseline will hold.
