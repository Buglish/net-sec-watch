# Net Sec Watch objectives and delivery roadmap

**Author:** Salomon du Preez

This roadmap breaks the project into independently verifiable phases. Check an
item only when its implementation, tests, documentation, and operational
evidence are complete.

## Progress summary

- [x] Phase 0 - Project foundation
- [x] Phase 1 - File and workload log collection
- [ ] Phase 2 - Network-device and syslog collection
- [x] Phase 3 - Event normalization and data quality
- [ ] Phase 4 - OpenSearch storage and lifecycle
- [ ] Phase 5 - Search, dashboards, and analyst experience
- [ ] Phase 6 - Security, privacy, and access control
- [ ] Phase 7 - Reliability, operations, and disaster recovery
- [ ] Phase 8 - Security detections and alerting
- [ ] Phase 9 - Security machine learning
- [ ] Phase 10 - Deployment portability and production release
- [ ] Phase 11 - Adaptive traffic intelligence and live model orchestration

---

## Phase 0 - Project foundation

**Outcome:** The repository is safe, repeatable, documented, and ready for
collaborative implementation.

- [x] Create the `net-sec-watch` Git repository.
- [x] Add the initial README and architecture diagram.
- [x] Document the author and project objectives.
- [x] Define an open-source-only dependency policy.
- [x] Add `.env.example` for safe runtime configuration examples.
- [x] Ignore real `.env`, local overrides, secrets, certificates, and keys.
- [x] Add `make init` to create private local configuration safely.
- [x] Add an OSI license file for the project.
- [x] Add contribution and code-review guidance.
- [x] Add automated formatting, linting, and secret scanning.
- [x] Add a CI workflow that runs repository verification on every change.

### Completion gate

- [x] A new contributor can clone the repository, initialize local
  configuration, and run all non-runtime checks using documented commands.
- [x] CI blocks invalid configuration, committed secrets, and failed tests.

---

## Phase 1 - File and workload log collection

**Outcome:** Logs are reliably collected from files, applications, containers,
and Linux operating systems.

Implementation guide:
[Objective 1: file and workload log collection](docs/objective-1-file-collection.md)

- [x] Add a Fluent Bit collector container.
- [x] Collect plain-text log files.
- [x] Collect structured JSON application logs.
- [x] Parse multiline Java stack traces.
- [x] Collect Linux system and authentication logs.
- [x] Collect Docker JSON container logs.
- [x] Persist independent file offsets using SQLite databases.
- [x] Enable filesystem buffering for temporary downstream interruption.
- [x] Configure rotation handling and provide a rotation test script.
- [x] Provide safe sample logs and a sample event generator.
- [x] Expose local health and Prometheus metrics endpoints.
- [x] Add static Objective 1 verification.
- [x] Enable Docker Desktop integration for the Ubuntu WSL distribution.
- [x] Run and verify the Fluent Bit container using Docker Compose.
- [x] Confirm new events are collected from every sample source.
- [x] Confirm collection continues correctly after file rotation.
- [x] Confirm offsets survive a collector restart without replaying all events.
- [x] Confirm buffered events recover after a simulated output interruption.
- [x] Add automated integration tests for collection, rotation, and restart.
- [x] Document onboarding for a new file or container log source.

### Completion gate

- [x] All supported sample inputs pass automated end-to-end tests.
- [x] No acknowledged file event is lost during rotation or collector restart.
- [x] Collector health, throughput, retries, and failures are observable.

---

## Phase 2 - Network-device and syslog collection

**Outcome:** Routers, firewalls, switches, and appliances can send logs to
redundant, observable syslog receivers.

