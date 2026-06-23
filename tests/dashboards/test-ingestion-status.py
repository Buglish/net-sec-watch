#!/usr/bin/env python3
import importlib.util
import unittest
from datetime import datetime, timedelta, timezone
from pathlib import Path
from types import SimpleNamespace
from unittest.mock import patch

ROOT = Path(__file__).resolve().parents[2]
SPEC = importlib.util.spec_from_file_location(
    "ingestion_status", ROOT / "scripts/check-ingestion-status.py"
)
STATUS = importlib.util.module_from_spec(SPEC)
SPEC.loader.exec_module(STATUS)


class IngestionStatusTest(unittest.TestCase):
    def setUp(self):
        self.now = datetime(2026, 6, 23, tzinfo=timezone.utc)

    def test_classifies_empty_current_and_delayed(self):
        self.assertEqual(STATUS.classify(None, self.now, 300), ("empty", None))
        state, age = STATUS.classify(
            self.now - timedelta(seconds=60), self.now, 300
        )
        self.assertEqual((state, age), ("current", 60))
        state, age = STATUS.classify(
            self.now - timedelta(seconds=301), self.now, 300
        )
        self.assertEqual((state, age), ("delayed", 301))

    def test_evaluate_isolates_query_errors(self):
        args = SimpleNamespace(max_age_seconds=300)
        values = [
            self.now - timedelta(seconds=10),
            None,
            RuntimeError("bad query"),
            self.now - timedelta(seconds=600),
        ]
        with patch.object(STATUS, "request_latest", side_effect=values):
            results = STATUS.evaluate(args, self.now)
        self.assertEqual(
            [result["state"] for result in results],
            ["current", "empty", "query_error", "delayed"],
        )
        self.assertEqual(results[2]["error"], "bad query")

    def test_timestamp_parser_requires_aware_result(self):
        parsed = STATUS.parse_timestamp("2026-06-23T01:02:03Z")
        self.assertEqual(parsed.tzinfo, timezone.utc)


if __name__ == "__main__":
    unittest.main()
