# Security machine learning

Author: SJ du Preez

## Outcome

Open-source machine learning assists analysts with explainable anomaly
detection and risk prioritization without autonomous enforcement.

## Selected use case

The selected measurable use case is authentication failure anomaly
prioritization, defined in `config/ml/ml-use-case-v1.json`.

The model may help analysts prioritize repeated failed-login activity, but it
must not disable accounts, block traffic, or trigger autonomous enforcement.

## Dataset policy

`config/ml/dataset-policy-v1.json` requires:

- privacy review before production use;
- exclusion of restricted fields such as secrets, tokens, cookies, and raw
  event payloads;
- time-separated training and evaluation ranges;
- explicit dataset usage rights.

The repository fixture at `tests/ml/fixtures/auth-shadow-evaluation.jsonl` is
synthetic and sanitized.

## Baselines and framework decisions

`config/ml/baselines-v1.json` defines deterministic and statistical baselines.

Framework decisions are documented in `config/ml/framework-evaluation-v1.json`:

- OpenSearch Anomaly Detection is a streaming-baseline candidate.
- scikit-learn is the approved offline-model candidate.
- River is deferred until online learning is justified.
- PyTorch is deferred until simpler methods fail approved requirements.

## MLflow tracking and registry

`config/ml/mlflow-experiment-contract-v1.json` defines required experiment
tags, metrics, and artifacts.

`config/ml/mlflow-model-registry-entry-v1.json` defines the registry metadata
required by Adaptive traffic intelligence:

- model type;
- input feature schema;
- output field names;
- shadow-mode status;
- promotion approval record;
- rollback pointer.

## Shadow mode

`scripts/ml-shadow-score.py` scores synthetic evaluation fixtures and writes
prediction records. Predictions are separate records and do not alter original
events.

Run:

```bash
make test-ml
```

## Explainability

Every prediction must include:

- contributing features;
- supporting evidence;
- score;
- confidence;
- model ID and version;
- human-readable explanation.

## Analyst feedback

Feedback records are append-only and use the predictions data-stream mapping.
An example is stored at `config/ml/analyst-feedback-example.json`.

## Drift and resource monitoring

`config/ml/drift-monitoring-v1.json` defines monitors for:

- data quality;
- feature drift;
- score drift;
- CPU and memory use.

## Approval, rollback, retraining, and retirement

`config/ml/ml-lifecycle-v1.json` defines ownership, required approvals,
minimum shadow-mode duration, rollback triggers, retraining cadence, and
retirement criteria.

## Production gates

The repository implementation supports shadow mode, but production completion
requires analyst-approved evaluation evidence showing explainable results and
an agreed investigation-metric improvement.
