#!/usr/bin/env bash
set -euo pipefail
export PS4='+ [remote-deploy] '
set -x

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "${REPO_ROOT}"

log_step() {
  printf '\n==> %s\n' "$1"
}

log_step "prepare directories and ids"
mkdir -p /opt/hermes-backups
HERMES_UID="$(id -u hermes)"
HERMES_GID="$(id -g hermes)"
sudo install -d -o hermes -g hermes -m 755 /home/hermes/sync /home/hermes/sync/wiki /home/hermes/sync/backups /home/hermes/sync/backups/hindsight
sudo chown -R hermes:hermes /home/hermes/sync
sudo install -d -m 755 /data /data/audiobookshelf
sudo install -d -o hermes -g hermes -m 755 /data/audiobookshelf/config /data/audiobookshelf/metadata /data/audiobookshelf/audiobooks /data/audiobookshelf/podcasts /data/audiobookshelf/podcasts/ai-generated

log_step "ensure python yaml"
python3 -c 'import yaml' 2>/dev/null || { sudo apt-get update -qq && sudo apt-get install -y -qq python3-yaml; }

log_step "render hermes config and sync profiles"
sudo -u hermes python3 scripts/render-config.py --env-id vps --target-home /home/hermes --profile default --output /home/hermes/.hermes/config.yaml
sudo env HERMES_ENV_ID=vps bash scripts/provision-profile.sh --sync-all-profiles --gateway skip

log_step "install systemd units and helper executables"
sudo install -m 644 scripts/hermes-gateway.service /etc/systemd/system/hermes-gateway.service
sudo install -m 644 scripts/hermes-dashboard.service /etc/systemd/system/hermes-dashboard.service
sudo chmod +x scripts/configure-tailscale-serve.sh scripts/repair-syncthing-volume.sh scripts/repair-backup-volume.sh scripts/verify-local-web-bindings.sh scripts/verify-tailnet-web-routes.sh scripts/setup-podcast-pipeline.sh scripts/make-podcast.py scripts/detect-env.sh scripts/render-config.py scripts/render-environment-context.py scripts/ensure-python-yaml.sh scripts/remote-deploy.sh
sudo systemctl daemon-reload
sudo systemctl enable hermes-gateway hermes-dashboard

log_step "refresh hermes python deps and podcast tooling"
sudo -iu hermes bash -lc 'export PATH="$HOME/.local/bin:$PATH"; HERMES_PY="$(head -n 1 \"$(command -v hermes)\" | sed "s/^#!//")"; uv pip install --python "$HERMES_PY" --quiet --upgrade "hindsight-client>=0.4.22"; cd /opt/hermes && bash scripts/setup-podcast-pipeline.sh'

log_step "repair persisted service state"
HERMES_UID="$HERMES_UID" HERMES_GID="$HERMES_GID" bash scripts/repair-syncthing-volume.sh
bash scripts/repair-backup-volume.sh

log_step "refresh containers"
docker system prune -af
docker compose pull --quiet --ignore-buildable
HERMES_UID="$HERMES_UID" HERMES_GID="$HERMES_GID" docker compose -f docker-compose.yml -f docker-compose.vps.yml up -d --remove-orphans

log_step "bootstrap service-specific state"
set -a
set +x
if [ -f .env ]; then . ./.env; fi
set -x
set +a
python3 scripts/bootstrap-audiobookshelf.py

log_step "restart host services"
sudo systemctl restart hermes-dashboard
sudo systemctl restart hermes-gateway
sudo bash scripts/configure-tailscale-serve.sh

log_step "validate live services"
systemctl is-active hermes-dashboard
systemctl is-active hermes-gateway
docker compose -f docker-compose.yml -f docker-compose.vps.yml ps
bash scripts/verify-local-web-bindings.sh
bash scripts/verify-tailnet-web-routes.sh
tailscale serve status --json
