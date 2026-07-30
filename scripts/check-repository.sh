#!/usr/bin/env bash
set -euo pipefail

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$repo_root"

required_files=(
  LICENSE
  CONTRIBUTING.md
  README.md
  docs/index.md
  docs/features-and-roadmap.md
  .editorconfig
  .gitleaks.toml
  .github/workflows/ci.yaml
)

for file in "${required_files[@]}"; do
  test -s "$file" || {
    echo "Missing or empty repository foundation file: $file" >&2
    exit 1
  }
done

git diff --check

while IFS= read -r script; do
  bash -n "$script"
done < <(find scripts tests -type f -name '*.sh' -print | sort)

./scripts/check-format.sh
./scripts/check-secrets.sh
./scripts/verify-file-collection.sh
./scripts/verify-network-syslog.sh
./tests/telemetry-policy/run.sh
python3 ./tests/schema/test-schema-contract.py
python3 ./tests/opensearch/test-capacity-calculator.py
python3 ./tests/opensearch/searchability-slo.py --help >/dev/null
python3 ./tests/dashboards/test-search-examples.py
python3 ./tests/dashboards/test-data-views.py
python3 ./tests/dashboards/test-saved-searches.py
python3 ./tests/dashboards/test-dashboards.py
python3 ./tests/dashboards/test-export-events.py
python3 ./tests/dashboards/test-ingestion-status.py
python3 ./tests/dashboards/test-analyst-workflows.py
python3 ./tests/dashboards/test-usability-study.py
python3 ./tests/dashboards/test-search-performance.py
python3 ./tests/dashboards/test-saved-object-bundle.py
./scripts/build-dashboards-bundle.py --check
python3 ./scripts/compare-dashboards-export.py --help >/dev/null
python3 ./scripts/benchmark-seven-day-searches.py --help >/dev/null
python3 ./tests/security/test-security.py
python3 ./tests/operations/test-operations.py
python3 ./tests/detections/test-detections.py
python3 ./scripts/run-detections.py \
  --events tests/detections/fixtures/detection-positive-events.jsonl \
  --expect tests/detections/fixtures/detection-expected-alerts.json >/dev/null
python3 ./scripts/run-detections.py \
  --events tests/detections/fixtures/detection-negative-events.jsonl \
  --expect tests/detections/fixtures/detection-expected-negative-alerts.json >/dev/null
python3 ./tests/ml/test-ml.py
python3 ./scripts/ml-shadow-score.py \
  --events tests/ml/fixtures/auth-shadow-evaluation.jsonl \
  --model-metadata config/ml/mlflow-model-registry-entry-v1.json \
  --output /tmp/net-sec-watch-ml-shadow-predictions.jsonl
python3 ./tests/deployment/test-deployment.py
./scripts/preflight-deployment.sh --check-files-only
python3 ./tests/orchestration/test-orchestration.py
python3 ./scripts/traffic-classifier-service.py \
  --events tests/orchestration/fixtures/live-events.jsonl \
  --registry config/orchestration/model-registry-events-v1.json \
  --output /tmp/net-sec-watch-orchestration-predictions.jsonl \
  --metrics-output /tmp/net-sec-watch-orchestration-metrics.prom >/dev/null
python3 ./scripts/model-orchestrator.py \
  --events tests/orchestration/fixtures/unknown-traffic-events.jsonl \
  --config config/orchestration/orchestration-policy-v1.json \
  --output /tmp/net-sec-watch-orchestration-candidates.json >/dev/null
./tests/opensearch/tls-certificate-config.sh
python3 -m json.tool \
  config/identity/net-sec-watch-realm.json >/dev/null
./tests/opensearch/check-config.sh

if command -v shellcheck >/dev/null 2>&1; then
  mapfile -t shell_files < <(find scripts tests -type f -name '*.sh' -print | sort)
  shellcheck "${shell_files[@]}"
else
  echo "shellcheck is unavailable; syntax checks completed."
fi

if command -v yamllint >/dev/null 2>&1; then
  yamllint .
else
  echo "yamllint is unavailable; Docker Compose validation completed."
fi

echo "Repository checks passed."
