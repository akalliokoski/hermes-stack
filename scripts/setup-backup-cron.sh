#!/bin/bash
# setup-backup-cron.sh
# Configures the daily cron job for Hindsight backups on the host.

set -eu

SCRIPT_PATH="/opt/hermes/scripts/backup-hindsight-host.sh"
CRON_SCHEDULE="0 3 * * *"
LOG_DIR="/home/hermes/sync/backups/hindsight"
LOG_FILE="${LOG_DIR}/hermes-backup.log"
CRON_CMD="${SCRIPT_PATH} >> ${LOG_FILE} 2>&1"

echo "Setting up Hindsight backup cron job..."

# Ensure the log directory exists and the script is executable.
mkdir -p "${LOG_DIR}"
chmod +x "${SCRIPT_PATH}"

# Check if cron job already exists to avoid duplicates.
(crontab -l 2>/dev/null | grep -F "${SCRIPT_PATH}") && echo "Cron job already exists. Skipping." || (crontab -l 2>/dev/null; echo "${CRON_SCHEDULE} ${CRON_CMD}") | crontab -

echo "Cron job setup complete. Logs: ${LOG_FILE}"
