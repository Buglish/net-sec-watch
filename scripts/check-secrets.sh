#!/usr/bin/env bash
set -euo pipefail

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$repo_root"

candidate_files="$(git ls-files --cached --others --exclude-standard)"

if printf '%s\n' "$candidate_files" |
    grep -Eq '(^|/)\.env$|^config/fluent-bit\.local\.conf$|^secrets/|(\.pem|\.key|\.p12)$'; then
  echo "A private runtime, secret, certificate, or key file would be committed." >&2
  exit 1
fi

patterns=(
  'AKIA[0-9A-Z]{16}'
  '-----BEGIN (RSA |EC |OPENSSH )?PRIVATE KEY-----'
  'gh[pousr]_[A-Za-z0-9_]{20,}'
  'github_pat_[A-Za-z0-9_]{20,}'
  '(password|passwd|secret|token)[[:space:]]*[:=][[:space:]]*[^$<{][^[:space:]]{7,}'
)

mapfile -t scan_files < <(
  printf '%s\n' "$candidate_files" |
    grep -Ev '^(scripts/check-secrets\.sh|\.gitleaks\.toml|docs/test-results/)'
)

for pattern in "${patterns[@]}"; do
  if ((${#scan_files[@]} > 0)) &&
      grep -IEn -- "$pattern" "${scan_files[@]}"; then
    echo "Potential committed secret matched pattern: $pattern" >&2
    exit 1
  fi
done

echo "Repository secret checks passed."
