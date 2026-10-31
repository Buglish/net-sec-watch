# Net Sec Watch feature status

Author: SJ du Preez

This document replaces the milestone checklist. It describes what
exists in the application today and what still needs evidence or production
hardening, grouped by product capability.

## Available features

### Project foundation

- Open-source-only project policy and MIT license.
- Safe `.env.example` configuration pattern with real `.env` ignored by Git.
- Repository verification, formatting, secret scanning, and CI workflow.
- Local initialization with `make init`.
- Architecture diagram and project specification.

### Log collection and ingestion

- Fluent Bit collector container.
- Plain-text log collection.
- Structured JSON application log collection.
- Multiline Java stack trace parsing.
- Linux system and authentication log collection.
- Docker JSON container log collection.
- File offset persistence and filesystem buffering.
- Rotation handling and sample log generation.
- UDP, TCP, and TLS syslog reception.
- RFC 3164 and RFC 5424 syslog support.
- ASUS RT-AC68U UDP syslog support and firewall-drop parsing.
- Enterprise firewall key/value syslog normalization for common source,
  destination, action, protocol, device, and policy fields.
- Malformed-event dead-letter routing.
- Optional Zeek network-metadata sensor.
- Optional Suricata IDS/flow sensor.
- Normalization across router firewall, Zeek, and Suricata observations.
- Step-by-step guide for connecting routers and firewalls (ASUS, pfSense,
  OPNsense, FortiGate, UniFi, Meraki, MikroTik, OpenWrt, Cisco IOS), Linux
  servers, Windows computers, application files, and traffic sensors.

### Normalization and data quality

- Canonical event schema.
- OpenTelemetry-aligned log conventions.
- Security fields for source, destination, action, outcome, and severity.
- Parser error handling and dead-letter records.
- Mapping explosion protection.
- Golden parser fixtures and automated parser tests.
- Reserved ML field namespace.

### Storage, lifecycle, and search

- OpenSearch development deployment.
- Secure OpenSearch profile.
- Index templates and data-stream routing.
- Hot/warm/archive/delete lifecycle policy.
- Snapshot repository configuration and restore test.
- Replica and disk-watermark configuration.
- Storage expansion and capacity planning.
- Searchability SLO tooling.
- Prediction and model-metadata storage contracts.

### Dashboards and analyst workflow

- OpenSearch Dashboards deployment.
- Managed saved objects, data views, saved searches, and dashboards.
- Managed data views include field metadata for `@timestamp` and mapped
  investigation fields so saved visualizations load reliably after import.
- Search examples for common analyst tasks.
- Investigation workflow documentation.
- Event export tooling.
- Saved-object reproducibility checks.
- Seven-day search benchmark tooling.
- Local dashboard default route can point to a managed Net Sec Watch dashboard
  instead of stale sample dashboard IDs.

### Security, privacy, and access control

- TLS for browser/API/syslog paths in the secure profile.
- OIDC integration using optional Keycloak profile.
- Administrator, analyst, read-only, source-owner, and service roles.
- Data restrictions by stream, tenant, field, and source-owner document filter.
- OpenSearch Security audit configuration.
- Collector-side sensitive-field redaction and hashing.
- Data classification and source-onboarding review policy.
- Secret and certificate rotation procedures.
- SBOM and vulnerability audit workflow with Syft and Grype.
- Approved-license policy.

### Operations and disaster recovery

- Monitoring thresholds for ingestion, queues, OpenSearch, snapshots, and TLS.
- Alert routing policy and ownership.
- `make ingestion-status` reports application, system, network, and dead-letter
  freshness using local `.env` values without shell-evaluating secrets/config.
- Runbooks for collector backlog, parser failure, disk pressure, mapping
  conflicts, backup/restore, failure testing, load testing, upgrades, rollback,
  and disaster recovery.
- Service-level targets, RTO/RPO targets, and escalation ownership.
- Syslog load-test script.
- Disaster-recovery dry-run script.

### Security detections and alerting

- Deterministic detection use cases for authentication, firewall, VPN, and
  network correlation.
- Query, threshold, and correlation rule support.
- Source-agnostic alert schema compatible with deterministic and ML alerts.
- Asset criticality and source confidence priority adjustments.
- Webhook and email-compatible destination definitions.
- Deduplication and suppression policy.
- Positive and negative detection fixtures.
- Analyst disposition and false-positive register.
- Rule lifecycle, ownership, tuning, exception, and retirement policy.

### Security machine learning

