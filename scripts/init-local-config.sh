#!/usr/bin/env bash
set -euo pipefail

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$repo_root"

copy_if_missing() {
  local example="$1"
  local target="$2"

  if [[ -e "$target" ]]; then
    echo "Keeping existing $target"
    return
  fi

  cp "$example" "$target"
  echo "Created $target from $example"
}

copy_if_missing .env.example .env
copy_if_missing config/fluent-bit.local.conf.example config/fluent-bit.local.conf

echo
echo "Local files are Git-ignored. Review .env before running Docker Compose."

