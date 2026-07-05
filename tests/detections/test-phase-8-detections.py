#!/usr/bin/env python3
"""Static Phase 8 detection and alerting contract checks."""

from __future__ import annotations

import json
import re
import subprocess
import sys
from pathlib import Path


ROOT = Path(__file__).resolve().parents[2]


def read(path: str) -> str:
    return (ROOT / path).read_text(encoding="utf-8")


def load_json(path: str):
    return json.loads(read(path))


def assert_true(condition: bool, message: str) -> None:
    if not condition:
        raise AssertionError(message)


def test_use_cases_and_rule_kinds() -> None:
    use_cases = load_json("config/detections/detection-use-cases-v1.json")
    categories = {item["category"] for item in use_cases["use_cases"]}
    assert_true(
        {"authentication", "firewall", "vpn", "network"} <= categories,
        "initial detection categories missing",
    )
    rules = load_json("config/detections/rules-v1.json")["rules"]
    kinds = {rule["kind"] for rule in rules}
    assert_true({"query", "threshold", "correlation"} <= kinds, "rule kind gap")
    ids = {rule["id"] for rule in rules}
    for use_case in use_cases["use_cases"]:
        for rule_id in use_case["rule_ids"]:
            assert_true(rule_id in ids, f"use case references missing {rule_id}")


def test_source_agnostic_alert_schema() -> None:
    schema = load_json("config/detections/alert-schema-v1.json")
    required = set(schema["required_fields"])
    for field in [
        "alert.source.type",
        "alert.routing.destination",
        "alert.notification.channels",
        "alert.deduplication.key",
        "alert.suppression.key",
    ]:
        assert_true(field in required, f"schema missing {field}")
    assert_true("ml_model" in schema["source_types"], "ML alert source missing")
    assert_true(
        "alert.model.score" in schema["ml_compatibility"]["reserved_fields"],
        "ML score field not reserved",
    )


def test_rules_are_production_ready() -> None:
    lifecycle = load_json("config/detections/rule-lifecycle-v1.json")
    required = set(lifecycle["required_rule_fields"])
    rules = load_json("config/detections/rules-v1.json")["rules"]
    destinations = load_json("config/detections/notification-destinations-v1.json")
    destination_ids = set(destinations["destinations"])
    seen_versions = set()
    for rule in rules:
        missing = required - set(rule)
        assert_true(not missing, f"{rule['id']} missing {sorted(missing)}")
        assert_true(rule["status"] == "production", f"{rule['id']} not production")
        assert_true(rule["route"] in destination_ids, f"{rule['id']} route missing")
        assert_true(
            Path(ROOT / rule["response_procedure"]).is_file(),
            f"{rule['id']} response procedure missing",
        )
        assert_true(
            Path(ROOT / rule["test_fixture_positive"]).is_file(),
            f"{rule['id']} positive fixture missing",
        )
        assert_true(
            Path(ROOT / rule["test_fixture_negative"]).is_file(),
            f"{rule['id']} negative fixture missing",
        )
        version_key = (rule["id"], rule["version"])
        assert_true(version_key not in seen_versions, f"duplicate version {version_key}")
        seen_versions.add(version_key)


def test_priority_routing_dedup_and_disposition() -> None:
    asset = load_json("config/detections/asset-criticality-v1.json")
    confidence = load_json("config/detections/source-confidence-v1.json")
    dedup = load_json("config/detections/dedup-suppression-v1.json")
    destinations = load_json("config/detections/notification-destinations-v1.json")
    disposition = load_json("config/detections/false-positive-register-v1.json")
    rules = load_json("config/detections/rules-v1.json")["rules"]
    assert_true("critical" in asset["scores"], "critical asset score missing")
    assert_true("high" in confidence["scores"], "source confidence score missing")
    for rule in rules:
        assert_true(rule["id"] in dedup["rules"], f"{rule['id']} dedup missing")
    for destination in destinations["destinations"].values():
        channel_types = {channel["type"] for channel in destination["channels"]}
        assert_true({"webhook", "email"} <= channel_types, "destination channel gap")
    assert_true(
        "false_positive" in disposition["dispositions"],
        "false-positive disposition missing",
    )
    assert_true(
        disposition["accepted_false_positive_rate"]["repository_test_threshold"] == 0,
        "repository fixture false positives should be zero",
    )


def test_detection_runner_positive_and_negative() -> None:
    positive = subprocess.run(
        [
            sys.executable,
            "scripts/run-detections.py",
            "--events",
            "tests/detections/fixtures/phase8-positive-events.jsonl",
            "--expect",
            "tests/detections/fixtures/phase8-expected-alerts.json",
        ],
        cwd=ROOT,
        check=True,
        capture_output=True,
        text=True,
    )
    payload = json.loads(positive.stdout)
    assert_true(len(payload["alerts"]) == 4, "positive fixture alert count mismatch")
    for alert in payload["alerts"]:
        assert_true(alert["alert.schema_version"] == "1.0.0", "schema mismatch")
        assert_true(alert["alert.notification.channels"], "channels missing")

    negative = subprocess.run(
        [
            sys.executable,
            "scripts/run-detections.py",
            "--events",
            "tests/detections/fixtures/phase8-negative-events.jsonl",
            "--expect",
            "tests/detections/fixtures/phase8-expected-negative-alerts.json",
        ],
        cwd=ROOT,
        check=True,
        capture_output=True,
        text=True,
    )
    assert_true(json.loads(negative.stdout)["alerts"] == [], "negative alerts fired")


def test_docs_and_objectives() -> None:
    docs = [
        "docs/phase-8-security-detections-alerting.md",
        "docs/runbooks/detections/authentication-failures.md",
        "docs/runbooks/detections/firewall-deny-sensitive-service.md",
        "docs/runbooks/detections/vpn-untrusted-login.md",
        "docs/runbooks/detections/network-ids-correlation.md",
        "docs/runbooks/detections/rule-ownership-tuning-retirement.md",
    ]
    for path in docs:
        assert_true((ROOT / path).is_file(), f"{path} missing")
    objectives = read("OBJECTIVES.md")
    phase8 = objectives.split("## Phase 8 - Security detections and alerting", 1)[1]
    phase8 = phase8.split("## Phase 9", 1)[0]
    tasks, gates = phase8.split("### Completion gate", 1)
    assert_true(
        not re.findall(r"^- \[ \] .+$", tasks, flags=re.MULTILINE),
        "Phase 8 tasks still unchecked",
    )
    assert_true(
        "Alert volume and false-positive rate meet analyst-approved thresholds"
        in gates,
        "analyst approval gate missing",
    )


if __name__ == "__main__":
    for test in [
        test_use_cases_and_rule_kinds,
        test_source_agnostic_alert_schema,
        test_rules_are_production_ready,
        test_priority_routing_dedup_and_disposition,
        test_detection_runner_positive_and_negative,
        test_docs_and_objectives,
    ]:
        test()
    print("Phase 8 detection contract is valid.")
