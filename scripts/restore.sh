#!/usr/bin/env bash
# scripts/restore.sh – Hermes agent state restore utility
#
# Usage:
#   bash scripts/restore.sh list                         # list available snapshots
#   bash scripts/restore.sh db [timestamp|latest]        # restore state.db via Litestream
#   bash scripts/restore.sh volume [tarball]             # restore full hermes_data from tarball
#   bash scripts/restore.sh file <path> [tarball]        # extract single file from tarball
#
# Or via make:
#   make restore ARGS="list"
#   make restore ARGS="db latest"
#   make restore ARGS="volume hermes_data_2026-04-05T03-00-00.tar.gz"
#   make restore ARGS="file memories/MEMORY.md hermes_data_2026-04-05T03-00-00.tar.gz"

set -euo pipefail

CONTAINER="hermes_agent"
LITESTREAM_IMAGE="litestream/litestream:latest"
LITESTREAM_CONFIG="./litestream.yml"
ARCHIVE_DIR="${BACKUP_DIR:-./backups}"
HERMES_DATA_VOLUME="hermes_hermes_data"
HERMES_BACKUPS_VOLUME="hermes_hermes_backups"

# Use local litestream config if it exists (local dev)
if [[ -f "./litestream.local.yml" && -z "${FORCE_VPS_CONFIG:-}" ]]; then
  LITESTREAM_CONFIG="./litestream.local.yml"
fi

RED='\033[0;31m'; YELLOW='\033[1;33m'; GREEN='\033[0;32m'; CYAN='\033[0;36m'; NC='\033[0m'

err()  { echo -e "${RED}error:${NC} $*" >&2; exit 1; }
info() { echo -e "${CYAN}→${NC} $*"; }
ok()   { echo -e "${GREEN}✓${NC} $*"; }
warn() { echo -e "${YELLOW}warn:${NC} $*"; }

# ── helpers ────────────────────────────────────────────────────────────────────

find_archive_dir() {
  # Try to resolve from running backup container label
  local vol
  vol=$(docker volume ls --format '{{.Name}}' | grep -E '(hermes_hermes_backups|hermes_backups)' | head -1 || true)
  if [[ -n "${vol}" ]]; then
    echo "${vol}"
  else
    echo "${ARCHIVE_DIR}"
  fi
}

