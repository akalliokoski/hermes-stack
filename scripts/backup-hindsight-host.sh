#!/usr/bin/env bash
# backup-hindsight-host.sh
# Canonical host-side logical backup for the Hindsight database.

set -euo pipefail

HINDSIGHT_CONTAINER="${HINDSIGHT_CONTAINER:-hermes-hindsight-1}"
PG_DUMP_BIN="${PG_DUMP_BIN:-/home/hindsight/.pg0/installation/18.1.0/bin/pg_dump}"
BACKUP_DIR="${HINDSIGHT_BACKUP_DIR:-/home/hermes/sync/backups/hindsight}"
COMPRESSION="${HINDSIGHT_BACKUP_COMPRESSION:-gzip}"
KEEP_LATEST="${HINDSIGHT_BACKUP_KEEP_LATEST:-7}"
RETENTION_DAYS="${HINDSIGHT_BACKUP_RETENTION_DAYS:-14}"
TIMESTAMP="$(date -u +%Y-%m-%dT%H-%M-%SZ)"

case "${COMPRESSION}" in
  gzip)
    OUTPUT_FILE="${BACKUP_DIR}/hindsight_dump_${TIMESTAMP}.sql.gz"
    ;;
  none)
    OUTPUT_FILE="${BACKUP_DIR}/hindsight_dump_${TIMESTAMP}.sql"
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
trap cleanup_tmp EXIT

prune_backups() {
  local -a files=()
  local file

  while IFS= read -r file; do
    files+=("${file}")
  done < <(find "${BACKUP_DIR}" -maxdepth 1 -type f \( -name 'hindsight_dump_*.sql' -o -name 'hindsight_dump_*.sql.gz' \) | sort)

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
    done < <(find "${BACKUP_DIR}" -maxdepth 1 -type f \( -name 'hindsight_dump_*.sql' -o -name 'hindsight_dump_*.sql.gz' \) -mtime +"${RETENTION_DAYS}" | sort)
  fi
}

echo "--- Hindsight Host-Side Backup Start ---"
mkdir -p "${BACKUP_DIR}"

echo "Fetching password from container ${HINDSIGHT_CONTAINER}..."
DB_PASSWORD="$(docker exec "${HINDSIGHT_CONTAINER}" printenv HINDSIGHT_DB_PASSWORD)"

echo "Dumping hindsight from ${HINDSIGHT_CONTAINER} to ${OUTPUT_FILE} using compression=${COMPRESSION}"

if [[ "${COMPRESSION}" == "gzip" ]]; then
  docker exec -e PGPASSWORD="${DB_PASSWORD}" "${HINDSIGHT_CONTAINER}" "${PG_DUMP_BIN}" -U hindsight hindsight \
    | gzip -n > "${TMP_FILE}"
else
  docker exec -e PGPASSWORD="${DB_PASSWORD}" "${HINDSIGHT_CONTAINER}" "${PG_DUMP_BIN}" -U hindsight hindsight > "${TMP_FILE}"
fi

mv "${TMP_FILE}" "${OUTPUT_FILE}"
prune_backups

echo "Hindsight dump complete: ${OUTPUT_FILE}"
echo "--- Hindsight Host-Side Backup End ---"
