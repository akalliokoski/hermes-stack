#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(dirname "${SCRIPT_DIR}")"
CONFIG_RENDERER="${REPO_ROOT}/scripts/render-config.py"
IMPORT_SCRIPT="${REPO_ROOT}/scripts/import-profile.sh"
VERIFY_SCRIPT="${REPO_ROOT}/scripts/verify-environment.sh"
DETECT_ENV_SCRIPT="${REPO_ROOT}/scripts/detect-env.sh"

PROFILE=""
VPS_HOST=""
REMOTE_REPO_ROOT="${HERMES_REMOTE_REPO_ROOT:-}"
ENV_ID="${HERMES_ENV_ID:-}"
SERVICE_MODE="${HERMES_SERVICE_MODE:-remote}"
GATEWAY_MODE="skip"
ARCHIVE_PATH=""
WORKSPACE_MODE="copy"
CLONE_MODE="complete"
COPY_AUTH=-1
COPY_ENV=-1
COPY_PROFILE_SKILLS=-1
HERMES_HOME="${HERMES_HOME:-$HOME/.hermes}"
TARGET_HOME="$(dirname "${HERMES_HOME}")"
SSH_OPTIONS=(-o StrictHostKeyChecking=accept-new)
REMOTE_HERMES_HOME="/home/hermes/.hermes"
REMOTE_WORK_ROOT="/home/hermes/work"

usage() {
  cat <<'EOF'
Usage:
  scripts/clone-profile-from-vps.sh --profile <name> [options]

Fetches a Hermes profile bundle from the VPS over SSH/SCP (typically over Tailscale),
imports it locally, and optionally clones the profile workspace and selected
profile-local files.

Options:
  --profile <name>           Profile to clone (required)
  --vps-host <host>          SSH target for the VPS (defaults to VPS_HOST from repo .env)
  --remote-repo-root <path>  VPS repo path used to run export-profile.sh (default: auto-detect via VPS_DIR, /home/hermes/work/hermes-stack, /opt/hermes)
  --archive <path>           Local archive destination (default: <sync_root>/exports/profiles/<name>/...)
  --env-id <id>              Local environment manifest id (default: auto-detect)
  --target-home <path>       Base directory for local install layout (default: parent of ~/.hermes)
  --service-mode <mode>      Local import service mode: auto|local|remote (default: remote)
  --gateway <mode>           Passed through to import-profile.sh (default: skip)
  --clone-mode <mode>        complete|minimal (default: complete)
  --workspace <mode>         copy|skip the VPS workspace into the local work root (default: copy)
  --copy-auth                Also copy profile auth.json from VPS (enabled by default in complete mode)
  --no-copy-auth             Skip copying profile auth.json
  --copy-env                 Also copy profile .env from VPS (enabled by default in complete mode)
  --no-copy-env              Skip copying profile .env
  --copy-profile-skills      Also copy profile-local skills/ from VPS (enabled by default in complete mode)
  --no-copy-profile-skills   Skip copying profile-local skills/
  --ssh-option <option>      Extra ssh/scp option; repeatable
  -h, --help                 Show this help

Examples:
  bash scripts/clone-profile-from-vps.sh --profile ai-lab --vps-host vps
  bash scripts/clone-profile-from-vps.sh --profile ai-lab
  bash scripts/clone-profile-from-vps.sh --profile ai-lab --target-home "$HOME/machines/hermes-mac"
  bash scripts/clone-profile-from-vps.sh --profile ai-lab --remote-repo-root /home/hermes/work/hermes-stack
  bash scripts/clone-profile-from-vps.sh --profile ai-lab --clone-mode minimal --workspace skip
EOF
}

log() {
  printf '%s\n' "$*"
}

warn() {
  printf 'WARN: %s\n' "$*" >&2
}

die() {
  printf 'ERROR: %s\n' "$*" >&2
  exit 1
}

shell_quote() {
  printf '%q' "$1"
}

default_vps_host() {
  local env_file="${REPO_ROOT}/.env"
  if [[ -f "${env_file}" ]]; then
    awk -F= '/^VPS_HOST=/{print $2; exit}' "${env_file}"
  fi
}

default_remote_repo_root() {
  local env_file="${REPO_ROOT}/.env"
  if [[ -f "${env_file}" ]]; then
    awk -F= '/^VPS_DIR=/{print $2; exit}' "${env_file}"
  fi
}

