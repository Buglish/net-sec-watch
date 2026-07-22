# Adaptive traffic intelligence and live model orchestration

Author: SJ du Preez

## Outcome

Adaptive traffic intelligence defines a self-hosted, source-agnostic pipeline for live
classification, unknown-traffic detection, model candidate generation,
shadow-mode staging, analyst approval, hot-swap promotion, rollback, and
optional local LLM explanation.

## Serving API

`config/orchestration/serving-api-v1.json` defines a FastAPI-compatible
self-hosted service. The service subscribes to enriched events from OpenSearch
or a Fluent Bit forward stream and writes predictions to the OpenSearch storage
predictions data stream.

Disabling the serving API must not interrupt ingestion, OpenSearch indexing,
search, or deterministic detection and alerting rules.

## Classification output

`config/orchestration/classification-output-v1.json` defines classification
labels, threat levels, confidence, model identifiers, contributing features,
supporting evidence, dashboard fields, and detection and alerting alert routing.

Predictions are separate records. Original events are never modified.

## Unknown traffic and orchestration

`config/orchestration/unknown-traffic-policy-v1.json` defines unknown traffic
as low-confidence or unlabeled events. Unknowns are routed to a monitored
orchestration queue that is separate from the network collection dead-letter stream.

`config/orchestration/orchestration-policy-v1.json` defines dataset slicing,
DBSCAN/k-means clustering, candidate training, evaluation thresholds, rejection
logging, and shadow-mode staging.

## Dynamic model registry

`config/orchestration/model-registry-events-v1.json` records training,
evaluation, promotion, rollback, and retirement events. Active slots and
rollback pointers are maintained per traffic class. Promotions are consumed by
the serving API without restart.

## Optional local LLM enrichment

`config/orchestration/llm-enrichment-policy-v1.json` defines Ollama-compatible
self-hosted LLM enrichment. The LLM is optional and advisory only. It cannot
promote models or generate alerts directly.

## Analyst oversight

`config/orchestration/analyst-oversight-v1.json` defines approval/rejection,
event reclassification, threat-level override, false-positive flagging, and
append-only feedback.

## Monitoring and safety

`config/orchestration/governance-monitoring-v1.json` defines serving,
orchestration, quality, and optional LLM metrics. It also requires free,
self-hostable, open-source runtime components and no paid API dependency.

## Local validation

```bash
make test-orchestration
```

## Production gate still open

The live gate for detecting, clustering, modeling, staging, approving, and
promoting a novel unknown-traffic pattern remains open until recorded in a real
environment.