- [x] Add a Fluent Bit syslog input for TCP.
- [x] Add a Fluent Bit syslog input for UDP.
- [x] Add TLS-protected syslog reception.
- [x] Provide separate example configuration for certificates and private keys.
- [x] Preserve sender IP, transport, receive time, facility, severity, and raw event.
- [x] Support RFC 3164 and RFC 5424 messages.
- [x] Add sample router and firewall messages from approved test fixtures.
- [x] Add vendor parser fixtures for the first selected router/firewall vendor.
- [x] Route malformed messages to a dead-letter stream.
- [x] Monitor UDP receive errors, socket buffers, and unexpected volume drops.
- [x] Document firewall rules, ports, certificates, and device configuration.
- [x] Enable and verify ASUS firewall packet logging for dropped traffic.
- [x] Add ASUS firewall-event fixtures and parse source/destination addresses,
  ports, protocol, interface, and allow/deny action where the firmware supplies them.
- [x] Clearly document that router syslog contains system, authentication,
  wireless, and selected firewall events but is not a complete network-flow feed.
- [x] Test redundant receivers and sender failover.

### Network traffic visibility

Router syslog alone cannot describe every connection crossing the network.
Full traffic metadata and intrusion-detection visibility require a sensor that
can observe the traffic, normally through a managed-switch mirror/SPAN port,
network TAP, or supported gateway deployment.

- [x] Add Zeek as an optional open-source network-metadata sensor.
- [x] Collect Zeek connection, DNS, HTTP, TLS, DHCP, and notice logs through
  Fluent Bit.
- [x] Add Suricata as an optional open-source IDS and flow sensor.
- [x] Collect Suricata EVE JSON alerts, flows, DNS, HTTP, and TLS events through
  Fluent Bit.
- [x] Document sensor placement using a switch mirror/SPAN port, network TAP,
  or gateway interface, including the limitations of each option.
- [x] Ensure sensor deployment does not require decrypting TLS payloads to
  produce connection and protocol metadata.
- [x] Add representative, sanitized Zeek fixtures with automated ingestion tests.
- [x] Add representative, sanitized Suricata fixtures with automated ingestion tests.
- [x] Normalize router firewall, Zeek, and Suricata events without treating
  duplicate observations as separate incidents.
- [x] Document storage-volume, privacy, packet-loss, and retention implications
  before enabling high-volume traffic telemetry.

### Completion gate

- [ ] The RT-AC68U sends system and selected firewall events through UDP syslog,
  and the documented limitations are verified.
- [ ] A selected enterprise router or firewall sends searchable events through
  TCP/TLS.
- [x] UDP limitations and loss monitoring are demonstrated and documented.
- [x] Receiver failure does not interrupt all supported network-device ingestion.
- [ ] At least one Zeek or Suricata sensor produces searchable connection
  metadata from mirrored, tapped, or gateway traffic.

---

## Phase 3 - Event normalization and data quality

**Outcome:** Different sources produce a consistent, vendor-neutral event
schema while retaining the original log.

- [x] Define the canonical event schema and field naming conventions.
- [x] Align appropriate fields with OpenTelemetry log conventions.
- [x] Define security fields for source, destination, action, outcome, and severity.
- [x] Preserve every raw source message in `event.original`.
- [x] Normalize timestamps to UTC and preserve source timezone information.
- [x] Add timestamp inference and clock-skew indicators.
- [x] Normalize log levels and syslog severities.
- [x] Add host, service, device, environment, site, and collector metadata.
- [x] Add controlled parsing-error fields and dead-letter routing.
- [x] Prevent uncontrolled dynamic fields and mapping explosion.
- [x] Add golden input/output parser tests for every supported source.
- [x] Add parser version metadata to normalized events.
- [x] Document schema compatibility and migration rules.
- [x] Reserve the ML enrichment field namespace (`event.classification`,
  `event.threat_level`, `event.threat_score`, `event.ml_model_id`,
  `event.ml_confidence`) as defined but initially unpopulated, so Phase 11
  live classification can write to these fields without schema conflicts or
  mapping explosions.

### Completion gate

- [x] Golden parser tests pass for all onboarded source types.
- [x] Required normalized fields are populated or carry an explicit error reason.
- [x] Parser changes are versioned, reviewable, and backward-compatible or migrated.

---

## Phase 4 - OpenSearch storage and lifecycle

**Outcome:** Normalized events are securely indexed, searchable, retained, and
recoverable using a self-hosted OpenSearch cluster.

