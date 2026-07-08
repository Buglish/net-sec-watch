# Phase 8 - Security Detections and Alerting

Author: SJ du Preez

## Outcome

Deterministic security rules identify important activity and route actionable
alerts to analysts. The alert schema is source-agnostic so deterministic query
rules, threshold rules, correlation rules, and future Phase 11 ML model outputs
can share the same notification destinations without a schema migration.

## Detection coverage

The initial use cases are defined in `config/detections/detection-use-cases-v1.json`:

- authentication: repeated failed login attempts;
- firewall: denied traffic to sensitive services;
- VPN: successful login from an untrusted network;
- network: Zeek connection correlated with Suricata IDS alert.

Rules are versioned in Git in `config/detections/rules-v1.json`.

## Alert schema and routing

`config/detections/alert-schema-v1.json` defines the shared alert fields. Every
alert includes:

- source type (`deterministic_query`, `deterministic_threshold`,
  `deterministic_correlation`, or future `ml_model`);
- rule ID, version, owner, kind, severity, and priority;
- deduplication and suppression keys;
- routing destination and notification channels;
- event references.

Notification destinations are configured in
`config/detections/notification-destinations-v1.json` with webhook and
email-compatible environment-variable placeholders.

## Priority inputs

Alert priority combines:

- rule severity;
- asset criticality from `config/detections/asset-criticality-v1.json`;
- source confidence from `config/detections/source-confidence-v1.json`.

## Deduplication and suppression

`config/detections/dedup-suppression-v1.json` defines per-rule keys and
suppression windows. Suppression must be time bounded and must not delete the
original alert evidence.

## Analyst disposition and false positives

`config/detections/false-positive-register-v1.json` defines the required
analyst disposition fields. Production false-positive completion remains open
until analysts approve alert-volume and false-positive thresholds from real
operational data.

## Rule lifecycle

`config/detections/rule-lifecycle-v1.json` requires every production rule to
have an owner, version, tests, response procedure, tuning guidance, exception
policy, and retirement criteria.

## Tests

Run:

```bash
make test-phase8-detections
```

The tests execute positive and negative fixtures through
`scripts/run-detections.py`.
