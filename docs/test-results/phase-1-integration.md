# Phase 1 integration test result

**Date:** 20 June 2026  
**Environment:** Ubuntu on WSL 2 with Docker Desktop  
**Docker Engine:** 29.5.2  
**Fluent Bit:** 4.0.14  
**Command:** `make test-integration`

## Result

Phase 1 passed.

- [x] Plain-text file events collected.
- [x] JSON application events collected and parsed.
- [x] Linux-style system events collected.
- [x] Docker JSON events collected and parsed.
- [x] Multiline Java stack traces assembled into single events.
- [x] Collection continued after file rotation.
- [x] Persisted SQLite offsets prevented replay after collector restart.
- [x] Filesystem buffering recovered events after the downstream receiver was
  stopped and restarted.
- [x] Test containers, network, and state volume were removed after completion.

## Test architecture

The integration harness creates:

1. A Fluent Bit collector with four file-based inputs.
2. A Fluent Bit receiver using the Forward protocol.
3. A persistent collector state volume for offsets and filesystem buffering.
4. An ignored `tests/runtime/` directory containing isolated test fixtures.

Unique markers are appended during each test and must appear in receiver output
within the configured timeout. The restart test also asserts that its marker
appears exactly once.

## Console summary

```text
PASS: all sample source types were collected
PASS: multiline stack trace was assembled into one event
PASS: collection continued after file rotation
PASS: persisted offsets prevented replay after collector restart
PASS: filesystem buffering recovered after receiver interruption
PASS: all Objective 1 integration tests completed
```
