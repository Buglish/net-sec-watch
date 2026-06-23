#!/usr/bin/env python3
import json
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]
GUIDE = ROOT / "docs/phase-5-analyst-workflows.md"
text = GUIDE.read_text(encoding="utf-8")

required_sections = (
    "## Before starting an investigation",
    "## DQL quick reference",
    "## Common investigation controls",
    "## Workflow 1: failed authentication triage",
    "## Workflow 2: router or firewall DROP investigation",
    "## Workflow 3: parser and dead-letter investigation",
    "## Workflow 4: application incident investigation",
    "## Export bounded evidence",
    "## Investigation completion checklist",
)
for section in required_sections:
    assert section in text, f"analyst guide is missing {section}"

for phrase in (
    "current",
    "empty",
    "delayed",
    "query_error",
    "event.original",
    "make ingestion-status",
    "scripts/export-events.py",
    "absolute UTC",
    "source.ip",
    "destination.ip",
):
    assert phrase in text, f"analyst guide is missing {phrase}"

saved_searches = [
    json.loads(line)
    for line in (
        ROOT / "config/dashboards/saved-searches-v1.ndjson"
    ).read_text(encoding="utf-8").splitlines()
    if line
]
for saved_search in saved_searches:
    title = saved_search["attributes"]["title"]
    assert title in text, f"analyst guide does not cover {title}"

examples = json.loads(
    (ROOT / "config/dashboards/search-examples-v1.json").read_text(
        encoding="utf-8"
    )
)
documented_queries = (
    "error",
    'message: "connection refused"',
    "event.action: authentication AND event.outcome: failure",
    "event.severity >= 7",
    "destination.port >= 1 AND destination.port <= 1024 AND source.ip: *",
    "NOT host.name: *",
)
catalog_queries = {item["query"] for item in examples["examples"]}
assert set(documented_queries) <= catalog_queries
for query in documented_queries:
    assert f"`{query}`" in text, f"analyst guide is missing query {query}"

assert (
    "https://docs.opensearch.org/latest/dashboards/dql/" in text
), "analyst guide must link to the upstream DQL reference"

print("OpenSearch Dashboards analyst workflow documentation is valid.")
