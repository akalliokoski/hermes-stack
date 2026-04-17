#!/bin/bash
# backup-hindsight-host.sh
# This script runs on the HOST to perform a logical pg_dump of the Hindsight container.
# It saves the dump directly into the Syncthing-synced directory.

set -eu

echo "--- Hindsight Host-Side Backup Start ---"

# Configuration
HINDSIGHT_CONTAINER="hermes-hindsight-1"
BACKUP_DIR="/home/hermes/sync/backups/hindsight"
TIMESTAMP=$(date -u +%Y-%m-%dT%H-%M-%SZ)
OUTPUT_FILE="${BACKUP_DIR}/hindsight_dump_${TIMESTAMP}.sql"

# Ensure backup directory exists
mkdir -p "${BACKUP_DIR}"

echo "Dumping Hindsight database from ${HINDSIGHT_CONTAINER} to ${OUTPUT_FILE}..."

# Perform the dump using the host's docker command
# We use a temporary file to ensure the move is atomic
TMP_FILE="${OUTPUT_FILE}.tmp"
if docker exec "${HINDSIGHT_CONTAINER}" pg_dump -U hindsight hindsight > "${TMP_FILE}"; then
    mv "${TMP_FILE}" "${OUTPUT_FILE}"
    echo "Hindsight dump complete: ${OUTPUT_FILE}"
else
    echo "ERROR: pg_dump failed!" >&2
    rm -f "${TMP_FILE}"
    exit 1
fi

echo "--- Hindsight Host-Side Backup End ---"
