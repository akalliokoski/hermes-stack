#!/usr/bin/env bash
# scripts/backup-volumes.sh – back up all named Docker volumes to a tarball
#
# Usage (on VPS):
#   bash scripts/backup-volumes.sh              # backs up to /opt/hermes-backups/
#   BACKUP_DIR=/mnt/nas bash scripts/backup-volumes.sh
#
# Add to cron for weekly backups:
#   0 3 * * 0 cd /opt/hermes && bash scripts/backup-volumes.sh >> /var/log/hermes-backup.log 2>&1
#
set -euo pipefail

BACKUP_DIR="${BACKUP_DIR:-/opt/hermes-backups}"
TIMESTAMP="$(date +%Y%m%dT%H%M%S)"
COMPOSE_PROJECT="${COMPOSE_PROJECT:-hermes}"
RETAIN_DAYS="${RETAIN_DAYS:-30}"

VOLUMES=(
  "${COMPOSE_PROJECT}_hermes_data"
  "${COMPOSE_PROJECT}_postgres_data"
  "${COMPOSE_PROJECT}_hindsight_data"
  "${COMPOSE_PROJECT}_redis_data"
  "${COMPOSE_PROJECT}_syncthing_config"
  "${COMPOSE_PROJECT}_tailscale_state"
)

mkdir -p "${BACKUP_DIR}"

echo "[${TIMESTAMP}] Starting volume backups → ${BACKUP_DIR}"

for vol in "${VOLUMES[@]}"; do
  # Skip if volume doesn't exist
  if ! docker volume inspect "${vol}" &>/dev/null; then
    echo "  skip  ${vol} (not found)"
    continue
  fi

  out="${BACKUP_DIR}/${vol}_${TIMESTAMP}.tar.gz"
  echo "  backup ${vol} → ${out}"
  docker run --rm \
    -v "${vol}:/data:ro" \
    -v "${BACKUP_DIR}:/backup" \
    alpine \
    tar czf "/backup/$(basename "${out}")" -C /data .
done

# Remove backups older than RETAIN_DAYS
echo "  pruning backups older than ${RETAIN_DAYS} days"
find "${BACKUP_DIR}" -name "*.tar.gz" -mtime +"${RETAIN_DAYS}" -delete

echo "[${TIMESTAMP}] Backup complete"