- [x] Add an OpenSearch development deployment.
- [x] Add authenticated TLS ingestion from Fluent Bit to OpenSearch.
- [x] Store credentials using ignored environment files or mounted secrets.
- [ ] Define index templates and explicit field mappings.
- [ ] Define data streams by log class and environment.
- [ ] Configure rollover based on age and size.
- [ ] Configure hot, warm, archive, and deletion policies as required.
- [ ] Configure replica counts and disk watermarks.
- [ ] Add a dead-letter data stream.
- [ ] Add snapshot repository configuration.
- [ ] Test snapshot creation and restoration.
- [ ] Measure raw-to-indexed storage expansion using representative logs.
- [ ] Document capacity formulas and scaling thresholds.
- [ ] Define a predictions data stream and a model-metadata index for Phase 11
  classification write-back, model registry queries, and analyst feedback
  storage. These streams do not need to be populated until Phase 11 but must
  not conflict with existing index templates.

### Completion gate

- [ ] At least 95% of accepted events are searchable within 10 seconds at normal load.
- [ ] Retention policies roll over and delete test data automatically.
- [ ] A snapshot restores successfully into a clean test environment.

---

## Phase 5 - Search, dashboards, and analyst experience

**Outcome:** Users have a Kibana-like interface for finding, filtering,
visualizing, saving, and exporting log evidence.

- [ ] Deploy OpenSearch Dashboards.
- [ ] Configure data views for each approved log class.
- [ ] Provide free-text and fielded search examples.
- [ ] Configure time selection, histograms, filters, and event expansion.
- [ ] Display normalized fields and `event.original`.
- [ ] Create saved searches for common operational and security investigations.
- [ ] Create infrastructure, application, network, and security dashboards.
- [ ] Add bounded CSV or JSON export.
- [ ] Add clear empty-result, query-error, and delayed-ingestion states.
- [ ] Document query syntax and analyst workflows.
- [ ] Perform usability testing with target users.

### Completion gate

- [ ] An analyst can complete the agreed investigation scenarios without direct server access.
- [ ] Standard seven-day searches meet the agreed response-time target.
- [ ] Saved searches and dashboards are exportable and reproducible.

---

## Phase 6 - Security, privacy, and access control

**Outcome:** Collection and analysis protect sensitive logs through
authentication, authorization, encryption, redaction, and audit controls.

- [ ] Enable TLS for browser, API, ingestion, and cluster traffic.
- [ ] Integrate OIDC, SAML, LDAP, or Active Directory.
- [ ] Define administrator, analyst, read-only, source-owner, and service roles.
- [ ] Restrict data by data stream, tenant, field, or document where required.
- [ ] Enable security audit logging.
- [ ] Audit privileged searches, exports, and configuration changes.
- [ ] Add collector-side redaction and hashing for approved sensitive fields.
- [ ] Define log-data classification and source-onboarding reviews.
- [ ] Define secret rotation and certificate renewal procedures.
- [ ] Add dependency and container vulnerability scanning.
- [ ] Generate and retain a software bill of materials.
- [ ] Verify every runtime dependency uses an approved open-source license.

### Completion gate

- [ ] Unauthorized test users cannot access restricted logs or exports.
- [ ] No production credential or private key is stored in Git.
- [ ] Security review findings are resolved or formally accepted.

---

## Phase 7 - Reliability, operations, and disaster recovery

**Outcome:** Operators can observe, scale, recover, upgrade, and support the
platform predictably.

- [ ] Monitor accepted, dropped, retried, buffered, and failed events.
- [ ] Monitor collector silence and unexpected source-volume changes.
- [ ] Monitor queue depth, rejected writes, shard health, and disk watermarks.
- [ ] Alert on snapshot failure and certificate expiry.
- [ ] Add runbooks for collector backlog and parser failure.
- [ ] Add runbooks for node failure, disk pressure, and mapping conflicts.
- [ ] Add backup and restore runbooks.
- [ ] Add certificate rotation and secret rotation runbooks.
- [ ] Perform load testing at 1.5 times expected peak ingestion.
- [ ] Perform collector, network, and OpenSearch failure testing.
- [ ] Test rolling upgrades and rollback.
- [ ] Perform a disaster-recovery exercise.
- [ ] Define operational service levels and escalation ownership.

