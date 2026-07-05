# Detection Rule Ownership, Tuning, Exceptions, and Retirement

Author: SJ du Preez

## Ownership

Every production rule requires:

- rule owner;
- rule version;
- positive and negative tests;
- response procedure;
- tuning guidance;
- exception policy;
- retirement criteria.

## Tuning

Tuning changes require fixture updates and must not remove evidence fields from
alerts. If a rule is noisy, prefer narrowing the rule logic before adding broad
suppression.

## Exceptions

Exceptions require:

- owner;
- reason;
- expiry date;
- affected rule ID;
- affected source, asset, or user;
- compensating control.

Permanent exceptions are not allowed without documented risk acceptance.

## Retirement

Retire a rule only when:

- it is replaced by a better rule;
- the source no longer exists;
- the risk is formally accepted;
- tests and dashboards are updated.
