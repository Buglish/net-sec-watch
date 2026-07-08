#!/usr/bin/env python3
"""Local Phase 11 traffic classifier simulation."""

from __future__ import annotations

import argparse
import json
import time
from pathlib import Path


def load_json(path: str):
    return json.loads(Path(path).read_text(encoding="utf-8"))


def load_jsonl(path: str):
    return [
        json.loads(line)
        for line in Path(path).read_text(encoding="utf-8").splitlines()
        if line.strip()
    ]


def classify(event, registry):
    dataset = event.get("event.dataset", "")
    if dataset.startswith("zeek") or dataset.startswith("suricata"):
        traffic_class = "network"
    else:
        traffic_class = "syslog"
    slot = registry["active_slots"][traffic_class]
    confidence = float(event.get("model_hint.confidence", 0.8))
    classification = event.get("model_hint.classification") or (
        "unknown" if confidence < 0.45 else "expected"
    )
    threat_score = round(1.0 - confidence, 4)
    if threat_score >= 0.8:
        threat_level = "critical"
    elif threat_score >= 0.6:
        threat_level = "high"
    elif threat_score >= 0.4:
        threat_level = "medium"
    elif threat_score > 0.1:
        threat_level = "low"
    else:
        threat_level = "info"
    features = ["event.dataset", "destination.port", "network.transport"]
    return {
        "@timestamp": event["@timestamp"],
        "record": {"kind": "prediction"},
        "event.classification": classification,
        "event.threat_level": threat_level,
        "event.threat_score": threat_score,
        "event.ml_model_id": slot["active_model_id"],
        "event.ml_confidence": confidence,
        "prediction": {
            "source_event_id": event["event.id"],
            "classification": classification,
            "threat_level": threat_level,
            "score": threat_score,
            "confidence": confidence,
            "model_id": slot["active_model_id"],
            "model_version": slot["active_model_version"],
            "contributing_features": features,
            "supporting_evidence": [
                f"dataset={dataset}",
                f"confidence={confidence}",
                f"traffic_class={traffic_class}"
            ],
            "explanation": "Phase 11 local classifier simulation generated a shadow/live-compatible prediction."
        }
    }


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("--events", required=True)
    parser.add_argument("--registry", required=True)
    parser.add_argument("--output", required=True)
    parser.add_argument("--metrics-output", required=True)
    args = parser.parse_args()

    events = load_jsonl(args.events)
    registry = load_json(args.registry)
    start = time.perf_counter()
    predictions = [classify(event, registry) for event in events]
    elapsed = max(time.perf_counter() - start, 0.0001)
    Path(args.output).write_text(
        "\n".join(json.dumps(item, sort_keys=True) for item in predictions) + "\n",
        encoding="utf-8",
    )
    metrics = [
        "# TYPE net_sec_watch_inference_latency_seconds gauge",
        f"net_sec_watch_inference_latency_seconds {elapsed:.6f}",
        "# TYPE net_sec_watch_inference_throughput_total counter",
        f"net_sec_watch_inference_throughput_total {len(predictions)}",
        "# TYPE net_sec_watch_inference_queue_depth gauge",
        "net_sec_watch_inference_queue_depth 0",
        "# TYPE net_sec_watch_inference_errors_total counter",
        "net_sec_watch_inference_errors_total 0"
    ]
    Path(args.metrics_output).write_text("\n".join(metrics) + "\n", encoding="utf-8")
    print(json.dumps({"prediction_count": len(predictions), "errors": 0}, sort_keys=True))


if __name__ == "__main__":
    main()
