#!/usr/bin/env bash
set -euo pipefail

PROFILE="${1:?usage: run-profile-cron-tick.sh <profile>}"
INTERVAL_SECONDS="${HERMES_CRON_TICK_INTERVAL_SECONDS:-30}"
HERMES_BIN="${HERMES_BIN:-/home/hermes/.local/bin/hermes}"

if [[ "${PROFILE}" == "default" ]]; then
  PROFILE_HOME="/home/hermes/.hermes"
else
  PROFILE_HOME="/home/hermes/.hermes/profiles/${PROFILE}"
fi
WORKDIR="/home/hermes/work/${PROFILE}"

if [[ ! -d "${PROFILE_HOME}" ]]; then
  echo "[$(date --iso-8601=seconds)] missing profile home: ${PROFILE_HOME}" >&2
  exit 1
fi

if [[ ! -x "${HERMES_BIN}" ]]; then
  echo "[$(date --iso-8601=seconds)] missing hermes binary: ${HERMES_BIN}" >&2
  exit 1
fi

if [[ -d "${WORKDIR}" ]]; then
  cd "${WORKDIR}"
else
  cd /opt/hermes
fi

while true; do
  echo "[$(date --iso-8601=seconds)] ticking profile ${PROFILE}"
  HERMES_HOME="${PROFILE_HOME}" "${HERMES_BIN}" cron tick --accept-hooks || true
  sleep "${INTERVAL_SECONDS}"
done
