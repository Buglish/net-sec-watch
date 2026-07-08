# Detection Runbook: Repeated Authentication Failures

Author: SJ du Preez

Rule: `NSW-DET-AUTH-001`

## Triage

1. Confirm the source IP, username, and affected host or service.
2. Check whether failures are followed by a successful login.
3. Determine whether the source is an approved scanner or test automation.
4. Search for related VPN, firewall, and IDS alerts from the same source.

## Response

- Disable or reset the account if compromise is suspected.
- Block the source IP when policy allows.
- Preserve event references and authentication logs.

## Tuning

Only suppress known scanners or test accounts with an expiry date and owner.
