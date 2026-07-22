# Add-ons and special features

Core Net Sec Watch can run as a log/SIEM platform without these optional
features. Enable them when the environment and operational need justify them.

## Zeek network metadata

Use Zeek when you can observe network traffic through SPAN, TAP, or gateway
placement.

```bash
make up-zeek
```

Detailed guide: `docs/zeek-network-sensor.md`.

## Suricata IDS and flow telemetry

Use Suricata for IDS alerts and EVE JSON flow metadata.

```bash
make up-suricata
make update-suricata-rules
```

Detailed guide: `docs/suricata-ids-sensor.md`.

## Security detections

Detection rules live under `config/detections/`.

```bash
make test-detections
```

Detection runbooks live under `docs/runbooks/detections/`.

## Machine learning shadow mode

ML is governed and explainable. It does not autonomously enforce actions.

```bash
make test-ml
```

Configuration lives under `config/ml/`.

## Adaptive traffic intelligence

Adaptive traffic intelligence simulates live classification, unknown-traffic
orchestration, candidate model staging, and model rollback.

```bash
make test-orchestration
```

For a quick demo with screenshot-friendly output:

```bash
make traffic-classification-demo
```

The demo writes:

- `runtime/demos/traffic-classification/predictions.jsonl`
- `runtime/demos/traffic-classification/candidates.json`
- `runtime/demos/traffic-classification/summary.md`

If local OpenSearch is running, it also indexes the prediction records into
`net-sec-watch-network-development`. Open Discover, select
`net-sec-watch-network`, and search:

```text
event.dataset:"traffic.classification.demo"
```

Configuration lives under `config/orchestration/`.

## Optional local LLM enrichment

LLM enrichment is optional and self-hosted only. The LLM is advisor-only and
cannot promote models or generate alerts directly.

Policy lives in `config/orchestration/llm-enrichment-policy-v1.json`.
