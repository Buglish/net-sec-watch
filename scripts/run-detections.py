#!/usr/bin/env python3
"""Run deterministic Net Sec Watch detection rules against JSONL events."""

from __future__ import annotations

import argparse
import hashlib
import json
from datetime import datetime, timezone
from pathlib import Path
from typing import Any


ROOT = Path(__file__).resolve().parents[1]


def load_json(path: str | Path) -> Any:
    target = Path(path)
    if not target.is_absolute():
        target = ROOT / target
    return json.loads(target.read_text(encoding="utf-8"))


def load_jsonl(path: str | Path) -> list[dict[str, Any]]:
    target = Path(path)
    if not target.is_absolute():
        target = ROOT / target
    events: list[dict[str, Any]] = []
    for line in target.read_text(encoding="utf-8").splitlines():
        if line.strip():
            events.append(json.loads(line))
    return events


def field(record: dict[str, Any], name: str) -> Any:
    if name in record:
        return record[name]
    current: Any = record
    for part in name.split("."):
        if not isinstance(current, dict) or part not in current:
            return None
        current = current[part]
    return current


def parse_time(value: str) -> datetime:
    return datetime.fromisoformat(value.replace("Z", "+00:00")).astimezone(
        timezone.utc
    )


def condition_matches(event: dict[str, Any], condition: dict[str, Any]) -> bool:
    value = field(event, condition["field"])
    if "equals" in condition:
        return value == condition["equals"]
    if "in" in condition:
        return value in condition["in"]
    if "contains" in condition:
        return condition["contains"] in str(value or "")
    raise ValueError(f"unsupported condition: {condition}")


def query_matches(event: dict[str, Any], query: dict[str, Any]) -> bool:
    return all(condition_matches(event, item) for item in query.get("all", []))


def priority_for(
    severity: str,
    events: list[dict[str, Any]],
    asset_policy: dict[str, Any],
    source_policy: dict[str, Any],
) -> str:
    severity_score = {"low": 0, "medium": 1, "high": 2, "critical": 3}[severity]
    asset_scores = asset_policy["scores"]
    source_scores = source_policy["scores"]
    max_asset = 0
    max_source = 0
    for event in events:
        for key in ["destination.ip", "source.ip", "host.ip"]:
            ip = field(event, key)
            if ip in asset_policy["assets"]:
                criticality = asset_policy["assets"][ip]["criticality"]
                max_asset = max(max_asset, asset_scores[criticality])
        dataset = field(event, "event.dataset")
        if dataset in source_policy["sources"]:
            confidence = source_policy["sources"][dataset]["confidence"]
            max_source = max(max_source, source_scores[confidence])
    score = max(0, min(3, severity_score + max_asset + max_source - 1))
    return ["p4", "p3", "p2", "p1"][score]


def dedup_key(rule: dict[str, Any], event: dict[str, Any]) -> str:
    policy = load_json("config/detections/dedup-suppression-v1.json")
    configured = policy["rules"].get(rule["id"], {})
    fields = configured.get("deduplication_key_fields", ["alert.rule.id"])
    values = []
    for name in fields:
        values.append(rule["id"] if name == "alert.rule.id" else str(field(event, name)))
    return "|".join(values)


def make_alert(
    rule: dict[str, Any],
    events: list[dict[str, Any]],
    asset_policy: dict[str, Any],
    source_policy: dict[str, Any],
    destinations: dict[str, Any],
) -> dict[str, Any]:
    first = events[0]
    dedup = dedup_key(rule, first)
    seed = f"{rule['id']}|{rule['version']}|{dedup}"
    alert_id = "alert-" + hashlib.sha256(seed.encode("utf-8")).hexdigest()[:16]
    destination = rule.get("route", destinations["default_destination"])
    channels = [
        channel["type"]
        for channel in destinations["destinations"][destination]["channels"]
    ]
    return {
        "alert.schema_version": "1.0.0",
        "alert.id": alert_id,
        "alert.generated_at": datetime.now(timezone.utc)
        .replace(microsecond=0)
        .isoformat()
        .replace("+00:00", "Z"),
        "alert.source.type": rule["source_type"],
        "alert.rule.id": rule["id"],
        "alert.rule.version": rule["version"],
        "alert.rule.name": rule["name"],
        "alert.rule.owner": rule["owner"],
        "alert.rule.kind": rule["kind"],
        "alert.title": rule["name"],
        "alert.severity": rule["severity"],
        "alert.priority": priority_for(
            rule["severity"], events, asset_policy, source_policy
        ),
        "alert.status": "new",
        "alert.deduplication.key": dedup,
        "alert.suppression.key": f"{rule['id']}|{dedup}",
        "alert.routing.destination": destination,
        "alert.notification.channels": channels,
        "event.references": [
            event.get("event.id")
            or event.get("event.observation_id")
            or event.get("event.original")
            for event in events
        ],
        "source.ip": field(first, "source.ip"),
        "destination.ip": field(first, "destination.ip"),
        "user.name": field(first, "user.name"),
    }