- Governed authentication anomaly use case.
- Privacy-reviewed, time-separated dataset policy.
- Deterministic and statistical baselines.
- OpenSearch Anomaly Detection, scikit-learn, River, and PyTorch evaluation
  decisions.
- MLflow experiment and registry metadata contracts.
- Shadow-mode scoring fixture and local scorer.
- ML job templates that run on real indexed logs: firewall denies per source,
  port fan-out per source, authentication failures per host, and log volume per
  host. Each entity is compared with its own baseline.
- `make ml-jobs` runner with continuous mode, stable finding IDs, run
  summaries, and the managed `Net Sec Watch - ML Findings` dashboard.
- Prediction explainability fields and append-only feedback pattern.
- Drift and resource monitoring policy.
- Approval, rollback, retraining, retirement, and licensing policy.

### Deployment portability

- Docker Compose development deployment.
- Secure/production-style Compose override.
- Linux VM installation script.
- Kubernetes manifests for namespace, service accounts, RBAC, config, secret
  example, PVCs, deployments, services, and network policies.
- Environment examples for development, test, staging, and production.
- Deployment preflight, upgrade, and rollback helpers.
- Supported-version and compatibility policy.
- Installation, administration, and troubleshooting guide.

### Adaptive traffic intelligence

- Self-hosted traffic-classifier service contract and local simulation.
- Screenshot-friendly traffic classification demo that writes local summaries
  and indexes demo predictions into OpenSearch.
- Managed `Net Sec Watch - Traffic Classification` dashboard with saved
  searches for all classification events and unknown/high-interest traffic.
- Managed model orchestration saved search and dashboard panel for staged and
  rejected candidate model records.
- Unknown-traffic policy and monitored orchestration queue.
- Candidate model orchestration simulation with staged and rejected candidates.
- Dynamic model registry events, active slots, promotion, rollback, and
  retirement records.
- Optional self-hosted LLM enrichment policy with advisor-only constraints.
- Analyst oversight and feedback policy.
- Governance, monitoring, safety, and open-source runtime policy.

## Still needs real-world evidence or release action

### Ingestion sources

- Enterprise router/firewall TCP/TLS collection validated with the actual
  target appliance and production-like certificates.
- Live Zeek or Suricata sensor producing searchable metadata from mirrored,
  tapped, or gateway traffic.

### Analyst experience

- Usability testing with target users.
- Analyst completion of agreed investigations without server access.
- Standard seven-day searches meeting the agreed response-time target on real
  data volume.

### Operations and resilience

- Production service-level targets met under agreed load.
- Documented disaster-recovery exercise meeting approved RTO/RPO.
- Operator confirmation that critical alerts are diagnosable using runbooks.

### Detection quality

- Analyst-approved alert volume and false-positive thresholds from operational
  data.

### Machine learning quality

- Analyst-approved shadow-mode model evaluation.
- Evidence that explainable ML results improve an agreed investigation metric.

### Deployment and release

- Tag and publish the first supported release.
- Clean-environment deployment using only documented automation.
- Security, resilience, performance, and recovery tests in the target
  deployment environment.

### Adaptive model orchestration

- Live novel unknown-traffic pattern detected, clustered, approved, and
  promoted without manual configuration changes.

## Proposed objectives (for review)

**Status:** proposed on 2026-11-01. Not yet approved or scheduled.

The features below are common in SIEM platforms but missing from Net Sec
Watch. Each one was checked against the repository. Review each objective and
mark it approved, changed, deferred, or rejected before work starts.

Priority key: **P1** closes a gap in the core collect → detect → alert →
investigate loop. **P2** improves coverage or analyst context. **P3** is useful
but can wait.

### Detection and alerting

| ID | Objective | Current state | Done when | Priority | Decision |
| --- | --- | --- | --- | --- | --- |
| OBJ-01 | Run detection rules on a schedule against indexed data | `scripts/run-detections.py` only reads a JSONL file (`--events`). Rules never run against OpenSearch | Rules run every N minutes against the network, system, and application indexes, with no duplicate alerts across runs | P1 | |
| OBJ-02 | Store alerts in OpenSearch with an alerts dashboard | No alerts index, data view, or dashboard. Alerts only exist in script output | Alerts are written to a `net-sec-watch-alerts` index and shown in a managed **Alerts** dashboard and saved search | P1 | |
| OBJ-03 | Deliver alert notifications | `notification-destinations-v1.json` defines webhook and email contracts, but nothing sends them | High and critical alerts reach a configured webhook or SMTP server, with retry, rate limits, and a test command | P1 | |
| OBJ-04 | Track alert triage status | Dispositions and false positives are recorded in a config file, not per alert | Each alert has a status (new, investigating, closed), owner, disposition, and notes, editable by analysts with an audit trail | P2 | |
| OBJ-05 | Map rules and alerts to MITRE ATT&CK | No tactic or technique fields on rules or alerts | Every rule declares ATT&CK tactic and technique IDs, alerts carry them, and a dashboard panel shows coverage | P2 | |
| OBJ-06 | Import Sigma community rules | No Sigma support | A documented, tested path converts approved Sigma rules into Net Sec Watch rules with fixtures | P3 | |

