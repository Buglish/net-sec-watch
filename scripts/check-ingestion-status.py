#!/usr/bin/env python3
"""Report freshness states for approved Net Sec Watch event streams."""

import argparse
import base64
import json
import os
import ssl
import sys
import urllib.error
import urllib.request
from datetime import datetime, timezone

STREAMS = ("application", "system", "network", "dead-letter")


def parse_timestamp(value):
    if not value:
        return None
    normalized = value[:-1] + "+00:00" if value.endswith("Z") else value
    return datetime.fromisoformat(normalized).astimezone(timezone.utc)


def classify(latest, now, max_age_seconds):
    if latest is None:
        return "empty", None
    age = max(0.0, (now - latest).total_seconds())
    return ("current" if age <= max_age_seconds else "delayed"), age


def request_latest(args, stream):
    index = f"net-sec-watch-{stream}-{args.environment}"
    url = (
        f"{args.endpoint.rstrip('/')}/{index}/_search"
        "?ignore_unavailable=true&allow_no_indices=true"
    )
    body = {
        "size": 0,
        "track_total_hits": True,
        "aggs": {"latest_event": {"max": {"field": "@timestamp"}}},
    }
    credentials = base64.b64encode(
        f"{args.username}:{args.password}".encode("utf-8")
    ).decode("ascii")
    request = urllib.request.Request(
        url,
        data=json.dumps(body).encode("utf-8"),
        headers={
            "Authorization": f"Basic {credentials}",
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
            payload = json.load(response)
    except (urllib.error.URLError, json.JSONDecodeError) as error:
        raise RuntimeError(str(error)) from error
    return parse_timestamp(
        payload.get("aggregations", {})
        .get("latest_event", {})
        .get("value_as_string")
    )


def evaluate(args, now):
    results = []
    for stream in STREAMS:
        try:
            latest = request_latest(args, stream)
            state, age = classify(latest, now, args.max_age_seconds)
            results.append({
                "stream": stream,
                "state": state,
                "latest_event": (
                    latest.isoformat().replace("+00:00", "Z")
                    if latest else None
                ),
                "age_seconds": round(age, 3) if age is not None else None,
                "error": None,
            })
        except RuntimeError as error:
            results.append({
                "stream": stream,
                "state": "query_error",
                "latest_event": None,
                "age_seconds": None,
                "error": str(error),
            })
    return results


def parse_args(argv=None):
    parser = argparse.ArgumentParser(description=__doc__)
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
    parser.add_argument("--max-age-seconds", type=int, default=300)
    parser.add_argument("--timeout", type=int, default=10)
    parser.add_argument("--now", type=parse_timestamp)
    parser.add_argument("--json", action="store_true")
    parser.add_argument("--insecure", action="store_true")
    args = parser.parse_args(argv)
    if not args.password:
        parser.error("provide --password or set OPENSEARCH_PASSWORD")
    if args.max_age_seconds <= 0:
        parser.error("--max-age-seconds must be greater than zero")
    if args.timeout <= 0:
        parser.error("--timeout must be greater than zero")
    return args


def main(argv=None):
    args = parse_args(argv)
    now = args.now or datetime.now(timezone.utc)
    results = evaluate(args, now)
    if args.json:
        json.dump(
            {
                "environment": args.environment,
                "checked_at": now.isoformat().replace("+00:00", "Z"),
                "max_age_seconds": args.max_age_seconds,
                "streams": results,
            },
            sys.stdout,
            indent=2,
        )
        sys.stdout.write("\n")
    else:
        print(f"{'STREAM':<14} {'STATE':<12} {'AGE_SECONDS':<12} LATEST_EVENT")
        for result in results:
            age = (
                f"{result['age_seconds']:.3f}"
                if result["age_seconds"] is not None else "-"
            )
            latest = result["latest_event"] or result["error"] or "-"
            print(
                f"{result['stream']:<14} {result['state']:<12} "
                f"{age:<12} {latest}"
            )
    return 1 if any(
        result["state"] in {"delayed", "query_error"}
        for result in results
    ) else 0


if __name__ == "__main__":
    raise SystemExit(main())
