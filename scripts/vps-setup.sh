#!/usr/bin/env bash
# scripts/vps-setup.sh – one-time setup on a fresh VPS
# Run: ssh user@vps 'bash -s' < scripts/vps-setup.sh
set -euo pipefail

VPS_DIR="${VPS_DIR:-/opt/hermes}"

# ── Docker ────────────────────────────────────────────────────────────────────
if ! command -v docker &>/dev/null; then
  echo "→ Installing Docker"
  curl -fsSL https://get.docker.com | sh
  systemctl enable --now docker
fi

# ── Directory & env file ──────────────────────────────────────────────────────
mkdir -p "${VPS_DIR}"

if [[ ! -f "${VPS_DIR}/.env" ]]; then
  echo "→ Creating .env from template (edit before running the stack)"
  cp "${VPS_DIR}/.env.example" "${VPS_DIR}/.env"
  echo "  !! Fill in ${VPS_DIR}/.env then run: cd ${VPS_DIR} && docker compose up -d"
fi

echo "✓ VPS setup complete"
