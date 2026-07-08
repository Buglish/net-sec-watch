# Search and dashboards guide

Net Sec Watch uses OpenSearch and OpenSearch Dashboards for storage, search,
investigation, and visualization.

## Start Dashboards

Development profile:

```bash
make up-dashboards
```

Secure identity profile:

```bash
make up-identity
```

## Data views and saved objects

Managed objects live under `config/dashboards/`:

- data views;
- saved searches;
- dashboards;
- discover settings;
- analyst workflow states.

Validate them:

```bash
make dashboards-bundle
make test-opensearch-dashboards
make test-dashboards-reproducibility
```

## Search examples

Search examples are defined in `config/dashboards/search-examples-v1.json`.
They cover application, system, network, and dead-letter streams.

## Analyst workflow

Use:

- `docs/phase-5-analyst-workflows.md`
- `docs/phase-5-opensearch-dashboards.md`
- `docs/phase-5-search-performance.md`

These remain as detailed references, even though delivery is no longer tracked
by phases.
