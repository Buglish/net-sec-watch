# Phase 5 saved-object reproducibility result

**Test date:** June 23, 2026  
**Result:** PASS

The isolated secured OpenSearch Dashboards round-trip test completed
successfully:

- generated bundle: 13 managed objects;
- bundle SHA-256:
  `775c4396d185e49c7e61609145293836e57b4d6094ea46dddeb901ae9dea5864`;
- initial API export matched the versioned bundle;
- all managed objects were deleted and confirmed absent;
- the versioned bundle restored all 13 objects;
- the post-restore API export matched the versioned object graph.

The tested graph contains four data views, four saved searches, one analyst
state visualization, and four dashboards. The disposable OpenSearch and
Dashboards volumes were removed after the test.

Reproduce the result with:

```bash
make test-dashboards-reproducibility
```
