#!/usr/bin/env bash
# deploy.sh – run from MacBook to deploy the stack to VPS over Tailscale
#
# One-time bootstrap (first deploy only):
#   scp .env "${VPS_HOST}:${VPS_DIR}/.env"
#   ssh "${VPS_HOST}" "bash -s" < scripts/vps-setup.sh
#
set -euo pipefail

# Load VPS_HOST / VPS_DIR from local .env if present
if [[ -f .env ]]; then
  # shellcheck disable=SC2046
  export $(grep -E '^(VPS_HOST|VPS_DIR)=' .env | xargs)
fi

# VPS_HOST should be the Tailscale hostname or IP (e.g. my-vps or 100.x.x.x)
VPS_HOST="${VPS_HOST:?Set VPS_HOST in .env (Tailscale hostname or IP)}"
VPS_DIR="${VPS_DIR:-/opt/hermes}"

echo "→ Syncing to ${VPS_HOST}:${VPS_DIR}"
rsync -az --delete \
  --exclude='.git' \
  --exclude='.env' \
  --exclude='sync/' \
  . "${VPS_HOST}:${VPS_DIR}/"

echo "→ Restarting stack"
ssh "${VPS_HOST}" "
  set -e
  cd ${VPS_DIR}
  docker compose pull --quiet
  docker compose build hermes-agent
  docker compose up -d --remove-orphans
  docker compose ps
"

echo "✓ Done"
