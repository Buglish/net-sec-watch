#!/usr/bin/env python3
"""Benchmark managed seven-day searches against an OpenSearch design load."""

import argparse
import base64
import json
import math
import os
import ssl
import sys
import time
import urllib.error
import urllib.request
from datetime import datetime, timedelta, timezone
from pathlib import Path

sys.dont_write_bytecode = True

ROOT = Path(__file__).resolve().parents[1]
DEFAULT_CONFIG = ROOT / "config/dashboards/search-performance-v1.json"
DEFAULT_SEARCHES = ROOT / "config/dashboards/saved-searches-v1.ndjson"
VIEW_STREAMS = {
    "net-sec-watch-application": "application",
    "net-sec-watch-system": "system",
    "net-sec-watch-network": "network",
    "net-sec-watch-dead-letter": "dead-letter",
}


def load_json(path):
    return json.loads(Path(path).read_text(encoding="utf-8"))


def load_searches(path=DEFAULT_SEARCHES):
    searches = []
    for line in Path(path).read_text(encoding="utf-8").splitlines():
        if not line:
            continue
        item = json.loads(line)
        source = json.loads(
            item["attributes"]["kibanaSavedObjectMeta"]["searchSourceJSON"]
        )
        view_id = item["references"][0]["id"]
        searches.append({
            "id": item["id"],
            "title": item["attributes"]["title"],
            "stream": VIEW_STREAMS[view_id],
            "query": source["query"]["query"],
            "fields": item["attributes"]["columns"],
        })
    return searches


def percentile(values, quantile):
    if not values:
        return math.inf
    ordered = sorted(values)
    position = max(0, math.ceil(len(ordered) * quantile) - 1)
    return ordered[position]


def authorization(username, password):
    encoded_credentials = base64.b64encode(
        f"{username}:{password}".encode("utf-8")
    ).decode("ascii")
    return f"Basic {encoded_credentials}"


class OpenSearch:
    def __init__(self, endpoint, username, password, insecure, timeout):
        self.endpoint = endpoint.rstrip("/")
        self.authorization = authorization(username, password)
        self.timeout = timeout
        self.context = (
            ssl._create_unverified_context()
            if insecure else ssl.create_default_context()
        )

    def post(self, path, body):
        request = urllib.request.Request(
            f"{self.endpoint}/{path.lstrip('/')}",
            data=json.dumps(body).encode("utf-8"),
            method="POST",
            headers={
                "Authorization": self.authorization,
                "Content-Type": "application/json",
            },
        )
        started = time.perf_counter()
        try:
            with urllib.request.urlopen(
                request, context=self.context, timeout=self.timeout
            ) as response:
                payload = json.load(response)
        except (urllib.error.URLError, json.JSONDecodeError) as error:
            raise RuntimeError(str(error)) from error
        return payload, time.perf_counter() - started


def time_range(now, window_days):
    end = now.astimezone(timezone.utc)
    return end - timedelta(days=window_days), end


def timestamp(value):
    return value.isoformat().replace("+00:00", "Z")


def count_query(start, end):
    return {
        "size": 0,
        "track_total_hits": True,
        "query": {
            "range": {
                "@timestamp": {
                    "gte": timestamp(start),
                    "lt": timestamp(end),
                }
            }
        },
    }


def search_query(search, start, end, page_size):
    return {
        "size": page_size,
        "track_total_hits": False,
        "_source": search["fields"],
        "sort": [{"@timestamp": {"order": "desc", "unmapped_type": "date"}}],
        "query": {
            "bool": {
                "must": [{
                    "query_string": {
                        "query": search["query"],
                        "analyze_wildcard": True,
                    }
                }],
                "filter": [{
                    "range": {
                        "@timestamp": {
                            "gte": timestamp(start),
                            "lt": timestamp(end),
                        }
                    }
                }],
            }
        },
    }


def index_name(stream, environment):
    return f"net-sec-watch-{stream}-{environment}"


