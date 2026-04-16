#!/usr/bin/env bash
set -euo pipefail

HERMES_USER="${HERMES_USER:-hermes}"
HERMES_HOME="${HERMES_HOME:-/home/hermes/.hermes}"
WORK_ROOT="${WORK_ROOT:-/home/hermes/work}"
SHARED_SOUL_ROOT="${SHARED_SOUL_ROOT:-${HERMES_HOME}/shared/soul}"
HINDSIGHT_API_URL="${HINDSIGHT_API_URL:-http://127.0.0.1:8888}"
PROFILE="${PROFILE:-}"
TELEGRAM_BOT_TOKEN="${TELEGRAM_BOT_TOKEN:-}"
SYNC_ALL_SOULS=0
SYNC_ALL_PROFILES=0
GATEWAY_MODE="auto"

usage() {
  cat <<'EOF'
Usage:
  scripts/provision-profile.sh --profile <name> [--telegram-bot-token <token>] [--gateway auto|skip|required]
  scripts/provision-profile.sh --sync-all-souls
  scripts/provision-profile.sh --sync-all-profiles [--gateway auto|skip|required]

What it does:
  - creates or updates a Hermes profile on the VPS
  - gives the profile its own /home/hermes/work/<profile> workspace
  - writes profile-local Hindsight config with bankId hermes-<profile>
  - manages shared SOUL sources under ~/.hermes/shared/soul/
  - renders profile SOUL.md from shared base + per-profile override
  - installs/starts the system gateway when root/passwordless sudo is available

Shared SOUL layout:
  ~/.hermes/shared/soul/base.md
  ~/.hermes/shared/soul/profiles/<profile>.md
EOF
}

log() {
  printf '%s\n' "$*"
}

die() {
  printf 'ERROR: %s\n' "$*" >&2
  exit 1
}

have_passwordless_sudo() {
  sudo -n true >/dev/null 2>&1
}

run_as_hermes() {
  if [[ "$(id -un)" == "${HERMES_USER}" ]]; then
    "$@"
  else
    sudo -iu "${HERMES_USER}" "$@"
  fi
}

run_as_root_if_possible() {
  if [[ ${EUID} -eq 0 ]]; then
    "$@"
  elif have_passwordless_sudo; then
    sudo "$@"
  else
    return 1
  fi
}

profile_home() {
  local profile="$1"
  if [[ "${profile}" == "default" ]]; then
    printf '%s\n' "${HERMES_HOME}"
  else
    printf '%s\n' "${HERMES_HOME}/profiles/${profile}"
  fi
}

profile_soul_path() {
  printf '%s/SOUL.md\n' "$(profile_home "$1")"
}

profile_env_path() {
  printf '%s/.env\n' "$(profile_home "$1")"
}

profile_hindsight_dir() {
  printf '%s/hindsight\n' "$(profile_home "$1")"
}

profile_override_path() {
  printf '%s/profiles/%s.md\n' "${SHARED_SOUL_ROOT}" "$1"
}

ensure_shared_soul_layout() {
  run_as_hermes mkdir -p "${SHARED_SOUL_ROOT}/profiles"

  local default_soul
  default_soul="$(profile_soul_path default)"
  if ! run_as_hermes test -f "${SHARED_SOUL_ROOT}/base.md"; then
    if run_as_hermes test -s "${default_soul}"; then
      log "→ Seeding shared SOUL base from ${default_soul}"
      run_as_hermes cp "${default_soul}" "${SHARED_SOUL_ROOT}/base.md"
    else
      run_as_hermes touch "${SHARED_SOUL_ROOT}/base.md"
    fi
  fi

  if ! run_as_hermes test -f "${SHARED_SOUL_ROOT}/README.md"; then
    run_as_hermes bash -lc "cat > \"${SHARED_SOUL_ROOT}/README.md\" <<'EOF'
Shared SOUL instructions
========================

Edit base.md for instructions shared by every Hermes profile.
Edit profiles/<name>.md for profile-specific instructions.

After changing either file, rerun:
  bash /opt/hermes/scripts/provision-profile.sh --sync-all-souls

Or update a single profile:
  bash /opt/hermes/scripts/provision-profile.sh --profile <name>
EOF"
  fi
}

ensure_profile_override_file() {
  local override
  override="$(profile_override_path "$1")"
  if ! run_as_hermes test -f "${override}"; then
    run_as_hermes touch "${override}"
  fi
}