### Ingestion and parsing

| ID | Objective | Current state | Done when | Priority | Decision |
| --- | --- | --- | --- | --- | --- |
| OBJ-07 | Parse more common firewall formats | pfSense and OPNsense `filterlog`, MikroTik, UniFi, and Meraki logs are stored as text only, so firewall dashboards and ML jobs can't use them | Each format fills `source.ip`, `destination.ip`, ports, protocol, and action, with golden parser fixtures | P1 | |
| OBJ-08 | Parse Windows security events | Windows events forwarded through NXLog are stored as text only | Logon success and failure, account lockout, and privilege events (for example 4624, 4625, 4740, 4672) fill user, host, source IP, and outcome fields | P2 | |
| OBJ-09 | Collect NetFlow, IPFIX, or sFlow | No flow-export input. Full connection data needs a Zeek or Suricata sensor | An open-source flow collector receives router flow exports and indexes normalized connection records | P2 | |
| OBJ-10 | Collect DNS query logs | No parser for Pi-hole, AdGuard Home, or dnsmasq query logs | DNS queries from at least one home or small-office resolver are searchable by client, domain, and response | P2 | |
| OBJ-11 | Forward from remote collectors to a central stack | The architecture describes edge collectors with mutual-TLS forwarding, but only the integration test uses Fluent Bit forwarding | A documented remote-collector profile buffers locally and forwards over mutual TLS to the central collector | P3 | |

### Enrichment and context

| ID | Objective | Current state | Done when | Priority | Decision |
| --- | --- | --- | --- | --- | --- |
| OBJ-12 | Add GeoIP and ASN enrichment | Nothing fills `source.geo` or `source.asn`, although the orchestration policy lists `source.asn` as a clustering feature | Public IPs gain country and ASN from a self-hosted open database, refreshed on a schedule, with private ranges skipped | P2 | |
| OBJ-13 | Match events against threat intelligence | No IP or domain indicator matching | Approved open-source blocklists are downloaded on a schedule and matching events are tagged and raise an alert | P2 | |
| OBJ-14 | Map internal IPs to device names | Asset criticality exists, but there's no IP-to-device lookup | DHCP leases or a maintained asset list add a device name and owner to internal `source.ip` and `destination.ip` values | P2 | |

### Operations

| ID | Objective | Current state | Done when | Priority | Decision |
| --- | --- | --- | --- | --- | --- |
| OBJ-15 | Schedule snapshots automatically | The backup runbook sets a daily target, but snapshots are created by hand | A snapshot policy takes and prunes snapshots daily, and a failed snapshot raises an operations alert | P1 | |
| OBJ-16 | Add a platform health dashboard | Health is checked from the terminal (`make ingestion-status`, Fluent Bit metrics) | A managed dashboard shows stream freshness, events per source, dead-letter rate, and collector metrics | P2 | |
| OBJ-17 | Run ML jobs as a service | ML jobs run from a terminal (`--every`) or from cron set up by hand | An optional Compose service runs the ML jobs on a schedule and reports its last run | P3 | |
| OBJ-18 | Send scheduled summary reports | No scheduled reporting | A weekly summary of alerts, ML findings, and top denied sources is generated and delivered | P3 | |

### Response (later)

| ID | Objective | Current state | Done when | Priority | Decision |
| --- | --- | --- | --- | --- | --- |
| OBJ-19 | Analyst-approved response actions | Out of scope by design: everything runs in shadow mode | After shadow-mode quality is approved, an analyst can trigger a reviewed, reversible action (for example, adding an IP to a firewall block list) with a full audit trail. Nothing runs automatically | P3 | |

## Current usability

Net Sec Watch is usable today as a local development/prototype SIEM platform
for open-source log ingestion, OpenSearch storage, dashboards, deterministic
detections, security controls, and simulated ML/adaptive workflows.

It is not yet a production release until the remaining real-world validation
and release actions above are completed.
