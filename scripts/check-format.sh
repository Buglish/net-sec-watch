#!/usr/bin/env bash
set -euo pipefail

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$repo_root"

mapfile -t candidate_files < <(
  git ls-files --cached --others --exclude-standard |
    grep -Ev '\.(docx|png|jpg|jpeg|gif|ico|pdf)$'
)

failed=0

for file in "${candidate_files[@]}"; do
  [[ -f "$file" ]] || continue
  grep -Iq . "$file" || continue

  if grep -q $'\r' "$file"; then
    echo "CRLF line endings are not allowed: $file" >&2
    failed=1
  fi

  if [[ -s "$file" ]] && [[ "$(tail -c 1 "$file" | wc -l)" -eq 0 ]]; then
    echo "Missing final newline: $file" >&2
    failed=1
  fi

  case "$file" in
    *.md) ;;
    *)
      if grep -nE '[[:blank:]]+$' "$file"; then
        echo "Trailing whitespace found: $file" >&2
        failed=1
      fi
      ;;
  esac
done

if [[ "$failed" -ne 0 ]]; then
  exit 1
fi

echo "Repository formatting checks passed."

