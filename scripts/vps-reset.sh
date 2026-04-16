#!/usr/bin/env bash
# scripts/vps-reset.sh – wipe the previous hermes-agent-in-docker setup.
#
# Run ONCE on the existing VPS before vps-setup.sh. Tears down the old
# compose stack, removes its named volumes (hermes_data, hermes_backups,
# syncthing_config, redis/postgres/hindsight data), and clears
# /opt/hermes-backups. The project is rebuilt from scratch after this.
#
# Usage:  ssh <vps> 'sudo bash -s' < scripts/vps-reset.sh
set -euo pipefail

if [[ $EUID -ne 0 ]]; then
  echo "ERROR: run as root (sudo)." >&2
  exit 1
fi

VPS_DIR="${VPS_DIR:-/opt/hermes}"

echo "→ Stopping hermes services (if present)"
systemctl stop hermes-dashboard 2>/dev/null || true
systemctl disable hermes-dashboard 2>/dev/null || true
rm -f /etc/systemd/system/hermes-dashboard.service
systemctl stop hermes-gateway 2>/dev/null || true
systemctl disable hermes-gateway 2>/dev/null || true
rm -f /etc/systemd/system/hermes-gateway.service
systemctl daemon-reload || true

if command -v tailscale >/dev/null 2>&1; then
  echo "→ Resetting Tailscale Serve config"
  tailscale serve reset 2>/dev/null || true
fi

if [[ -d "${VPS_DIR}" ]]; then
  echo "→ Stopping old compose stack in ${VPS_DIR}"
  (cd "${VPS_DIR}" && docker compose down --volumes --remove-orphans 2>/dev/null || true)
  (cd "${VPS_DIR}" && docker compose -f docker-compose.yml -f docker-compose.vps.yml down --volumes --remove-orphans 2>/dev/null || true)
fi

echo "→ Removing any stray hermes containers"
docker ps -aq --filter 'name=hermes' | xargs -r docker rm -f

echo "→ Removing old named volumes"
for vol in \
  hermes_hermes_data \
  hermes_hermes_backups \
  hermes_syncthing_config \
  hermes_redis_data \
  hermes_postgres_data \
  hermes_hindsight_data \
  hermes_rabbitmq_data \
  hermes_playwright_cache; do
  docker volume rm -f "${vol}" 2>/dev/null && echo "  removed ${vol}" || true
done

echo "→ Clearing legacy /opt/hermes-backups (if any)"
rm -rf /opt/hermes-backups

echo "→ Removing old hermes home (state, prior install, sync dirs)"
rm -rf /home/hermes/.hermes /home/hermes/work /home/hermes/sync

echo "→ Pruning dangling images"
docker image prune -f >/dev/null || true

echo ""
echo "✓ Reset complete. Next: run scripts/vps-setup.sh, then make deploy."
