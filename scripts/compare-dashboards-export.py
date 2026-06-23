#!/usr/bin/env python3
"""Compare an OpenSearch Dashboards export with the versioned managed bundle."""

import argparse
import json
import sys
from pathlib import Path

sys.dont_write_bytecode = True

ROOT = Path(__file__).resolve().parents[1]
DEFAULT_EXPECTED = (
    ROOT / "config/dashboards/managed-saved-objects-v1.ndjson"
)


def canonical(item):
    return {
        "id": item["id"],
        "type": item["type"],
        "attributes": item["attributes"],
        "references": item.get("references", []),
    }


def read_objects(path):
    objects = {}
    for line in Path(path).read_text(encoding="utf-8").splitlines():
        if not line:
            continue
        item = json.loads(line)
        if (
            item.get("type") == "export-details"
            or (
                "exportedCount" in item
                and "id" not in item
                and "attributes" not in item
            )
        ):
            continue
        value = canonical(item)
        key = (value["type"], value["id"])
        if key in objects:
            raise ValueError(f"duplicate object in {path}: {key}")
        objects[key] = value
    return objects


def compare(expected_path, actual_path):
    expected = read_objects(expected_path)
    actual = read_objects(actual_path)
    missing = sorted(set(expected) - set(actual))
    unexpected = sorted(set(actual) - set(expected))
    changed = sorted(
        key for key in set(expected) & set(actual)
        if expected[key] != actual[key]
    )
    return missing, unexpected, changed


def parse_args(argv=None):
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("actual")
    parser.add_argument("--expected", default=str(DEFAULT_EXPECTED))
    return parser.parse_args(argv)


def main(argv=None):
    args = parse_args(argv)
    missing, unexpected, changed = compare(args.expected, args.actual)
    if missing or unexpected or changed:
        for label, values in (
            ("missing", missing),
            ("unexpected", unexpected),
            ("changed", changed),
        ):
            for item in values:
                print(f"{label}: {item[0]}/{item[1]}", file=sys.stderr)
        return 1
    print("Dashboards export matches the versioned managed bundle.")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
