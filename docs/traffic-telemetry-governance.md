# Traffic Telemetry Governance and Capacity

High-volume network telemetry must not be enabled solely because a sensor can
capture it. Every Zeek or Suricata deployment requires an approved scope,
measured capacity estimate, privacy review, loss monitoring, and retention
policy.

## Required onboarding gate

Create the private policy file:

```bash
make init
```

This copies:

```text
config/traffic-telemetry-policy.example.yaml
```

to the Git-ignored:

```text
config/traffic-telemetry-policy.yaml
```

Complete the policy, then run:

```bash
make telemetry-readiness
```

The checker rejects placeholders, zero measurements, missing retention values,
enabled packet capture or TLS decryption, and incomplete approval gates.

## What the sensors collect

| Source | Typical data | Key limitation |
| --- | --- | --- |
| ASUS syslog | Router events and selected firewall decisions | UDP is best effort and does not represent every connection. |
| Zeek | Connections, DNS, HTTP, TLS, DHCP and notices | Sees only traffic delivered to its capture interface. |
| Suricata | IDS alerts, flows and protocol metadata | Alerts depend on rule coverage and tuning. |

Metadata can reveal internal addresses, device names, DNS requests, URLs,
certificate identities, user behavior, and communication relationships. Treat
it as confidential security data even when payloads are not retained.

## Capacity measurement

Run a representative pilot for at least 24 hours; seven days is preferred when
traffic varies by weekday. Record measured bytes, event rate and peak rate in
the policy file.

Use:

```text
daily raw bytes = measured bytes / measured hours × 24

retained raw bytes = daily raw bytes × retention days

planned storage = retained raw bytes
                  × index expansion factor
                  × (1 + replica count)
                  × (1 + growth percentage)
                  × operational headroom
```

Until OpenSearch measurements exist, use conservative planning assumptions:

- Index expansion factor: `1.5` to `2.5`.
- Operational headroom: at least `1.25`.
- Growth allowance: at least `25%`.
- Keep sufficient free space for merges, rollover and recovery.

The final values must come from representative indexed data, not these
defaults.

## Initial retention defaults

These are starting limits, not legal requirements:

| Dataset | Initial retention |
| --- | ---: |
| IDS alerts | 90 days |
| Connection and firewall flows | 30 days |
| DNS metadata | 30 days |
| TLS metadata | 30 days |
| HTTP metadata | 14 days |
| DHCP metadata | 30 days |
| Sensor health and packet-loss metrics | 30 days |
| Raw packet capture | Disabled (`0` days) |

Shorten retention for sensitive or high-volume datasets. Extend it only after
legal, privacy, security and storage approval. Incident holds must be explicit,
time bounded and audited.

## Privacy controls

- Capture only approved networks, VLANs and interfaces.
- Exclude guest, personal, regulated or administrative networks when they are
  outside the approved purpose.
- Do not enable payload capture or TLS decryption in the default platform.
- Restrict access by role and audit searches, exports and policy changes.
- Redact or hash approved identifiers before indexing when investigation does
  not require the original value.
- Never commit the completed policy because it can disclose network ranges,
  capacity and internal ownership.

## Packet-loss and pipeline monitoring

No sensor can report on packets it never received. Monitor each layer:

| Layer | Evidence |
| --- | --- |
| Switch/TAP | Mirror oversubscription, interface errors and dropped packets |
| Zeek | Capture-loss and packet statistics logs |
| Suricata | `stats` EVE events, including kernel and capture drops |
| Fluent Bit | Input records, retries, dropped records and filesystem backlog |
| Storage | Rejected writes, queue growth and indexing latency |

Initial thresholds:

- Capture drop rate: alert above `1%` for five minutes.
- Pipeline drop rate: target `0%`.
- Unexpected sensor silence: alert after five minutes during expected traffic.
- Sustained queue growth or rejected writes: alert immediately.

Document known blind spots such as asymmetric routing, unmirrored VLANs,
encrypted payloads, sampling and sensor maintenance.

## Production acceptance

Before production enablement:

1. The policy passes `make telemetry-readiness`.
2. Sensor placement and monitored networks are documented.
3. A representative pilot establishes bytes/day and peak events/second.
4. Loss thresholds are tested by generating or simulating a visible condition.
5. Access and retention owners approve the data classification.
6. Search storage has adequate capacity and deletion policies.
7. Sensor disablement does not interrupt routing, firewalling or log ingestion.
