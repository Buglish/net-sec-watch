#!/usr/bin/env python3
import json
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]


def read_ndjson(path):
    return [
        json.loads(line)
        for line in path.read_text(encoding="utf-8").splitlines()
        if line
    ]


dashboards = read_ndjson(
    ROOT / "config/dashboards/dashboards-v1.ndjson"
)
saved_searches = read_ndjson(
    ROOT / "config/dashboards/saved-searches-v1.ndjson"
)
search_ids = {item["id"] for item in saved_searches}
guide_id = "net-sec-watch-analyst-state-guide"
guide = read_ndjson(
    ROOT / "config/dashboards/analyst-states-v1.ndjson"
)
assert len(guide) == 1
assert guide[0]["id"] == guide_id
assert guide[0]["type"] == "visualization"
guide_state = json.loads(guide[0]["attributes"]["visState"])
assert guide_state["type"] == "markdown"
guide_markdown = guide_state["params"]["markdown"]
for phrase in ("No matching events", "Delayed ingestion", "Query error"):
    assert phrase in guide_markdown
expected = {
    "net-sec-watch-infrastructure",
    "net-sec-watch-application",
    "net-sec-watch-network",
    "net-sec-watch-security",
}

assert {item["id"] for item in dashboards} == expected

for item in dashboards:
    assert item["type"] == "dashboard"
    attributes = item["attributes"]
    assert attributes["title"].startswith("Net Sec Watch - ")
    assert attributes["description"]
    assert attributes["timeRestore"] is False
    assert json.loads(attributes["optionsJSON"]) == {
        "useMargins": True,
        "hidePanelTitles": False,
    }
    search_source = json.loads(
        attributes["kibanaSavedObjectMeta"]["searchSourceJSON"]
    )
    assert search_source["query"] == {"query": "", "language": "kuery"}
    assert search_source["filter"] == []

    panels = json.loads(attributes["panelsJSON"])
    references = item["references"]
    assert panels
    assert len(panels) == len(references)
    assert len({panel["panelIndex"] for panel in panels}) == len(panels)
    assert len({panel["panelRefName"] for panel in panels}) == len(panels)
    assert {panel["panelRefName"] for panel in panels} == {
        reference["name"] for reference in references
    }
    for panel in panels:
        grid = panel["gridData"]
        assert grid["w"] > 0 and grid["h"] > 0
        assert panel["version"] == "3.7.0"
    for reference in references:
        if reference["name"] == "panel_guide":
            assert reference == {
                "name": "panel_guide",
                "type": "visualization",
                "id": guide_id,
            }
        else:
            assert reference["type"] == "search"
            assert reference["id"] in search_ids
    assert sum(
        reference["id"] == guide_id for reference in references
    ) == 1

security = next(
    item for item in dashboards if item["id"] == "net-sec-watch-security"
)
assert len(security["references"]) == 4

print("OpenSearch Dashboards investigation dashboards are valid.")
