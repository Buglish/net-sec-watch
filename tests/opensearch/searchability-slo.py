#!/usr/bin/env python3
"""Measure syslog-to-search latency through Fluent Bit and OpenSearch."""

import argparse
import base64
import datetime
import json
import math
import socket
import ssl
import sys
import time
import urllib.request
import uuid


sys.dont_write_bytecode = True


def positive_integer(value):
    number = int(value)
    if number <= 0:
        raise argparse.ArgumentTypeError("value must be greater than zero")
    return number


def percentage(value):
    number = float(value)
    if not 0 < number <= 100:
        raise argparse.ArgumentTypeError("percentage must be in (0, 100]")
    return number


def percentile(values, quantile):
    ordered = sorted(values)
    if not ordered:
        return math.inf
    position = max(0, math.ceil(len(ordered) * quantile) - 1)
    return ordered[position]


def search(endpoint, username, password, service_name, size):
    body = json.dumps(
        {
            "size": size,
            "_source": ["message"],
            "query": {"term": {"service.name": service_name}},
        }
    ).encode("utf-8")
    encoded_credentials = base64.b64encode(
        f"{username}:{password}".encode("utf-8")
    ).decode("ascii")
    request = urllib.request.Request(
        f"{endpoint}/net-sec-watch-network-development/_search",
        data=body,
        method="POST",
        headers={
            "Authorization": f"Basic {encoded_credentials}",
            "Content-Type": "application/json",
        },
    )
    context = ssl.create_default_context()
    context.check_hostname = False
    context.verify_mode = ssl.CERT_NONE
    with urllib.request.urlopen(
        request, context=context, timeout=3
    ) as response:
        return json.load(response)["hits"]["hits"]


def run(args):
    run_id = uuid.uuid4().hex[:12]
    service_name = f"searchability-slo-{run_id}"
    sent_at = {}

    with socket.create_connection(
        (args.syslog_host, args.syslog_port), timeout=5
    ) as connection:
        for number in range(args.events):
            marker = f"SearchabilitySLO-{run_id}-{number:04d}"
            timestamp = datetime.datetime.now().astimezone().strftime(
                "%b %e %H:%M:%S"
            )
            frame = (
                f"<134>{timestamp} slo-host {service_name}[1]: "
                f"{marker}\n"
            ).encode("utf-8")
            connection.sendall(frame)
            sent_at[marker] = time.monotonic()

    visible_at = {}
    last_send = max(sent_at.values())
    stop_at = last_send + args.deadline_seconds
    while time.monotonic() <= stop_at and len(visible_at) < args.events:
        observed_at = time.monotonic()
        try:
            hits = search(
                args.endpoint,
                args.username,
                args.password,
                service_name,
                args.events,
            )
        except Exception:
            time.sleep(args.poll_interval)
            continue
        for hit in hits:
            message = hit.get("_source", {}).get("message", "")
            marker = message.strip()
            if marker in sent_at and marker not in visible_at:
                visible_at[marker] = observed_at
        if len(visible_at) < args.events:
            time.sleep(args.poll_interval)

    latencies = {
        marker: visible_at[marker] - sent_time
        for marker, sent_time in sent_at.items()
        if marker in visible_at
    }
    within_deadline = sum(
        latency <= args.deadline_seconds for latency in latencies.values()
    )
    success_percent = within_deadline * 100.0 / args.events
    required = math.ceil(args.events * args.required_percent / 100.0)
    latency_values = list(latencies.values())

    result = {
        "accepted_events": args.events,
        "searchable_events": len(visible_at),
        "searchable_within_deadline": within_deadline,
        "required_within_deadline": required,
        "success_percent": round(success_percent, 2),
        "deadline_seconds": args.deadline_seconds,
        "p50_seconds": round(percentile(latency_values, 0.50), 3),
        "p95_seconds": round(percentile(latency_values, 0.95), 3),
        "max_seconds": (
            round(max(latency_values), 3) if latency_values else None
        ),
        "missing_events": sorted(set(sent_at) - set(visible_at)),
    }
    print(json.dumps(result, indent=2, sort_keys=True))

    if within_deadline < required:
        raise SystemExit(
            f"FAIL: {within_deadline}/{args.events} events were searchable "
            f"within {args.deadline_seconds}s; required {required}"
        )
    print(
        f"PASS: {within_deadline}/{args.events} events "
        f"({success_percent:.2f}%) were searchable within "
        f"{args.deadline_seconds}s"
    )


def parser():
    command = argparse.ArgumentParser(description=__doc__)
    command.add_argument("--syslog-host", default="127.0.0.1")
    command.add_argument("--syslog-port", type=positive_integer, required=True)
    command.add_argument("--endpoint", required=True)
    command.add_argument("--username", required=True)
    command.add_argument("--password", required=True)
    command.add_argument("--events", type=positive_integer, default=100)
    command.add_argument("--deadline-seconds", type=float, default=10.0)
    command.add_argument("--required-percent", type=percentage, default=95.0)
    command.add_argument("--poll-interval", type=float, default=0.2)
    return command


def main():
    arguments = parser().parse_args()
    if arguments.deadline_seconds <= 0 or arguments.poll_interval <= 0:
        raise SystemExit("deadline and poll interval must be greater than zero")
    run(arguments)


if __name__ == "__main__":
    main()
