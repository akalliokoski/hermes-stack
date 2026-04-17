#!/bin/bash
# backup-hindsight-host.sh
# This script runs on the HOST to perform a logical pg_dump of the Hindsight container.
# It uses the absolute path to the pg_dump binary found inside the container.

set -eu

echo "--- Hindsight Host-Side Backup Start ---"

# Configuration
HINDSIGHT_CONTAINER="hermes-hindsight-1"
PG_DUMP_BIN="/home/hindsight/.pg0/installation/18.1.0/pg_dump"
# Wait, let me re-verify the path from the successful run.
# The successful run used: /home/hindsight/.pg0/installation/18.1.0/bin/pg_dump
PG_DUMP_BIN="/home/hindsight/.pg0/installation/18.1.0/bin/pg_dump"
BACKUP_DIR="/home/hermes/sync/backups/hindsight"
TIMESTAMP=$(date -u +%Y-%m-%dT%H-%M-%SZ)
OUTPUT_FILE="${BACKUP_DIR}/hindsight_dump_${TIMESTAMP}.sql"
TMP_FILE="${OUTPUT_FILE}.tmp"

# Ensure backup directory exists
mkdir -p "${BACKUP_DIR}"

echo "Fetching password from container ${HINDSIGHT_CONTAINER}..."
# We fetch the password from the container's env to use it for the dump
DB_PASSWORD=$(docker exec "${HINDSIGHT_CONTAINER}" printenv HINDSIGHT_DB_PASSWORD)

echo "Executing: docker exec -e PGPASSWORD=${DB_PASSWORD} ${HINDSIGHT_CONTAINER} ${PG_DUMP_BIN} -U hindsight hindsight"

# Perform the dump
if docker exec -e PGPASSWORD="${DB_PASSWORD}" "${HINDSIGHT_CONTAINER}" "${PG_DUMP_BIN}" -U hindsight hindsight > "${TMP_FILE}"; then
    mv "${TMP_FILE}" "${OUTPUT_FILE}"
    echo "Hindsight dump complete: ${OUTPUT_FILE}"
else
    echo "ERROR: pg_dump failed!" >&2
    rm -f "${TMP_FILE}"
    exit 1
fi

echo "--- Hindsight Host-Side Backup End ---"
