# Machine learning: start with a result

You can try authentication anomaly scoring without Docker, extra Python packages,
or an ML server:

```bash
python3 scripts/ml-demo.py
# Or: make ml-demo
```

Read the printed explanations or `runtime/demos/ml/summary.txt`. Each evaluation
event gets a classification (`baseline` or `anomalous`) and a score from 0 to 1.
Higher scores mean more failed logins than the normal baseline. Anomalous events
need investigation; the command does not block traffic or promote models.

## What actually runs

Authentication scoring computes the average and variation of normal failed-login
counts, then compares new counts with that baseline. It flags counts of at least
five that are at least three standard deviations above normal. This is a small
statistical example. It does not require MLflow, a GPU, or model training software.
The metadata files describe the shadow model; they do not start an MLflow server.
The fixed confidence value is example metadata, not a calibrated probability.

Traffic classification and model orchestration are separate simulated workflows
using fixture events and policy logic. Candidate staging demonstrates review
states; it does not train or deploy a production model automatically.

## View the traffic example in a dashboard

```bash
python3 scripts/setup.py --demo --ml
# Or: make setup-ml
```

This starts the local stack, imports all default dashboards, and indexes traffic
classification and candidate records. Open the URL printed by setup, choose
**Net Sec Watch - Traffic Classification**, and use **Last 24 hours**.
In Discover select `net-sec-watch-network` and search
`event.dataset:"traffic.classification.demo"`. Candidate decisions use
`event.dataset:"traffic.model_orchestration.demo"`.

Authentication `ml-demo` results are local files; they are not automatically
shown in this traffic dashboard.

## Score your own authentication data

Create a JSONL file: one JSON object per line. Aggregate failed logins into
10-minute windows for a consistent source or peer group before scoring.
The scorer does not turn raw syslog into features for you.

Minimal runnable example (`auth-windows.jsonl`):

```json
{"event.id":"normal-1","split":"training","features":{"failed_login_count_10m":1}}
{"event.id":"normal-2","split":"training","features":{"failed_login_count_10m":2}}
{"event.id":"normal-3","split":"training","features":{"failed_login_count_10m":0}}
{"event.id":"new-1","split":"evaluation","features":{"failed_login_count_10m":12}}
```

Run:

```bash
python3 scripts/ml-demo.py --events auth-windows.jsonl --output-dir runtime/my-ml
```

`training` rows supply the normal baseline; only `evaluation` rows get predictions.
Use unique IDs, non-negative whole counts, and both splits. For real evaluation,
use representative known-normal history for training and a later time period for
evaluation. Keep different populations separate; a busy server and a quiet router
need different baselines. Tiny examples verify the workflow, not reliability.

Outputs are `predictions.jsonl`, `summary.txt`, and `metrics.json`.
For meaningful accuracy metrics, label evaluation rows with
`"label":"analyst_confirmed_suspicious"` or
`"label":"analyst_confirmed_benign"`. The fixture evaluator treats every other
label (including missing labels) as benign, so its metrics are not accuracy
evidence for unlabelled data. `p95_latency_ms` and `alert_reduction` are fixed
contract example values, not measurements of your run.

Review anomalous events against original logs and deterministic detections.
Record false positives, adjust the baseline population, and rerun on later
labelled data before considering automation. Continuous feature extraction,
training, calibrated confidence, and automatic promotion require additional
implementation. See [ML contracts](../ml-storage-contracts.md) and
[advanced add-ons](addons-and-special-features.md) for the existing interfaces.
