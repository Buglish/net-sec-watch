# Net Sec Watch

**Author:** Salomon du Preez

Net Sec Watch is a fully self-hosted, free and open-source platform for collecting,
searching, visualizing, and analyzing logs from servers, applications, routers,
firewalls, switches, and other network devices.

The reference architecture uses:

- Fluent Bit for file tailing, syslog reception, parsing, buffering, and forwarding.
- OpenSearch for indexed storage, full-text search, lifecycle management, and snapshots.
- OpenSearch Dashboards for Discover-style searching, filtering, dashboards, and alerts.
- OpenSearch Anomaly Detection, scikit-learn, River, MLflow, and optional PyTorch for
  later security machine-learning capabilities.

All required production components and libraries must be self-hostable and use
approved OSI open-source licenses. The platform must not depend on paid APIs,
proprietary cloud services, license keys, or feature-gated enterprise modules.

## Objectives

1. Collect logs from text files, rotated files, applications, containers, and
   operating systems.
2. Receive syslog over TCP, UDP, or TLS from routers, firewalls, switches, and
   other network appliances.
3. Normalize vendor-specific logs into a consistent, searchable event schema
   while retaining each original event.
4. Provide a Kibana-like experience with free-text search, field filters,
   time-range analysis, histograms, saved searches, dashboards, and exports.
5. Protect log data through TLS, centralized authentication, role-based access,
   tenant isolation, audit logging, retention policies, and sensitive-data redaction.
6. Support reliable buffering, lifecycle management, snapshots, health monitoring,
   disaster recovery, and horizontal scaling.
7. Add a governed machine-learning phase for security anomaly detection, transparent
   risk scoring, analyst feedback, explainability, and model-drift monitoring.
8. Run on Linux virtual machines, bare metal, Docker, or Kubernetes without a
   mandatory proprietary service.

## Architecture

![OpenLog architecture](docs/images/openlog-architecture.png)

The event flow is:

1. Fluent Bit agents tail log files, while redundant receivers accept network
   device syslog.
2. Processing pipelines parse, normalize, enrich, redact, and classify events.
3. OpenSearch stores events in managed data streams and provides indexed search.
4. OpenSearch Dashboards provides exploration, dashboards, alerts, and analyst workflows.
5. A later security ML phase consumes governed event features and returns anomaly
   scores and supporting evidence without performing automatic enforcement.

## Planned delivery phases

1. Discovery and sizing
2. Technical proof of concept
3. Minimum viable product
4. Production hardening
5. Source and dashboard expansion
6. Security machine learning

## Repository status

This repository currently contains the project overview and reference architecture.
Implementation manifests, collector configurations, parsers, dashboards, tests,
and runbooks will be added during delivery.
