#!/usr/bin/env python3
import argparse
import csv
import importlib.util
import io
import json
import unittest
from datetime import datetime, timedelta, timezone
from pathlib import Path
from types import SimpleNamespace
from unittest.mock import patch

ROOT = Path(__file__).resolve().parents[2]
SPEC = importlib.util.spec_from_file_location(
    "export_events", ROOT / "scripts/export-events.py"
)
EXPORT = importlib.util.module_from_spec(SPEC)
SPEC.loader.exec_module(EXPORT)


class ExportEventsTest(unittest.TestCase):
    def test_rejects_invalid_bounds(self):
        start = datetime(2026, 6, 1, tzinfo=timezone.utc)
        with self.assertRaises(ValueError):
            EXPORT.validate_range(start, start)
        with self.assertRaises(ValueError):
            EXPORT.validate_range(start, start + timedelta(days=8))

    def test_limit_is_hard_bounded(self):
        self.assertEqual(EXPORT.positive_limit("5000"), 5000)
        with self.assertRaises(argparse.ArgumentTypeError):
            EXPORT.positive_limit("5001")

    def test_default_export_fields_are_mapped(self):
        self.assertLessEqual(
            set(EXPORT.DEFAULT_FIELDS), EXPORT.approved_fields()
        )

    def test_query_has_time_filter_and_approved_source_fields(self):
        args = SimpleNamespace(
            start=datetime(2026, 6, 1, tzinfo=timezone.utc),
            end=datetime(2026, 6, 2, tzinfo=timezone.utc),
            fields=["@timestamp", "event.original"],
            query="event.action: dropped",
        )
        body = EXPORT.build_query(args, 50)
        self.assertEqual(body["size"], 50)
        self.assertEqual(body["_source"], args.fields)
        self.assertEqual(
            body["query"]["bool"]["must"][0]["query_string"]["query"],
            args.query,
        )
        self.assertIn(
            "range", body["query"]["bool"]["filter"][0]
        )

    def test_collect_stops_at_limit_across_pages(self):
        args = SimpleNamespace(
            limit=3,
            fields=["message"],
            query="*",
            start=datetime(2026, 6, 1, tzinfo=timezone.utc),
            end=datetime(2026, 6, 2, tzinfo=timezone.utc),
        )
        pages = [
            {
                "hits": {
                    "hits": [
                        {"_source": {"message": "one"}, "sort": [1, "a"]},
                        {"_source": {"message": "two"}, "sort": [2, "b"]},
                    ]
                }
            },
            {
                "hits": {
                    "hits": [
                        {"_source": {"message": "three"}, "sort": [3, "c"]}
                    ]
                }
            },
        ]
        with patch.object(EXPORT, "PAGE_SIZE", 2), patch.object(
            EXPORT, "request_page", side_effect=pages
        ):
            rows = EXPORT.collect(args)
        self.assertEqual([row["message"] for row in rows], [
            "one", "two", "three"
        ])

    def test_csv_neutralizes_formula_values(self):
        args = SimpleNamespace(
            format="csv", fields=["message", "event.original"]
        )
        output = io.StringIO(newline="")
        EXPORT.write_export(
            args,
            [{"message": "=CMD()", "event": {"original": "+SUM(1,1)"}}],
            output,
        )
        row = next(csv.DictReader(io.StringIO(output.getvalue())))
        self.assertEqual(row["message"], "'=CMD()")
        self.assertEqual(row["event.original"], "'+SUM(1,1)")

    def test_jsonl_contains_only_selected_fields(self):
        args = SimpleNamespace(
            format="jsonl", fields=["@timestamp", "source.ip"]
        )
        output = io.StringIO()
        EXPORT.write_export(
            args,
            [{
                "@timestamp": "2026-06-01T00:00:00Z",
                "source": {"ip": "192.0.2.10"},
                "secret": "excluded",
            }],
            output,
        )
        self.assertEqual(json.loads(output.getvalue()), {
            "@timestamp": "2026-06-01T00:00:00Z",
            "source.ip": "192.0.2.10",
        })


if __name__ == "__main__":
    unittest.main()
