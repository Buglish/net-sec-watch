#!/usr/bin/env bash
set -euo pipefail

repo_url="${NET_SEC_WATCH_REPO_URL:-https://github.com/Buglish/net-sec-watch.git}"
install_dir="${NET_SEC_WATCH_INSTALL_DIR:-/opt/net-sec-watch}"
branch="${NET_SEC_WATCH_BRANCH:-main}"

if [[ "${1:---check}" == "--check" ]]; then
  for command in git docker; do
    command -v "$command" >/dev/null 2>&1 || {
      echo "Missing required command: $command" >&2
      exit 1
    }
  done
  docker compose version >/dev/null
  echo "Linux VM deployment prerequisites are present."
  exit 0
fi

if [[ "$EUID" -ne 0 ]]; then
  echo "Run as root or with sudo for installation into ${install_dir}." >&2
  exit 2
fi

if [[ ! -d "$install_dir/.git" ]]; then
  git clone --branch "$branch" "$repo_url" "$install_dir"
else
  git -C "$install_dir" fetch origin "$branch"
  git -C "$install_dir" checkout "$branch"
  git -C "$install_dir" pull --ff-only origin "$branch"
fi

cd "$install_dir"
cp -n deploy/environments/production.env.example .env
./scripts/init-local-config.sh
./scripts/preflight-deployment.sh
docker compose --env-file .env \
  --file compose.yaml \
  --file compose.opensearch-secure.yaml \
  --file deploy/compose/compose.production.yaml \
  --profile opensearch up -d

echo "Net Sec Watch installed in ${install_dir}."
