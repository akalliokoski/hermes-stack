#!/usr/bin/env bash
set -euo pipefail

COMPOSE_FILES=(-f docker-compose.yml -f docker-compose.vps.yml)
VOLUME_NAME="${VOLUME_NAME:-hermes_hermes_backups}"
EXPECTED_DEVICE="${EXPECTED_DEVICE:-/home/hermes/sync/backups}"
LEGACY_DEVICE="${LEGACY_DEVICE:-/opt/hermes-backups}"
SQL_DIR="${SQL_DIR:-/home/hermes/sync/backups/hindsight}"

mkdir -p "${EXPECTED_DEVICE}" "${SQL_DIR}"

if ! docker volume inspect "${VOLUME_NAME}" >/dev/null 2>&1; then
  echo "✓ Backup volume ${VOLUME_NAME} does not exist yet"
  exit 0
fi

current_device="$(docker volume inspect "${VOLUME_NAME}" --format '{{ index .Options "device" }}')"
if [[ "${current_device}" == "${EXPECTED_DEVICE}" ]]; then
  echo "✓ Backup volume ${VOLUME_NAME} already points at ${EXPECTED_DEVICE}"
  exit 0
fi

echo "→ Repairing backup volume ${VOLUME_NAME}: ${current_device} -> ${EXPECTED_DEVICE}"

if [[ -d "${current_device}" ]]; then
  rsync -a "${current_device}/" "${EXPECTED_DEVICE}/"
fi

# Services using the volume must be stopped before the volume can be recreated.
docker compose "${COMPOSE_FILES[@]}" stop backup litestream >/dev/null 2>&1 || true
docker compose "${COMPOSE_FILES[@]}" rm -f backup litestream >/dev/null 2>&1 || true

docker volume rm "${VOLUME_NAME}" >/dev/null

echo "✓ Backup files copied to ${EXPECTED_DEVICE}; ${VOLUME_NAME} will be recreated on next docker compose up"
