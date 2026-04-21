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

declare -A PROFILE_CONFIG_DIGEST_BEFORE=()
declare -A PROFILE_UNIT_DIGEST_BEFORE=()
declare -A PROFILE_CONFIG_DIGEST_AFTER=()
declare -A PROFILE_UNIT_DIGEST_AFTER=()

capture_named_profile_state_before() {
  local profiles_root="/home/hermes/.hermes/profiles"
  local profile config_path unit_name unit_path

  [[ -d "${profiles_root}" ]] || return 0

  while IFS= read -r profile; do
    [[ -n "${profile}" ]] || continue
    config_path="${profiles_root}/${profile}/config.yaml"
    unit_name="hermes-gateway-${profile}.service"
    unit_path="/etc/systemd/system/${unit_name}"
    PROFILE_CONFIG_DIGEST_BEFORE["${profile}"]="$(file_digest "${config_path}")"
    PROFILE_UNIT_DIGEST_BEFORE["${profile}"]="$(file_digest "${unit_path}")"
  done < <(find "${profiles_root}" -mindepth 1 -maxdepth 1 -type d -printf '%f\n' | sort)
}

capture_named_profile_state_after() {
  local profiles_root="/home/hermes/.hermes/profiles"
  local profile config_path unit_name unit_path

  [[ -d "${profiles_root}" ]] || return 0

  while IFS= read -r profile; do
    [[ -n "${profile}" ]] || continue
    config_path="${profiles_root}/${profile}/config.yaml"
    unit_name="hermes-gateway-${profile}.service"
    unit_path="/etc/systemd/system/${unit_name}"
    PROFILE_CONFIG_DIGEST_AFTER["${profile}"]="$(file_digest "${config_path}")"
    PROFILE_UNIT_DIGEST_AFTER["${profile}"]="$(file_digest "${unit_path}")"
  done < <(find "${profiles_root}" -mindepth 1 -maxdepth 1 -type d -printf '%f\n' | sort)
}

