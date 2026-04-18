#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(dirname "${SCRIPT_DIR}")"
CONFIG_RENDERER="${REPO_ROOT}/scripts/render-config.py"
ENV_CONTEXT_RENDERER="${REPO_ROOT}/scripts/render-environment-context.py"
PROVISION_SCRIPT="${REPO_ROOT}/scripts/provision-profile.sh"

ENV_ID="${HERMES_ENV_ID:-}"
SERVICE_MODE="${HERMES_SERVICE_MODE:-auto}"
SYNC_PROFILES=1
FORCE_LINK_SHARED=0

usage() {
  cat <<'EOF'
Usage:
  scripts/bootstrap-machine.sh [--env-id <id>] [--service-mode auto|local|remote]
                              [--skip-sync-profiles] [--force-link-shared]

What it does:
  - detects/renders the current machine's Hermes config + ENVIRONMENT.md
  - creates the Syncthing-friendly shared asset layout under env.sync_root
  - mirrors env manifests into <sync_root>/envs for cross-machine discovery
  - links ~/.hermes/shared/{soul,skills} to the synced folders when safe
  - optionally normalizes the default + named local profiles for this machine
EOF
}

log() {
  printf '%s\n' "$*"
}

die() {
  printf 'ERROR: %s\n' "$*" >&2
  exit 1
}

link_shared_dir() {
  local link_path="$1"
  local target_path="$2"

  mkdir -p "$(dirname "${link_path}")"
  mkdir -p "${target_path}"

  if [[ -L "${link_path}" ]]; then
    local current_target
    current_target="$(readlink "${link_path}")"
    if [[ "${current_target}" == "${target_path}" ]]; then
      log "✓ Shared path already linked: ${link_path} -> ${target_path}"
      return 0
    fi
    if [[ ${FORCE_LINK_SHARED} -eq 1 ]]; then
      rm -f "${link_path}"
    else
      die "${link_path} already points to ${current_target}; rerun with --force-link-shared to replace it"
    fi
  elif [[ -e "${link_path}" ]]; then
    if [[ -d "${link_path}" ]] && [[ ${FORCE_LINK_SHARED} -eq 1 ]]; then
      rm -rf "${link_path}"
    else
      log "• Leaving existing directory in place: ${link_path}"
      return 0
    fi
  fi

  ln -s "${target_path}" "${link_path}"
  log "✓ Linked ${link_path} -> ${target_path}"
}

while [[ $# -gt 0 ]]; do
  case "$1" in
    --env-id)
      ENV_ID="${2:?missing env id}"
      shift 2
      ;;
    --service-mode)
      SERVICE_MODE="${2:?missing service mode}"
      shift 2
      ;;
    --skip-sync-profiles)
      SYNC_PROFILES=0
      shift
      ;;
    --force-link-shared)
      FORCE_LINK_SHARED=1
      shift
      ;;
    -h|--help)
      usage
      exit 0
      ;;
    *)
      die "Unknown argument: $1"
      ;;
  esac
done

if [[ -z "${ENV_ID}" ]]; then
  ENV_ID="$(bash "${REPO_ROOT}/scripts/detect-env.sh" --repo-root "${REPO_ROOT}")"
fi

case "${SERVICE_MODE}" in
  auto|local|remote) ;;
  *) die "Unsupported service mode: ${SERVICE_MODE}" ;;
esac

bash "${REPO_ROOT}/scripts/ensure-python-yaml.sh"

TARGET_HOME="$(dirname "${HERMES_HOME:-$HOME/.hermes}")"
HERMES_HOME="${HERMES_HOME:-${TARGET_HOME}/.hermes}"
SYNC_ROOT="$(python3 "${CONFIG_RENDERER}" --repo-root "${REPO_ROOT}" --env-id "${ENV_ID}" --target-home "${TARGET_HOME}" --print-meta env.sync_root)"
WIKI_PATH="$(python3 "${CONFIG_RENDERER}" --repo-root "${REPO_ROOT}" --env-id "${ENV_ID}" --target-home "${TARGET_HOME}" --print-meta env.wiki_path)"
WORK_ROOT="$(python3 "${CONFIG_RENDERER}" --repo-root "${REPO_ROOT}" --env-id "${ENV_ID}" --target-home "${TARGET_HOME}" --print-meta env.work_root)"

mkdir -p "${HERMES_HOME}" \
         "${WORK_ROOT}" \
         "${SYNC_ROOT}" \
         "${WIKI_PATH}" \
         "${SYNC_ROOT}/backups/hindsight" \
         "${SYNC_ROOT}/exports" \
         "${SYNC_ROOT}/envs" \
         "${SYNC_ROOT}/soul/profiles" \
         "${SYNC_ROOT}/skills"

cp -f "${REPO_ROOT}"/config/env/*.yaml "${SYNC_ROOT}/envs/"
log "✓ Mirrored environment manifests into ${SYNC_ROOT}/envs"

link_shared_dir "${HERMES_HOME}/shared/soul" "${SYNC_ROOT}/soul"
link_shared_dir "${HERMES_HOME}/shared/skills" "${SYNC_ROOT}/skills"

python3 "${CONFIG_RENDERER}" \
  --repo-root "${REPO_ROOT}" \
  --env-id "${ENV_ID}" \
  --target-home "${TARGET_HOME}" \
  --profile default \
  --output "${HERMES_HOME}/config.yaml"

python3 "${ENV_CONTEXT_RENDERER}" \
  --repo-root "${REPO_ROOT}" \
  --env-id "${ENV_ID}" \
  --profile default \
  --profile-home "${HERMES_HOME}" \
  --config-path "${HERMES_HOME}/config.yaml" \
  --service-mode "${SERVICE_MODE}" \
  --output "${HERMES_HOME}/ENVIRONMENT.md"

log "✓ Rendered ${HERMES_HOME}/config.yaml"
log "✓ Rendered ${HERMES_HOME}/ENVIRONMENT.md"

if [[ ${SYNC_PROFILES} -eq 1 ]]; then
  HERMES_ENV_ID="${ENV_ID}" \
  HERMES_SERVICE_MODE="${SERVICE_MODE}" \
  HERMES_HOME="${HERMES_HOME}" \
  HERMES_USER="$(id -un)" \
  WORK_ROOT="${WORK_ROOT}" \
  HINDSIGHT_API_URL="$(python3 "${CONFIG_RENDERER}" --repo-root "${REPO_ROOT}" --env-id "${ENV_ID}" --target-home "${TARGET_HOME}" --print-service-url hindsight --service-mode "${SERVICE_MODE}")" \
  bash "${PROVISION_SCRIPT}" --sync-all-profiles --gateway skip
  log "✓ Synchronized local profiles for ${ENV_ID}"
else
  log "• Skipped local profile sync"
fi

cat <<EOF

Machine bootstrap complete.
- Environment: ${ENV_ID}
- Service mode: ${SERVICE_MODE}
- Hermes home: ${HERMES_HOME}
- Work root: ${WORK_ROOT}
- Sync root: ${SYNC_ROOT}
- Wiki path: ${WIKI_PATH}

Next recommended checks:
  bash scripts/verify-environment.sh --all-profiles --service-mode ${SERVICE_MODE}
  hermes chat
EOF
