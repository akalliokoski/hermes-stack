#!/usr/bin/env bash
# backup-hindsight.sh
# Create a logical pg_dump snapshot of the Hindsight database and place it in
# a dedicated archive path so docker-volume-backup's tarball pruning cannot
# touch unrelated SQL dump files.

set -euo pipefail

echo "--- Hindsight Backup Start ---"

ARCHIVE_DIR="${ARCHIVE_DIR:-/hindsight-archive}"
COMPRESSION="${HINDSIGHT_BACKUP_COMPRESSION:-gzip}"
KEEP_LATEST="${HINDSIGHT_BACKUP_KEEP_LATEST:-7}"
RETENTION_DAYS="${HINDSIGHT_BACKUP_RETENTION_DAYS:-14}"
TIMESTAMP="$(date -u +%Y-%m-%dT%H-%M-%SZ)"
SELF_CONTAINER="${HOSTNAME:-}"
PROJECT_NAME="${COMPOSE_PROJECT_NAME:-}"

case "${COMPRESSION}" in
  gzip)
    OUTPUT_FILE="${ARCHIVE_DIR}/hindsight_dump_${TIMESTAMP}.sql.gz"
    ;;
  none)
    OUTPUT_FILE="${ARCHIVE_DIR}/hindsight_dump_${TIMESTAMP}.sql"
    ;;
  *)
    echo "ERROR: unsupported HINDSIGHT_BACKUP_COMPRESSION=${COMPRESSION} (expected gzip or none)" >&2
    exit 1
    ;;
esac

TMP_FILE="${OUTPUT_FILE}.tmp"

cleanup_tmp() {
  rm -f "${TMP_FILE}"
}

prune_backups() {
  local -a files=()
  local file

  while IFS= read -r file; do
    files+=("${file}")
  done < <(find "${ARCHIVE_DIR}" -maxdepth 1 -type f \( -name 'hindsight_dump_*.sql' -o -name 'hindsight_dump_*.sql.gz' \) | sort)

  if [[ "${KEEP_LATEST}" =~ ^[0-9]+$ ]] && (( KEEP_LATEST >= 0 )) && (( ${#files[@]} > KEEP_LATEST )); then
    for file in "${files[@]:0:${#files[@]}-KEEP_LATEST}"; do
      rm -f -- "${file}"
      echo "Pruned old Hindsight dump by count: ${file}"
    done
  fi

  if [[ "${RETENTION_DAYS}" =~ ^[0-9]+$ ]] && (( RETENTION_DAYS >= 0 )); then
    while IFS= read -r file; do
      rm -f -- "${file}"
      echo "Pruned old Hindsight dump by age: ${file}"
    done < <(find "${ARCHIVE_DIR}" -maxdepth 1 -type f \( -name 'hindsight_dump_*.sql' -o -name 'hindsight_dump_*.sql.gz' \) -mtime +"${RETENTION_DAYS}" | sort)
  fi
}

trap cleanup_tmp EXIT

if [[ -z "${PROJECT_NAME}" && -n "${SELF_CONTAINER}" ]]; then
  PROJECT_NAME="$(docker inspect --format '{{ index .Config.Labels "com.docker.compose.project" }}' "${SELF_CONTAINER}")"
fi

if [[ -z "${PROJECT_NAME}" ]]; then
  echo "ERROR: could not determine compose project name" >&2
  exit 1
fi

HINDSIGHT_CONTAINER="$(docker ps \
  --filter "label=com.docker.compose.project=${PROJECT_NAME}" \
  --filter 'label=com.docker.compose.service=hindsight' \
  --format '{{.Names}}' | head -n1)"

if [[ -z "${HINDSIGHT_CONTAINER}" ]]; then
  echo "ERROR: could not find a running hindsight container for compose project '${PROJECT_NAME}'" >&2
  exit 1
fi

mkdir -p "${ARCHIVE_DIR}"

echo "Dumping Hindsight database from ${HINDSIGHT_CONTAINER} to ${OUTPUT_FILE}..."

if [[ "${CHECK_ONLY:-0}" == "1" ]]; then
  echo "CHECK_ONLY=1, skipping pg_dump"
  exit 0
fi

if [[ "${COMPRESSION}" == "gzip" ]]; then
  docker exec "${HINDSIGHT_CONTAINER}" pg_dump -U hindsight hindsight | gzip -n > "${TMP_FILE}"
else
  docker exec "${HINDSIGHT_CONTAINER}" pg_dump -U hindsight hindsight > "${TMP_FILE}"
fi
mv "${TMP_FILE}" "${OUTPUT_FILE}"
prune_backups

echo "Hindsight dump complete: ${OUTPUT_FILE}"
echo "--- Hindsight Backup End ---"
