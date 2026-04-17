#!/bin/bash
# backup-hindsight-host.sh
# This script runs on the HOST to perform a logical pg_dump of the Hindsight container.
# It uses an ephemeral postgres container to ensure pg_dump is available.

set -eu

echo "--- Hindsight Host-Side Backup Start ---"

# Configuration
HINDSIGHT_CONTAINER="hermes-hindsight-1"
NETWORK="hermes_hermes"
BACKUP_DIR="/home/hermes/sync/backups/hindsight"
TIMESTAMP=$(date -u +%Y-%m-%dT%H-%M-%SZ)
OUTPUT_FILE="${BACKUP_DIR}/hindsight_dump_${TIMESTAMP}.sql"
TMP_FILE="${OUTPUT_FILE}.tmp"

# Ensure backup directory exists
mkdir -p "${BACKUP_DIR}"

echo "Using ephemeral postgres container to dump ${HINDSIGHT_CONTAINER} on network ${NETWORK}..."

# Execute pg_dump via an ephemeral container
# We connect to the 'hindsight' database with user 'hindsight'
# Note: We use the container name as the hostname since they share a network.
if docker run --rm     --network "${NETWORK}"     postgres:16-alpine     pg_dump -h "${HINDSIGHT_CONTAINER}" -U hindsight hindsight > "${TMP_FILE}"; then
    
    mv "${TMP_FILE}" "${OUTPUT_FILE}"
    echo "Hindsight dump complete: ${OUTPUT_FILE}"
else
    echo "ERROR: pg_dump failed!" >&2
    rm -f "${TMP_FILE}"
    exit 1
fi

echo "--- Hindsight Host-Side Backup End ---"
