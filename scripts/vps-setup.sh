#!/usr/bin/env bash
# scripts/vps-setup.sh – one-time setup on a fresh VPS.
#
# Installs Docker, creates the `hermes` system user, installs hermes-agent via
# its official install.sh, lays down config + .env, and enables the
# hermes-gateway systemd unit.
#
# Usage:  scp -r scripts config .env <vps>:/tmp/hermes-bootstrap/
#         ssh <vps> 'sudo bash /tmp/hermes-bootstrap/scripts/vps-setup.sh'
#
# Or from MacBook in one shot:
#         ssh <vps> 'bash -s' < scripts/vps-setup.sh
#         (then stage the repo config directory and .env separately — see above)
set -euo pipefail

VPS_DIR="${VPS_DIR:-/opt/hermes}"
HERMES_HOME="/home/hermes"
HERMES_DATA="${HERMES_HOME}/.hermes"

if [[ $EUID -ne 0 ]]; then
  echo "ERROR: run as root (sudo)." >&2
  exit 1
fi

# ── System packages (ripgrep + ffmpeg for hermes; curl for install.sh) ────────
# Pre-installed here so the upstream install.sh doesn't try to open /dev/tty
# for a sudo password prompt over the non-interactive ssh session.
if command -v apt-get &>/dev/null; then
  export DEBIAN_FRONTEND=noninteractive
  apt-get update -qq
  apt-get install -y -qq \
    curl ca-certificates rsync git \
    ripgrep ffmpeg \
    build-essential python3-dev python3-yaml libffi-dev
fi

# ── Docker ────────────────────────────────────────────────────────────────────
if ! command -v docker &>/dev/null; then
  echo "→ Installing Docker"
  curl -fsSL https://get.docker.com | sh
  systemctl enable --now docker
else
  echo "✓ Docker already installed ($(docker --version))"
fi

# ── Hermes system user ────────────────────────────────────────────────────────
if ! id hermes &>/dev/null; then
  echo "→ Creating hermes user"
  useradd --system --create-home --shell /bin/bash --home-dir "${HERMES_HOME}" hermes
fi
usermod -aG docker hermes
echo "✓ hermes user in docker group"

install -d -o hermes -g hermes -m 700 "${HERMES_DATA}"
install -d -o hermes -g hermes -m 755 "${HERMES_HOME}/sync"
install -d -o hermes -g hermes -m 755 "${HERMES_HOME}/sync/wiki"
install -d -o hermes -g hermes -m 755 "${HERMES_HOME}/sync/backups"
# Each profile gets its own workspace subdirectory mounted as /workspace in Docker.
# default profile workspace (add more with: make add-profile PROFILE=<name>)
install -d -o hermes -g hermes -m 755 "${HERMES_HOME}/work/default"

# ── Drop in .env and render config BEFORE install.sh so the setup wizard is skipped
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_DIR="$(dirname "${SCRIPT_DIR}")"

for f in .env; do
  src=""
  for candidate in "${REPO_DIR}/${f}" "${VPS_DIR}/${f}"; do
    [[ -f "${candidate}" ]] && { src="${candidate}"; break; }
  done
  if [[ -n "${src}" ]]; then
    install -o hermes -g hermes -m 600 "${src}" "${HERMES_DATA}/${f}"
    echo "✓ Installed ${f} → ${HERMES_DATA}/${f}"
  else
    echo "  (no ${f} found at ${REPO_DIR} or ${VPS_DIR} — copy it manually)"
  fi
done

