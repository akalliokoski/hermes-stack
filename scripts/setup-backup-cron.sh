#!/bin/bash
# setup-backup-cron.sh
# Configures the daily cron job for Hindsight backups on the host.

set -eu

SCRIPT_PATH="/opt/hermes/scripts/backup-hindsight-host.sh"
CRON_SCHEDULE="0 3 * * *"
CRON_CMD="${SCRIPT_PATH} >> /var/log/hermes-backup.log 2>&1"

echo "Setting up Hindsight backup cron job..."

# Check if script is executable
chmod +x "${SCRIPT_PATH}"

# Check if cron job already exists to avoid duplicates
(crontab -l 2>/dev/null | grep -F "${SCRIPT_PATH}") && echo "Cron job already exists. Skipping." || (crontab -l 2>/dev/null; echo "${CRON_SCHEDULE} ${CRON_CMD}") | crontab -

echo "Cron job setup complete."
