# Detection Runbook: Network Connection Correlated with IDS Alert

Author: SJ du Preez

Rule: `NSW-DET-NET-001`

## Triage

1. Review Zeek connection metadata and Suricata signature details.
2. Confirm source, destination, port, protocol, and asset criticality.
3. Search for related authentication, firewall, DNS, HTTP, or TLS events.
4. Determine whether the signature is known noisy in this environment.

## Response

- Isolate or block traffic if the destination is critical and activity is
  suspicious.
- Preserve packet metadata and original events.
- Tune the IDS signature at the sensor/rule source when appropriate.

## Tuning

Prefer Suricata rule tuning over suppressing the Net Sec Watch correlation.
