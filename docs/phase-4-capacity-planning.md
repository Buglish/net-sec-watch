# OpenSearch capacity planning

Capacity planning uses the measured event size and primary-store ratio from
`docs/phase-4-storage-expansion.md`, with conservative safety limits defined in
`config/opensearch/capacity-planning-v1.json`.

Run the default example:

```bash
make capacity-plan
```

Or calculate a specific workload:

```bash
./scripts/calculate-capacity.py \
  --events-per-second 250 \
  --retention-days 90 \
  --replicas 1 \
  --active-streams 5 \
  --data-node-disk-gb 2000
```

Use `--json` for machine-readable output.

## Formulas

Let:

- `E` = events per second;
- `B` = average compact raw bytes per event;
- `R` = conservative primary-store ratio;
- `D` = retention days;
- `N` = replica count;
- `U` = planned disk utilization;
- `S` = snapshot full-data equivalents retained.

The calculator uses:

```text
events_per_day = E × 86,400
raw_daily_bytes = events_per_day × B
primary_daily_bytes = raw_daily_bytes × R
primary_retained_bytes = primary_daily_bytes × D
live_bytes_with_replicas = primary_retained_bytes × (1 + N)
provisioned_live_bytes = live_bytes_with_replicas ÷ U
snapshot_bytes = primary_retained_bytes × S
total_local_bytes = provisioned_live_bytes + snapshot_bytes
```

The planning ratio is the greater of `1.0` or the measured `0.6057×` ratio
multiplied by `1.5`. This currently produces `R = 1.0`, deliberately avoiding a
capacity plan that depends on synthetic compression continuing in production.

## Shards and data nodes

Primary shard count is the greater of:

```text
ceil(primary_retained_bytes ÷ 20 GB)
active_streams × retention_days
```

The second term accounts for daily age-based rollover even when streams are
small. Total open shards include replicas.

Required data nodes are the greatest of:

- nodes needed to keep live shard data below 70% of node disk;
- nodes needed to remain below 600 open shards per data node;
- two production data nodes.

The default 100 EPS example with 90-day retention, one replica, five active
streams, and 1 TB data-node disks requires approximately:

| Output | Value |
| --- | ---: |
| Events per day | 8,640,000 |
| Raw daily data | 4.51 GiB |
| Primary indexed daily data | 4.51 GiB |
| Provisioned live storage | 1,161 GiB |
| Snapshot allowance | 406 GiB |
| Total local storage | 1,567 GiB |
| Primary shards | 450 |
| Total shards with replica | 900 |
| Required data nodes | 2 |

## Scaling thresholds

Treat these as operational triggers, not failure limits:

| Signal | Scale or investigate when |
| --- | --- |
| Disk | Forecast reaches 70%; low watermark is 75%. |
| Shards | Forecast exceeds 600 open shards per data node. |
| Heap | Sustained JVM heap use exceeds 75%. |
| CPU | Sustained data-node CPU exceeds 70% during normal load. |
| Ingestion | Fewer than 95% of accepted events are searchable within 10 seconds. |
| Backpressure | Fluent Bit retries or filesystem backlog grow continuously. |
| Recovery | Snapshot or shard recovery cannot finish inside the required recovery window. |

Scale vertically only while enough disk, heap, and recovery margin remain.
Add data nodes when disk or shard-driven node counts increase, and keep at
least one failure domain beyond the minimum needed for current load. Re-run the
storage benchmark after mapping, parser, OpenSearch, or representative event
mix changes.
