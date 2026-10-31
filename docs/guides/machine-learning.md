# Machine learning

Net Sec Watch includes two ML features. They are separate, need different
things to run, and show results in different places.

| | Authentication anomaly scoring | Traffic classification |
| --- | --- | --- |
| What it does | Flags unusually high failed-login counts against a learned normal baseline | Labels network events (expected, unknown, and so on) and proposes candidate models for unknown traffic |
| How it works | Real statistics on the input you give it | Simulated: fixture events and policy rules show the workflow |
| Needs Docker? | No | Yes, to view results in Dashboards |
| Run it | `make ml-demo` | `make setup-ml` (new install) or `make traffic-classification-demo` (stack already running) |
| Results | Terminal and `runtime/demos/ml/` | **Net Sec Watch - Traffic Classification** dashboard and `runtime/demos/traffic-classification/` |
| Your own data? | Yes, see [score your own data](#score-your-own-authentication-data) | Not yet |

Neither feature blocks traffic, trains production models, or promotes models
automatically. Both run in **shadow mode**: they suggest, and an analyst
decides.

```text
ML suggests -> analyst reviews -> detection is tuned -> automation is approved later
```

You don't need MLflow, a GPU, or extra Python packages for either feature.
Files under `config/ml/` that mention MLflow describe the model metadata
format. They don't start a server.

## Authentication anomaly scoring

```bash
python3 scripts/ml-demo.py               # or: make ml-demo
```

Each evaluation event gets a classification (`baseline` or `anomalous`) and a
score from 0 to 1. A higher score means more failed logins than normal. The
explanations are printed and also saved in `runtime/demos/ml/summary.txt`.

**How it scores:** it calculates the average and spread of failed-login counts
in the `training` rows. An `evaluation` row is flagged when its count is at
least 5 *and* at least three standard deviations above that average. The
confidence value in the output is fixed example metadata, not a calibrated
probability.

These results stay in local files. They don't appear in the Traffic
Classification dashboard.

### Score your own authentication data

The scorer reads a JSONL file (one JSON object per line). It doesn't turn raw
syslog into features. You need to count failed logins per 10-minute window
first, for one source or one group of similar sources.

Example `auth-windows.jsonl`:

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

Rules for the input:

- `training` rows set the normal baseline. Only `evaluation` rows get scored.
  Include both.
- Give each row a unique `event.id` and a whole, non-negative count.
- Train on known-normal history, then evaluate a later time period.
- Keep different populations in separate files. A busy server and a quiet
  router need different baselines.
- A tiny file only shows the workflow works. It doesn't show the scores are
  reliable.

The run writes `predictions.jsonl`, `summary.txt`, and `metrics.json` to the
output folder. Accuracy metrics only mean something when evaluation rows have
labels: `"label":"analyst_confirmed_suspicious"` or
`"label":"analyst_confirmed_benign"`. Rows without a label count as benign.
`p95_latency_ms` and `alert_reduction` are fixed example values, not
measurements.

## Traffic classification

**New install:** `make setup-ml` runs this for you. See
[getting started](getting-started.md).

**Stack already running:**

```bash
make traffic-classification-demo
```

This command:

1. classifies the fixture network events;
2. decides which unknown-traffic clusters get a candidate model (staged or
   rejected);
3. writes local files under `runtime/demos/traffic-classification/`;
4. indexes the results into OpenSearch, if OpenSearch is reachable. If it isn't
   reachable, it says it skipped this step.

Then open **Net Sec Watch - Traffic Classification** with the time picker set
to **Last 24 hours**. If the dashboard is missing, run `make import-dashboards`.

In Discover (`net-sec-watch-network` data view):

| Records | Search |
| --- | --- |
| Classifications | `event.dataset:"traffic.classification.demo"` |
| Candidate model decisions | `event.dataset:"traffic.model_orchestration.demo"` |

Useful fields:

| Field | Meaning |
| --- | --- |
| `event.classification` | Predicted class, for example `expected` or `unknown` |
| `event.ml_confidence` | Confidence score |
| `event.threat_level` / `event.threat_score` | Normalized threat level and score |
| `event.ml_model_id` | Active or candidate model ID |
| `event.action` | Candidate state: `staged_shadow` or `rejected` |
| `message` | Plain-language explanation |
| `event.original` | Original prediction or candidate payload |

Local output files:

| File | Contents |
| --- | --- |
| `predictions.jsonl` | Classification predictions |
| `candidates.json` | Candidate model staged and rejected decisions |
| `summary.md` | Readable summary |
| `opensearch-bulk.ndjson` | Records sent to OpenSearch |

The classifier uses hints already present in the fixture events, so the
results show the review workflow, not real traffic analysis. Classifying live
traffic needs more implementation work. See
[advanced add-ons](addons-and-special-features.md).

## Check the ML code

```bash
make test-ml             # authentication scoring contracts
make test-orchestration  # traffic classification and orchestration contracts
```

`compose.orchestration.yaml` (the `orchestration` Compose profile) runs the
same fixture-based classifier and orchestrator in containers to check they work
there. It doesn't write to OpenSearch or the dashboards, so you don't need it to
view ML results.

## Using results responsibly

- Check flagged events against the original logs and the deterministic
  detections (`make test-detections`).
- Record false positives, adjust the baseline group, and re-score later
  labelled data before trusting any score.
- Don't automatically block traffic based on unvalidated model output.

More detail: [ML storage contracts](../ml-storage-contracts.md),
[security machine learning](../security-machine-learning.md), and
[adaptive traffic intelligence](../adaptive-traffic-intelligence.md).
