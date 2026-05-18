#!/usr/bin/env bash
set -euo pipefail

LOG_DIR="${REMOTE_DEPLOY_LOG_DIR:-/opt/hermes-backups/deploy-logs}"
DEPLOY_LOG="${REMOTE_DEPLOY_LOG:-${LOG_DIR}/remote-deploy-$(date +%Y%m%d-%H%M%S).log}"
LOG_PARENT="$(dirname "${DEPLOY_LOG}")"
sudo install -d -o "$(id -un)" -g "$(id -gn)" -m 755 "${LOG_PARENT}"
: > "${DEPLOY_LOG}"
exec > >(tee -a "${DEPLOY_LOG}") 2>&1

export PS4='+ [remote-deploy] '
set -x

LAST_COMMAND=""
CURRENT_STEP="startup"
trap 'LAST_COMMAND=${BASH_COMMAND}' DEBUG
trap 'status=$?; echo "[remote-deploy] ERROR: step=${CURRENT_STEP} command=${LAST_COMMAND} exit=${status} log=${DEPLOY_LOG}" >&2' ERR

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "${REPO_ROOT}"

echo "[remote-deploy] log_path=${DEPLOY_LOG}"

load_repo_env() {
  if [[ -f .env ]]; then
    set -a
    { set +x; } 2>/dev/null || true
    . ./.env
    set -x
    set +a
  fi
  export TELEGRAM_HOME_CHANNEL="${TELEGRAM_HOME_CHANNEL:-${TELEGRAM_CHAT_ID:-}}"
}

load_repo_env

log_step() {
  CURRENT_STEP="$1"
  printf '\n==> %s\n' "$1"
}

file_digest() {
  local path="$1"
  if [[ -f "${path}" ]]; then
    sha256sum "${path}" | awk '{print $1}'
  else
    printf '%s\n' '__missing__'
  fi
}

unit_is_active() {
  local unit_name="$1"
  systemctl is-active --quiet "${unit_name}"
}

PROFILE_CRON_TICKER_CONFIG="${REPO_ROOT}/config/profile-cron-tickers.txt"

profile_home_path() {
  local profile="$1"
  if [[ "${profile}" == "default" ]]; then
    printf '%s\n' "/home/hermes/.hermes"
  else
    printf '%s\n' "/home/hermes/.hermes/profiles/${profile}"
  fi
}

cron_ticker_unit_name() {
  local profile="$1"
  printf 'hermes-cron-tick@%s.service\n' "${profile}"
}

managed_cron_ticker_profiles() {
  local config_path="${PROFILE_CRON_TICKER_CONFIG}"
  [[ -f "${config_path}" ]] || return 0
  python3 - "${config_path}" <<'PY'
from pathlib import Path
import sys
for raw in Path(sys.argv[1]).read_text().splitlines():
    line = raw.strip()
    if not line or line.startswith('#'):
        continue
    print(line)
PY
}

reconcile_profile_cron_tickers() {
  local profile unit_name profile_home
  declare -A wanted=()

  while IFS= read -r profile; do
    [[ -n "${profile}" ]] || continue
    wanted["${profile}"]=1
    unit_name="$(cron_ticker_unit_name "${profile}")"
    profile_home="$(profile_home_path "${profile}")"

    if [[ ! -d "${profile_home}" ]]; then
      log_step "skip ${unit_name} (profile home missing)"
      continue
    fi

    log_step "enable ${unit_name}"
    sudo systemctl enable "${unit_name}"

    if unit_is_active "${unit_name}"; then
      log_step "restart ${unit_name}"
      sudo systemctl restart "${unit_name}"
    else
      log_step "start ${unit_name}"
      sudo systemctl start "${unit_name}"
    fi
  done < <(managed_cron_ticker_profiles)

  while IFS= read -r unit_name; do
    [[ -n "${unit_name}" ]] || continue
    profile="${unit_name#hermes-cron-tick@}"
    profile="${profile%.service}"
    if [[ -z "${wanted[${profile}]:-}" ]]; then
      log_step "disable stale ${unit_name}"
      sudo systemctl disable --now "${unit_name}" || true
    fi
  done < <(find /etc/systemd/system/multi-user.target.wants -maxdepth 1 -type l -name 'hermes-cron-tick@*.service' -printf '%f\n' 2>/dev/null | sort)
}