### Completion gate

- [ ] Production service-level targets are met under the agreed load.
- [ ] A documented recovery exercise meets the approved RTO and RPO.
- [ ] Operators can diagnose all critical alerts using maintained runbooks.

---

## Phase 8 - Security detections and alerting

**Outcome:** Deterministic security rules identify important activity and route
actionable alerts to analysts.

- [ ] Define initial authentication, firewall, VPN, and network detection use cases.
- [ ] Add query-based and threshold-based detection rules.
- [ ] Correlate related events across an approved time window.
- [ ] Add asset criticality and source confidence to alert priority.
- [ ] Configure webhook and email-compatible notification destinations.
- [ ] Add alert deduplication and suppression.
- [ ] Add detection testing with positive and negative fixtures.
- [ ] Track false positives and analyst disposition.
- [ ] Version detection rules in Git.
- [ ] Document rule ownership, tuning, exceptions, and retirement.
- [ ] Design the alert schema and notification routing to be source-agnostic:
  alerts from deterministic query rules, threshold rules, and Phase 11 ML
  model outputs must share the same schema and reach the same notification
  destinations without schema changes in Phase 11.

### Completion gate

- [ ] Agreed test scenarios reliably generate the expected alerts.
- [ ] Alert volume and false-positive rate meet analyst-approved thresholds.
- [ ] Every production rule has an owner, test, version, and response procedure.

---

## Phase 9 - Security machine learning

**Outcome:** Open-source machine learning assists analysts with explainable
anomaly detection and risk prioritization without autonomous enforcement.

- [ ] Select one measurable authentication or network anomaly use case.
- [ ] Define analyst decisions, success metrics, and prohibited uses.
- [ ] Build privacy-reviewed, time-separated training and evaluation datasets.
- [ ] Establish deterministic and statistical baselines.
- [ ] Evaluate OpenSearch Anomaly Detection for streaming baselines.
- [ ] Evaluate scikit-learn models for offline anomaly detection.
- [ ] Evaluate River only where online learning is justified.
- [ ] Use PyTorch only if simpler methods fail the approved requirements.
- [ ] Track experiments, datasets, metrics, and artifacts using MLflow.
- [ ] Report precision, recall, false-positive rate, latency, and alert reduction.
- [ ] Provide contributing features and supporting evidence for every score.
- [ ] Run selected models in shadow mode.
- [ ] Add analyst feedback without altering original events.
- [ ] Monitor data quality, feature drift, score drift, and resource use.
- [ ] Define approval, rollback, retraining, retirement, and ownership processes.
- [ ] Confirm model and dataset licensing and usage rights.
- [ ] Design the model serving API to support hot-swap loading: new model
  versions registered in MLflow must be consumable by the serving API without
  a full restart, so Phase 11 can promote models into a live pipeline.
- [ ] Structure MLflow model registry entries to include the metadata fields
  required by Phase 11: model type, input feature schema, output field names,
  shadow-mode status, promotion approval record, and rollback pointer.

### Completion gate

- [ ] A model completes an analyst-approved shadow-mode evaluation.
- [ ] Results are explainable and improve an agreed investigation metric.
- [ ] Disabling ML alerts does not interrupt ingestion, search, or deterministic rules.

---

## Phase 10 - Deployment portability and production release

**Outcome:** Net Sec Watch can be deployed and maintained consistently on
supported Linux, Docker, and Kubernetes environments without proprietary
runtime dependencies.