if [[ -f "${REPO_DIR}/scripts/render-config.py" ]]; then
  install -o hermes -g hermes -m 755 "${REPO_DIR}/scripts/render-config.py" "${HERMES_DATA}/render-config.py"
  if [[ -f "${REPO_DIR}/scripts/apply-model-strategy.py" ]]; then
    install -o hermes -g hermes -m 755 "${REPO_DIR}/scripts/apply-model-strategy.py" "${HERMES_DATA}/apply-model-strategy.py"
  fi
  sudo -iu hermes python3 "${HERMES_DATA}/render-config.py" --repo-root "${REPO_DIR}" --env-id vps --target-home /home/hermes --profile default --output "${HERMES_DATA}/config.yaml"
  if [[ -f "${HERMES_DATA}/apply-model-strategy.py" ]]; then
    sudo -iu hermes python3 "${HERMES_DATA}/apply-model-strategy.py" "${HERMES_DATA}/config.yaml"
  fi
  rm -f "${HERMES_DATA}/render-config.py" "${HERMES_DATA}/apply-model-strategy.py"
  echo "✓ Rendered VPS config → ${HERMES_DATA}/config.yaml"
else
  echo "  (render-config.py not found — copy config.yaml manually if needed)"
fi

# ── Install hermes-agent for the hermes user ──────────────────────────────────
if ! sudo -iu hermes bash -c 'command -v hermes &>/dev/null'; then
  echo "→ Installing hermes-agent via upstream install.sh"
  sudo -iu hermes bash -c 'curl -fsSL https://raw.githubusercontent.com/NousResearch/hermes-agent/main/scripts/install.sh | bash < /dev/null'
else
  echo "✓ hermes already installed ($(sudo -iu hermes hermes --version 2>/dev/null || echo unknown))"
fi

echo "→ Ensuring Hermes Python deps for Hindsight local_external mode"
sudo -iu hermes bash -lc 'export PATH="$HOME/.local/bin:$PATH"; HERMES_PY="$(head -n 1 \"$(command -v hermes)\" | sed "s/^#!//")"; uv pip install --python "$HERMES_PY" --quiet --upgrade "hindsight-client>=0.4.22"'

# ── App directory (docker compose files) ──────────────────────────────────────
mkdir -p "${VPS_DIR}"
echo "✓ App directory: ${VPS_DIR}"

# ── systemd units ─────────────────────────────────────────────────────────────
if [[ -f "${SCRIPT_DIR}/hermes-gateway.service" ]]; then
  install -m 644 "${SCRIPT_DIR}/hermes-gateway.service" /etc/systemd/system/hermes-gateway.service
  systemctl daemon-reload
  systemctl enable hermes-gateway
  echo "✓ hermes-gateway.service installed & enabled"
  echo "  Start with: systemctl start hermes-gateway"
else
  echo "  (hermes-gateway.service not staged next to this script — install manually)"
fi

if [[ -f "${SCRIPT_DIR}/hermes-dashboard.service" ]]; then
  install -m 644 "${SCRIPT_DIR}/hermes-dashboard.service" /etc/systemd/system/hermes-dashboard.service
  systemctl daemon-reload
  systemctl enable hermes-dashboard
  echo "✓ hermes-dashboard.service installed & enabled"
  echo "  Start with: systemctl start hermes-dashboard"
else
  echo "  (hermes-dashboard.service not staged next to this script — install manually)"
fi

# ── Profile provisioning helper ───────────────────────────────────────────────
if [[ -f "${SCRIPT_DIR}/provision-profile" ]]; then
  install -m 755 "${SCRIPT_DIR}/provision-profile" /usr/local/bin/provision-profile
  echo "✓ provision-profile helper installed at /usr/local/bin/provision-profile"
else
  echo "  (provision-profile helper not staged next to this script — install manually)"
fi

echo ""
echo "✓ VPS setup complete"
echo ""
echo "Next steps:"
echo "  1. Ensure ${HERMES_DATA}/.env and ${HERMES_DATA}/config.yaml are populated."
echo "  2. cd ${VPS_DIR} && docker compose -f docker-compose.yml -f docker-compose.vps.yml up -d"
echo "  3. systemctl start hermes-gateway"
echo "  4. journalctl -u hermes-gateway -f"