verify_profile_cron_tickers() {
  local profile unit_name profile_home
  while IFS= read -r profile; do
    [[ -n "${profile}" ]] || continue
    unit_name="$(cron_ticker_unit_name "${profile}")"
    profile_home="$(profile_home_path "${profile}")"
    if [[ -d "${profile_home}" ]]; then
      systemctl is-active "${unit_name}"
    fi
  done < <(managed_cron_ticker_profiles)
}

declare -A PROFILE_CONFIG_DIGEST_BEFORE=()
declare -A PROFILE_UNIT_DIGEST_BEFORE=()
declare -A PROFILE_ENV_DIGEST_BEFORE=()
declare -A PROFILE_CONFIG_DIGEST_AFTER=()
declare -A PROFILE_UNIT_DIGEST_AFTER=()
declare -A PROFILE_ENV_DIGEST_AFTER=()

capture_named_profile_state_before() {
  local profiles_root="/home/hermes/.hermes/profiles"
  local profile config_path env_path unit_name unit_path

  [[ -d "${profiles_root}" ]] || return 0

  while IFS= read -r profile; do
    [[ -n "${profile}" ]] || continue
    config_path="${profiles_root}/${profile}/config.yaml"
    env_path="${profiles_root}/${profile}/.env"
    unit_name="hermes-gateway-${profile}.service"
    unit_path="/etc/systemd/system/${unit_name}"
    PROFILE_CONFIG_DIGEST_BEFORE["${profile}"]="$(file_digest "${config_path}")"
    PROFILE_UNIT_DIGEST_BEFORE["${profile}"]="$(file_digest "${unit_path}")"
    PROFILE_ENV_DIGEST_BEFORE["${profile}"]="$(file_digest "${env_path}")"
  done < <(find "${profiles_root}" -mindepth 1 -maxdepth 1 -type d -printf '%f\n' | sort)
}

capture_named_profile_state_after() {
  local profiles_root="/home/hermes/.hermes/profiles"
  local profile config_path env_path unit_name unit_path

  [[ -d "${profiles_root}" ]] || return 0

  while IFS= read -r profile; do
    [[ -n "${profile}" ]] || continue
    config_path="${profiles_root}/${profile}/config.yaml"
    env_path="${profiles_root}/${profile}/.env"
    unit_name="hermes-gateway-${profile}.service"
    unit_path="/etc/systemd/system/${unit_name}"
    PROFILE_CONFIG_DIGEST_AFTER["${profile}"]="$(file_digest "${config_path}")"
    PROFILE_UNIT_DIGEST_AFTER["${profile}"]="$(file_digest "${unit_path}")"
    PROFILE_ENV_DIGEST_AFTER["${profile}"]="$(file_digest "${env_path}")"
  done < <(find "${profiles_root}" -mindepth 1 -maxdepth 1 -type d -printf '%f\n' | sort)
}

