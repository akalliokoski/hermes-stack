#!/usr/bin/env bash
# deploy.sh – run from MacBook to deploy the stack to VPS over Tailscale.
#
# One-time bootstrap (first deploy only):
#   scp .env config.yaml "${VPS_HOST}:/tmp/"
#   ssh "${VPS_HOST}" "sudo bash -s" < scripts/vps-setup.sh
#
# Routine deploys (this script):
#   - rsync the repo (compose files, scripts, config) to the VPS
#   - sync config.yaml into /home/hermes/.hermes/
#   - `docker compose up -d` for auxiliary services
#   - `systemctl restart hermes-gateway` for the host-installed agent
#
# Hermes itself updates separately via `make update-agent`
# (runs `hermes update` as the hermes user — no rebuild needed).
# Deploy also re-installs the Hindsight client dependency into Hermes's own venv.
set -euo pipefail

if [[ -f .env ]]; then
  # shellcheck disable=SC2046
  export $(grep -E '^(VPS_HOST|VPS_DIR)=' .env | xargs)
fi

VPS_HOST="${VPS_HOST:?Set VPS_HOST in .env (Tailscale hostname or IP)}"
VPS_DIR="${VPS_DIR:-/opt/hermes}"

echo "→ Syncing to ${VPS_HOST}:${VPS_DIR}"
rsync -az --delete \
  --exclude='.git' \
  --exclude='.env' \
  --exclude='backups/' \
  . "${VPS_HOST}:${VPS_DIR}/"

echo "→ Restarting stack"
ssh "${VPS_HOST}" "
  set -e
  cd ${VPS_DIR}
  mkdir -p /opt/hermes-backups
  HERMES_UID=\$(id -u hermes)
  HERMES_GID=\$(id -g hermes)
  sudo install -d -o hermes -g hermes -m 755 /home/hermes/sync /home/hermes/sync/wiki /home/hermes/sync/backups /home/hermes/sync/backups/hindsight
  sudo chown -R hermes:hermes /home/hermes/sync
  sudo install -d -m 755 /data /data/audiobookshelf
  sudo install -d -o hermes -g hermes -m 755 /data/audiobookshelf/config /data/audiobookshelf/metadata /data/audiobookshelf/audiobooks /data/audiobookshelf/podcasts /data/audiobookshelf/podcasts/ai-generated
  sudo install -o hermes -g hermes -m 600 config.yaml /home/hermes/.hermes/config.yaml
  sudo install -m 644 scripts/hermes-gateway.service /etc/systemd/system/hermes-gateway.service
  sudo install -m 644 scripts/hermes-dashboard.service /etc/systemd/system/hermes-dashboard.service
  sudo chmod +x scripts/configure-tailscale-serve.sh scripts/repair-syncthing-volume.sh scripts/verify-local-web-bindings.sh scripts/verify-tailnet-web-routes.sh scripts/setup-podcast-pipeline.sh scripts/make-podcast.py
  sudo -iu hermes bash -lc 'export PATH="$HOME/.local/bin:$PATH"; HERMES_PY="$(head -n 1 \"$(command -v hermes)\" | sed "s/^#!//")"; uv pip install --python "$HERMES_PY" --quiet --upgrade "hindsight-client>=0.4.22"; cd /opt/hermes && bash scripts/setup-podcast-pipeline.sh'
  sudo systemctl daemon-reload
  sudo systemctl enable hermes-gateway hermes-dashboard
  HERMES_UID=\$HERMES_UID HERMES_GID=\$HERMES_GID bash scripts/repair-syncthing-volume.sh
  docker compose pull --quiet --ignore-buildable
  HERMES_UID=\$HERMES_UID HERMES_GID=\$HERMES_GID docker compose -f docker-compose.yml -f docker-compose.vps.yml up -d --remove-orphans
  set -a
  if [ -f .env ]; then . ./.env; fi
  set +a
  python3 scripts/bootstrap-audiobookshelf.py
  sudo systemctl restart hermes-dashboard
  sudo systemctl restart hermes-gateway
  sudo bash scripts/configure-tailscale-serve.sh
  systemctl is-active hermes-dashboard
  systemctl is-active hermes-gateway
  docker compose -f docker-compose.yml -f docker-compose.vps.yml ps
  bash scripts/verify-local-web-bindings.sh
  bash scripts/verify-tailnet-web-routes.sh
  tailscale serve status --json
"

echo "✓ Done"
