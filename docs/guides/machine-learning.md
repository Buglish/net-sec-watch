# Machine learning

There are two ways to use ML in Net Sec Watch:

- **On your real logs:** ML job templates read events already stored in
  OpenSearch, score them, and show findings in the **Net Sec Watch - ML
  Findings** dashboard. Start here once logs are flowing. See
  [Run ML on your real logs](#run-ml-on-your-real-logs).
- **Demos:** two examples that run on built-in sample data so you can see
  the workflow before connecting real sources. The table below compares them.

| Demo | Authentication anomaly scoring | Traffic classification |
| --- | --- | --- |
| What it does | Flags unusually high failed-login counts against a learned normal baseline | Labels network events (expected, unknown, and so on) and proposes candidate models for unknown traffic |
| How it works | Real statistics on the input you give it | Simulated: fixture events and policy rules show the workflow |
| Needs Docker? | No | Yes, to view results in Dashboards |
| Run it | `make ml-demo` | `make setup-ml` (new install) or `make traffic-classification-demo` (stack already running) |
| Results | Terminal and `runtime/demos/ml/` | **Net Sec Watch - Traffic Classification** dashboard and `runtime/demos/traffic-classification/` |
| Your own data? | Yes, see [score your own data](#score-your-own-authentication-data) | Not yet |

Nothing here blocks traffic, trains production models, or promotes models
automatically. Everything runs in **shadow mode**: it suggests, and an analyst
decides.

```text
ML suggests -> analyst reviews -> detection is tuned -> automation is approved later
```

You don't need MLflow, a GPU, or extra Python packages. Files under
`config/ml/` that mention MLflow describe the model metadata format. They
don't start a server.

## Run ML on your real logs

**Needs:** the running stack (`make setup`) with real logs arriving. To
connect routers, servers, and sensors, see
[connect your network](ingestion.md). Each job
compares an entity (an IP or host) with its own history, so you need some
history first. With the default 7-day baseline, results get more reliable
after about a week of logs. Before that, every entity looks "new".

```bash
make ml-jobs-list                            # see the templates
make ml-jobs                                 # run them all once
make ml-job JOB=firewall-denies-per-source   # run one
```

Without `make`: `python3 scripts/ml-run-job.py --all` or
`python3 scripts/ml-run-job.py --job firewall-denies-per-source`.

Then open **Net Sec Watch - ML Findings** (time picker: **Last 24 hours**).
If the dashboard is missing, run `make import-dashboards`.

### Included templates

Templates live in `config/ml/jobs/`. Each one is a short JSON file.

| Job | Reads | Flags |
| --- | --- | --- |
| `firewall-denies-per-source` | Network logs with `event.type:denied` | A source IP with far more denied connections than usual |
| `port-fanout-per-source` | Firewall, Zeek, and Suricata records with a source IP and destination port | A source IP contacting far more distinct ports than usual (scanning) |
| `auth-failures-per-host` | Normalized auth failures plus sshd/PAM "Failed password", "authentication failure", "Invalid user" messages | A host with far more failed logins than usual |
| `log-volume-per-host` | All application, system, and network logs | A host sending far more events per hour than usual |

### What a job does

1. Queries OpenSearch for matching events over the baseline period (default
   7 days) plus the evaluation period (default the last 24 hours).
2. Counts the metric per entity per window (for example denied connections
   per `source.ip` per 10 minutes). Empty windows count as zero.
3. Learns each entity's normal level (average and spread) from the baseline
   period.
4. Flags an evaluation window as **anomalous** when it is at least
   `thresholds.z_score` standard deviations above that entity's normal *and*
   at least `thresholds.min_value`.
5. Writes anomalies, plus one run summary per job, to the
   `net-sec-watch-ml-development` index. It also writes every scored window
   to `runtime/ml-jobs/<job>/scores.jsonl` and a readable
   `runtime/ml-jobs/<job>/summary.txt`.

Findings have stable IDs, so running a job again doesn't create duplicates.
Use `--no-index` to score without writing to OpenSearch, and
`--index-all-scores` to also index the windows that weren't flagged.

### Reading a finding

| Field | Meaning |
| --- | --- |
| `rule.name` / `rule.id` | Which job produced it |
| `event.correlation_key` | The entity, for example `source.ip=203.0.113.5` |
| `message` | Observed value against normal, for example `41 events in 10m (normal 0.2 ± 0.6, z=68.5)` |
| `event.threat_score` / `event.threat_level` | Score from 0 to 1 (z-score ÷ 6, capped) and its level |
| `event.original` | Full detail, including `investigate_query` |

To see the raw logs behind a finding, copy `investigate_query` from
`event.original` into Discover. Use the data view for the index in `indices`
and set the time picker to the finding's `window_start` to `window_end`.
[Analyst workflow 6](../analyst-workflows.md#workflow-6-ml-findings-review)
walks through a full review.

### Run jobs continuously

Keep jobs running every 10 minutes in a terminal:

```bash
python3 scripts/ml-run-job.py --all --every 10
```

Or schedule them with cron on the Docker host:

```text
*/10 * * * * cd /path/to/net-sec-watch && python3 scripts/ml-run-job.py --all >> runtime/ml-jobs/cron.log 2>&1
```

### Connect to a secured stack

The defaults target the local HTTP stack at `http://127.0.0.1:9200`. For the
TLS stack ([security guide](security.md)), set the connection first:

```bash
export OPENSEARCH_ENDPOINT=https://127.0.0.1:9200
export OPENSEARCH_USERNAME=admin
export OPENSEARCH_PASSWORD='<password from .env>'
export OPENSEARCH_CA_FILE=config/tls/ca.crt
make ml-jobs
```

Set `ML_RESULTS_INDEX` to write findings to a different index. Keep the
`net-sec-watch-ml-` prefix so the dashboard and analyst roles can read it.

### Make your own job

Copy a template, give it a new `id` that matches the file name, and change
the query, entity, or metric:

```json
{
  "id": "dns-queries-per-host",
  "version": "1.0.0",
  "title": "DNS queries per host",
  "description": "Flags a host making far more DNS queries than usual.",
  "source": {
    "indices": "net-sec-watch-network-*",
    "query": "_exists_:dns.question.name"
  },
  "entity_field": "host.name",
  "metric": {"type": "count"},
  "window_minutes": 10,
  "baseline_days": 7,
  "evaluation_hours": 24,
  "thresholds": {"z_score": 3.0, "min_value": 50},
  "shadow_mode": true
}
```

| Setting | Meaning |
| --- | --- |
| `source.indices` | Comma-separated index patterns to read |
| `source.query` | [Lucene query string](https://opensearch.org/docs/latest/query-dsl/full-text/query-string/). Test it in Discover first (switch the query language from DQL to Lucene) |
| `entity_field` | What to compare against its own history. It must be a keyword or IP field, for example `source.ip`, `host.name`, or `destination.ip` |
| `metric` | `{"type": "count"}` counts events. `{"type": "distinct", "field": "destination.port"}` counts different values |
| `window_minutes` | Size of each scoring window |
| `baseline_days` | How much history sets "normal" |
| `evaluation_hours` | How far back to look for anomalies on each run |
| `thresholds.z_score` | How unusual a window must be. Raise it to reduce noise |
| `thresholds.min_value` | Ignore windows below this value, however unusual |
| `shadow_mode` | Must be `true`. Jobs only suggest |

Run `make test-ml` after adding a job. It checks that every template loads.

**Limits:** this is per-entity statistical baselining, not a trained model.
It doesn't learn daily or weekly patterns, so a host that is only busy during
business hours may be flagged each morning. Raise `min_value` or `z_score`
for noisy jobs, and record false positives as described in
[analyst workflow 6](../analyst-workflows.md#workflow-6-ml-findings-review).

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
