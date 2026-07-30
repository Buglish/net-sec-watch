#!/usr/bin/env python3
import json
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]

objects = [
    json.loads(line)
    for line in (
        ROOT / "config/dashboards/data-views-v1.ndjson"
    ).read_text(encoding="utf-8").splitlines()
    if line
]

expected = {
    "net-sec-watch-application": "net-sec-watch-application-*",
    "net-sec-watch-system": "net-sec-watch-system-*",
    "net-sec-watch-network": "net-sec-watch-network-*",
    "net-sec-watch-dead-letter": "net-sec-watch-dead-letter-*",
}

assert {item["id"] for item in objects} == set(expected)

for item in objects:
    assert item["type"] == "index-pattern"
    attributes = item["attributes"]
    assert attributes["title"] == expected[item["id"]]
    assert attributes["timeFieldName"] == "@timestamp"
    fields = json.loads(attributes["fields"])
    by_name = {field["name"]: field for field in fields}
    assert by_name["@timestamp"]["type"] == "date"
    assert by_name["@timestamp"]["aggregatable"] is True
    assert by_name["@timestamp"]["searchable"] is True
    for field in ("event.dataset", "event.original", "message"):
        assert field in by_name

print("OpenSearch Dashboards data views include searchable fields.")
