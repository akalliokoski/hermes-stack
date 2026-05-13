#!/usr/bin/env bash
set -euo pipefail

SCRIPT="/opt/hermes/scripts/backup-hindsight-host.sh"
LOG_DIR="/home/hermes/sync/backups/hindsight"
LOG_FILE="${LOG_DIR}/hermes-backup.log"
STAMP="$(date -u +%Y-%m-%dT%H:%M:%SZ)"
TMP="$(mktemp)"

mkdir -p "${LOG_DIR}"

if "${SCRIPT}" >"${TMP}" 2>&1; then
  {
    echo "[${STAMP}] OK"
    cat "${TMP}"
  } >>"${LOG_FILE}"
  rm -f "${TMP}"
  exit 0
else
  status=$?
  {
    echo "[${STAMP}] ERROR exit=${status}"
    cat "${TMP}"
  } >>"${LOG_FILE}"
  cat "${TMP}"
  rm -f "${TMP}"
  exit "${status}"
fi