- [ ] Complete the Docker Compose development deployment.
- [ ] Add automated Linux VM deployment.
- [ ] Add Kubernetes manifests or a Helm chart.
- [ ] Separate development, test, staging, and production configuration.
- [ ] Add resource requests, limits, and storage classes.
- [ ] Add network policies and least-privilege service identities.
- [ ] Add environment validation and preflight checks.
- [ ] Add upgrade, rollback, backup, and restore automation.
- [ ] Publish supported-version and compatibility policies.
- [ ] Complete installation, administration, and troubleshooting documentation.
- [ ] Complete production readiness and security reviews.
- [ ] Tag and publish the first supported release.

### Completion gate

- [ ] A clean environment can be deployed using only documented automation.
- [ ] The deployment passes security, resilience, performance, and recovery tests.
- [ ] All required runtime components remain free, self-hostable, and open source.

---

## Phase 11 - Adaptive traffic intelligence and live model orchestration

**Outcome:** The platform streams events through a live classification and
threat-scoring pipeline and continuously improves itself. When unknown or
low-confidence traffic is detected, an autonomous orchestration loop clusters
the new patterns, trains candidate models, evaluates them against quality
thresholds, stages them in shadow mode, and promotes approved models into the
live serving pipeline — no manual retraining required. A self-hosted large
language model (Ollama / Llama 3 or equivalent) optionally enriches
analyst-facing explanations of new patterns but is never required for the
automation loop. The platform grows progressively smarter while analysts
retain full override authority and observability at every step. All components
must satisfy the open-source license policy.

### 11.1 Streaming classification engine

- [ ] Deploy a self-hosted model serving API (FastAPI or equivalent) alongside
  the OpenSearch stack.
- [ ] Subscribe the classification engine to enriched events from the Fluent
  Bit forward stream or OpenSearch.
- [ ] Run inference on network and syslog events in near-real-time.
- [ ] Write per-event classification output back to the predictions data stream
  defined in Phase 4 using the reserved field namespace from Phase 3.
- [ ] Expose classification latency, throughput, queue depth, and error rate as
  Prometheus metrics.
- [ ] Confirm that disabling the serving API does not interrupt ingestion,
  OpenSearch indexing, search, or deterministic detection rules.

### 11.2 Traffic classification and threat scoring

- [ ] Output a classification label, threat level (critical / high / medium /
  low / info), confidence score, and model identifier per event.
- [ ] Output the contributing features for every non-trivial score (explainability
  requirement carried forward from Phase 9).
- [ ] Populate `event.classification`, `event.threat_level`,
  `event.threat_score`, `event.ml_model_id`, and `event.ml_confidence`
  (schema reserved in Phase 3) without modifying the original event fields.
- [ ] Surface classification output in the Phase 5 analyst dashboards and
  route threat-level alerts through the Phase 8 alert pipeline.

### 11.3 Unknown-traffic detection and orchestration trigger

- [ ] Define and document the "unknown traffic" threshold: events with
  confidence below an analyst-approved value and no matching classification
  label.
- [ ] Route low-confidence events to a monitored orchestration queue, separate
  from the Phase 2 dead-letter stream.
- [ ] Apply rate limiting and event deduplication to prevent orchestration
  storms during burst or scanning traffic.
- [ ] Emit an observable signal and optional alert when the rate of unknown
  events exceeds a configurable threshold.

### 11.4 Autonomous model update loop

The core automation pipeline uses open-source ML only. No external API or LLM
is required for the update loop to function.

- [ ] Extract a labeled dataset slice from recent events matching each
  unknown-traffic cluster.
- [ ] Apply unsupervised clustering (DBSCAN or k-means) to group novel events
  into candidate new-pattern sets.
- [ ] Train a candidate classifier or anomaly model (scikit-learn or River)
  for each sufficiently large candidate cluster.
- [ ] Evaluate the candidate model against approved precision, recall,
  false-positive rate, and latency thresholds.
- [ ] Reject and log any model that fails evaluation rather than silently
  discarding it; emit a metric for rejected candidates.
- [ ] Stage passing models in shadow mode using the Phase 9 shadow infrastructure.
- [ ] Accumulate analyst feedback from shadow-mode observations and use it in
  the next retraining cycle to improve the candidate.

