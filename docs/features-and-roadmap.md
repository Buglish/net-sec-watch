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
- Malformed-event dead-letter routing.
- Optional Zeek network-metadata sensor.
- Optional Suricata IDS/flow sensor.
- Normalization across router firewall, Zeek, and Suricata observations.

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
- Search examples for common analyst tasks.
- Investigation workflow documentation.
- Event export tooling.
- Saved-object reproducibility checks.
- Seven-day search benchmark tooling.

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
- Unknown-traffic policy and monitored orchestration queue.
- Candidate model orchestration simulation with staged and rejected candidates.
- Dynamic model registry events, active slots, promotion, rollback, and
  retirement records.
- Optional self-hosted LLM enrichment policy with advisor-only constraints.
- Analyst oversight and feedback policy.
- Governance, monitoring, safety, and open-source runtime policy.

## Still needs real-world evidence or release action

### Ingestion sources

- Enterprise router/firewall sending searchable TCP/TLS logs.
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

- Live novel unknown-traffic pattern detected, clustered, modeled, staged,
  approved, and promoted without manual configuration changes.

## Current usability

Net Sec Watch is usable today as a local development/prototype SIEM platform
for open-source log ingestion, OpenSearch storage, dashboards, deterministic
detections, security controls, and simulated ML/adaptive workflows.

It is not yet a production release until the remaining real-world validation
and release actions above are completed.
