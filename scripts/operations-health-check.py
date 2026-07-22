#!/usr/bin/env python3
"""Validate operations operations configuration."""

from __future__ import annotations

import argparse
import json
from pathlib import Path


ROOT = Path(__file__).resolve().parents[1]


def load_json(path: str):
    return json.loads((ROOT / path).read_text(encoding="utf-8"))


def check_config() -> None:
    thresholds = load_json("config/operations/monitoring-thresholds-v1.json")
    alerts = load_json("config/operations/alert-rules-v1.json")
    service_levels = load_json("config/operations/service-levels-v1.json")

    required_metrics = {
        "collector_events_accepted",
        "collector_events_dropped",
        "collector_events_retried",
        "collector_events_buffered",
        "collector_events_failed",
        "collector_silence",
        "source_volume_change",
        "queue_depth",
        "rejected_writes",
        "shard_health",
        "disk_watermark",
        "snapshot_failure",
        "certificate_expiry",
    }
    missing = required_metrics - set(thresholds["metrics"])
    if missing:
        raise SystemExit(f"missing monitoring thresholds: {sorted(missing)}")

    alert_signals = {alert["signal"] for alert in alerts["alerts"]}
    missing_alerts = {
        "collector_events_dropped",
        "collector_events_retried",
        "collector_events_buffered",
        "collector_silence",
        "source_volume_change",
        "rejected_writes",
        "shard_health",
        "disk_watermark",
        "snapshot_failure",
        "certificate_expiry",
    } - alert_signals
    if missing_alerts:
        raise SystemExit(f"missing alert coverage: {sorted(missing_alerts)}")

    if service_levels["targets"]["load_test_multiplier"] < 1.5:
        raise SystemExit("load-test multiplier must be at least 1.5")
    if "rto" not in service_levels["targets"]:
        raise SystemExit("RTO target is missing")
    if "rpo" not in service_levels["targets"]:
        raise SystemExit("RPO target is missing")


def main() -> None:
    parser = argparse.ArgumentParser()
    parser.add_argument("--check-config", action="store_true")
    args = parser.parse_args()
    if args.check_config:
        check_config()
        print("operations operations configuration is valid.")
    else:
        parser.print_help()


if __name__ == "__main__":
    main()
