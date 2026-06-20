#!/usr/bin/env python3
"""Compare emitted JSON events with stable golden expected subsets."""

import argparse
import json
from pathlib import Path
from typing import Any


ROOT = Path(__file__).resolve().parents[2]
DEFAULT_MANIFEST = ROOT / "tests/golden/expected-events.json"


def parse_events(path: Path) -> list[dict[str, Any]]:
    events: list[dict[str, Any]] = []
    for line in path.read_text(encoding="utf-8").splitlines():
        start = line.find("{")
        if start < 0:
            continue
        try:
            value = json.loads(line[start:])
        except json.JSONDecodeError:
            continue
        if isinstance(value, dict):
            events.append(value)
    return events


def matches(event: dict[str, Any], rule: dict[str, Any]) -> bool:
    value = event.get(rule["field"])
    if "equals" in rule:
        return value == rule["equals"]
    if "contains" in rule:
        return rule["contains"] in str(value or "")
    raise ValueError(f"unsupported match rule: {rule}")


def main() -> None:
    parser = argparse.ArgumentParser()
    parser.add_argument("--logs", type=Path, required=True)
    parser.add_argument("--manifest", type=Path, default=DEFAULT_MANIFEST)
    args = parser.parse_args()

    manifest = json.loads(args.manifest.read_text(encoding="utf-8"))
    events = parse_events(args.logs)
    failures: list[str] = []

    for case in manifest["cases"]:
        candidates = [event for event in events if matches(event, case["match"])]
        if not candidates:
            failures.append(f"{case['name']}: matching output event not found")
            continue

        event = candidates[-1]
        differences = [
            f"{field}: expected {expected!r}, got {event.get(field)!r}"
            for field, expected in case["expected"].items()
            if event.get(field) != expected
        ]
        if differences:
            failures.append(f"{case['name']}: " + "; ".join(differences))

    if failures:
        raise SystemExit("FAIL: golden parser outputs\n" + "\n".join(failures))

    print(f"PASS: {len(manifest['cases'])} golden parser output cases")


if __name__ == "__main__":
    main()