### 11.5 Dynamic model registry and hot-swap

- [ ] Extend the Phase 9 MLflow model registry with promotion events that the
  serving API consumes to load new models without restart (hot-swap designed
  in Phase 9).
- [ ] Maintain an active model slot and a rollback pointer for every traffic
  class; promotion atomically replaces the active slot.
- [ ] Record every training run, evaluation result, promotion, rollback, and
  retirement as an auditable event in the model-metadata index defined in
  Phase 4.
- [ ] Demonstrate rollback to the previous model version within one serving
  cycle after a quality-degradation alert.

### 11.6 Optional self-hosted LLM enrichment layer

This sub-phase is optional. The autonomous update loop (11.3–11.5) operates
fully without it.

- [ ] Select and deploy a self-hosted LLM (Ollama with Llama 3, Mistral, or
  Phi) confirmed under an approved open-source license.
- [ ] Design structured prompts that supply the LLM with the normalized event
  sample, cluster statistics, and recent similar events, and request a
  human-readable interpretation and recommended feature list.
- [ ] Parse and validate all LLM output before it enters the model generation
  pipeline; reject malformed or out-of-schema responses.
- [ ] Surface LLM-generated pattern descriptions as analyst-readable
  annotations on new-model promotion records and in dashboards.
- [ ] Log all LLM queries, prompt versions, response latency, and resource
  use to the audit trail.
- [ ] The LLM acts as advisor only: no LLM output triggers model promotion or
  alert generation directly without passing through the evaluation and
  approval gate.
- [ ] Confirm that disabling the LLM component leaves 11.1–11.5 fully
  operational.

### 11.7 Analyst oversight and feedback

- [ ] New models may not promote from shadow to live without explicit analyst
  approval (manual review or a configurable automatic-approval threshold
  backed by documented evaluation criteria).
- [ ] Provide an approval and rejection workflow in the Phase 5 dashboards or
  a dedicated operator interface.
- [ ] Allow analysts to reclassify individual events, override threat levels,
  and flag false positives without modifying original indexed events.
- [ ] Persist analyst feedback as labeled records in the analyst-feedback index
  and incorporate them into the next retraining cycle.
- [ ] Track analyst disposition rates, override frequency, and model agreement
  rate as quality metrics.

### 11.8 Governance, monitoring, and safety

- [ ] Monitor the serving API: inference latency, queue depth, error rate, and
  resource use.
- [ ] Monitor the autonomous loop: candidate models trained, evaluated,
  rejected, promoted, and rolled back per time window.
- [ ] Monitor model quality after live promotion: classification drift, score
  drift, and analyst override rate; alert when any metric crosses an approved
  threshold.
- [ ] Monitor the LLM component if enabled: query rate, latency, error rate,
  and resource use.
- [ ] Confirm all Phase 11 runtime components satisfy the open-source license
  policy and have no dependency on paid APIs or proprietary cloud services.
- [ ] Define ownership, review frequency, minimum performance floor, and
  retirement criteria for every live model.
- [ ] Document the full orchestration loop, approval gates, rollback procedure,
  and safety constraints.

### Completion gate

- [ ] A novel unknown-traffic pattern is detected, clustered, modeled, staged,
  approved, and promoted to the live pipeline without manual configuration
  changes.
- [ ] Model promotion and rollback are observable, auditable, and reversible
  within one serving cycle.
- [ ] Disabling Phase 11 entirely leaves the platform fully operational at
  Phase 9 capability with no data loss and no interruption to ingestion,
  search, or deterministic detection rules.
- [ ] All runtime components in Phase 11 remain free, self-hostable, and
  open source.

---

## Definition of done for every checklist item

An item is complete only when:

- [ ] The implementation is committed and reviewed.
- [ ] Relevant automated tests pass.
- [ ] Security and privacy implications are addressed.
- [ ] Configuration examples contain no private values.
- [ ] Operational and user documentation is updated.
- [ ] Monitoring and failure behavior are defined where applicable.
- [ ] Acceptance evidence is linked from the pull request or release record.
