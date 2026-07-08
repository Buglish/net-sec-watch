# Detection Runbook: VPN Login from Untrusted Network

Author: SJ du Preez

Rule: `NSW-DET-VPN-001`

## Triage

1. Confirm the user, source IP, and VPN gateway.
2. Check whether the login matches approved travel, remote work, or emergency
   access.
3. Review recent failed authentication attempts for the same user.
4. Confirm MFA status if available.

## Response

- Contact the user or account owner.
- Revoke sessions and rotate credentials if suspicious.
- Escalate high-confidence compromise indicators to incident response.

## Tuning

Travel exceptions must be time bounded and approved by the rule owner.
