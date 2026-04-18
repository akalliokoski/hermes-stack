#!/usr/bin/env bash
# deploy.sh – run from MacBook to deploy the stack to VPS over Tailscale.
#
# One-time bootstrap (first deploy only):
#   scp .env "${VPS_HOST}:/tmp/"
#   ssh "${VPS_HOST}" "sudo bash -s" < scripts/vps-setup.sh
#
# Routine deploys (this script):
#   - rsync the repo (compose files, scripts, config overlays) to the VPS
#   - render the VPS-specific config into /home/hermes/.hermes/
#   - `docker compose up -d` for auxiliary services
#   - `systemctl restart hermes-gateway` for the host-installed agent
#
# Hermes itself updates separately via `make update-agent`
# (runs `hermes update` as the hermes user — no rebuild needed).
# Deploy also re-installs the Hindsight client dependency into Hermes's own venv.
set -euo pipefail

if [[ -f .env ]]; then
  # shellcheck disable=SC2046
  export $(grep -E '^(VPS_HOST|VPS_DIR)=' .env | xargs)
fi

VPS_HOST="${VPS_HOST:?Set VPS_HOST in .env (Tailscale hostname or IP)}"
VPS_DIR="${VPS_DIR:-/opt/hermes}"

echo "→ Syncing to ${VPS_HOST}:${VPS_DIR}"
rsync -az --delete \
  --exclude='.git' \
  --exclude='.env' \
  --exclude='backups/' \
  . "${VPS_HOST}:${VPS_DIR}/"

echo "→ Restarting stack"
ssh "${VPS_HOST}" "
  set -e
  cd ${VPS_DIR}
  bash scripts/remote-deploy.sh
"

echo "✓ Done"