restart_default_gateway_if_needed() {
  local config_changed=0
  local unit_changed=0
  local env_changed=0
  local override_changed=0
  local reasons=()

  [[ "${DEFAULT_GATEWAY_CONFIG_DIGEST_BEFORE}" == "${DEFAULT_GATEWAY_CONFIG_DIGEST_AFTER}" ]] || config_changed=1
  [[ "${DEFAULT_GATEWAY_UNIT_DIGEST_BEFORE}" == "${DEFAULT_GATEWAY_UNIT_DIGEST_AFTER}" ]] || unit_changed=1
  [[ "${DEFAULT_GATEWAY_ENV_DIGEST_BEFORE}" == "${DEFAULT_GATEWAY_ENV_DIGEST_AFTER}" ]] || env_changed=1
  [[ "${DEFAULT_GATEWAY_OVERRIDE_DIGEST_BEFORE}" == "${DEFAULT_GATEWAY_OVERRIDE_DIGEST_AFTER}" ]] || override_changed=1

  (( config_changed )) && reasons+=("config changed")
  (( unit_changed )) && reasons+=("unit changed")
  (( env_changed )) && reasons+=("env changed")
  (( override_changed )) && reasons+=("override changed")

  if (( ${#reasons[@]} > 0 )); then
    log_step "restart hermes-gateway (${reasons[*]})"
    sudo systemctl restart hermes-gateway
    return 0
  fi

  if unit_is_active hermes-gateway; then
    log_step "restart hermes-gateway (deploy refresh)"
    sudo systemctl restart hermes-gateway
    return 0
  fi

  log_step "start hermes-gateway (service was inactive)"
  sudo systemctl start hermes-gateway
}

restart_named_profile_gateways() {
  local profiles_root="/home/hermes/.hermes/profiles"
  local profile unit_name before_config before_env before_unit after_config after_env after_unit config_changed env_changed unit_changed

  [[ -d "${profiles_root}" ]] || return 0

  while IFS= read -r profile; do
    [[ -n "${profile}" ]] || continue
    unit_name="hermes-gateway-${profile}.service"
    if sudo systemctl list-unit-files --full --type=service "${unit_name}" 2>/dev/null | grep -Fq "${unit_name}"; then
      before_config="${PROFILE_CONFIG_DIGEST_BEFORE[${profile}]:-__missing__}"
      before_env="${PROFILE_ENV_DIGEST_BEFORE[${profile}]:-__missing__}"
      before_unit="${PROFILE_UNIT_DIGEST_BEFORE[${profile}]:-__missing__}"
      after_config="${PROFILE_CONFIG_DIGEST_AFTER[${profile}]:-__missing__}"
      after_env="${PROFILE_ENV_DIGEST_AFTER[${profile}]:-__missing__}"
      after_unit="${PROFILE_UNIT_DIGEST_AFTER[${profile}]:-__missing__}"
      config_changed=0
      env_changed=0
      unit_changed=0
      local reasons=()

      [[ "${before_config}" == "${after_config}" ]] || config_changed=1
      [[ "${before_env}" == "${after_env}" ]] || env_changed=1
      [[ "${before_unit}" == "${after_unit}" ]] || unit_changed=1

      (( config_changed )) && reasons+=("config changed")
      (( env_changed )) && reasons+=("env changed")
      (( unit_changed )) && reasons+=("unit changed")

      if (( ${#reasons[@]} > 0 )); then
        log_step "restart ${unit_name} (${reasons[*]})"
        sudo systemctl restart "${unit_name}"
      elif unit_is_active "${unit_name}"; then
        log_step "restart ${unit_name} (deploy refresh)"
        sudo systemctl restart "${unit_name}"
      else
        log_step "start ${unit_name} (service was inactive)"
        sudo systemctl start "${unit_name}"
      fi
    fi
  done < <(find "${profiles_root}" -mindepth 1 -maxdepth 1 -type d -printf '%f\n' | sort)
}

DEFAULT_GATEWAY_CONFIG_PATH="/home/hermes/.hermes/config.yaml"
DEFAULT_GATEWAY_ENV_PATH="/home/hermes/.hermes/.env"
DEFAULT_GATEWAY_UNIT_PATH="/etc/systemd/system/hermes-gateway.service"
DEFAULT_GATEWAY_OVERRIDE_PATH="/etc/systemd/system/hermes-gateway.service.d/override.conf"
DEFAULT_GATEWAY_CONFIG_DIGEST_BEFORE="$(file_digest "${DEFAULT_GATEWAY_CONFIG_PATH}")"
DEFAULT_GATEWAY_ENV_DIGEST_BEFORE="$(file_digest "${DEFAULT_GATEWAY_ENV_PATH}")"
DEFAULT_GATEWAY_UNIT_DIGEST_BEFORE="$(file_digest "${DEFAULT_GATEWAY_UNIT_PATH}")"
DEFAULT_GATEWAY_OVERRIDE_DIGEST_BEFORE="$(file_digest "${DEFAULT_GATEWAY_OVERRIDE_PATH}")"
capture_named_profile_state_before

log_step "prepare directories and ids"
mkdir -p /opt/hermes-backups
HERMES_UID="$(id -u hermes)"
HERMES_GID="$(id -g hermes)"
sudo install -d -o hermes -g hermes -m 755 /home/hermes/sync /home/hermes/sync/wiki /home/hermes/sync/backups /home/hermes/sync/backups/hindsight
sudo chown -R hermes:hermes /home/hermes/sync
sudo install -d -m 755 /data /data/audiobookshelf
sudo install -d -o hermes -g hermes -m 755 /data/audiobookshelf/config /data/audiobookshelf/metadata /data/audiobookshelf/audiobooks /data/audiobookshelf/podcasts /data/audiobookshelf/podcasts/ai-generated /data/audiobookshelf/podcasts/profiles /data/audiobookshelf/projects
sudo install -d -m 755 /data/jellyfin
sudo install -d -o hermes -g hermes -m 755 /data/jellyfin/config /data/jellyfin/cache /data/jellyfin/videos /data/jellyfin/videos/profiles /data/jellyfin/projects

log_step "ensure python yaml"
python3 -c 'import yaml' 2>/dev/null || { sudo apt-get update -qq && sudo apt-get install -y -qq python3-yaml; }

log_step "render hermes config and sync profiles"
sudo -u hermes python3 scripts/render-config.py --env-id vps --target-home /home/hermes --profile default --output /home/hermes/.hermes/config.yaml
sudo env HERMES_ENV_ID=vps bash scripts/provision-profile.sh --sync-all-profiles --gateway existing

log_step "install systemd units and helper executables"
sudo env PATH="/home/hermes/.local/bin:${PATH}" HERMES_HOME=/home/hermes/.hermes /home/hermes/.local/bin/hermes gateway install --system --run-as-user hermes --force
sudo install -d -m 755 /etc/systemd/system/hermes-gateway.service.d
sudo install -m 644 scripts/hermes-gateway.override.conf /etc/systemd/system/hermes-gateway.service.d/override.conf
sudo install -m 644 scripts/hermes-dashboard.service /etc/systemd/system/hermes-dashboard.service
sudo install -m 644 scripts/hermes-dashboard-proxy.service /etc/systemd/system/hermes-dashboard-proxy.service
sudo install -m 644 scripts/hermes-webui.service /etc/systemd/system/hermes-webui.service
sudo install -m 644 scripts/hermes-cron-tick@.service /etc/systemd/system/hermes-cron-tick@.service
HELPER_SRC="$(readlink -f scripts/run-profile-cron-tick.sh)"
HELPER_DST="$(readlink -f /opt/hermes/scripts/run-profile-cron-tick.sh 2>/dev/null || true)"
if [[ -n "${HELPER_DST}" && "${HELPER_SRC}" == "${HELPER_DST}" ]]; then
  sudo chmod 755 /opt/hermes/scripts/run-profile-cron-tick.sh
else
  sudo install -m 755 scripts/run-profile-cron-tick.sh /opt/hermes/scripts/run-profile-cron-tick.sh
fi
sudo chmod +x scripts/configure-tailscale-serve.sh scripts/repair-syncthing-volume.sh scripts/repair-backup-volume.sh scripts/verify-local-web-bindings.sh scripts/verify-tailnet-web-routes.sh scripts/setup-podcast-pipeline.sh scripts/setup-video-pipeline.sh scripts/setup-hermes-webui.sh scripts/run-hermes-webui.sh scripts/make-podcast.py scripts/make-manim-video.py scripts/run_podcastfy_pipeline.py scripts/audiobookshelf_api.py scripts/bootstrap-jellyfin.py scripts/sync-modal-hf-secret.py scripts/detect-env.sh scripts/render-config.py scripts/render-environment-context.py scripts/ensure-python-yaml.sh scripts/remote-deploy.sh scripts/apply-model-strategy.py scripts/cleanup-hermes-gateway-state.py scripts/run-profile-cron-tick.sh scripts/run-hermes-dashboard-proxy.py scripts/backup-hindsight-host.sh scripts/setup-backup-cron.sh scripts/backup-hindsight-watchdog.sh scripts/verify-web-research.sh
sudo systemctl daemon-reload
sudo systemctl enable hermes-gateway hermes-dashboard hermes-dashboard-proxy hermes-webui

log_step "install hindsight backup cron"
sudo bash scripts/setup-backup-cron.sh

DEFAULT_GATEWAY_CONFIG_DIGEST_AFTER="$(file_digest "${DEFAULT_GATEWAY_CONFIG_PATH}")"
DEFAULT_GATEWAY_ENV_DIGEST_AFTER="$(file_digest "${DEFAULT_GATEWAY_ENV_PATH}")"
DEFAULT_GATEWAY_UNIT_DIGEST_AFTER="$(file_digest "${DEFAULT_GATEWAY_UNIT_PATH}")"
DEFAULT_GATEWAY_OVERRIDE_DIGEST_AFTER="$(file_digest "${DEFAULT_GATEWAY_OVERRIDE_PATH}")"
capture_named_profile_state_after

log_step "install video pipeline system packages"
sudo apt-get update -qq
sudo apt-get install -y -qq ffmpeg

log_step "refresh hermes python deps and media tooling"
sudo -iu hermes bash -lc 'export PATH="$HOME/.local/bin:$PATH"; HERMES_PY="$(head -n 1 "$(command -v hermes)" | sed "s/^#!//")"; uv pip install --python "$HERMES_PY" --quiet --upgrade "hindsight-client>=0.4.22"; cd /opt/hermes && bash scripts/setup-podcast-pipeline.sh && bash scripts/setup-video-pipeline.sh'

log_step "refresh Hermes WebUI checkout"
sudo bash scripts/setup-hermes-webui.sh

log_step "repair persisted service state"
HERMES_UID="$HERMES_UID" HERMES_GID="$HERMES_GID" bash scripts/repair-syncthing-volume.sh
bash scripts/repair-backup-volume.sh

log_step "refresh containers"
docker system prune -af
docker compose pull --quiet --ignore-buildable
HERMES_UID="$HERMES_UID" HERMES_GID="$HERMES_GID" docker compose -f docker-compose.yml -f docker-compose.vps.yml up -d --remove-orphans

log_step "refresh host services"
sudo systemctl restart hermes-webui
sudo systemctl restart hermes-dashboard
sudo systemctl restart hermes-dashboard-proxy
restart_default_gateway_if_needed
restart_named_profile_gateways
reconcile_profile_cron_tickers
sudo bash scripts/configure-tailscale-serve.sh

log_step "validate live services"
if [[ "${API_SERVER_ENABLED:-}" =~ ^(true|TRUE|1|yes|YES)$ || -n "${API_SERVER_KEY:-}" ]]; then
  curl -fsS --max-time 10 http://127.0.0.1:8642/health >/dev/null
fi
systemctl is-active hermes-webui
systemctl is-active hermes-dashboard
systemctl is-active hermes-dashboard-proxy
systemctl is-active hermes-gateway
verify_profile_cron_tickers
grep -F '/opt/hermes/scripts/backup-hindsight-host.sh' /etc/cron.d/hermes-hindsight-backup
docker compose -f docker-compose.yml -f docker-compose.vps.yml ps
bash scripts/verify-local-web-bindings.sh
bash scripts/verify-tailnet-web-routes.sh
tailscale serve status --json