detect_remote_repo_root() {
  local candidate
  local candidates=()

  if [[ -n "${REMOTE_REPO_ROOT}" ]]; then
    candidates+=("${REMOTE_REPO_ROOT}")
  fi

  candidate="$(default_remote_repo_root)"
  if [[ -n "${candidate}" ]]; then
    candidates+=("${candidate}")
  fi

  candidates+=("/home/hermes/work/hermes-stack" "/opt/hermes")

  local remote_path
  local seen="|"
  for remote_path in "${candidates[@]}"; do
    [[ -n "${remote_path}" ]] || continue
    if [[ "${seen}" == *"|${remote_path}|"* ]]; then
      continue
    fi
    seen+="${remote_path}|"
    if run_ssh "test -f $(shell_quote "${remote_path}/scripts/export-profile.sh")" >/dev/null 2>&1; then
      REMOTE_REPO_ROOT="${remote_path}"
      return 0
    fi
  done

  return 1
}

profile_home() {
  local base_home="$1"
  local profile="$2"
  if [[ "${profile}" == "default" ]]; then
    printf '%s\n' "${base_home}"
  else
    printf '%s/profiles/%s\n' "${base_home}" "${profile}"
  fi
}

run_ssh() {
  ssh "${SSH_OPTIONS[@]}" "${VPS_HOST}" "$1"
}

run_scp() {
  scp "${SSH_OPTIONS[@]}" "$@"
}

backup_if_exists() {
  local path="$1"
  if [[ -e "${path}" ]]; then
    local backup_path="${path}.bak.$(date +%Y%m%d%H%M%S)"
    mv "${path}" "${backup_path}"
    log "• Backed up existing ${path} -> ${backup_path}"
  fi
}

copy_remote_tree() {
  local remote_dir="$1"
  local local_dir="$2"
  mkdir -p "${local_dir}"

  if ! run_ssh "test -d $(shell_quote "${remote_dir}")" >/dev/null 2>&1; then
    warn "Remote directory missing, skipping: ${remote_dir}"
    return 0
  fi

  if command -v rsync >/dev/null 2>&1 && run_ssh 'command -v rsync >/dev/null 2>&1'; then
    local rsync_rsh='ssh'
    local opt
    for opt in "${SSH_OPTIONS[@]}"; do
      rsync_rsh+=" ${opt}"
    done
    rsync -az --delete -e "${rsync_rsh}" "${VPS_HOST}:${remote_dir}/" "${local_dir}/"
  else
    warn "rsync unavailable locally or remotely; falling back to tar stream without delete semantics"
    run_ssh "cd $(shell_quote "${remote_dir}") && tar -cf - ." | tar -xf - -C "${local_dir}"
  fi
}

while [[ $# -gt 0 ]]; do
  case "$1" in
    --profile)
      PROFILE="${2:?missing profile}"
      shift 2
      ;;
    --vps-host)
      VPS_HOST="${2:?missing vps host}"
      shift 2
      ;;
    --remote-repo-root)
      REMOTE_REPO_ROOT="${2:?missing remote repo root}"
      shift 2
      ;;
    --archive)
      ARCHIVE_PATH="${2:?missing archive path}"
      shift 2
      ;;
    --env-id)
      ENV_ID="${2:?missing env id}"
      shift 2
      ;;
    --target-home)
      TARGET_HOME="${2:?missing target home}"
      HERMES_HOME="${TARGET_HOME}/.hermes"
      shift 2
      ;;
    --service-mode)
      SERVICE_MODE="${2:?missing service mode}"
      shift 2
      ;;
    --gateway)
      GATEWAY_MODE="${2:?missing gateway mode}"
      shift 2
      ;;
    --workspace)
      WORKSPACE_MODE="${2:?missing workspace mode}"
      shift 2
      ;;
    --clone-mode)
      CLONE_MODE="${2:?missing clone mode}"
      shift 2
      ;;
    --copy-auth)
      COPY_AUTH=1
      shift
      ;;
    --no-copy-auth)
      COPY_AUTH=0
      shift
      ;;
    --copy-env)
      COPY_ENV=1
      shift
      ;;
    --no-copy-env)
      COPY_ENV=0
      shift
      ;;
    --copy-profile-skills)
      COPY_PROFILE_SKILLS=1
      shift
      ;;
    --no-copy-profile-skills)
      COPY_PROFILE_SKILLS=0
      shift
      ;;
    --ssh-option)
      SSH_OPTIONS+=("${2:?missing ssh option}")
      shift 2
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