def threshold_alerts(
    rule: dict[str, Any],
    events: list[dict[str, Any]],
    asset_policy: dict[str, Any],
    source_policy: dict[str, Any],
    destinations: dict[str, Any],
) -> list[dict[str, Any]]:
    matches = [event for event in events if query_matches(event, rule["query"])]
    threshold = rule["threshold"]
    window_seconds = threshold["window_minutes"] * 60
    group_by = threshold["group_by"]
    grouped: dict[tuple[Any, ...], list[dict[str, Any]]] = {}
    for event in matches:
        grouped.setdefault(tuple(field(event, key) for key in group_by), []).append(event)
    alerts: list[dict[str, Any]] = []
    for group_events in grouped.values():
        group_events.sort(key=lambda item: parse_time(item["@timestamp"]))
        for index, start_event in enumerate(group_events):
            start = parse_time(start_event["@timestamp"])
            window = [
                item
                for item in group_events[index:]
                if (parse_time(item["@timestamp"]) - start).total_seconds()
                <= window_seconds
            ]
            if len(window) >= threshold["count"]:
                alerts.append(
                    make_alert(rule, window[: threshold["count"]], asset_policy, source_policy, destinations)
                )
                break
    return alerts


def query_alerts(
    rule: dict[str, Any],
    events: list[dict[str, Any]],
    asset_policy: dict[str, Any],
    source_policy: dict[str, Any],
    destinations: dict[str, Any],
) -> list[dict[str, Any]]:
    return [
        make_alert(rule, [event], asset_policy, source_policy, destinations)
        for event in events
        if query_matches(event, rule["query"])
    ]


def correlation_alerts(
    rule: dict[str, Any],
    events: list[dict[str, Any]],
    asset_policy: dict[str, Any],
    source_policy: dict[str, Any],
    destinations: dict[str, Any],
) -> list[dict[str, Any]]:
    correlation = rule["correlation"]
    stages = correlation["stages"]
    window_seconds = correlation["window_minutes"] * 60
    first_stage = [event for event in events if query_matches(event, stages[0]["query"])]
    second_stage = [event for event in events if query_matches(event, stages[1]["query"])]
    alerts: list[dict[str, Any]] = []
    for first in first_stage:
        first_time = parse_time(first["@timestamp"])
        for second in second_stage:
            if any(
                field(first, join_field) != field(second, join_field)
                for join_field in correlation["join_fields"]
            ):
                continue
            delta = abs((parse_time(second["@timestamp"]) - first_time).total_seconds())
            if delta <= window_seconds:
                alerts.append(
                    make_alert(rule, [first, second], asset_policy, source_policy, destinations)
                )
                break
    return alerts


def run(events: list[dict[str, Any]]) -> list[dict[str, Any]]:
    rules = load_json("config/detections/rules-v1.json")["rules"]
    asset_policy = load_json("config/detections/asset-criticality-v1.json")
    source_policy = load_json("config/detections/source-confidence-v1.json")
    destinations = load_json("config/detections/notification-destinations-v1.json")
    alerts: list[dict[str, Any]] = []
    for rule in rules:
        if rule["kind"] == "threshold":
            alerts.extend(
                threshold_alerts(rule, events, asset_policy, source_policy, destinations)
            )
        elif rule["kind"] == "query":
            alerts.extend(
                query_alerts(rule, events, asset_policy, source_policy, destinations)
            )
        elif rule["kind"] == "correlation":
            alerts.extend(
                correlation_alerts(rule, events, asset_policy, source_policy, destinations)
            )
        else:
            raise ValueError(f"unsupported rule kind: {rule['kind']}")
    return sorted(alerts, key=lambda item: item["alert.rule.id"])


def compare_expected(alerts: list[dict[str, Any]], expect_path: str) -> None:
    expected = load_json(expect_path)
    expected_ids = sorted(expected["expected_rule_ids"])
    actual_ids = sorted(alert["alert.rule.id"] for alert in alerts)
    if actual_ids != expected_ids:
        raise SystemExit(f"expected alerts {expected_ids}, got {actual_ids}")
    minimum_priorities = expected.get("minimum_priorities", {})
    priority_rank = {"p4": 0, "p3": 1, "p2": 2, "p1": 3}
    by_rule = {alert["alert.rule.id"]: alert for alert in alerts}
    for rule_id, priority in minimum_priorities.items():
        actual = by_rule[rule_id]["alert.priority"]
        if priority_rank[actual] < priority_rank[priority]:
            raise SystemExit(f"{rule_id} priority {actual} lower than {priority}")


def main() -> None:
    parser = argparse.ArgumentParser()
    parser.add_argument("--events", required=True)
    parser.add_argument("--expect")
    parser.add_argument("--output")
    args = parser.parse_args()

    alerts = run(load_jsonl(args.events))
    if args.expect:
        compare_expected(alerts, args.expect)
    payload = json.dumps({"alerts": alerts}, indent=2, sort_keys=True)
    if args.output:
        Path(args.output).write_text(payload + "\n", encoding="utf-8")
    else:
        print(payload)


if __name__ == "__main__":
    main()
