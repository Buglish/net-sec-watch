# Detection Runbook: Firewall Deny to Sensitive Service

Author: SJ du Preez

Rule: `NSW-DET-FW-001`

## Triage

1. Identify source IP, destination IP, destination port, and firewall action.
2. Check asset criticality for the destination.
3. Look for repeated attempts from the same source.
4. Correlate with Zeek and Suricata events where available.

## Response

- Confirm the destination service should not be exposed.
- Block or rate-limit abusive sources where policy allows.
- Escalate if the destination is a critical asset.

## Tuning

Known internal scanners may be excepted with expiry and owner approval.
