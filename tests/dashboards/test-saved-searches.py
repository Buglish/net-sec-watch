#!/usr/bin/env python3
import json
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


objects = [
    json.loads(line)
    for line in (
        ROOT / "config/dashboards/saved-searches-v1.ndjson"
    ).read_text(encoding="utf-8").splitlines()
    if line
]
template = json.loads(
    (ROOT / "config/opensearch/index-template-v1.json").read_text(
        encoding="utf-8"
    )
)
fields = mapped_fields(template["template"]["mappings"]["properties"])
approved_views = {
    "net-sec-watch-application",
    "net-sec-watch-system",
    "net-sec-watch-network",
    "net-sec-watch-dead-letter",
}
expected_ids = {
    "net-sec-watch-authentication-failures",
    "net-sec-watch-parser-failures",
    "net-sec-watch-suspicious-network-activity",
    "net-sec-watch-application-errors",
}

assert {item["id"] for item in objects} == expected_ids

for item in objects:
    assert item["type"] == "search"
    attributes = item["attributes"]
    assert attributes["title"].startswith("Net Sec Watch - ")
    assert attributes["description"]
    assert attributes["sort"] == [["@timestamp", "desc"]]
    assert "event.original" in attributes["columns"]
    assert set(attributes["columns"]) <= fields

    source = json.loads(
        attributes["kibanaSavedObjectMeta"]["searchSourceJSON"]
    )
    assert source["query"]["language"] == "kuery"
    assert source["query"]["query"]
    assert source["filter"] == []
    assert source["indexRefName"] == (
        "kibanaSavedObjectMeta.searchSourceJSON.index"
    )

    assert item["references"] == [
        {
            "name": "kibanaSavedObjectMeta.searchSourceJSON.index",
            "type": "index-pattern",
            "id": item["references"][0]["id"],
        }
    ]
    assert item["references"][0]["id"] in approved_views

print("OpenSearch Dashboards saved investigations are valid.")
