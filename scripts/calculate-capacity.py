#!/usr/bin/env python3
"""Calculate Net Sec Watch OpenSearch storage and node capacity."""

import argparse
import json
import math
from pathlib import Path


ROOT = Path(__file__).resolve().parents[1]
DEFAULT_CONFIG = ROOT / "config/opensearch/capacity-planning-v1.json"
SECONDS_PER_DAY = 86_400
DECIMAL_GB = 1_000_000_000


def positive(value):
    number = float(value)
    if number <= 0:
        raise argparse.ArgumentTypeError("value must be greater than zero")
    return number


def non_negative_integer(value):
    number = int(value)
    if number < 0:
        raise argparse.ArgumentTypeError("value must be zero or greater")
    return number


def load_config(path):
    return json.loads(Path(path).read_text(encoding="utf-8"))


def calculate(config, args):
    measurement = config["measurement"]
    storage = config["storage"]
    topology = config["topology"]

    raw_bytes_per_event = (
        args.raw_bytes_per_event
        if args.raw_bytes_per_event is not None
        else measurement["average_raw_bytes_per_event"]
    )
    measured_ratio = (
        args.primary_store_ratio
        if args.primary_store_ratio is not None
        else measurement["measured_primary_store_ratio"]
    )
    planning_ratio = max(
        measured_ratio * measurement["ratio_safety_multiplier"],
        measurement["minimum_planning_ratio"],
    )
    retention_days = args.retention_days or storage["default_retention_days"]
    replicas = (
        args.replicas
        if args.replicas is not None
        else storage["default_replicas"]
    )
    active_streams = args.active_streams or topology["default_active_streams"]
    snapshot_equivalents = (
        args.snapshot_full_equivalents
        if args.snapshot_full_equivalents is not None
        else storage["default_snapshot_full_equivalents"]
    )

    events_per_day = args.events_per_second * SECONDS_PER_DAY
    raw_daily_bytes = events_per_day * raw_bytes_per_event
    primary_daily_bytes = raw_daily_bytes * planning_ratio
    primary_retained_bytes = primary_daily_bytes * retention_days
    live_shard_bytes = primary_retained_bytes * (1 + replicas)
    provisioned_live_bytes = (
        live_shard_bytes / storage["target_disk_utilization"]
    )
    snapshot_bytes = primary_retained_bytes * snapshot_equivalents
    total_local_bytes = provisioned_live_bytes + snapshot_bytes

    rollover_bytes = storage["rollover_size_gb"] * DECIMAL_GB
    size_primary_shards = math.ceil(primary_retained_bytes / rollover_bytes)
    age_primary_shards = active_streams * retention_days
    primary_shards = max(size_primary_shards, age_primary_shards)
    total_shards = primary_shards * (1 + replicas)

    usable_node_bytes = (
        args.data_node_disk_gb
        * DECIMAL_GB
        * storage["target_disk_utilization"]
    )
    nodes_by_disk = math.ceil(live_shard_bytes / usable_node_bytes)
    nodes_by_shards = math.ceil(
        total_shards / topology["maximum_shards_per_data_node"]
    )
    required_data_nodes = max(
        nodes_by_disk,
        nodes_by_shards,
        topology["minimum_production_data_nodes"],
    )

    return {
        "inputs": {
            "events_per_second": args.events_per_second,
            "raw_bytes_per_event": raw_bytes_per_event,
            "measured_primary_store_ratio": measured_ratio,
            "planning_primary_store_ratio": planning_ratio,
            "retention_days": retention_days,
            "replicas": replicas,
            "active_streams": active_streams,
            "data_node_disk_gb": args.data_node_disk_gb,
            "snapshot_full_equivalents": snapshot_equivalents,
        },
        "daily": {
            "events": events_per_day,
            "raw_bytes": raw_daily_bytes,
            "primary_index_bytes": primary_daily_bytes,
        },
        "retention": {
            "primary_index_bytes": primary_retained_bytes,
            "live_bytes_with_replicas": live_shard_bytes,
            "provisioned_live_bytes": provisioned_live_bytes,
            "snapshot_bytes": snapshot_bytes,
            "total_local_bytes": total_local_bytes,
        },
        "shards": {
            "primary_by_size": size_primary_shards,
            "primary_by_age_floor": age_primary_shards,
            "primary": primary_shards,
            "total_with_replicas": total_shards,
        },
        "nodes": {
            "by_disk": nodes_by_disk,
            "by_shards": nodes_by_shards,
            "minimum_production": topology["minimum_production_data_nodes"],
            "required_data_nodes": required_data_nodes,
        },
    }


def gibibytes(value):
    return value / (1024**3)


def print_text(result):
    inputs = result["inputs"]
    daily = result["daily"]
    retention = result["retention"]
    shards = result["shards"]
    nodes = result["nodes"]
    print(f"events_per_second={inputs['events_per_second']:.2f}")
    print(f"events_per_day={daily['events']:.0f}")
    print(
        "planning_primary_store_ratio="
        f"{inputs['planning_primary_store_ratio']:.4f}"
    )
    print(f"raw_daily_gib={gibibytes(daily['raw_bytes']):.2f}")
    print(
        "primary_index_daily_gib="
        f"{gibibytes(daily['primary_index_bytes']):.2f}"
    )
    print(
        "live_with_replicas_gib="
        f"{gibibytes(retention['live_bytes_with_replicas']):.2f}"
    )
    print(
        "provisioned_live_gib="
        f"{gibibytes(retention['provisioned_live_bytes']):.2f}"
    )
    print(f"snapshot_gib={gibibytes(retention['snapshot_bytes']):.2f}")
    print(
        "total_local_gib="
        f"{gibibytes(retention['total_local_bytes']):.2f}"
    )
    print(f"primary_shards={shards['primary']}")
    print(f"total_shards_with_replicas={shards['total_with_replicas']}")
    print(f"nodes_by_disk={nodes['by_disk']}")
    print(f"nodes_by_shards={nodes['by_shards']}")
    print(f"required_data_nodes={nodes['required_data_nodes']}")


def parser():
    command = argparse.ArgumentParser(description=__doc__)
    command.add_argument("--config", default=DEFAULT_CONFIG)
    command.add_argument("--events-per-second", type=positive, default=100.0)
    command.add_argument("--retention-days", type=int)
    command.add_argument("--replicas", type=non_negative_integer)
    command.add_argument("--active-streams", type=int)
    command.add_argument("--data-node-disk-gb", type=positive, default=1000.0)
    command.add_argument("--raw-bytes-per-event", type=positive)
    command.add_argument("--primary-store-ratio", type=positive)
    command.add_argument("--snapshot-full-equivalents", type=float)
    command.add_argument("--json", action="store_true")
    return command


def main():
    args = parser().parse_args()
    for name in ("retention_days", "active_streams"):
        value = getattr(args, name)
        if value is not None and value <= 0:
            raise SystemExit(f"{name.replace('_', '-')} must be greater than zero")
    if (
        args.snapshot_full_equivalents is not None
        and args.snapshot_full_equivalents < 0
    ):
        raise SystemExit("snapshot-full-equivalents must be zero or greater")

    result = calculate(load_config(args.config), args)
    if args.json:
        print(json.dumps(result, indent=2, sort_keys=True))
    else:
        print_text(result)


if __name__ == "__main__":
    main()
