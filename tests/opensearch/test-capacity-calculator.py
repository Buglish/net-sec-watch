#!/usr/bin/env python3
import argparse
import importlib.util
import json
import sys
import unittest
from pathlib import Path


sys.dont_write_bytecode = True
ROOT = Path(__file__).resolve().parents[2]
SCRIPT = ROOT / "scripts/calculate-capacity.py"
SPEC = importlib.util.spec_from_file_location("capacity", SCRIPT)
capacity = importlib.util.module_from_spec(SPEC)
SPEC.loader.exec_module(capacity)


class CapacityCalculatorTest(unittest.TestCase):
    def setUp(self):
        self.config = capacity.load_config(capacity.DEFAULT_CONFIG)

    def args(self, **overrides):
        values = {
            "events_per_second": 100.0,
            "raw_bytes_per_event": None,
            "primary_store_ratio": None,
            "retention_days": None,
            "replicas": None,
            "active_streams": None,
            "data_node_disk_gb": 1000.0,
            "snapshot_full_equivalents": None,
        }
        values.update(overrides)
        return argparse.Namespace(**values)

    def test_default_example(self):
        result = capacity.calculate(self.config, self.args())
        self.assertEqual(result["daily"]["events"], 8_640_000)
        self.assertEqual(
            result["inputs"]["planning_primary_store_ratio"],
            1.0,
        )
        self.assertEqual(result["shards"]["primary_by_age_floor"], 450)
        self.assertEqual(result["shards"]["primary"], 450)
        self.assertEqual(result["shards"]["total_with_replicas"], 900)
        self.assertEqual(result["nodes"]["by_disk"], 2)
        self.assertEqual(result["nodes"]["by_shards"], 2)
        self.assertEqual(result["nodes"]["required_data_nodes"], 2)

    def test_size_driven_scale(self):
        result = capacity.calculate(
            self.config,
            self.args(events_per_second=5000.0),
        )
        self.assertGreater(
            result["shards"]["primary_by_size"],
            result["shards"]["primary_by_age_floor"],
        )
        self.assertGreater(result["nodes"]["by_disk"], 2)

    def test_configuration_contract(self):
        thresholds = self.config["thresholds"]
        rollover = json.loads(
            (
                ROOT / "config/opensearch/rollover-policy-v1.json"
            ).read_text(encoding="utf-8")
        )
        cluster = json.loads(
            (
                ROOT / "config/opensearch/cluster-settings-v1.json"
            ).read_text(encoding="utf-8")
        )
        rollover_action = rollover["policy"]["states"][0]["actions"][0][
            "rollover"
        ]
        self.assertEqual(
            self.config["storage"]["rollover_size_gb"],
            int(rollover_action["min_size"].removesuffix("gb")),
        )
        self.assertLess(
            thresholds["disk_plan_percent"],
            thresholds["disk_low_watermark_percent"],
        )
        self.assertLess(
            thresholds["disk_low_watermark_percent"],
            thresholds["disk_high_watermark_percent"],
        )
        self.assertLess(
            thresholds["disk_high_watermark_percent"],
            thresholds["disk_flood_stage_percent"],
        )
        persistent = cluster["persistent"]
        self.assertEqual(
            f"{thresholds['disk_low_watermark_percent']}%",
            persistent["cluster.routing.allocation.disk.watermark.low"],
        )
        self.assertEqual(
            f"{thresholds['disk_high_watermark_percent']}%",
            persistent["cluster.routing.allocation.disk.watermark.high"],
        )
        self.assertEqual(
            f"{thresholds['disk_flood_stage_percent']}%",
            persistent[
                "cluster.routing.allocation.disk.watermark.flood_stage"
            ],
        )
        self.assertEqual(thresholds["searchable_within_seconds"], 10)
        self.assertEqual(thresholds["searchable_success_percent"], 95)


if __name__ == "__main__":
    unittest.main()
