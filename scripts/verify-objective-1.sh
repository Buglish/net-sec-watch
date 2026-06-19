#!/usr/bin/env bash
set -euo pipefail

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$repo_root"

required=(
  .env.example
  compose.yaml
  config/fluent-bit.conf
  config/fluent-bit.local.conf.example
  config/parsers-custom.conf
  tests/integration/compose.integration.yaml
  tests/integration/config/collector.conf
  tests/integration/config/receiver.conf
  tests/integration/run.sh
  tests/integration/smoke-production.sh
  docs/onboarding-file-source.md
  scripts/security-audit.sh
  security/audits/README.md
  examples/logs/text/service.log
  examples/logs/app/application.json.log
  examples/logs/system/syslog
  examples/logs/containers/demo/demo-json.log
)

for file in "${required[@]}"; do
  test -s "$file" || {
    echo "Missing or empty required file: $file" >&2
    exit 1
  }
done

grep -q 'DB.*text-files.db' config/fluent-bit.conf
grep -q 'Rotate_Wait' config/fluent-bit.conf
grep -q 'Multiline.Parser.*java_stacktrace' config/fluent-bit.conf
grep -q 'Parser.*application_json' config/fluent-bit.conf
grep -q 'Parser.*docker' config/fluent-bit.conf
grep -q 'storage.type.*filesystem' config/fluent-bit.conf
grep -q 'FLUENT_BIT_CONFIG_PATH' .env.example
grep -q 'FLUENT_BIT_CONFIG_PATH' compose.yaml
grep -q 'test-integration' Makefile
grep -q 'storage.total_limit_size' tests/integration/config/collector.conf
grep -q 'test_buffer_recovery' tests/integration/run.sh
grep -q 'test_restart_offsets' tests/integration/run.sh
grep -q 'test_rotation' tests/integration/run.sh
grep -q 'test_multiline' tests/integration/run.sh
grep -q 'audit-runtime-sbom' compose.yaml
grep -q 'audit-source-sbom' compose.yaml
grep -q 'audit-vulnerabilities' compose.yaml
grep -q 'security-audit' Makefile

git check-ignore --quiet .env
git check-ignore --quiet config/fluent-bit.local.conf
git check-ignore --quiet tests/runtime/.probe
if git check-ignore --quiet .env.example; then
  echo ".env.example must remain commit-eligible." >&2
  exit 1
fi
if git check-ignore --quiet config/fluent-bit.local.conf.example; then
  echo "The local Fluent Bit example must remain commit-eligible." >&2
  exit 1
fi

bash -n scripts/init-local-config.sh
bash -n scripts/generate-sample-logs.sh
bash -n scripts/rotate-sample-log.sh
bash -n scripts/verify-objective-1.sh
bash -n tests/integration/run.sh
bash -n tests/integration/smoke-production.sh
bash -n scripts/security-audit.sh

if docker compose version >/dev/null 2>&1; then
  docker compose --env-file .env.example config --quiet
  echo "Compose configuration is valid."
else
  echo "Docker Compose is unavailable; static collector checks passed."
fi

echo "Objective 1 configuration checks passed."
