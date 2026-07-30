#!/usr/bin/env bash
set -euo pipefail

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$repo_root"

events="${TRAFFIC_CLASSIFICATION_EVENTS:-tests/orchestration/fixtures/live-events.jsonl}"
unknown_events="${TRAFFIC_CLASSIFICATION_UNKNOWN_EVENTS:-tests/orchestration/fixtures/unknown-traffic-events.jsonl}"
registry="${TRAFFIC_CLASSIFICATION_REGISTRY:-config/orchestration/model-registry-events-v1.json}"
policy="${TRAFFIC_CLASSIFICATION_POLICY:-config/orchestration/orchestration-policy-v1.json}"
outdir="${TRAFFIC_CLASSIFICATION_OUTDIR:-runtime/demos/traffic-classification}"
endpoint="${OPENSEARCH_ENDPOINT:-http://127.0.0.1:9200}"
index="${TRAFFIC_CLASSIFICATION_INDEX:-net-sec-watch-network-development}"

mkdir -p "$outdir"

predictions="$outdir/predictions.jsonl"
metrics="$outdir/metrics.prom"
candidates="$outdir/candidates.json"
summary="$outdir/summary.md"
bulk="$outdir/opensearch-bulk.ndjson"

echo "Running traffic classification demo..."

python3 ./scripts/traffic-classifier-service.py \
  --events "$events" \
  --registry "$registry" \
  --output "$predictions" \
  --metrics-output "$metrics"

python3 ./scripts/model-orchestrator.py \
  --events "$unknown_events" \
  --config "$policy" \
  --output "$candidates"

python3 - "$predictions" "$candidates" "$summary" <<'PY'
import json
import sys
from collections import Counter
from pathlib import Path

predictions = [
    json.loads(line)
    for line in Path(sys.argv[1]).read_text(encoding="utf-8").splitlines()
    if line.strip()
]
candidates = json.loads(Path(sys.argv[2]).read_text(encoding="utf-8"))
summary = Path(sys.argv[3])

classes = Counter(item["prediction"]["classification"] for item in predictions)
threats = Counter(item["prediction"]["threat_level"] for item in predictions)

lines = [
    "# Net Sec Watch traffic classification demo",
    "",
    "## Prediction summary",
    "",
    f"- Predictions: {len(predictions)}",
    f"- Classes: {dict(classes)}",
    f"- Threat levels: {dict(threats)}",
    f"- Candidate models staged: {len(candidates.get('candidates', []))}",
    f"- Candidate models rejected: {len(candidates.get('rejected', []))}",
    "",
    "## Predictions",
    "",
    "| Source event | Dataset | Classification | Threat level | Confidence | Score | Model |",
    "| --- | --- | --- | --- | ---: | ---: | --- |",
]

for item in predictions:
    pred = item["prediction"]
    evidence = {
        part.split("=", 1)[0]: part.split("=", 1)[1]
        for part in pred.get("supporting_evidence", [])
        if "=" in part
    }
    lines.append(
        "| {source} | {dataset} | {classification} | {level} | {confidence:.2f} | {score:.2f} | {model} {version} |".format(
            source=pred["source_event_id"],
            dataset=evidence.get("dataset", "-"),
            classification=pred["classification"],
            level=pred["threat_level"],
            confidence=float(pred["confidence"]),
            score=float(pred["score"]),
            model=pred["model_id"],
            version=pred["model_version"],
        )
    )

if candidates.get("candidates") or candidates.get("rejected"):
    lines.extend(["", "## Unknown-traffic orchestration", ""])
    for bucket in ("candidates", "rejected"):
        for item in candidates.get(bucket, []):
            lines.append(
                "- {status}: cluster={cluster} events={count} framework={framework}{reason}".format(
                    status=item.get("status", bucket),
                    cluster=item.get("cluster_key"),
                    count=item.get("event_count"),
                    framework=item.get("framework"),
                    reason=(
                        f" reason={item['reason']}"
                        if item.get("reason") else ""
                    ),
                )
            )

summary.write_text("\n".join(lines) + "\n", encoding="utf-8")
print(summary)
PY

python3 - "$predictions" "$candidates" "$bulk" <<'PY'
import json
import sys
from datetime import datetime, timezone
from pathlib import Path

predictions = [
    json.loads(line)
    for line in Path(sys.argv[1]).read_text(encoding="utf-8").splitlines()
    if line.strip()
]
candidates = json.loads(Path(sys.argv[2]).read_text(encoding="utf-8"))
bulk = Path(sys.argv[3])
lines = []
indexed_at = datetime.now(timezone.utc).replace(microsecond=0).isoformat().replace("+00:00", "Z")
for item in predictions:
    pred = item["prediction"]
    item = dict(item)
    item["event.fixture_timestamp"] = item.get("@timestamp")
    item["@timestamp"] = indexed_at
    item["event.dataset"] = "traffic.classification.demo"
    item["event.kind"] = "prediction"
    item["message"] = (
        f"{pred['source_event_id']} classified as "
        f"{pred['classification']} threat={pred['threat_level']} "
        f"confidence={pred['confidence']}"
    )
    lines.append(json.dumps({"index": {}}))
    lines.append(json.dumps(item, sort_keys=True))

for bucket in ("candidates", "rejected"):
    for number, candidate in enumerate(candidates.get(bucket, []), start=1):
        model_status = candidate.get("status", bucket)
        model_id = "candidate-{cluster}-{number}".format(
            cluster="-".join(str(part) for part in candidate.get("cluster_key", [])),
            number=number,
        ).replace("/", "-").replace(" ", "-")
        record = {
            "@timestamp": indexed_at,
            "event.dataset": "traffic.model_orchestration.demo",
            "event.kind": "model_candidate",
            "event.category": "ml",
            "event.type": "info",
            "event.action": model_status,
            "event.outcome": (
                "success" if model_status == "staged_shadow" else "failure"
            ),
            "event.ml_model_id": model_id,
            "event.ml_confidence": candidate.get("precision", 0),
            "event.threat_level": (
                "medium" if model_status == "staged_shadow" else "low"
            ),
            "event.threat_score": candidate.get("false_positive_rate", 0),
            "event.original": json.dumps(candidate, sort_keys=True),
            "message": (
                "model orchestration {status} cluster={cluster} "
                "events={count} framework={framework}{reason}"
            ).format(
                status=model_status,
                cluster=candidate.get("cluster_key"),
                count=candidate.get("event_count"),
                framework=candidate.get("framework"),
                reason=(
                    " reason=" + candidate["reason"]
                    if candidate.get("reason") else ""
                ),
            ),
        }
        lines.append(json.dumps({"index": {}}))
        lines.append(json.dumps(record, sort_keys=True))
bulk.write_text("\n".join(lines) + "\n", encoding="utf-8")
PY

if curl --fail --silent "$endpoint" >/dev/null; then
  echo "Indexing demo predictions into ${index}..."
  curl --fail --silent \
    --header "Content-Type: application/x-ndjson" \
    --request POST \
    --data-binary "@${bulk}" \
    "${endpoint%/}/${index}/_bulk?refresh=true" >/dev/null
  echo "Indexed predictions into ${index}."
else
  echo "OpenSearch is not reachable at ${endpoint}; skipped indexing."
fi

echo
echo "Traffic classification demo complete."
echo "Summary: ${summary}"
echo "Predictions: ${predictions}"
echo "Candidates: ${candidates}"
echo
echo "If OpenSearch was running, open Discover with data view net-sec-watch-network"
echo "and search for: event.dataset:\"traffic.classification.demo\""
echo "For model orchestration records, search for: event.dataset:\"traffic.model_orchestration.demo\""
