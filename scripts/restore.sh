#!/usr/bin/env bash
# scripts/restore.sh – Hermes agent state restore utility.
#
# Hermes state lives on the host at ${HERMES_DATA_DIR:-~/.hermes} (VPS: /home/hermes/.hermes).
# Backups live in the hermes_backups Docker volume (bind-mounted to
# /opt/hermes-backups on VPS or ./backups locally).
#
# Usage:
#   bash scripts/restore.sh list                         # list available snapshots
#   bash scripts/restore.sh db [timestamp|latest]        # restore state.db via Litestream
#   bash scripts/restore.sh volume <tarball>             # restore full .hermes from tarball
#   bash scripts/restore.sh file <path> <tarball>        # extract single file from tarball
#
# Or via make:
#   make restore ARGS="list"
#   make restore ARGS="db latest"
#   make restore ARGS="volume hermes_data_2026-04-05T03-00-00.tar.gz"
#   make restore ARGS="file memories/MEMORY.md hermes_data_...tar.gz"

set -euo pipefail

LITESTREAM_IMAGE="litestream/litestream:latest"
LITESTREAM_CONFIG="./litestream.yml"
HERMES_DATA_DIR="${HERMES_DATA_DIR:-${HOME}/.hermes}"
HERMES_BACKUPS_VOLUME="${HERMES_BACKUPS_VOLUME:-hermes_hermes_backups}"
GATEWAY_UNIT="${GATEWAY_UNIT:-hermes-gateway}"

# Prefer local litestream config if present (local dev)
if [[ -f "./litestream.local.yml" && -z "${FORCE_VPS_CONFIG:-}" ]]; then
  LITESTREAM_CONFIG="./litestream.local.yml"
fi

RED='\033[0;31m'; YELLOW='\033[1;33m'; GREEN='\033[0;32m'; CYAN='\033[0;36m'; NC='\033[0m'
err()  { echo -e "${RED}error:${NC} $*" >&2; exit 1; }
info() { echo -e "${CYAN}→${NC} $*"; }
ok()   { echo -e "${GREEN}✓${NC} $*"; }
warn() { echo -e "${YELLOW}warn:${NC} $*"; }

stop_agent() {
  if systemctl list-unit-files "${GATEWAY_UNIT}.service" &>/dev/null; then
    info "Stopping ${GATEWAY_UNIT}..."
    sudo systemctl stop "${GATEWAY_UNIT}" || true
  else
    warn "systemd unit ${GATEWAY_UNIT} not found (local dev?) — stop hermes manually if running."
  fi
  docker compose stop litestream 2>/dev/null || true
}

start_agent() {
  docker compose up -d litestream 2>/dev/null || true
  if systemctl list-unit-files "${GATEWAY_UNIT}.service" &>/dev/null; then
    info "Starting ${GATEWAY_UNIT}..."
    sudo systemctl start "${GATEWAY_UNIT}"
  fi
}

list_tarballs() {
  echo -e "\n${CYAN}── Volume snapshots (.hermes tarballs) ──${NC}"
  if docker volume inspect "${HERMES_BACKUPS_VOLUME}" &>/dev/null; then
    docker run --rm -v "${HERMES_BACKUPS_VOLUME}:/arc:ro" alpine \
      sh -c 'ls -lh /arc/*.tar.gz 2>/dev/null | awk "{print \$5, \$9}" | sed "s|/arc/||"' \
      || warn "No tarballs found yet."
  else
    warn "hermes_backups volume not found."
  fi
}

list_litestream_snapshots() {
  echo -e "\n${CYAN}── Litestream SQLite snapshots ──${NC}"
  docker volume inspect "${HERMES_BACKUPS_VOLUME}" &>/dev/null || { warn "hermes_backups volume not found."; return; }
  docker run --rm \
    -v "$(pwd)/${LITESTREAM_CONFIG#./}:/etc/litestream.yml:ro" \
    -v "${HERMES_BACKUPS_VOLUME}:/opt/backups" \
    "${LITESTREAM_IMAGE}" snapshots \
    || warn "No Litestream snapshots yet."
}

cmd_list() { list_tarballs; list_litestream_snapshots; }

cmd_db() {
  local timestamp="${1:-latest}"
  info "Restoring state.db from Litestream (timestamp: ${timestamp})"
  [[ -d "${HERMES_DATA_DIR}" ]] || err "HERMES_DATA_DIR not found: ${HERMES_DATA_DIR}"

  stop_agent
  local ts_arg=""
  [[ "${timestamp}" != "latest" ]] && ts_arg="-timestamp ${timestamp}"

  docker run --rm \
    -v "$(pwd)/${LITESTREAM_CONFIG#./}:/etc/litestream.yml:ro" \
    -v "${HERMES_DATA_DIR}:/opt/data" \
    -v "${HERMES_BACKUPS_VOLUME}:/opt/backups" \
    "${LITESTREAM_IMAGE}" \
    restore ${ts_arg} -if-replica-exists /opt/data/state.db

  ok "state.db restored."
  start_agent
}

cmd_volume() {
  local tarball="${1:-}"
  [[ -z "${tarball}" ]] && { list_tarballs; read -r -p "Enter tarball filename: " tarball; }
  info "Restoring full .hermes from: ${tarball}"
  [[ -d "${HERMES_DATA_DIR}" ]] || err "HERMES_DATA_DIR not found: ${HERMES_DATA_DIR}"

  stop_agent
  sudo docker run --rm \
    -v "${HERMES_BACKUPS_VOLUME}:/arc:ro" \
    -v "${HERMES_DATA_DIR}:/data" \
    alpine \
    sh -c "rm -rf /data/* /data/.[!.]* 2>/dev/null; tar xzf \"/arc/${tarball}\" -C /data --strip-components=2"
  ok ".hermes restored from ${tarball}."
  start_agent
}

cmd_file() {
  local filepath="${1:-}" tarball="${2:-}"
  [[ -z "${filepath}" ]] && err "Usage: restore file <path> <tarball>"
  [[ -z "${tarball}" ]] && { list_tarballs; read -r -p "Enter tarball filename: " tarball; }

  info "Extracting ${filepath} from ${tarball}..."
  docker run --rm -v "${HERMES_BACKUPS_VOLUME}:/arc:ro" alpine \
    sh -c "tar xzf \"/arc/${tarball}\" -O \"backup/hermes_data/${filepath}\"" \
    | sudo tee "${HERMES_DATA_DIR}/${filepath}" >/dev/null \
    || err "Could not extract ${filepath}"
  ok "${filepath} restored into ${HERMES_DATA_DIR}."
  warn "The agent may have the old file cached — 'make restart' to reload."
}

CMD="${1:-list}"; shift || true
case "${CMD}" in
  list)   cmd_list ;;
  db)     cmd_db "$@" ;;
  volume) cmd_volume "$@" ;;
  file)   cmd_file "$@" ;;
  *)      err "Unknown command: ${CMD}\nUsage: restore.sh [list|db|volume|file] [args...]" ;;
esac