render_profile_soul() {
  local profile="$1"
  local base_file override_file target tmp_file
  base_file="${SHARED_SOUL_ROOT}/base.md"
  override_file="$(profile_override_path "${profile}")"
  target="$(profile_soul_path "${profile}")"
  tmp_file="$(mktemp)"

  run_as_hermes mkdir -p "$(dirname "${target}")"
  ensure_profile_override_file "${profile}"

  run_as_hermes bash -lc "
    if [[ -s \"${base_file}\" ]]; then
      cat \"${base_file}\"
    fi
    if [[ -s \"${base_file}\" && -s \"${override_file}\" ]]; then
      printf '\n\n'
    fi
    if [[ -s \"${override_file}\" ]]; then
      cat \"${override_file}\"
    fi
  " > "${tmp_file}"

  if run_as_hermes test -f "${target}" && cmp -s "${tmp_file}" <(run_as_hermes cat "${target}"); then
    rm -f "${tmp_file}"
    log "✓ SOUL.md already up to date for profile '${profile}'"
    return
  fi

  if [[ "$(id -un)" == "${HERMES_USER}" ]]; then
    cp "${tmp_file}" "${target}"
    chmod 644 "${target}"
  else
    install -o "${HERMES_USER}" -g "${HERMES_USER}" -m 644 "${tmp_file}" "${target}"
  fi

  rm -f "${tmp_file}"
  log "✓ Rendered SOUL.md for profile '${profile}'"
}

sync_all_souls() {
  ensure_shared_soul_layout
  render_profile_soul default

  local profiles_root="${HERMES_HOME}/profiles"
  if run_as_hermes test -d "${profiles_root}"; then
    while IFS= read -r profile; do
      [[ -n "${profile}" ]] || continue
      render_profile_soul "${profile}"
    done < <(run_as_hermes bash -lc "find \"${profiles_root}\" -mindepth 1 -maxdepth 1 -type d -printf '%f\n' | sort")
  fi
}

sync_all_profiles() {
  ensure_shared_soul_layout

  local profiles=(default)
  local profiles_root="${HERMES_HOME}/profiles"
  if run_as_hermes test -d "${profiles_root}"; then
    while IFS= read -r profile; do
      [[ -n "${profile}" ]] || continue
      profiles+=("${profile}")
    done < <(run_as_hermes bash -lc "find \"${profiles_root}\" -mindepth 1 -maxdepth 1 -type d -printf '%f\n' | sort")
  fi

  local profile
  for profile in "${profiles[@]}"; do
    create_profile_if_needed "${profile}"
    configure_workspace "${profile}"
    configure_git_include "${profile}"
    configure_hindsight "${profile}"
    render_profile_soul "${profile}"
  done
}

create_profile_if_needed() {
  local profile="$1"
  [[ "${profile}" != "default" ]] || return 0

  if run_as_hermes test -d "$(profile_home "${profile}")"; then
    log "✓ Profile '${profile}' already exists"
    return 0
  fi

  log "→ Creating profile '${profile}'"
  run_as_hermes hermes profile create "${profile}"
}

configure_workspace() {
  local profile="$1"
  local config_path
  [[ "${profile}" != "default" ]] || return 0

  config_path="$(profile_home "${profile}")/config.yaml"
  run_as_hermes mkdir -p "${WORK_ROOT}/${profile}"

  run_as_hermes python3 - <<PY
from pathlib import Path
profile = ${profile@Q}
path = Path(${config_path@Q})
old = "/home/hermes/work/default:/workspace"
new = f"/home/hermes/work/{profile}:/workspace"
text = path.read_text()
if new not in text:
    if old not in text:
        raise SystemExit(f"Expected to find {old!r} in {path}")
    path.write_text(text.replace(old, new))
PY

  log "✓ Workspace mapped to ${WORK_ROOT}/${profile}"
}

write_telegram_env() {
  local profile="$1"
  local env_path
  env_path="$(profile_env_path "${profile}")"

  if [[ -z "${TELEGRAM_BOT_TOKEN}" ]]; then
    log "• TELEGRAM_BOT_TOKEN not provided; leaving ${env_path} unchanged"
    return 0
  fi

  run_as_hermes python3 - <<PY
from pathlib import Path
path = Path(${env_path@Q})
key = "TELEGRAM_BOT_TOKEN"
value = ${TELEGRAM_BOT_TOKEN@Q}
lines = []
if path.exists():
    lines = path.read_text().splitlines()
updated = False
new_lines = []
for line in lines:
    if line.startswith(f"{key}="):
        new_lines.append(f"{key}={value}")
        updated = True
    else:
        new_lines.append(line)
if not updated:
    new_lines.append(f"{key}={value}")
path.write_text("\n".join(new_lines).rstrip() + "\n")
PY
  run_as_hermes chmod 600 "${env_path}"
  log "✓ Updated TELEGRAM_BOT_TOKEN in ${env_path}"
}

configure_git_include() {
  local profile="$1"
  local home_dir gitconfig_path
  home_dir="$(profile_home "${profile}")/home"
  gitconfig_path="${home_dir}/.gitconfig"

  run_as_hermes mkdir -p "${home_dir}"
  run_as_hermes bash -lc "cat > \"${gitconfig_path}\" <<'EOF'
[include]
  path = /home/hermes/.config/git/shared.gitconfig
EOF"
  run_as_hermes chmod 644 "${gitconfig_path}"
  log "✓ Shared git defaults enabled for profile '${profile}'"
}

configure_hindsight() {
  local profile="$1"
  local bank_id hindsight_dir config_path
  bank_id="hermes-${profile}"
  hindsight_dir="$(profile_hindsight_dir "${profile}")"
  config_path="${hindsight_dir}/config.json"

  run_as_hermes mkdir -p "${hindsight_dir}"
  run_as_hermes python3 - <<PY
from pathlib import Path
import json
path = Path(${config_path@Q})
payload = {
    "hindsightApiUrl": ${HINDSIGHT_API_URL@Q},
    "bankId": ${bank_id@Q},
    "autoRecall": True,
    "autoRetain": True,
}
path.write_text(json.dumps(payload, separators=(",", ":")) + "\n")
PY
  run_as_hermes chmod 600 "${config_path}"
  log "✓ Hindsight configured for profile '${profile}' (bank: ${bank_id})"
}

configure_gateway() {
  local profile="$1"
  [[ "${profile}" != "default" ]] || return 0

  case "${GATEWAY_MODE}" in
    skip)
      log "• Skipping gateway install/start for profile '${profile}'"
      return 0
      ;;
    auto|required)
      ;;
    *)
      die "Unsupported gateway mode: ${GATEWAY_MODE}"
      ;;
  esac

  if [[ ${EUID} -eq 0 ]] || have_passwordless_sudo; then
    log "→ Installing system gateway for profile '${profile}'"
    if [[ ${EUID} -eq 0 ]]; then
      sudo -iu "${HERMES_USER}" hermes -p "${profile}" gateway install --system --run-as-user "${HERMES_USER}"
      HERMES_HOME="${HERMES_HOME}" hermes -p "${profile}" gateway start --system
    else
      sudo -iu "${HERMES_USER}" hermes -p "${profile}" gateway install --system --run-as-user "${HERMES_USER}"
      sudo env HERMES_HOME="${HERMES_HOME}" hermes -p "${profile}" gateway start --system
    fi
    log "✓ Gateway running as hermes-gateway-${profile}.service"
    return 0
  fi

  if [[ "${GATEWAY_MODE}" == "required" ]]; then
    die "Need root or passwordless sudo to install/start a system gateway for '${profile}'"
  fi

  log "• No root/passwordless sudo available; profile created but gateway install/start was skipped"
}

while [[ $# -gt 0 ]]; do
  case "$1" in
    --profile)
      PROFILE="${2:-}"
      shift 2
      ;;
    --telegram-bot-token)
      TELEGRAM_BOT_TOKEN="${2:-}"
      shift 2
      ;;
    --gateway)
      GATEWAY_MODE="${2:-}"
      shift 2
      ;;
    --sync-all-souls)
      SYNC_ALL_SOULS=1
      shift
      ;;
    --sync-all-profiles)
      SYNC_ALL_PROFILES=1
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

if [[ ${SYNC_ALL_SOULS} -eq 1 ]]; then
  sync_all_souls
  exit 0
fi

if [[ ${SYNC_ALL_PROFILES} -eq 1 ]]; then
  sync_all_profiles
  exit 0
fi

[[ -n "${PROFILE}" ]] || die "--profile <name> is required"
[[ "${PROFILE}" =~ ^[A-Za-z0-9_-]+$ ]] || die "Profile names must be alphanumeric with hyphens/underscores"

ensure_shared_soul_layout
create_profile_if_needed "${PROFILE}"
configure_workspace "${PROFILE}"
write_telegram_env "${PROFILE}"
configure_git_include "${PROFILE}"
configure_hindsight "${PROFILE}"
render_profile_soul "${PROFILE}"
configure_gateway "${PROFILE}"

log "✓ Profile '${PROFILE}' ready"
