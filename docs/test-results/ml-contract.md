# ML contract test results

Author: SJ du Preez

## Result

Pass.

The machine-learning repository contract validates:

- selected authentication anomaly use case;
- analyst decisions, success metrics, and prohibited uses;
- privacy-reviewed time-separated dataset policy;
- deterministic and statistical baselines;
- OpenSearch Anomaly Detection, scikit-learn, River, and PyTorch evaluation
  decisions;
- MLflow experiment and model registry metadata;
- precision, recall, false-positive rate, latency, and alert-reduction metrics;
- contributing features and supporting evidence for predictions;
- shadow-mode scoring;
- append-only analyst feedback;
- drift and resource monitoring policy;
- approval, rollback, retraining, retirement, and ownership processes;
- model/dataset licensing and usage rights;
- model-serving hot-swap API contract;
- ML-disabled behavior that preserves ingestion, search, and deterministic
  detections.

## Command

```bash
make test-ml
```

## Production gates still open

- A model completes an analyst-approved shadow-mode evaluation.
- Results are explainable and improve an agreed investigation metric.
