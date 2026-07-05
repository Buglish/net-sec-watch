#!/usr/bin/env python3
"""Static Phase 9 ML governance and shadow-mode contract checks."""

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


def test_use_case_dataset_and_prohibited_uses() -> None:
    use_case = load_json("config/ml/ml-use-case-v1.json")
    selected = use_case["selected_use_case"]
    assert_true(selected["id"] == "ML-AUTH-001", "unexpected ML use case")
    assert_true(selected["model_mode"] == "shadow", "model must be shadow")
    assert_true(not selected["autonomous_enforcement"], "autonomous enforcement not allowed")
    assert_true(
        "autonomous_account_disablement" in use_case["prohibited_uses"],
        "prohibited uses missing enforcement guardrail",
    )
    dataset = load_json("config/ml/dataset-policy-v1.json")
    train_end = dataset["time_separation"]["training_range"]["end"]
    eval_start = dataset["time_separation"]["evaluation_range"]["start"]
    assert_true(train_end < eval_start, "dataset ranges are not time separated")
    assert_true(
        "event.original" in dataset["restricted_fields_excluded"],
        "raw event payload must be excluded from ML fixtures",
    )


def test_baselines_frameworks_and_mlflow() -> None:
    baselines = load_json("config/ml/baselines-v1.json")
    assert_true(baselines["deterministic_baselines"], "deterministic baseline missing")
    assert_true(baselines["statistical_baselines"], "statistical baseline missing")
    frameworks = load_json("config/ml/framework-evaluation-v1.json")["frameworks"]
    assert_true(
        frameworks["opensearch_anomaly_detection"]["decision"]
        == "evaluate_for_streaming_baselines",
        "OpenSearch AD decision missing",
    )
    assert_true(
        frameworks["scikit_learn"]["phase_9_status"] == "approved_candidate",
        "scikit-learn evaluation missing",
    )
    assert_true(frameworks["river"]["phase_9_status"] == "deferred", "River should be deferred")
    assert_true(frameworks["pytorch"]["phase_9_status"] == "deferred", "PyTorch should be deferred")
    mlflow = load_json("config/ml/mlflow-experiment-contract-v1.json")["tracking"]
    for metric in ["precision", "recall", "false_positive_rate", "p95_latency_ms", "alert_reduction"]:
        assert_true(metric in mlflow["required_metrics"], f"missing metric {metric}")
    assert_true("model_card.md" in mlflow["required_artifacts"], "model card artifact missing")


def test_registry_serving_and_templates() -> None:
    registry = load_json("config/ml/mlflow-model-registry-entry-v1.json")
    model = registry["model"]
    for key in [
        "type",
        "input_feature_schema",
        "output_field_names",
        "shadow_mode",
        "promotion_approval_record",
        "rollback_pointer",
    ]:
        assert_true(key in model, f"registry model missing {key}")
    assert_true(model["shadow_mode"], "registry model must be shadow")
    serving = load_json("config/ml/model-serving-api-v1.json")
    assert_true(serving["hot_swap"]["enabled"], "hot-swap loading disabled")
    assert_true(
        serving["failure_policy"]["ml_disabled"]
        == "ingestion_search_and_deterministic_rules_continue",
        "ML-disabled behavior not safe",
    )
    model_template = load_json("config/opensearch/model-metadata-template-v1.json")
    model_props = model_template["template"]["mappings"]["properties"]["model"]["properties"]
    for field in ["type", "input_feature_schema", "output_field_names", "shadow_mode", "rollback_pointer"]:
        assert_true(field in model_props, f"model metadata mapping missing {field}")
    prediction_template = load_json("config/opensearch/predictions-template-v1.json")
    prediction_props = prediction_template["template"]["mappings"]["properties"]["prediction"]["properties"]
    for field in ["features", "contributing_features", "supporting_evidence"]:
        assert_true(field in prediction_props, f"prediction mapping missing {field}")


def test_shadow_scoring_and_explainability() -> None:
    with tempfile.TemporaryDirectory() as tmp:
        output = Path(tmp) / "predictions.jsonl"
        result = subprocess.run(
            [
                sys.executable,
                "scripts/ml-shadow-score.py",
                "--events",
                "tests/ml/fixtures/auth-shadow-evaluation.jsonl",
                "--model-metadata",
                "config/ml/mlflow-model-registry-entry-v1.json",
                "--output",
                str(output),
            ],
            cwd=ROOT,
            check=True,
            capture_output=True,
            text=True,
        )
        summary = json.loads(result.stdout)
        assert_true(summary["prediction_count"] == 3, "unexpected prediction count")
        assert_true(summary["metrics"]["precision"] >= 0.5, "precision not reported")
        predictions = [
            json.loads(line)
            for line in output.read_text(encoding="utf-8").splitlines()
            if line
        ]
    assert_true(any(item["prediction"]["classification"] == "anomalous" for item in predictions), "no anomaly found")
    for prediction in predictions:
        payload = prediction["prediction"]
        assert_true(payload["contributing_features"], "contributing features missing")
        assert_true(payload["supporting_evidence"], "supporting evidence missing")
        assert_true(payload["explanation"], "explanation missing")


def test_feedback_drift_lifecycle_and_licensing() -> None:
    feedback = load_json("config/ml/analyst-feedback-example.json")
    assert_true(feedback["record"]["kind"] == "feedback", "feedback record kind missing")
    assert_true("source_event_id" not in feedback["feedback"], "feedback must not alter source event")
    drift = load_json("config/ml/drift-monitoring-v1.json")["monitors"]
    for monitor in ["data_quality", "feature_drift", "score_drift", "resource_use"]:
        assert_true(monitor in drift, f"missing drift monitor {monitor}")
    lifecycle = load_json("config/ml/ml-lifecycle-v1.json")
    assert_true(lifecycle["owner"] == "SecOps", "ML owner missing")
    assert_true(lifecycle["approval"]["minimum_shadow_days"] >= 14, "shadow period too short")
    licenses = load_json("config/ml/ml-license-review-v1.json")
    assert_true(licenses["datasets"], "dataset license review missing")
    assert_true(licenses["models"], "model license review missing")


def test_deterministic_rules_still_work_with_ml_disabled() -> None:
    result = subprocess.run(
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
    alerts = json.loads(result.stdout)["alerts"]
    assert_true(len(alerts) == 4, "deterministic detections interrupted")


if __name__ == "__main__":
    for test in [
        test_use_case_dataset_and_prohibited_uses,
        test_baselines_frameworks_and_mlflow,
        test_registry_serving_and_templates,
        test_shadow_scoring_and_explainability,
        test_feedback_drift_lifecycle_and_licensing,
        test_deterministic_rules_still_work_with_ml_disabled,
    ]:
        test()
    print("Phase 9 ML contract is valid.")
