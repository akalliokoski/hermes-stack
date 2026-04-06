#!/usr/bin/env bash
# scripts/vps-setup.sh – one-time setup on a fresh or re-purposed VPS
# Run: ssh <vps-host> 'bash -s' < scripts/vps-setup.sh
set -euo pipefail

VPS_DIR="${VPS_DIR:-/opt/hermes}"

# ── Docker ────────────────────────────────────────────────────────────────────
if ! command -v docker &>/dev/null; then
  echo "→ Installing Docker"
  curl -fsSL https://get.docker.com | sh
  systemctl enable --now docker
else
  echo "✓ Docker already installed ($(docker --version))"
fi

# ── Backup directory (host bind-mount – survives docker compose down -v) ──────
mkdir -p /opt/hermes-backups
echo "✓ Backup directory: /opt/hermes-backups"

# ── App directory ─────────────────────────────────────────────────────────────
mkdir -p "${VPS_DIR}"
echo "✓ App directory: ${VPS_DIR}"

if [[ ! -f "${VPS_DIR}/.env" ]]; then
  echo ""
  echo "  Next step: copy your .env to ${VPS_DIR}/.env"
  echo "    scp .env <vps-host>:${VPS_DIR}/.env"
fi

echo "✓ VPS setup complete"
