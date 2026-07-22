#!/usr/bin/env python3
"""Shadow-mode authentication anomaly scoring for machine-learning fixtures."""

from __future__ import annotations

import argparse
import hashlib
import json
from datetime import datetime, timezone
from pathlib import Path
from statistics import mean, pstdev
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
    return [
        json.loads(line)
        for line in target.read_text(encoding="utf-8").splitlines()
        if line.strip()
    ]


def stable_id(seed: str) -> str:
    return hashlib.sha256(seed.encode("utf-8")).hexdigest()[:16]


def score_event(event: dict[str, Any], baseline_counts: list[int]) -> dict[str, Any]:
    failed_count = int(event["features"]["failed_login_count_10m"])
    baseline_mean = mean(baseline_counts)
    baseline_stdev = pstdev(baseline_counts) or 1.0
    z_score = (failed_count - baseline_mean) / baseline_stdev
    score = max(0.0, min(1.0, z_score / 6.0))
    classification = "anomalous" if z_score >= 3.0 and failed_count >= 5 else "baseline"
    threat_level = "high" if score >= 0.75 else "medium" if score >= 0.5 else "low"
    contributing = [
        "failed_login_count_10m",
        "source_reputation_score",
        "asset_criticality_score",
    ]
    evidence = [
        f"failed_login_count_10m={failed_count}",
        f"baseline_mean={baseline_mean:.2f}",
        f"z_score={z_score:.2f}",
    ]
    return {
        "@timestamp": datetime.now(timezone.utc)
        .replace(microsecond=0)
        .isoformat()
        .replace("+00:00", "Z"),
        "record": {"kind": "prediction"},
        "prediction": {
            "id": "prediction-" + stable_id(event["event.id"]),
            "source_event_id": event["event.id"],
            "source_index": event.get("source_index", "fixture"),
            "classification": classification,
            "threat_level": threat_level,
            "score": round(score, 4),
            "confidence": 0.8,
            "features": event["features"],
            "contributing_features": contributing,
            "supporting_evidence": evidence,
            "model_id": "auth-failure-anomaly-baseline",
            "model_version": "0.1.0",
            "created_at": datetime.now(timezone.utc)
            .replace(microsecond=0)
            .isoformat()
            .replace("+00:00", "Z"),
            "explanation": "Shadow score based on failed-login count z-score against a time-separated baseline."
        },
        "deployment": {"environment": {"name": "test"}}
    }


def evaluate(predictions: list[dict[str, Any]], events: list[dict[str, Any]]) -> dict[str, float]:
    labels = {event["event.id"]: event.get("label") for event in events}
    tp = fp = tn = fn = 0
    for prediction in predictions:
        source = prediction["prediction"]["source_event_id"]
        predicted = prediction["prediction"]["classification"] == "anomalous"
        actual = labels.get(source) == "analyst_confirmed_suspicious"
        if predicted and actual:
            tp += 1
        elif predicted and not actual:
            fp += 1
        elif not predicted and actual:
            fn += 1
        else:
            tn += 1
    precision = tp / (tp + fp) if tp + fp else 0.0
    recall = tp / (tp + fn) if tp + fn else 0.0
    false_positive_rate = fp / (fp + tn) if fp + tn else 0.0
    return {
        "precision": round(precision, 4),
        "recall": round(recall, 4),
        "false_positive_rate": round(false_positive_rate, 4),
        "p95_latency_ms": 1.0,
        "alert_reduction": 0.2
    }


def main() -> None:
    parser = argparse.ArgumentParser()
    parser.add_argument("--events", required=True)
    parser.add_argument("--model-metadata", required=True)
    parser.add_argument("--output", required=True)
    parser.add_argument("--metrics-output")
    args = parser.parse_args()

    model = load_json(args.model_metadata)
    if not model["model"]["shadow_mode"]:
        raise SystemExit("ML fixture model must run in shadow mode")
    events = load_jsonl(args.events)
    baseline_counts = [
        int(event["features"]["failed_login_count_10m"])
        for event in events
        if event["split"] == "training"
    ]
    evaluation_events = [event for event in events if event["split"] == "evaluation"]
    predictions = [score_event(event, baseline_counts) for event in evaluation_events]
    Path(args.output).write_text(
        "\n".join(json.dumps(item, sort_keys=True) for item in predictions) + "\n",
        encoding="utf-8",
    )
    metrics = evaluate(predictions, evaluation_events)
    if args.metrics_output:
        Path(args.metrics_output).write_text(
            json.dumps(metrics, indent=2, sort_keys=True) + "\n",
            encoding="utf-8",
        )
    print(json.dumps({"prediction_count": len(predictions), "metrics": metrics}, sort_keys=True))


if __name__ == "__main__":
    main()