def measure(client, searches, config, environment, start, end):
    counts = {}
    count_errors = {}
    for stream in sorted({item["stream"] for item in searches}):
        try:
            payload, _ = client.post(
                f"{index_name(stream, environment)}/_search"
                "?ignore_unavailable=true&allow_no_indices=true",
                count_query(start, end),
            )
            counts[stream] = payload["hits"]["total"]["value"]
        except (RuntimeError, KeyError) as error:
            counts[stream] = 0
            count_errors[stream] = str(error)

    results = []
    for search in searches:
        path = (
            f"{index_name(search['stream'], environment)}/_search"
            "?ignore_unavailable=true&allow_no_indices=true"
        )
        body = search_query(
            search, start, end, config["first_page_size"]
        )
        for _ in range(config["warmup_iterations"]):
            try:
                client.post(path, body)
            except RuntimeError:
                pass
        latencies = []
        errors = []
        for _ in range(config["measured_iterations"]):
            try:
                _, elapsed = client.post(path, body)
                latencies.append(elapsed)
            except RuntimeError as error:
                errors.append(str(error))
        deadline = config["response_time_seconds"]
        within = sum(value <= deadline for value in latencies)
        success_rate = (
            within * 100.0 / config["measured_iterations"]
        )
        p50 = percentile(latencies, 0.50)
        p95 = percentile(latencies, 0.95)
        results.append({
            "id": search["id"],
            "title": search["title"],
            "stream": search["stream"],
            "iterations": config["measured_iterations"],
            "successful_requests": len(latencies),
            "within_target": within,
            "success_percent": round(success_rate, 2),
            "p50_seconds": (
                round(p50, 4) if math.isfinite(p50) else None
            ),
            "p95_seconds": (
                round(p95, 4) if math.isfinite(p95) else None
            ),
            "max_seconds": (
                round(max(latencies), 4) if latencies else None
            ),
            "errors": errors,
        })
    return counts, count_errors, results


def evaluate(config, counts, count_errors, results):
    design = config["design_load"]
    required = config["required_percent"]
    expected_streams = {result["stream"] for result in results}
    corpus_ready = (
        not count_errors
        and set(counts) == expected_streams
        and sum(counts.values()) >= design["minimum_total_documents"]
        and all(
            count >= design["minimum_documents_per_stream"]
            for count in counts.values()
        )
    )
    queries_ready = all(
        not result["errors"]
        and result["success_percent"] >= required
        and result["p95_seconds"] is not None
        and result["p95_seconds"] <= config["response_time_seconds"]
        for result in results
    )
    return corpus_ready and queries_ready


def result_document(
    config, environment, start, end, counts, count_errors, results
):
    passed = evaluate(config, counts, count_errors, results)
    return {
        "schema_version": 1,
        "objective": config["objective"],
        "measured_at": timestamp(datetime.now(timezone.utc)),
        "environment": environment,
        "window": {
            "start": timestamp(start),
            "end": timestamp(end),
            "days": config["window_days"],
        },
        "target": {
            "first_page_seconds": config["response_time_seconds"],
            "required_percent": config["required_percent"],
            "first_page_size": config["first_page_size"],
        },
        "design_load": config["design_load"],
        "document_counts": counts,
        "count_errors": count_errors,
        "total_documents": sum(counts.values()),
        "searches": results,
        "passed": passed,
    }


def parse_time(value):
    normalized = value[:-1] + "+00:00" if value.endswith("Z") else value
    parsed = datetime.fromisoformat(normalized)
    if parsed.tzinfo is None:
        raise argparse.ArgumentTypeError("timestamp must include a timezone")
    return parsed.astimezone(timezone.utc)


def parse_args(argv=None):
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--config", default=str(DEFAULT_CONFIG))
    parser.add_argument("--searches", default=str(DEFAULT_SEARCHES))
    parser.add_argument(
        "--endpoint",
        default=os.environ.get("OPENSEARCH_ENDPOINT", "https://127.0.0.1:9200"),
    )
    parser.add_argument(
        "--username",
        default=os.environ.get("OPENSEARCH_USERNAME", "admin"),
    )
    parser.add_argument(
        "--password",
        default=os.environ.get("OPENSEARCH_PASSWORD"),
    )
    parser.add_argument(
        "--environment",
        default=os.environ.get("DEPLOYMENT_ENVIRONMENT", "development"),
    )
    parser.add_argument("--end", type=parse_time)
    parser.add_argument("--timeout", type=float, default=10.0)
    parser.add_argument("--insecure", action="store_true")
    parser.add_argument("--output")
    args = parser.parse_args(argv)
    if not args.password:
        parser.error("provide --password or set OPENSEARCH_PASSWORD")
    if args.timeout <= 0:
        parser.error("--timeout must be greater than zero")
    return args


def main(argv=None):
    args = parse_args(argv)
    config = load_json(args.config)
    searches = load_searches(args.searches)
    end = args.end or datetime.now(timezone.utc)
    start, end = time_range(end, config["window_days"])
    client = OpenSearch(
        args.endpoint,
        args.username,
        args.password,
        args.insecure,
        args.timeout,
    )
    counts, count_errors, results = measure(
        client, searches, config, args.environment, start, end
    )
    document = result_document(
        config,
        args.environment,
        start,
        end,
        counts,
        count_errors,
        results,
    )
    rendered = json.dumps(document, indent=2, sort_keys=True) + "\n"
    if args.output:
        Path(args.output).write_text(rendered, encoding="utf-8")
    else:
        sys.stdout.write(rendered)
    if not document["passed"]:
        print(
            "FAIL: seven-day search target or design-load requirement "
            "was not satisfied",
            file=sys.stderr,
        )
        return 2
    print(
        "PASS: every standard seven-day search met the response-time target",
        file=sys.stderr,
    )
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
