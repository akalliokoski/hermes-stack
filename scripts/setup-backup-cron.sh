#!/usr/bin/env bash
# setup-backup-cron.sh
# Configures the daily cron job for Hindsight backups on the host.

set -euo pipefail

SCRIPT_PATH="/opt/hermes/scripts/backup-hindsight-host.sh"
CRON_SCHEDULE="0 3 * * *"
LOG_DIR="/home/hermes/sync/backups/hindsight"
LOG_FILE="${LOG_DIR}/hermes-backup.log"
CRON_FILE="/etc/cron.d/hermes-hindsight-backup"

if [[ "$(id -u)" -ne 0 ]]; then
  echo "ERROR: setup-backup-cron.sh must run as root" >&2
  exit 1
fi

echo "Setting up Hindsight backup cron job..."

mkdir -p "${LOG_DIR}"
chmod +x "${SCRIPT_PATH}"

cat >"${CRON_FILE}" <<EOF
SHELL=/bin/bash
PATH=/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin
${CRON_SCHEDULE} root ${SCRIPT_PATH} >> ${LOG_FILE} 2>&1
EOF
chmod 644 "${CRON_FILE}"

echo "Cron job setup complete. File: ${CRON_FILE} Logs: ${LOG_FILE}"
