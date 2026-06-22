#!/usr/bin/env python3
import json
import re
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]


def mapped_fields(properties, prefix=""):
    fields = set()
    for name, definition in properties.items():
        path = f"{prefix}.{name}" if prefix else name
        fields.add(path)
        if "properties" in definition:
            fields.update(mapped_fields(definition["properties"], path))
    return fields


catalog = json.loads(
    (ROOT / "config/dashboards/search-examples-v1.json").read_text(
        encoding="utf-8"
    )
)
template = json.loads(
    (ROOT / "config/opensearch/index-template-v1.json").read_text(
        encoding="utf-8"
    )
)
mapping_fields = mapped_fields(
    template["template"]["mappings"]["properties"]
)
approved_views = {"application", "system", "network", "dead-letter", "all"}

assert catalog["version"] == 1
assert catalog["language"] == "DQL"
assert len(catalog["examples"]) >= 8

ids = set()
covered_views = set()
features = {
    "free_text": False,
    "fielded": False,
    "boolean": False,
    "range": False,
    "exists": False,
}

for example in catalog["examples"]:
    assert set(example) == {
        "id", "title", "data_view", "query", "fields"
    }
    assert re.fullmatch(r"[a-z0-9-]+", example["id"])
    assert example["id"] not in ids
    ids.add(example["id"])
    assert example["title"].strip()
    assert example["data_view"] in approved_views
    covered_views.add(example["data_view"])
    assert example["query"].strip()
    assert len(example["query"]) <= 256
    assert len(example["fields"]) == len(set(example["fields"]))
    assert set(example["fields"]) <= mapping_fields

    features["free_text"] |= not example["fields"]
    features["fielded"] |= bool(example["fields"])
    features["boolean"] |= any(
        operator in example["query"]
        for operator in (" AND ", " OR ", "NOT ")
    )
    features["range"] |= any(
        operator in example["query"] for operator in (">=", "<=")
    )
    features["exists"] |= ": *" in example["query"]

assert {"application", "system", "network", "dead-letter"} <= covered_views
assert all(features.values())

print("OpenSearch Dashboards DQL search examples are valid.")
