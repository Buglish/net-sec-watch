#!/usr/bin/env python3
import importlib.util
import unittest
from datetime import datetime, timezone
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]
SPEC = importlib.util.spec_from_file_location(
    "search_performance",
    ROOT / "scripts/benchmark-seven-day-searches.py",
)
BENCHMARK = importlib.util.module_from_spec(SPEC)
SPEC.loader.exec_module(BENCHMARK)


class SearchPerformanceTest(unittest.TestCase):
    def setUp(self):
        self.config = BENCHMARK.load_json(BENCHMARK.DEFAULT_CONFIG)
        self.searches = BENCHMARK.load_searches()

    def result(
        self, stream, success=100.0, p95=0.25, errors=None
    ):
        return {
            "stream": stream,
            "errors": errors or [],
            "success_percent": success,
            "p95_seconds": p95,
        }

    def test_catalog_covers_every_managed_saved_search(self):
        self.assertEqual(len(self.searches), 4)
        self.assertEqual(
            {item["stream"] for item in self.searches},
            {"application", "system", "network", "dead-letter"},
        )
        self.assertTrue(all(item["query"] for item in self.searches))

    def test_query_is_bounded_to_seven_days_and_first_page(self):
        end = datetime(2026, 6, 23, tzinfo=timezone.utc)
        start, end = BENCHMARK.time_range(
            end, self.config["window_days"]
        )
        body = BENCHMARK.search_query(
            self.searches[0],
            start,
            end,
            self.config["first_page_size"],
        )
        self.assertEqual(body["size"], 50)
        self.assertFalse(body["track_total_hits"])
        date_range = body["query"]["bool"]["filter"][0]["range"]["@timestamp"]
        self.assertEqual(date_range["gte"], "2026-06-16T00:00:00Z")
        self.assertEqual(date_range["lt"], "2026-06-23T00:00:00Z")
        self.assertEqual(body["sort"][0]["@timestamp"]["order"], "desc")

    def test_gate_requires_design_load_and_every_query(self):
        minimum = self.config["design_load"]["minimum_total_documents"]
        counts = {
            "application": minimum - 3000,
            "system": 1000,
            "network": 1000,
            "dead-letter": 1000,
        }
        passing = [
            self.result(search["stream"]) for search in self.searches
        ]
        self.assertTrue(
            BENCHMARK.evaluate(self.config, counts, {}, passing)
        )

        too_small = dict(counts)
        too_small["dead-letter"] = 999
        self.assertFalse(
            BENCHMARK.evaluate(self.config, too_small, {}, passing)
        )

        missing_stream = dict(counts)
        del missing_stream["dead-letter"]
        self.assertFalse(
            BENCHMARK.evaluate(self.config, missing_stream, {}, passing)
        )

        slow = list(passing)
        slow[0] = self.result(
            self.searches[0]["stream"], success=95.0, p95=3.01
        )
        self.assertFalse(
            BENCHMARK.evaluate(self.config, counts, {}, slow)
        )

        errored = list(passing)
        errored[0] = self.result(
            self.searches[0]["stream"], errors=["timeout"]
        )
        self.assertFalse(
            BENCHMARK.evaluate(self.config, counts, {}, errored)
        )

        no_latency = list(passing)
        no_latency[0] = self.result(self.searches[0]["stream"])
        no_latency[0]["p95_seconds"] = None
        self.assertFalse(
            BENCHMARK.evaluate(self.config, counts, {}, no_latency)
        )

    def test_reference_load_matches_seven_days_at_100_eps(self):
        design = self.config["design_load"]
        expected = (
            design["events_per_second"]
            * self.config["window_days"]
            * 24 * 60 * 60
        )
        self.assertEqual(design["minimum_total_documents"], expected)
        self.assertEqual(self.config["response_time_seconds"], 3.0)
        self.assertEqual(self.config["required_percent"], 95.0)


if __name__ == "__main__":
    unittest.main()
