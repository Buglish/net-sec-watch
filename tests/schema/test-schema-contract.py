#!/usr/bin/env python3
"""Validate the canonical event schema without third-party dependencies."""

import json
from pathlib import Path


ROOT = Path(__file__).resolve().parents[2]
SCHEMA = ROOT / "config/schema/canonical-event-schema-v1.json"

REQUIRED = {
    "@timestamp",
    "event.dataset",
    "event.kind",
    "event.original",
    "event.parser_version",
    "event.schema_version",
}
OTEL_FIELDS = {
    "@timestamp",
    "event.observed",
    "message",
    "log.level",
    "log.severity.number",
}
SECURITY_FIELDS = {
    "source.ip",
    "source.port",
    "destination.ip",
    "destination.port",
    "network.transport",
    "network.protocol",
    "event.action",
    "event.outcome",
    "event.severity",
}
ML_FIELDS = {
    "event.classification",
    "event.threat_level",
    "event.threat_score",
    "event.ml_model_id",
    "event.ml_confidence",
}


def main() -> None:
    schema = json.loads(SCHEMA.read_text(encoding="utf-8"))
    properties = schema["properties"]
    required = set(schema["required"])

    assert schema["$schema"].endswith("2020-12/schema")
    assert properties["event.schema_version"]["const"] == "1.0.0"
    assert REQUIRED <= required
    assert OTEL_FIELDS <= properties.keys()
    assert SECURITY_FIELDS <= properties.keys()
    assert ML_FIELDS <= properties.keys()
    assert ML_FIELDS.isdisjoint(required), "ML fields must remain optional"
    assert properties["log.severity.number"]["maximum"] == 24
    assert properties["source.port"]["maximum"] == 65535
    assert properties["destination.port"]["maximum"] == 65535

    invalid_names = [
        name
        for name in properties
        if name != "@timestamp" and (name.lower() != name or " " in name)
    ]
    assert not invalid_names, f"invalid canonical field names: {invalid_names}"

    print("PASS: canonical event schema contract")


if __name__ == "__main__":
    main()
