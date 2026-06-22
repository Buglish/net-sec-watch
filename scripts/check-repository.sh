#!/usr/bin/env bash
set -euo pipefail

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$repo_root"

required_files=(
  LICENSE
  CONTRIBUTING.md
  README.md
  OBJECTIVES.md
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
./scripts/verify-objective-1.sh
./scripts/verify-objective-2.sh
./tests/telemetry-policy/run.sh
python3 ./tests/schema/test-schema-contract.py
python3 ./tests/opensearch/test-capacity-calculator.py
python3 ./tests/opensearch/searchability-slo.py --help >/dev/null
python3 ./tests/dashboards/test-search-examples.py
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
