# Phase 11 machine-learning storage contracts

Phase 4 reserves OpenSearch storage structures for the Phase 11 security
classification workflow without requiring a model service to exist yet.

## Predictions and analyst feedback

Classification results and analyst feedback use the append-only data stream:

`net-sec-watch-predictions-<environment>`

The higher-priority `net-sec-watch-predictions-v1` template distinguishes two
record types with `record.kind`:

- `prediction` records link a source event to a model ID/version,
  classification, threat level, score, confidence, and explanation;
- `feedback` records link an analyst verdict and disposition to a prediction.

Feedback is appended as a separate event rather than updating the original
prediction. This preserves the prediction produced at inference time and an
auditable history of analyst decisions. The stream inherits the Phase 4
rollover, retention, replica, disk-protection, and snapshot behavior.

## Model metadata

The model registry uses the ordinary index:

`net-sec-watch-model-metadata`

It stores model identity, semantic version, task, framework, status, artifact
URI and SHA-256 digest, feature names, owner, training dataset/time range,
evaluation metrics, and registration timestamps.

This is deliberately an ordinary index rather than a data stream because model
records are registry entities queried by stable model ID and version. Phase 11
may update lifecycle status such as `candidate`, `active`, or `retired`.

## Template collision protection

The generic event data-stream template has priority 200. Predictions use
priority 300 and model metadata uses priority 400. Therefore:

- prediction names resolve to the dedicated predictions data-stream template;
- `net-sec-watch-model-metadata` resolves to a non-data-stream template;
- neither structure accidentally inherits an incompatible mapping contract.

Run `make test-opensearch-secure` to verify template resolution and query
representative prediction, feedback, and model metadata records.
