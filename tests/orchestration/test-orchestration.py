#!/usr/bin/env python3
"""Static Adaptive traffic intelligence adaptive orchestration contract checks."""

from __future__ import annotations

import json
import subprocess
import sys
import tempfile
from pathlib import Path


ROOT = Path(__file__).resolve().parents[2]


def read(path: str) -> str:
    return (ROOT / path).read_text(encoding="utf-8")


def load_json(path: str):
    return json.loads(read(path))


def assert_true(condition: bool, message: str) -> None:
    if not condition:
        raise AssertionError(message)


def test_serving_and_output_contracts() -> None:
    compose = read("compose.orchestration.yaml")
    assert_true("traffic-classifier:" in compose, "classifier compose service missing")
    assert_true("model-orchestrator:" in compose, "orchestrator compose service missing")
    serving = load_json("config/orchestration/serving-api-v1.json")
    assert_true(serving["runtime"]["open_source"], "serving runtime must be open source")
    assert_true(not serving["runtime"]["paid_api_required"], "paid API dependency not allowed")
    assert_true(serving["subscription"]["near_real_time_target_seconds"] <= 5, "near-real-time target too slow")
    assert_true("net_sec_watch_inference_latency_seconds" in serving["metrics"], "latency metric missing")
    output = load_json("config/orchestration/classification-output-v1.json")
    for field in [
        "prediction.classification",
        "prediction.threat_level",
        "prediction.score",
        "prediction.confidence",
        "prediction.model_id",
        "prediction.contributing_features",
        "prediction.supporting_evidence",
    ]:
        assert_true(field in output["required_prediction_fields"], f"missing {field}")
    assert_true(output["alert_routing"]["pipeline"] == "detection-alert-schema", "detection and alerting routing missing")


def test_unknown_and_orchestration_policy() -> None:
    unknown = load_json("config/orchestration/unknown-traffic-policy-v1.json")
    assert_true(unknown["queue"]["separate_from_dead_letter"], "unknown queue must not be dead-letter")
    assert_true(unknown["queue"]["max_events_per_minute"] > 0, "rate limit missing")
    assert_true(unknown["queue"]["deduplication_fields"], "dedup fields missing")
    orchestration = load_json("config/orchestration/orchestration-policy-v1.json")
    assert_true(orchestration["clustering"]["algorithm"] == "dbscan", "DBSCAN not configured")
    assert_true("scikit-learn" in orchestration["candidate_training"]["frameworks"], "scikit-learn missing")
    assert_true(orchestration["rejection"]["log_failed_candidates"], "rejection logging required")
    assert_true(orchestration["feedback"]["include_shadow_feedback_next_cycle"], "feedback loop missing")


def test_registry_llm_oversight_governance() -> None:
    registry = load_json("config/orchestration/model-registry-events-v1.json")
    assert_true("network" in registry["active_slots"], "network active slot missing")
    assert_true(registry["active_slots"]["network"]["rollback_model_version"], "rollback pointer missing")
    event_types = {event["type"] for event in registry["events"]}
    assert_true({"training_run", "evaluation_result", "promotion", "rollback", "retirement"} <= event_types, "registry event gap")
    assert_true(any(event.get("serving_cycles") == 1 for event in registry["events"] if event["type"] == "rollback"), "one-cycle rollback not demonstrated")
    llm = load_json("config/orchestration/llm-enrichment-policy-v1.json")
    assert_true(not llm["enabled_by_default"], "LLM must be optional")
    assert_true(llm["safety"]["advisor_only"], "LLM must be advisor only")
    assert_true(not llm["safety"]["may_promote_model"], "LLM must not promote")
    oversight = load_json("config/orchestration/analyst-oversight-v1.json")
    assert_true(oversight["promotion"]["requires_analyst_approval"], "analyst approval missing")
    assert_true(not oversight["feedback"]["modifies_original_event"], "feedback must not mutate originals")
    governance = load_json("config/orchestration/governance-monitoring-v1.json")
    assert_true(governance["license_policy"]["open_source_only"], "open-source policy missing")
    assert_true(not governance["license_policy"]["paid_api_dependency_allowed"], "paid APIs not allowed")


def test_local_classifier_and_orchestrator() -> None:
    with tempfile.TemporaryDirectory() as tmp:
        predictions = Path(tmp) / "predictions.jsonl"
        metrics = Path(tmp) / "metrics.prom"
        result = subprocess.run(
            [
                sys.executable,
                "scripts/traffic-classifier-service.py",
                "--events",
                "tests/orchestration/fixtures/live-events.jsonl",
                "--registry",
                "config/orchestration/model-registry-events-v1.json",
                "--output",
                str(predictions),
                "--metrics-output",
                str(metrics),
            ],
            cwd=ROOT,
            check=True,
            capture_output=True,
            text=True,
        )
        assert_true(json.loads(result.stdout)["prediction_count"] == 3, "prediction count mismatch")
        rows = [json.loads(line) for line in predictions.read_text().splitlines() if line]
        assert_true(all("event.classification" in row for row in rows), "reserved output field missing")
        assert_true("net_sec_watch_inference_errors_total 0" in metrics.read_text(), "metrics missing")

        candidates = Path(tmp) / "candidates.json"
        result = subprocess.run(
            [
                sys.executable,
                "scripts/model-orchestrator.py",
                "--events",
                "tests/orchestration/fixtures/unknown-traffic-events.jsonl",
                "--config",
                "config/orchestration/orchestration-policy-v1.json",
                "--output",
                str(candidates),
            ],
            cwd=ROOT,
            check=True,
            capture_output=True,
            text=True,
        )
        payload = json.loads(candidates.read_text())
        assert_true(payload["candidates"], "no staged candidate generated")
        assert_true(payload["rejected"], "failed candidate should be logged")


def test_docs_and_ml_fallback() -> None:
    assert_true((ROOT / "docs/adaptive-traffic-intelligence.md").is_file(), "Adaptive traffic intelligence doc missing")
    assert_true((ROOT / "docs/test-results/orchestration-contract.md").is_file(), "Adaptive traffic intelligence evidence missing")
    result = subprocess.run(
        [
            sys.executable,
            "scripts/run-detections.py",
            "--events",
            "tests/detections/fixtures/detection-positive-events.jsonl",
            "--expect",
            "tests/detections/fixtures/detection-expected-alerts.json",
        ],
        cwd=ROOT,
        check=True,
        capture_output=True,
        text=True,
    )
    assert_true(len(json.loads(result.stdout)["alerts"]) == 4, "deterministic rules interrupted")


if __name__ == "__main__":
    for test in [
        test_serving_and_output_contracts,
        test_unknown_and_orchestration_policy,
        test_registry_llm_oversight_governance,
        test_local_classifier_and_orchestrator,
        test_docs_and_ml_fallback,
    ]:
        test()
    print("Orchestration contract is valid.")
