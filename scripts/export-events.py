#!/usr/bin/env python3
"""Export a bounded set of Net Sec Watch events as CSV or JSON Lines."""

import argparse
import base64
import csv
import json
import os
import ssl
import sys
import urllib.error
import urllib.request
from datetime import datetime, timedelta, timezone
from pathlib import Path

APPROVED_STREAMS = {"application", "system", "network", "dead-letter"}
DEFAULT_FIELDS = [
    "@timestamp",
    "event.dataset",
    "event.action",
    "event.outcome",
    "event.severity",
    "source.ip",
    "source.port",
    "destination.ip",
    "destination.port",
    "host.name",
    "message",
    "event.original",
]
DEFAULT_LIMIT = 1_000
MAX_LIMIT = 5_000
MAX_RANGE = timedelta(days=7)
PAGE_SIZE = 500
FORMULA_PREFIXES = ("=", "+", "-", "@", "\t", "\r")
ROOT = Path(__file__).resolve().parents[1]


def parse_timestamp(value):
    normalized = value[:-1] + "+00:00" if value.endswith("Z") else value
    try:
        result = datetime.fromisoformat(normalized)
    except ValueError as error:
        raise argparse.ArgumentTypeError(
            "timestamp must use ISO 8601 format"
        ) from error
    if result.tzinfo is None:
        raise argparse.ArgumentTypeError("timestamp must include a timezone")
    return result.astimezone(timezone.utc)


def positive_limit(value):
    number = int(value)
    if not 1 <= number <= MAX_LIMIT:
        raise argparse.ArgumentTypeError(
            f"limit must be between 1 and {MAX_LIMIT}"
        )
    return number


def validate_range(start, end):
    if end <= start:
        raise ValueError("end timestamp must be later than start timestamp")
    if end - start > MAX_RANGE:
        raise ValueError("export time range may not exceed seven days")


def nested_value(source, path):
    value = source
    for part in path.split("."):
        if not isinstance(value, dict) or part not in value:
            return None
        value = value[part]
    return value


def mapped_fields(properties, prefix=""):
    fields = set()
    for name, definition in properties.items():
        path = f"{prefix}.{name}" if prefix else name
        fields.add(path)
        if "properties" in definition:
            fields.update(mapped_fields(definition["properties"], path))
    return fields


def approved_fields():
    template = json.loads(
        (ROOT / "config/opensearch/index-template-v1.json").read_text(
            encoding="utf-8"
        )
    )
    return mapped_fields(template["template"]["mappings"]["properties"])


def csv_safe(value):
    if value is None:
        return ""
    if isinstance(value, (dict, list)):
        text = json.dumps(value, separators=(",", ":"), ensure_ascii=False)
    else:
        text = str(value)
    if text.startswith(FORMULA_PREFIXES):
        return "'" + text
    return text


def build_query(args, size, search_after=None):
    query = {
        "size": size,
        "track_total_hits": False,
        "_source": args.fields,
        "sort": [
            {"@timestamp": {"order": "asc"}},
            {"_id": "asc"},
        ],
        "query": {
            "bool": {
                "filter": [
                    {
                        "range": {
                            "@timestamp": {
                                "gte": args.start.isoformat(),
                                "lt": args.end.isoformat(),
                            }
                        }
                    }
                ]
            }
        },
    }
    if args.query != "*":
        query["query"]["bool"]["must"] = [
            {
                "query_string": {
                    "query": args.query,
                    "analyze_wildcard": True,
                }
            }
        ]
    if search_after is not None:
        query["search_after"] = search_after
    return query


def request_page(args, body):
    url = (
        f"{args.endpoint.rstrip('/')}/"
        f"net-sec-watch-{args.stream}-*/_search"
        "?ignore_unavailable=true&allow_no_indices=true"
    )
    request = urllib.request.Request(
        url,
        data=json.dumps(body).encode("utf-8"),
        headers={
            "Authorization": "Basic "
            + base64.b64encode(
                f"{args.username}:{args.password}".encode("utf-8")
            ).decode("ascii"),
            "Content-Type": "application/json",
        },
        method="POST",
    )
    context = (
        ssl._create_unverified_context()
        if args.insecure
        else ssl.create_default_context()
    )
    try:
        with urllib.request.urlopen(
            request, context=context, timeout=args.timeout
        ) as response:
            return json.load(response)
    except urllib.error.HTTPError as error:
        detail = error.read().decode("utf-8", errors="replace")
        raise RuntimeError(
            f"OpenSearch export request failed with HTTP {error.code}: "
            f"{detail}"
        ) from error


def collect(args):
    rows = []
    search_after = None
    while len(rows) < args.limit:
        size = min(PAGE_SIZE, args.limit - len(rows))
        payload = request_page(
            args, build_query(args, size, search_after)
        )
        hits = payload.get("hits", {}).get("hits", [])
        if not hits:
            break
        rows.extend(hit.get("_source", {}) for hit in hits)
        search_after = hits[-1].get("sort")
        if len(hits) < size or search_after is None:
            break
    return rows


def write_export(args, rows, output):
    if args.format == "jsonl":
        for source in rows:
            record = {
                field: nested_value(source, field) for field in args.fields
            }
            output.write(json.dumps(record, ensure_ascii=False) + "\n")
        return

    writer = csv.DictWriter(output, fieldnames=args.fields)
    writer.writeheader()
    for source in rows:
        writer.writerow(
            {
                field: csv_safe(nested_value(source, field))
                for field in args.fields
            }
        )


def parse_args(argv=None):
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--stream", required=True, choices=sorted(APPROVED_STREAMS))
    parser.add_argument("--start", required=True, type=parse_timestamp)
    parser.add_argument("--end", required=True, type=parse_timestamp)
    parser.add_argument("--query", default="*")
    parser.add_argument("--format", choices=("csv", "jsonl"), default="jsonl")
    parser.add_argument("--limit", type=positive_limit, default=DEFAULT_LIMIT)
    parser.add_argument("--fields", nargs="+", default=DEFAULT_FIELDS)
    parser.add_argument("--output", type=Path)
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
    parser.add_argument("--timeout", type=positive_limit, default=30)
    parser.add_argument("--insecure", action="store_true")
    args = parser.parse_args(argv)
    try:
        validate_range(args.start, args.end)
    except ValueError as error:
        parser.error(str(error))
    if not args.password:
        parser.error(
            "provide --password or set OPENSEARCH_PASSWORD"
        )
    if len(args.fields) != len(set(args.fields)):
        parser.error("--fields may not contain duplicates")
    unknown_fields = set(args.fields) - approved_fields()
    if unknown_fields:
        parser.error(
            "unknown export fields: " + ", ".join(sorted(unknown_fields))
        )
    return args


def main(argv=None):
    args = parse_args(argv)
    rows = collect(args)
    if args.output:
        args.output.parent.mkdir(parents=True, exist_ok=True)
        with args.output.open("w", encoding="utf-8", newline="") as output:
            write_export(args, rows, output)
    else:
        write_export(args, rows, sys.stdout)
    print(
        f"Exported {len(rows)} events from net-sec-watch-{args.stream}-*",
        file=sys.stderr,
    )
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