[[ -n "${PROFILE}" ]] || die "--profile is required"
[[ "${WORKSPACE_MODE}" == "copy" || "${WORKSPACE_MODE}" == "skip" ]] || die "--workspace must be copy or skip"
[[ "${CLONE_MODE}" == "complete" || "${CLONE_MODE}" == "minimal" ]] || die "--clone-mode must be complete or minimal"
[[ "${SERVICE_MODE}" == "auto" || "${SERVICE_MODE}" == "local" || "${SERVICE_MODE}" == "remote" ]] || die "--service-mode must be auto, local, or remote"
[[ "${GATEWAY_MODE}" == "skip" || "${GATEWAY_MODE}" == "auto" || "${GATEWAY_MODE}" == "required" ]] || die "--gateway must be skip, auto, or required"

if [[ ${COPY_AUTH} -lt 0 ]]; then
  if [[ "${CLONE_MODE}" == "complete" ]]; then
    COPY_AUTH=1
  else
    COPY_AUTH=0
  fi
fi
if [[ ${COPY_ENV} -lt 0 ]]; then
  if [[ "${CLONE_MODE}" == "complete" ]]; then
    COPY_ENV=1
  else
    COPY_ENV=0
  fi
fi
if [[ ${COPY_PROFILE_SKILLS} -lt 0 ]]; then
  if [[ "${CLONE_MODE}" == "complete" ]]; then
    COPY_PROFILE_SKILLS=1
  else
    COPY_PROFILE_SKILLS=0
  fi
fi

if [[ -z "${VPS_HOST}" ]]; then
  VPS_HOST="$(default_vps_host)"
fi
[[ -n "${VPS_HOST}" ]] || die "Could not determine VPS host. Pass --vps-host or set VPS_HOST in ${REPO_ROOT}/.env"

if ! detect_remote_repo_root; then
  die "Could not find export-profile.sh on ${VPS_HOST}. Pass --remote-repo-root explicitly or set VPS_DIR in ${REPO_ROOT}/.env"
fi

if [[ -z "${ENV_ID}" ]]; then
  ENV_ID="$(bash "${DETECT_ENV_SCRIPT}" --repo-root "${REPO_ROOT}")"
fi

bash "${REPO_ROOT}/scripts/ensure-python-yaml.sh" >/dev/null
SYNC_ROOT="$(python3 "${CONFIG_RENDERER}" --repo-root "${REPO_ROOT}" --env-id "${ENV_ID}" --target-home "${TARGET_HOME}" --print-meta env.sync_root)"
WORK_ROOT="$(python3 "${CONFIG_RENDERER}" --repo-root "${REPO_ROOT}" --env-id "${ENV_ID}" --target-home "${TARGET_HOME}" --print-meta env.work_root)"
WIKI_PATH="$(python3 "${CONFIG_RENDERER}" --repo-root "${REPO_ROOT}" --env-id "${ENV_ID}" --target-home "${TARGET_HOME}" --print-meta env.wiki_path)"
LOCAL_PROFILE_HOME="$(profile_home "${HERMES_HOME}" "${PROFILE}")"
REMOTE_PROFILE_HOME="$(profile_home "${REMOTE_HERMES_HOME}" "${PROFILE}")"
REMOTE_WORKSPACE="${REMOTE_WORK_ROOT}/${PROFILE}"
LOCAL_WORKSPACE="${WORK_ROOT}/${PROFILE}"

if [[ -z "${ARCHIVE_PATH}" ]]; then
  mkdir -p "${SYNC_ROOT}/exports/profiles/${PROFILE}"
  ARCHIVE_PATH="${SYNC_ROOT}/exports/profiles/${PROFILE}/${PROFILE}_from_vps_$(date -u +%Y-%m-%dT%H-%M-%SZ).tar.gz"
else
  mkdir -p "$(dirname "${ARCHIVE_PATH}")"
fi

