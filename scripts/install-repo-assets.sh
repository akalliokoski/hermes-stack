#!/usr/bin/env bash
set -euo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
HERMES_USER="${HERMES_USER:-hermes}"
HERMES_HOME="${HERMES_HOME:-/home/hermes/.hermes}"
PRUNE_SYNC_COPIES="${PRUNE_SYNC_COPIES:-0}"

log() {
  printf '%s\n' "$*"
}

link_repo_dir() {
  local name="$1"
  local target="${REPO_ROOT}/${name}"
  local link_path="$2"
  local stamp

  [[ -d "${target}" ]] || mkdir -p "${target}"
  mkdir -p "$(dirname "${link_path}")"

  if [[ -L "${link_path}" ]]; then
    if [[ "$(readlink "${link_path}")" == "${target}" ]]; then
      log "✓ ${link_path} already points to ${target}"
      return 0
    fi
    rm -f "${link_path}"
  elif [[ -e "${link_path}" ]]; then
    stamp="$(date -u +%Y%m%dT%H%M%SZ)"
    mv "${link_path}" "${link_path}.pre-repo-assets.${stamp}"
    log "• Moved existing ${link_path} aside before linking repo asset"
  fi

  ln -s "${target}" "${link_path}"
  log "✓ Linked ${link_path} -> ${target}"
}

if [[ ${EUID} -eq 0 ]] && id "${HERMES_USER}" >/dev/null 2>&1; then
  chown -R "${HERMES_USER}:${HERMES_USER}" "${REPO_ROOT}/wiki" "${REPO_ROOT}/soul" "${REPO_ROOT}/skills" 2>/dev/null || true
fi

mkdir -p "${HERMES_HOME}/shared"
link_repo_dir soul "${HERMES_HOME}/shared/soul"
link_repo_dir skills "${HERMES_HOME}/shared/skills"

if [[ "${PRUNE_SYNC_COPIES}" == "1" ]]; then
  rm -rf /home/hermes/sync/wiki /home/hermes/sync/soul /home/hermes/sync/skills
  log "✓ Removed legacy Syncthing copies of wiki/soul/skills"
fi
