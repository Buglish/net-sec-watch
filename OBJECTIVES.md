# Net Sec Watch objectives and delivery roadmap

**Author:** Salomon du Preez

This roadmap breaks the project into independently verifiable phases. Check an
item only when its implementation, tests, documentation, and operational
evidence are complete.

## Progress summary

- [x] Phase 0 - Project foundation
- [x] Phase 1 - File and workload log collection
- [ ] Phase 2 - Network-device and syslog collection
- [ ] Phase 3 - Event normalization and data quality
- [ ] Phase 4 - OpenSearch storage and lifecycle
- [ ] Phase 5 - Search, dashboards, and analyst experience
- [ ] Phase 6 - Security, privacy, and access control
- [ ] Phase 7 - Reliability, operations, and disaster recovery
- [ ] Phase 8 - Security detections and alerting
- [ ] Phase 9 - Security machine learning
- [ ] Phase 10 - Deployment portability and production release

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

- [ ] Add a Fluent Bit syslog input for TCP.
- [ ] Add a Fluent Bit syslog input for UDP.
- [ ] Add TLS-protected syslog reception.
- [ ] Provide separate example configuration for certificates and private keys.
- [ ] Preserve sender IP, transport, receive time, facility, severity, and raw event.
- [ ] Support RFC 3164 and RFC 5424 messages.
- [ ] Add sample router and firewall messages from approved test fixtures.
- [ ] Add vendor parser fixtures for the first selected router/firewall vendor.
- [ ] Route malformed messages to a dead-letter stream.
- [ ] Monitor UDP receive errors, socket buffers, and unexpected volume drops.
- [ ] Document firewall rules, ports, certificates, and device configuration.
- [ ] Test redundant receivers and sender failover.

### Completion gate

- [ ] A selected router and firewall send searchable events through TCP/TLS.
- [ ] UDP limitations and loss monitoring are demonstrated and documented.
- [ ] Receiver failure does not interrupt all supported network-device ingestion.

---

## Phase 3 - Event normalization and data quality

**Outcome:** Different sources produce a consistent, vendor-neutral event
schema while retaining the original log.

- [ ] Define the canonical event schema and field naming conventions.
- [ ] Align appropriate fields with OpenTelemetry log conventions.
- [ ] Define security fields for source, destination, action, outcome, and severity.
- [ ] Preserve every raw source message in `event.original`.
- [ ] Normalize timestamps to UTC and preserve source timezone information.
- [ ] Add timestamp inference and clock-skew indicators.
- [ ] Normalize log levels and syslog severities.
- [ ] Add host, service, device, environment, site, and collector metadata.
- [ ] Add controlled parsing-error fields and dead-letter routing.
- [ ] Prevent uncontrolled dynamic fields and mapping explosion.
- [ ] Add golden input/output parser tests for every supported source.
- [ ] Add parser version metadata to normalized events.
- [ ] Document schema compatibility and migration rules.

### Completion gate

- [ ] Golden parser tests pass for all onboarded source types.
- [ ] Required normalized fields are populated or carry an explicit error reason.
- [ ] Parser changes are versioned, reviewable, and backward-compatible or migrated.

---

## Phase 4 - OpenSearch storage and lifecycle

**Outcome:** Normalized events are securely indexed, searchable, retained, and
recoverable using a self-hosted OpenSearch cluster.

- [ ] Add an OpenSearch development deployment.
- [ ] Add authenticated TLS ingestion from Fluent Bit to OpenSearch.
- [ ] Store credentials using ignored environment files or mounted secrets.
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

## Definition of done for every checklist item

An item is complete only when:

- [ ] The implementation is committed and reviewed.
- [ ] Relevant automated tests pass.
- [ ] Security and privacy implications are addressed.
- [ ] Configuration examples contain no private values.
- [ ] Operational and user documentation is updated.
- [ ] Monitoring and failure behavior are defined where applicable.
- [ ] Acceptance evidence is linked from the pull request or release record.