cat <<EOF
Local clone layout:
- Target home: ${TARGET_HOME}
- Hermes root: ${HERMES_HOME}
- Profile home: ${LOCAL_PROFILE_HOME}
- Shared skills: ${HERMES_HOME}/shared/skills
- Shared soul: ${HERMES_HOME}/shared/soul
- Work root: ${WORK_ROOT}
- Profile workspace: ${LOCAL_WORKSPACE}
- Sync root: ${SYNC_ROOT}
- Wiki path: ${WIKI_PATH}
- Archive path: ${ARCHIVE_PATH}
- Remote repo root: ${REMOTE_REPO_ROOT}
EOF

log "→ Exporting profile '${PROFILE}' on ${VPS_HOST} via ${REMOTE_REPO_ROOT}"
REMOTE_EXPORT_OUTPUT="$(run_ssh "cd $(shell_quote "${REMOTE_REPO_ROOT}") && sudo -iu hermes env HERMES_ENV_ID=vps bash scripts/export-profile.sh --profile $(shell_quote "${PROFILE}") --service-mode remote")"
printf '%s\n' "${REMOTE_EXPORT_OUTPUT}"
REMOTE_ARCHIVE_PATH="$(printf '%s\n' "${REMOTE_EXPORT_OUTPUT}" | awk -F': ' '/Exported profile bundle/ {print $2}' | tail -n1)"
[[ -n "${REMOTE_ARCHIVE_PATH}" ]] || die "Could not parse remote archive path from export output"

log "→ Downloading ${REMOTE_ARCHIVE_PATH} to ${ARCHIVE_PATH}"
run_scp "${VPS_HOST}:${REMOTE_ARCHIVE_PATH}" "${ARCHIVE_PATH}"

log "→ Importing profile locally"
bash "${IMPORT_SCRIPT}" --archive "${ARCHIVE_PATH}" --profile "${PROFILE}" --service-mode "${SERVICE_MODE}" --gateway "${GATEWAY_MODE}"

if [[ "${WORKSPACE_MODE}" == "copy" ]]; then
  log "→ Copying workspace ${REMOTE_WORKSPACE} -> ${LOCAL_WORKSPACE}"
  copy_remote_tree "${REMOTE_WORKSPACE}" "${LOCAL_WORKSPACE}"
  log "✓ Workspace copied"
else
  log "• Skipped workspace copy"
fi

if [[ ${COPY_PROFILE_SKILLS} -eq 1 ]]; then
  log "→ Copying profile-local skills"
  copy_remote_tree "${REMOTE_PROFILE_HOME}/skills" "${LOCAL_PROFILE_HOME}/skills"
  log "✓ Profile-local skills copied"
fi

if [[ ${COPY_AUTH} -eq 1 ]]; then
  log "→ Copying auth.json"
  mkdir -p "${LOCAL_PROFILE_HOME}"
  backup_if_exists "${LOCAL_PROFILE_HOME}/auth.json"
  run_scp "${VPS_HOST}:${REMOTE_PROFILE_HOME}/auth.json" "${LOCAL_PROFILE_HOME}/auth.json"
  log "✓ auth.json copied"
fi

if [[ ${COPY_ENV} -eq 1 ]]; then
  log "→ Copying .env"
  mkdir -p "${LOCAL_PROFILE_HOME}"
  backup_if_exists "${LOCAL_PROFILE_HOME}/.env"
  run_scp "${VPS_HOST}:${REMOTE_PROFILE_HOME}/.env" "${LOCAL_PROFILE_HOME}/.env"
  log "✓ .env copied"
fi

log "→ Verifying local profile wiring"
bash "${VERIFY_SCRIPT}" --profile "${PROFILE}" --service-mode "${SERVICE_MODE}"

cat <<EOF
Done.
- Profile: ${PROFILE}
- VPS host: ${VPS_HOST}
- Local archive: ${ARCHIVE_PATH}
- Local profile home: ${LOCAL_PROFILE_HOME}
- Local workspace: ${LOCAL_WORKSPACE}
- Clone mode: ${CLONE_MODE}
- Workspace copied: ${WORKSPACE_MODE}
- Auth copied: ${COPY_AUTH}
- Env copied: ${COPY_ENV}
- Profile-local skills copied: ${COPY_PROFILE_SKILLS}
EOF
