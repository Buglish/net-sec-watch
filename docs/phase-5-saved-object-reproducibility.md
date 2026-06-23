# Phase 5 saved-object export and reproducibility

Net Sec Watch stores every managed OpenSearch Dashboards data view, saved
search, visualization, and dashboard in source control. A generated bundle and
round-trip test prove that the complete object graph can be exported and
restored without manual recreation.

## Versioned source and bundle

The source definitions remain separated by purpose:

- `data-views-v1.ndjson`;
- `saved-searches-v1.ndjson`;
- `analyst-states-v1.ndjson`;
- `dashboards-v1.ndjson`.

`saved-objects-manifest-v1.json` defines their dependency order and expected
object counts. Generate the deployment bundle with:

```bash
./scripts/build-dashboards-bundle.py
```

Verify that the tracked bundle is current:

```bash
./scripts/build-dashboards-bundle.py --check
```

The generator canonicalizes JSON, rejects duplicate IDs, verifies type counts,
and fails when any reference points outside the managed bundle. The resulting
`managed-saved-objects-v1.ndjson` contains 13 stable objects and is imported by
the Dashboards bootstrap with overwrite enabled.

## Export and compare

The reproducibility test asks the Dashboards saved-object export API for all
managed objects. API-generated metadata such as update timestamps and versions
is excluded from comparison; IDs, types, attributes, and references must match
exactly.

Compare an exported file manually:

```bash
./scripts/compare-dashboards-export.py exported.ndjson
```

Unexpected, missing, or changed managed objects fail the comparison. Unmanaged
personal analyst objects are not part of this bundle and should be exported
through an approved backup process before an environment is replaced.

## Clean restore proof

Run the isolated round-trip test:

```bash
make test-dashboards-reproducibility
```

The test:

1. starts a disposable secured OpenSearch and Dashboards environment;
2. imports the versioned bundle through the normal bootstrap;
3. exports all managed objects and compares them with source control;
4. deletes every managed object from Dashboards;
5. imports the single versioned bundle into the now-clean saved-object set;
6. exports and compares the restored objects again; and
7. removes the disposable data volumes.

This proves configuration portability, not event-data recovery. OpenSearch
event indexes are protected separately by the snapshot and restore process.
