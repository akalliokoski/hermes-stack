#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(dirname "${SCRIPT_DIR}")"
CONFIG_RENDERER="${REPO_ROOT}/scripts/render-config.py"
ENV_CONTEXT_RENDERER="${REPO_ROOT}/scripts/render-environment-context.py"
TARGET_HOME="$(dirname "${HERMES_HOME:-/home/hermes/.hermes}")"

HERMES_USER="${HERMES_USER:-hermes}"
HERMES_HOME="${HERMES_HOME:-/home/hermes/.hermes}"
ENV_ID="${HERMES_ENV_ID:-$("${REPO_ROOT}/scripts/detect-env.sh" --repo-root "${REPO_ROOT}")}"
HERMES_SERVICE_MODE="${HERMES_SERVICE_MODE:-auto}"
WORK_ROOT="${WORK_ROOT:-$(python3 "${CONFIG_RENDERER}" --repo-root "${REPO_ROOT}" --env-id "${ENV_ID}" --target-home "${TARGET_HOME}" --print-meta env.work_root)}"
SHARED_SOUL_ROOT="${SHARED_SOUL_ROOT:-${HERMES_HOME}/shared/soul}"
SHARED_SKILLS_ROOT="${SHARED_SKILLS_ROOT:-${HERMES_HOME}/shared/skills}"
HINDSIGHT_API_URL="${HINDSIGHT_API_URL:-$(python3 "${CONFIG_RENDERER}" --repo-root "${REPO_ROOT}" --env-id "${ENV_ID}" --target-home "${TARGET_HOME}" --print-service-url hindsight --service-mode "${HERMES_SERVICE_MODE}")}"
PROFILE="${PROFILE:-}"
TELEGRAM_BOT_TOKEN="${TELEGRAM_BOT_TOKEN:-}"
TELEGRAM_HOME_CHANNEL="${TELEGRAM_HOME_CHANNEL:-${TELEGRAM_CHAT_ID:-}}"
AUDIOBOOKSHELF_BASE_URL="${AUDIOBOOKSHELF_BASE_URL:-}"
AUDIOBOOKSHELF_TOKEN="${AUDIOBOOKSHELF_TOKEN:-}"
AUDIOBOOKSHELF_ADMIN_USERNAME="${AUDIOBOOKSHELF_ADMIN_USERNAME:-}"
AUDIOBOOKSHELF_ADMIN_PASSWORD="${AUDIOBOOKSHELF_ADMIN_PASSWORD:-}"
AUDIOBOOKSHELF_LIBRARY_NAME="${AUDIOBOOKSHELF_LIBRARY_NAME:-}"
AUDIOBOOKSHELF_PODCASTS_PATH="${AUDIOBOOKSHELF_PODCASTS_PATH:-}"
TTS_BASE_URL="${TTS_BASE_URL:-}"
CHATTERBOX_BASE_URL="${CHATTERBOX_BASE_URL:-}"
PODCASTFY_PYTHON="${PODCASTFY_PYTHON:-}"
PODCAST_OUTPUT_DIR="${PODCAST_OUTPUT_DIR:-}"
HF_TOKEN="${HF_TOKEN:-}"
KOKORO_BASE_URL="${KOKORO_BASE_URL:-}"
SYNC_ALL_SOULS=0
SYNC_ALL_PROFILES=0
GATEWAY_MODE="auto"
GATEWAY_MODE_SET=0

