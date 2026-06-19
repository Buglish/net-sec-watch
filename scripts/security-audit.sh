#!/usr/bin/env bash
set -euo pipefail

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$repo_root"

command -v docker >/dev/null 2>&1 || {
  echo "Docker is required for the security audit." >&2
  exit 2
}
docker compose version >/dev/null

[[ -f .env ]] || {
  echo "Run 'make init' before the security audit." >&2
  exit 2
}

set -a
# shellcheck disable=SC1091
source .env
set +a

AUDIT_SOURCE_VERSION="$(
  git rev-parse --short=12 HEAD 2>/dev/null || echo working-tree
)"
export AUDIT_SOURCE_VERSION

timestamp="$(date --utc '+%Y%m%dT%H%M%SZ')"
year="${timestamp:0:4}"
run_dir="$repo_root/security/audits/$year/$timestamp"
relative_run_dir="security/audits/$year/$timestamp"
project="net-sec-watch"
compose_project="net-sec-watch-audit"

runtime_sbom="${project}_runtime_sbom_${timestamp}.spdx.json"
source_sbom="${project}_source_sbom_${timestamp}.spdx.json"
runtime_vulnerabilities="${project}_runtime_vulnerabilities_${timestamp}.grype.json"
source_vulnerabilities="${project}_source_vulnerabilities_${timestamp}.grype.json"
summary="${project}_security-audit_summary_${timestamp}.md"
manifest="${project}_security-audit_manifest_${timestamp}.sha256"

mkdir -p "$run_dir"

compose() {
  docker compose \
    --project-name "$compose_project" \
    --env-file "$repo_root/.env" \
    --profile audit \
    "$@"
}

cleanup() {
  compose down --remove-orphans >/dev/null 2>&1 || true
}

trap cleanup EXIT
cleanup

echo "Generating runtime SPDX SBOM..."
compose run --rm --no-deps audit-runtime-sbom > "$run_dir/$runtime_sbom"

echo "Generating source SPDX SBOM..."
compose run --rm --no-deps audit-source-sbom > "$run_dir/$source_sbom"

grype_scan() {
  local sbom_file="$1"
  local report_file="$2"
  local -a args=("sbom:/audit/$year/$timestamp/$sbom_file" "--output" "json")

  if [[ -n "${AUDIT_FAIL_ON:-}" ]]; then
    args+=("--fail-on" "$AUDIT_FAIL_ON")
  fi

  set +e
  compose run --rm --no-deps audit-vulnerabilities "${args[@]}" \
    > "$run_dir/$report_file"
  local status=$?
  set -e
  return "$status"
}

runtime_status=0
source_status=0

echo "Scanning runtime SBOM for vulnerabilities..."
grype_scan "$runtime_sbom" "$runtime_vulnerabilities" || runtime_status=$?

echo "Scanning source SBOM for vulnerabilities..."
grype_scan "$source_sbom" "$source_vulnerabilities" || source_status=$?

syft_version="$(
  compose run --rm --no-deps audit-runtime-sbom version 2>/dev/null |
    head -n 1
)"
grype_version="$(
  compose run --rm --no-deps audit-vulnerabilities version 2>/dev/null |
    head -n 1
)"
git_commit="$(git rev-parse --verify HEAD 2>/dev/null || echo uncommitted)"
runtime_digest="$(
  docker image inspect \
    --format '{{if .RepoDigests}}{{index .RepoDigests 0}}{{else}}{{.Id}}{{end}}' \
    "${AUDIT_TARGET_IMAGE:-fluent/fluent-bit:4.0}" 2>/dev/null ||
    echo unavailable
)"
git_dirty="false"
if [[ -n "$(git status --porcelain)" ]]; then
  git_dirty="true"
fi

cat > "$run_dir/$summary" <<EOF
# Net Sec Watch security audit

- Audit timestamp (UTC): \`$timestamp\`
- Repository commit: \`$git_commit\`
- Working tree dirty: \`$git_dirty\`
- Runtime target: \`${AUDIT_TARGET_IMAGE:-fluent/fluent-bit:4.0}\`
- Runtime resolved digest: \`$runtime_digest\`
- Syft: \`$syft_version\`
- Grype: \`$grype_version\`
- Vulnerability fail threshold: \`${AUDIT_FAIL_ON:-report-only}\`
- Runtime scan exit status: \`$runtime_status\`
- Source scan exit status: \`$source_status\`

## Evidence

- \`$runtime_sbom\`
- \`$source_sbom\`
- \`$runtime_vulnerabilities\`
- \`$source_vulnerabilities\`
- \`$manifest\`

The SPDX SBOMs contain the discovered package and license inventory. Review
the Grype JSON reports for vulnerability findings, fix status, severity,
EPSS/KEV context where available, and affected package locations.
EOF

(
  cd "$run_dir"
  sha256sum \
    "$runtime_sbom" \
    "$source_sbom" \
    "$runtime_vulnerabilities" \
    "$source_vulnerabilities" \
    "$summary" > "$manifest"
)

echo "Security audit evidence: $relative_run_dir"

if [[ "$runtime_status" -ne 0 || "$source_status" -ne 0 ]]; then
  echo "Audit evidence was generated, but the configured vulnerability threshold was exceeded." >&2
  exit 1
fi

echo "Security audit completed."