restart_default_gateway_if_needed() {
  local config_changed=0
  local unit_changed=0
  local reasons=()

  [[ "${DEFAULT_GATEWAY_CONFIG_DIGEST_BEFORE}" == "${DEFAULT_GATEWAY_CONFIG_DIGEST_AFTER}" ]] || config_changed=1
  [[ "${DEFAULT_GATEWAY_UNIT_DIGEST_BEFORE}" == "${DEFAULT_GATEWAY_UNIT_DIGEST_AFTER}" ]] || unit_changed=1

  (( config_changed )) && reasons+=("config changed")
  (( unit_changed )) && reasons+=("unit changed")

  if (( ${#reasons[@]} > 0 )); then
    log_step "restart hermes-gateway (${reasons[*]})"
    sudo systemctl restart hermes-gateway
    return 0
  fi

  if unit_is_active hermes-gateway; then
    log_step "skip hermes-gateway restart (config and unit unchanged)"
    return 0
  fi

  log_step "start hermes-gateway (service was inactive)"
  sudo systemctl start hermes-gateway
}

restart_named_profile_gateways() {
  local profiles_root="/home/hermes/.hermes/profiles"
  local profile unit_name before_config before_unit after_config after_unit config_changed unit_changed

  [[ -d "${profiles_root}" ]] || return 0

  while IFS= read -r profile; do
    [[ -n "${profile}" ]] || continue
    unit_name="hermes-gateway-${profile}.service"
    if sudo systemctl list-unit-files --full --type=service "${unit_name}" 2>/dev/null | grep -Fq "${unit_name}"; then
      before_config="${PROFILE_CONFIG_DIGEST_BEFORE[${profile}]:-__missing__}"
      before_unit="${PROFILE_UNIT_DIGEST_BEFORE[${profile}]:-__missing__}"
      after_config="${PROFILE_CONFIG_DIGEST_AFTER[${profile}]:-__missing__}"
      after_unit="${PROFILE_UNIT_DIGEST_AFTER[${profile}]:-__missing__}"
      config_changed=0
      unit_changed=0
      local reasons=()

      [[ "${before_config}" == "${after_config}" ]] || config_changed=1
      [[ "${before_unit}" == "${after_unit}" ]] || unit_changed=1

      (( config_changed )) && reasons+=("config changed")
      (( unit_changed )) && reasons+=("unit changed")

      if (( ${#reasons[@]} > 0 )); then
        log_step "restart ${unit_name} (${reasons[*]})"
        sudo systemctl restart "${unit_name}"
      elif unit_is_active "${unit_name}"; then
        log_step "skip ${unit_name} restart (config and unit unchanged)"
      else
        log_step "start ${unit_name} (service was inactive)"
        sudo systemctl start "${unit_name}"
      fi
    fi
  done < <(find "${profiles_root}" -mindepth 1 -maxdepth 1 -type d -printf '%f\n' | sort)
}

DEFAULT_GATEWAY_CONFIG_PATH="/home/hermes/.hermes/config.yaml"
DEFAULT_GATEWAY_UNIT_PATH="/etc/systemd/system/hermes-gateway.service"
DEFAULT_GATEWAY_CONFIG_DIGEST_BEFORE="$(file_digest "${DEFAULT_GATEWAY_CONFIG_PATH}")"
DEFAULT_GATEWAY_UNIT_DIGEST_BEFORE="$(file_digest "${DEFAULT_GATEWAY_UNIT_PATH}")"
capture_named_profile_state_before

log_step "prepare directories and ids"
mkdir -p /opt/hermes-backups
HERMES_UID="$(id -u hermes)"
HERMES_GID="$(id -g hermes)"
sudo install -d -o hermes -g hermes -m 755 /home/hermes/sync /home/hermes/sync/wiki /home/hermes/sync/backups /home/hermes/sync/backups/hindsight
sudo chown -R hermes:hermes /home/hermes/sync
sudo install -d -m 755 /data /data/audiobookshelf
sudo install -d -o hermes -g hermes -m 755 /data/audiobookshelf/config /data/audiobookshelf/metadata /data/audiobookshelf/audiobooks /data/audiobookshelf/podcasts /data/audiobookshelf/podcasts/ai-generated
sudo install -d -m 755 /data/jellyfin
sudo install -d -o hermes -g hermes -m 755 /data/jellyfin/config /data/jellyfin/cache /data/jellyfin/videos /data/jellyfin/videos/profiles /data/jellyfin/projects

log_step "ensure python yaml"
python3 -c 'import yaml' 2>/dev/null || { sudo apt-get update -qq && sudo apt-get install -y -qq python3-yaml; }

log_step "render hermes config and sync profiles"
sudo -u hermes python3 scripts/render-config.py --env-id vps --target-home /home/hermes --profile default --output /home/hermes/.hermes/config.yaml
sudo env HERMES_ENV_ID=vps bash scripts/provision-profile.sh --sync-all-profiles --gateway existing

log_step "install systemd units and helper executables"
sudo install -m 644 scripts/hermes-gateway.service /etc/systemd/system/hermes-gateway.service
sudo install -m 644 scripts/hermes-dashboard.service /etc/systemd/system/hermes-dashboard.service
sudo chmod +x scripts/configure-tailscale-serve.sh scripts/repair-syncthing-volume.sh scripts/repair-backup-volume.sh scripts/verify-local-web-bindings.sh scripts/verify-tailnet-web-routes.sh scripts/setup-podcast-pipeline.sh scripts/setup-video-pipeline.sh scripts/make-podcast.py scripts/make-manim-video.py scripts/run_podcastfy_pipeline.py scripts/audiobookshelf_api.py scripts/bootstrap-jellyfin.py scripts/sync-modal-hf-secret.py scripts/detect-env.sh scripts/render-config.py scripts/render-environment-context.py scripts/ensure-python-yaml.sh scripts/remote-deploy.sh scripts/apply-model-strategy.py
sudo systemctl daemon-reload
sudo systemctl enable hermes-gateway hermes-dashboard

DEFAULT_GATEWAY_CONFIG_DIGEST_AFTER="$(file_digest "${DEFAULT_GATEWAY_CONFIG_PATH}")"
DEFAULT_GATEWAY_UNIT_DIGEST_AFTER="$(file_digest "${DEFAULT_GATEWAY_UNIT_PATH}")"
capture_named_profile_state_after

log_step "install video pipeline system packages"
sudo apt-get update -qq
sudo apt-get install -y -qq ffmpeg

log_step "refresh hermes python deps and media tooling"
sudo -iu hermes bash -lc 'export PATH="$HOME/.local/bin:$PATH"; HERMES_PY="$(head -n 1 "$(command -v hermes)" | sed "s/^#!//")"; uv pip install --python "$HERMES_PY" --quiet --upgrade "hindsight-client>=0.4.22"; cd /opt/hermes && bash scripts/setup-podcast-pipeline.sh && bash scripts/setup-video-pipeline.sh'

log_step "repair persisted service state"
HERMES_UID="$HERMES_UID" HERMES_GID="$HERMES_GID" bash scripts/repair-syncthing-volume.sh
bash scripts/repair-backup-volume.sh

log_step "refresh containers"
docker system prune -af
docker compose pull --quiet --ignore-buildable
HERMES_UID="$HERMES_UID" HERMES_GID="$HERMES_GID" docker compose -f docker-compose.yml -f docker-compose.vps.yml up -d --remove-orphans

log_step "bootstrap service-specific state"
python3 scripts/bootstrap-audiobookshelf.py
python3 scripts/bootstrap-jellyfin.py

docker restart hermes-jellyfin-1 >/dev/null
sleep 10
python3 scripts/bootstrap-jellyfin.py --refresh

log_step "refresh host services"
sudo systemctl restart hermes-dashboard
restart_default_gateway_if_needed
restart_named_profile_gateways
sudo bash scripts/configure-tailscale-serve.sh

log_step "validate live services"
if [[ "${API_SERVER_ENABLED:-}" =~ ^(true|TRUE|1|yes|YES)$ || -n "${API_SERVER_KEY:-}" ]]; then
  curl -fsS --max-time 10 http://127.0.0.1:8642/health >/dev/null
fi
systemctl is-active hermes-dashboard
systemctl is-active hermes-gateway
docker compose -f docker-compose.yml -f docker-compose.vps.yml ps
bash scripts/verify-local-web-bindings.sh
bash scripts/verify-tailnet-web-routes.sh
tailscale serve status --json