list_tarballs() {
  local dir="${ARCHIVE_DIR}"
  # Try to find tarballs inside the Docker volume
  echo -e "\n${CYAN}── Volume snapshots (hermes_data tarballs) ──${NC}"
  if docker volume inspect "${HERMES_BACKUPS_VOLUME}" &>/dev/null; then
    docker run --rm \
      -v "${HERMES_BACKUPS_VOLUME}:/arc:ro" \
      alpine \
      sh -c "ls -lh /arc/*.tar.gz 2>/dev/null | awk '{print \$5, \$9}' | sed 's|/arc/||'" \
      || warn "No tarballs found yet."
  elif ls "${dir}"/*.tar.gz &>/dev/null 2>&1; then
    ls -lh "${dir}"/*.tar.gz | awk '{print $5, $9}'
  else
    warn "No tarballs found in ${dir}."
  fi
}

list_litestream_snapshots() {
  echo -e "\n${CYAN}── Litestream SQLite snapshots ──${NC}"
  if docker volume inspect "${HERMES_BACKUPS_VOLUME}" &>/dev/null; then
    docker run --rm \
      -v "${LITESTREAM_CONFIG}:/etc/litestream.yml:ro" \
      -v "${HERMES_BACKUPS_VOLUME}:/opt/backups" \
      "${LITESTREAM_IMAGE}" \
      snapshots \
      || warn "No Litestream snapshots found yet (DB not yet replicated)."
  else
    warn "hermes_backups volume not found — Litestream not yet started?"
  fi
}

stop_agent() {
  info "Stopping hermes_agent..."
  docker stop "${CONTAINER}" 2>/dev/null || true
}

start_agent() {
  info "Starting hermes_agent..."
  docker compose up -d hermes-agent 2>/dev/null \
    || docker start "${CONTAINER}" 2>/dev/null \
    || warn "Could not restart hermes_agent — run 'make local-up' or 'make up' manually."
}

# ── subcommands ────────────────────────────────────────────────────────────────

cmd_list() {
  list_tarballs
  list_litestream_snapshots
}

cmd_db() {
  local timestamp="${1:-latest}"
  info "Restoring state.db from Litestream replica (timestamp: ${timestamp})"

  docker volume inspect "${HERMES_BACKUPS_VOLUME}" &>/dev/null \
    || err "hermes_backups volume not found. Has the stack been started at least once?"

  stop_agent
  # Also stop litestream sidecar so it doesn't fight the restore
  docker stop hermes-litestream-1 2>/dev/null || docker stop "$(docker compose ps -q litestream 2>/dev/null)" 2>/dev/null || true

  info "Running litestream restore..."
  local ts_arg=""
  if [[ "${timestamp}" != "latest" ]]; then
    ts_arg="-timestamp ${timestamp}"
  fi

  docker run --rm \
    -v "${LITESTREAM_CONFIG}:/etc/litestream.yml:ro" \
    -v "${HERMES_DATA_VOLUME}:/opt/data" \
    -v "${HERMES_BACKUPS_VOLUME}:/opt/backups" \
    "${LITESTREAM_IMAGE}" \
    restore ${ts_arg} -if-replica-exists /opt/data/state.db

  ok "state.db restored."
  docker compose up -d litestream hermes-agent 2>/dev/null || start_agent
}

cmd_volume() {
  local tarball="${1:-}"
  if [[ -z "${tarball}" ]]; then
    echo "Available tarballs:"; list_tarballs
    echo ""
    read -r -p "Enter tarball filename: " tarball
  fi

  # Resolve tarball path — check volume first, then local dir
  info "Restoring full hermes_data from: ${tarball}"

  stop_agent
  docker stop hermes-litestream-1 2>/dev/null || docker stop "$(docker compose ps -q litestream 2>/dev/null)" 2>/dev/null || true

  info "Wiping hermes_data volume and restoring from tarball..."
  docker run --rm \
    -v "${HERMES_BACKUPS_VOLUME}:/arc:ro" \
    -v "${HERMES_DATA_VOLUME}:/data" \
    alpine \
    sh -c "rm -rf /data/* /data/.[!.]* 2>/dev/null; tar xzf \"/arc/${tarball}\" -C /data/backup/hermes_data --strip-components=3 2>/dev/null || tar xzf \"/arc/${tarball}\" -C /data"

  ok "hermes_data restored from ${tarball}."
  docker compose up -d litestream hermes-agent 2>/dev/null || start_agent
}

cmd_file() {
  local filepath="${1:-}"
  local tarball="${2:-}"
  [[ -z "${filepath}" ]] && err "Usage: restore file <path-inside-data> [tarball]\n  e.g.: restore file memories/MEMORY.md hermes_data_2026-04-05T03-00-00.tar.gz"

  if [[ -z "${tarball}" ]]; then
    echo "Available tarballs:"; list_tarballs; echo ""
    read -r -p "Enter tarball filename: " tarball
  fi

  info "Extracting ${filepath} from ${tarball}..."

  # Extract the file to a temp container, then docker cp into the running container
  docker run --rm \
    -v "${HERMES_BACKUPS_VOLUME}:/arc:ro" \
    --name hermes-restore-tmp \
    alpine \
    sh -c "mkdir -p /tmp/restore && tar xzf \"/arc/${tarball}\" -C /tmp/restore && find /tmp/restore -name '$(basename "${filepath}")' | head -1 | xargs -I{} cp {} /tmp/out 2>/dev/null || true" &

  sleep 2
  # Simpler: extract directly and copy
  docker run --rm \
    -v "${HERMES_BACKUPS_VOLUME}:/arc:ro" \
    alpine \
    sh -c "tar xzf \"/arc/${tarball}\" -O \"backup/hermes_data/${filepath}\" 2>/dev/null || tar xzf \"/arc/${tarball}\" -O \"${filepath}\"" \
    | docker cp - "${CONTAINER}:/opt/data/${filepath}" \
    || err "Could not extract ${filepath} from ${tarball}"

  ok "${filepath} restored into running container."
  warn "The agent is still running with the old file cached in memory. Consider 'make restart' to reload."
}

# ── main ───────────────────────────────────────────────────────────────────────

CMD="${1:-list}"
shift || true

case "${CMD}" in
  list)     cmd_list ;;
  db)       cmd_db "$@" ;;
  volume)   cmd_volume "$@" ;;
  file)     cmd_file "$@" ;;
  *)        err "Unknown command: ${CMD}\nUsage: restore.sh [list|db|volume|file] [args...]" ;;
esac