usage() {
  cat <<'EOF'
Usage:
  scripts/provision-profile.sh --profile <name> [--telegram-bot-token <token>] [--gateway auto|skip|required|existing]
  scripts/provision-profile.sh --sync-all-souls
  scripts/provision-profile.sh --sync-all-profiles [--gateway auto|skip|required|existing]

What it does:
  - creates or updates a Hermes profile on the VPS
  - gives the profile its own /home/hermes/work/<profile> workspace
  - writes profile-local Hindsight config with bankId hermes-<profile>
  - manages shared SOUL sources under ~/.hermes/shared/soul/
  - exposes shared reusable skills from ~/.hermes/shared/skills/
  - renders profile SOUL.md from shared base + per-profile override
  - installs/starts the system gateway when root/passwordless sudo is available

Shared SOUL layout:
  ~/.hermes/shared/soul/base.md
  ~/.hermes/shared/soul/profiles/<profile>.md

Shared skills layout:
  ~/.hermes/shared/skills/<category>/<skill>/SKILL.md
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

profile_config_path() {
  printf '%s/config.yaml\n' "$(profile_home "$1")"
}

profile_environment_path() {
  printf '%s/ENVIRONMENT.md\n' "$(profile_home "$1")"
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

ensure_shared_skills_layout() {
  run_as_hermes mkdir -p "${SHARED_SKILLS_ROOT}"

  if ! run_as_hermes test -f "${SHARED_SKILLS_ROOT}/README.md"; then
    run_as_hermes bash -lc "cat > \"${SHARED_SKILLS_ROOT}/README.md\" <<'EOF'
Shared Hermes skills
====================

Put cross-profile skills here so every Hermes profile can load them via
skills.external_dirs.

Profiles are normalized to include:
  ${SHARED_SKILLS_ROOT}

After adding or updating shared skills, rerun:
  bash /opt/hermes/scripts/provision-profile.sh --sync-all-profiles --gateway skip

Or update a single profile:
  bash /opt/hermes/scripts/provision-profile.sh --profile <name> --gateway skip
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
  local base_file override_file env_file target tmp_file
  base_file="${SHARED_SOUL_ROOT}/base.md"
  override_file="$(profile_override_path "${profile}")"
  env_file="$(profile_environment_path "${profile}")"
  target="$(profile_soul_path "${profile}")"
  tmp_file="$(mktemp)"

  run_as_hermes mkdir -p "$(dirname "${target}")"
  ensure_profile_override_file "${profile}"
  render_profile_environment "${profile}"

  python3 - "${tmp_file}" "${base_file}" "${override_file}" "${env_file}" <<'PY'
import pathlib
import sys

output_path = pathlib.Path(sys.argv[1])
parts = []
for candidate in sys.argv[2:]:
    path = pathlib.Path(candidate)
    if path.is_file() and path.stat().st_size > 0:
        parts.append(path.read_text())

output_path.write_text("\n\n".join(parts))
PY

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

render_profile_environment() {
  local profile="$1"
  local output_path config_path profile_dir
  output_path="$(profile_environment_path "${profile}")"
  config_path="$(profile_config_path "${profile}")"
  profile_dir="$(profile_home "${profile}")"

  run_as_hermes mkdir -p "${profile_dir}"
  run_as_hermes python3 "${ENV_CONTEXT_RENDERER}" \
    --repo-root "${REPO_ROOT}" \
    --env-id "${ENV_ID}" \
    --profile "${profile}" \
    --profile-home "${profile_dir}" \
    --config-path "${config_path}" \
    --service-mode "${HERMES_SERVICE_MODE}" \
    --output "${output_path}"

  log "✓ Rendered ENVIRONMENT.md for profile '${profile}' (env: ${ENV_ID})"
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
  ensure_shared_skills_layout

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
    render_profile_config "${profile}"
    configure_shared_skills "${profile}"
    write_runtime_env "${profile}"
    configure_git_include "${profile}"
    configure_hindsight "${profile}"
    render_profile_soul "${profile}"
    configure_gateway "${profile}"
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

render_profile_config() {
  local profile="$1"
  local config_path
  config_path="$(profile_config_path "${profile}")"
  run_as_hermes mkdir -p "${WORK_ROOT}/${profile}"

  run_as_hermes python3 "${CONFIG_RENDERER}" \
    --repo-root "${REPO_ROOT}" \
    --env-id "${ENV_ID}" \
    --target-home "${TARGET_HOME}" \
    --profile "${profile}" \
    --output "${config_path}"

  log "✓ Rendered config.yaml for profile '${profile}' (env: ${ENV_ID}, workspace: ${WORK_ROOT}/${profile})"
}

configure_shared_skills() {
  local profile="$1"
  local config_path
  config_path="$(profile_config_path "${profile}")"

  run_as_hermes mkdir -p "${SHARED_SKILLS_ROOT}"

  run_as_hermes python3 - <<PY
from pathlib import Path
import yaml

path = Path(${config_path@Q})
shared_dir = ${SHARED_SKILLS_ROOT@Q}

if not path.exists():
    raise SystemExit(f"Expected config file to exist: {path}")

raw = path.read_text()
parsed = yaml.safe_load(raw) or {}
if not isinstance(parsed, dict):
    raise SystemExit(f"Expected top-level mapping in {path}")

skills = parsed.get("skills")
if skills is None:
    skills = {}
    parsed["skills"] = skills
if not isinstance(skills, dict):
    raise SystemExit(f"Expected skills mapping in {path}")

external_dirs = skills.get("external_dirs")
if external_dirs is None:
    external_dirs = []
elif isinstance(external_dirs, str):
    external_dirs = [external_dirs]
elif not isinstance(external_dirs, list):
    raise SystemExit(f"Expected skills.external_dirs to be a list/string in {path}")

normalized = []
for entry in external_dirs:
    entry = str(entry).strip()
    if entry and entry not in normalized:
        normalized.append(entry)
if shared_dir not in normalized:
    normalized.append(shared_dir)

skills["external_dirs"] = normalized
path.write_text(yaml.safe_dump(parsed, sort_keys=False))
PY

  log "✓ Shared skills enabled for profile '${profile}'"
}

write_runtime_env() {
  local profile="$1"
  local env_path
  env_path="$(profile_env_path "${profile}")"

  if run_as_hermes python3 - <<PY
from pathlib import Path

path = Path(${env_path@Q})
updates = {
    "TELEGRAM_BOT_TOKEN": ${TELEGRAM_BOT_TOKEN@Q},
    "TELEGRAM_HOME_CHANNEL": ${TELEGRAM_HOME_CHANNEL@Q},
    "AUDIOBOOKSHELF_BASE_URL": ${AUDIOBOOKSHELF_BASE_URL@Q},
    "AUDIOBOOKSHELF_TOKEN": ${AUDIOBOOKSHELF_TOKEN@Q},
    "AUDIOBOOKSHELF_ADMIN_USERNAME": ${AUDIOBOOKSHELF_ADMIN_USERNAME@Q},
    "AUDIOBOOKSHELF_ADMIN_PASSWORD": ${AUDIOBOOKSHELF_ADMIN_PASSWORD@Q},
    "AUDIOBOOKSHELF_LIBRARY_NAME": ${AUDIOBOOKSHELF_LIBRARY_NAME@Q},
    "AUDIOBOOKSHELF_PODCASTS_PATH": ${AUDIOBOOKSHELF_PODCASTS_PATH@Q},
    "TTS_BASE_URL": ${TTS_BASE_URL@Q},
    "CHATTERBOX_BASE_URL": ${CHATTERBOX_BASE_URL@Q},
    "PODCASTFY_PYTHON": ${PODCASTFY_PYTHON@Q},
    "PODCAST_OUTPUT_DIR": ${PODCAST_OUTPUT_DIR@Q},
    "HF_TOKEN": ${HF_TOKEN@Q},
    "KOKORO_BASE_URL": ${KOKORO_BASE_URL@Q},
}
updates = {key: value for key, value in updates.items() if value}
if not updates:
    raise SystemExit(10)
lines = path.read_text().splitlines() if path.exists() else []
remaining = []
for line in lines:
    if any(line.startswith(f"{key}=") for key in updates):
        continue
    remaining.append(line)
for key, value in updates.items():
    remaining.append(f"{key}={value}")
path.write_text("\n".join(remaining).rstrip() + "\n")
PY
  then
    status=0
  else
    status=$?
  fi
  if [[ ${status} -eq 10 ]]; then
    log "• No runtime env vars provided; leaving ${env_path} unchanged"
    return 0
  fi
  [[ ${status} -eq 0 ]] || return ${status}
  run_as_hermes chmod 600 "${env_path}"
  log "✓ Updated runtime env in ${env_path}"
}

configure_git_include() {
  local profile="$1"
  local home_dir gitconfig_path shared_gitconfig user_home
  if [[ "$(basename "${HERMES_HOME}")" == ".hermes" ]]; then
    user_home="$(dirname "${HERMES_HOME}")"
  else
    user_home="${HOME}"
  fi
  shared_gitconfig="${user_home}/.config/git/shared.gitconfig"
  home_dir="$(profile_home "${profile}")/home"
  gitconfig_path="${home_dir}/.gitconfig"

  run_as_hermes mkdir -p "${home_dir}"
  run_as_hermes python3 - <<PY
from pathlib import Path
path = Path(${gitconfig_path@Q})
shared = ${shared_gitconfig@Q}
path.write_text(f"[include]\n  path = {shared}\n")
PY
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
    "mode": "local_external",
    "api_url": ${HINDSIGHT_API_URL@Q},
    "bank_id": ${bank_id@Q},
    "recall_budget": "mid",
    "memory_mode": "hybrid",
    "auto_recall": True,
    "auto_retain": True,
    "retain_every_n_turns": 1,
    "retain_async": True,
}
path.write_text(json.dumps(payload, separators=(",", ":")) + "\n")
PY
  run_as_hermes chmod 600 "${config_path}"
  log "✓ Hindsight configured for profile '${profile}' (bank: ${bank_id})"
}

write_gateway_override() {
  local profile="$1"
  local unit_name dropin_dir override_path
  unit_name="hermes-gateway-${profile}.service"
  dropin_dir="/etc/systemd/system/${unit_name}.d"
  override_path="${dropin_dir}/override.conf"

  run_as_root_if_possible mkdir -p "${dropin_dir}" || die "Need root or passwordless sudo to harden ${unit_name}"
  run_as_root_if_possible python3 - <<PY
from pathlib import Path
path = Path(${override_path@Q})
path.write_text('''[Service]\nNoNewPrivileges=true\nPrivateTmp=true\nProtectSystem=full\nProtectHome=false\nRestrictSUIDSGID=true\nLockPersonality=true\n''')
PY
}

system_gateway_exists() {
  local profile="$1"
  local unit_name="hermes-gateway-${profile}.service"

  if [[ ${EUID} -eq 0 ]]; then
    systemctl list-unit-files --full --type=service "${unit_name}" 2>/dev/null | grep -Fq "${unit_name}"
  elif have_passwordless_sudo; then
    sudo systemctl list-unit-files --full --type=service "${unit_name}" 2>/dev/null | grep -Fq "${unit_name}"
  else
    return 1
  fi
}

configure_gateway() {
  local profile="$1"
  [[ "${profile}" != "default" ]] || return 0

  case "${GATEWAY_MODE}" in
    skip)
      log "• Skipping gateway install/start for profile '${profile}'"
      return 0
      ;;
    existing)
      if ! system_gateway_exists "${profile}"; then
        log "• No existing system gateway for profile '${profile}'; skipping gateway refresh"
        return 0
      fi
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
      env HERMES_HOME="${HERMES_HOME}" hermes -p "${profile}" gateway install --system --run-as-user "${HERMES_USER}"
      write_gateway_override "${profile}"
      systemctl daemon-reload
      env HERMES_HOME="${HERMES_HOME}" hermes -p "${profile}" gateway start --system
    else
      sudo env HERMES_HOME="${HERMES_HOME}" hermes -p "${profile}" gateway install --system --run-as-user "${HERMES_USER}"
      write_gateway_override "${profile}"
      sudo systemctl daemon-reload
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
      GATEWAY_MODE_SET=1
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
  if [[ ${GATEWAY_MODE_SET} -eq 0 ]]; then
    GATEWAY_MODE="skip"
  fi
  sync_all_profiles
  exit 0
fi

[[ -n "${PROFILE}" ]] || die "--profile <name> is required"
[[ "${PROFILE}" =~ ^[A-Za-z0-9_-]+$ ]] || die "Profile names must be alphanumeric with hyphens/underscores"

ensure_shared_soul_layout
ensure_shared_skills_layout
create_profile_if_needed "${PROFILE}"
render_profile_config "${PROFILE}"
configure_shared_skills "${PROFILE}"
write_runtime_env "${PROFILE}"
configure_git_include "${PROFILE}"
configure_hindsight "${PROFILE}"
render_profile_soul "${PROFILE}"
configure_gateway "${PROFILE}"

log "✓ Profile '${PROFILE}' ready"
