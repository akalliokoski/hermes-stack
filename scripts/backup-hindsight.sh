#!/bin/sh
# backup-hindsight.sh
# Create a logical pg_dump snapshot of the Hindsight database and place it in
# a dedicated archive path so docker-volume-backup's tarball pruning cannot
# touch unrelated SQL dump files.

set -eu

echo "--- Hindsight Backup Start ---"

ARCHIVE_DIR="${ARCHIVE_DIR:-/hindsight-archive}"
TIMESTAMP="$(date -u +%Y-%m-%dT%H-%M-%SZ)"
OUTPUT_FILE="${ARCHIVE_DIR}/hindsight_dump_${TIMESTAMP}.sql"
TMP_FILE="${OUTPUT_FILE}.tmp"
SELF_CONTAINER="${HOSTNAME:-}"
PROJECT_NAME="${COMPOSE_PROJECT_NAME:-}"

if [ -z "${PROJECT_NAME}" ] && [ -n "${SELF_CONTAINER}" ]; then
  PROJECT_NAME="$(docker inspect --format '{{ index .Config.Labels "com.docker.compose.project" }}' "${SELF_CONTAINER}")"
fi

if [ -z "${PROJECT_NAME}" ]; then
  echo "ERROR: could not determine compose project name" >&2
  exit 1
fi

HINDSIGHT_CONTAINER="$(docker ps \
  --filter "label=com.docker.compose.project=${PROJECT_NAME}" \
  --filter 'label=com.docker.compose.service=hindsight' \
  --format '{{.Names}}' | head -n1)"

if [ -z "${HINDSIGHT_CONTAINER}" ]; then
  echo "ERROR: could not find a running hindsight container for compose project '${PROJECT_NAME}'" >&2
  exit 1
fi

mkdir -p "${ARCHIVE_DIR}"

echo "Dumping Hindsight database from ${HINDSIGHT_CONTAINER} to ${OUTPUT_FILE}..."

if [ "${CHECK_ONLY:-0}" = "1" ]; then
  echo "CHECK_ONLY=1, skipping pg_dump"
  exit 0
fi

docker exec "${HINDSIGHT_CONTAINER}" pg_dump -U hindsight hindsight > "${TMP_FILE}"
mv "${TMP_FILE}" "${OUTPUT_FILE}"

echo "Hindsight dump complete: ${OUTPUT_FILE}"
echo "--- Hindsight Backup End ---"
