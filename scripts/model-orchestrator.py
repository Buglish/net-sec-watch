#!/usr/bin/env python3
"""Local Phase 11 unknown-traffic orchestration simulation."""

from __future__ import annotations

import argparse
import json
from collections import defaultdict
from pathlib import Path


def load_json(path: str):
    return json.loads(Path(path).read_text(encoding="utf-8"))


def load_jsonl(path: str):
    return [
        json.loads(line)
        for line in Path(path).read_text(encoding="utf-8").splitlines()
        if line.strip()
    ]


def cluster_key(event):
    return (
        event.get("destination.port"),
        event.get("network.transport"),
        event.get("event.dataset"),
        event.get("source.asn", "unknown")
    )


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("--events", required=True)
    parser.add_argument("--config", required=True)
    parser.add_argument("--output", required=True)
    args = parser.parse_args()

    events = load_jsonl(args.events)
    config = load_json(args.config)
    minimum = config["dataset_slice"]["minimum_cluster_size"]
    grouped = defaultdict(list)
    for event in events:
        if event.get("event.classification") == "unknown" and event.get("event.ml_confidence", 1.0) < 0.45:
            grouped[cluster_key(event)].append(event)

    candidates = []
    rejected = []
    for key, cluster_events in grouped.items():
        record = {
            "cluster_key": list(key),
            "event_count": len(cluster_events),
            "algorithm": config["clustering"]["algorithm"],
            "framework": config["candidate_training"]["default_framework"]
        }
        if len(cluster_events) >= minimum:
            record.update({
                "status": "staged_shadow",
                "precision": 0.75,
                "recall": 0.65,
                "false_positive_rate": 0.05,
                "latency_ms_p95": 40
            })
            candidates.append(record)
        else:
            record.update({"status": "rejected", "reason": "cluster_too_small"})
            rejected.append(record)

    payload = {
        "candidates": candidates,
        "rejected": rejected,
        "metrics": {
            "net_sec_watch_candidate_models_trained_total": len(candidates),
            "net_sec_watch_candidate_models_rejected_total": len(rejected)
        }
    }
    Path(args.output).write_text(json.dumps(payload, indent=2, sort_keys=True) + "\n", encoding="utf-8")
    print(json.dumps(payload["metrics"], sort_keys=True))


if __name__ == "__main__":
    main()
