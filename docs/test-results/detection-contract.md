# Detection contract test results

Author: SJ du Preez

## Result

Pass.

The detection and alerting contract validates:

- authentication, firewall, VPN, and network detection use cases;
- query, threshold, and correlation rule kinds;
- asset criticality and source confidence priority inputs;
- webhook and email-compatible destinations;
- deduplication and suppression keys;
- positive and negative fixtures;
- analyst disposition and false-positive register;
- Git-versioned production rules;
- owner, test, version, and response procedure for every production rule;
- source-agnostic alert schema compatible with Adaptive traffic intelligence ML model outputs.

## Commands

```bash
make test-detections
```

## Production gate still open

Alert volume and false-positive rate require analyst-approved thresholds from
real operational data.
