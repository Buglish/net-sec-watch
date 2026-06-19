# Security audit evidence

Run:

```bash
make security-audit
```

Generated evidence is private operational output and is ignored by Git by
default. Preserve required reports in an approved evidence store with access
controls and retention appropriate to the environment.

## File naming convention

Audit artifacts use a filesystem-safe UTC ISO 8601 timestamp:

```text
<project>_<scope>_<artifact>_<YYYYMMDDTHHMMSSZ>.<format>
```

Examples:

```text
net-sec-watch_runtime_sbom_20260620T091500Z.spdx.json
net-sec-watch_source_vulnerabilities_20260620T091500Z.grype.json
net-sec-watch_security-audit_summary_20260620T091500Z.md
net-sec-watch_security-audit_manifest_20260620T091500Z.sha256
```

Each run is stored beneath:

```text
security/audits/<year>/<YYYYMMDDTHHMMSSZ>/
```

This convention provides chronological sorting, an unambiguous timezone,
stable project/scope identification, and artifact-type discoverability.

## Generated artifacts

- Runtime SPDX JSON SBOM, including packages and declared licenses.
- Repository/filesystem SPDX JSON SBOM.
- Runtime Grype vulnerability report.
- Repository/filesystem Grype vulnerability report.
- Markdown summary containing tool versions, image, commit, and scan status.
- SHA-256 manifest covering the generated evidence files.

Syft and Grype are open-source Apache-2.0 projects from Anchore.

