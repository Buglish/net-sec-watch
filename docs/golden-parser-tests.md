# Golden parser tests

Golden tests compare real collector output from sanitized fixtures with
versioned expected field subsets in `tests/golden/expected-events.json`.

The suite covers:

- plain text, application JSON, host logs, and Docker JSON;
- RFC 3164 syslog and ASUS firewall events;
- Zeek connection, DNS, HTTP, TLS, DHCP, and notice records;
- Suricata alert, flow, DNS, HTTP, and TLS records;
- a representative parser failure routed to dead-letter.

Expected outputs contain stable, security-relevant fields and deliberately omit
runtime values such as collector observation time, clock skew, and correlation
time buckets. This keeps the tests deterministic while still detecting schema,
type, parser-version, and semantic regressions.

Run the complete suite with:

```bash
make test-integration
```

When a parser change intentionally alters normalized output, update its parser
version and the golden manifest in the same reviewed commit. Do not regenerate
expected output blindly: each changed field should be checked against the
canonical schema and source fixture.
