#!/usr/bin/env bash
# scripts/vps-bootstrap.sh – one-shot VPS bootstrap from the MacBook.
#
# Runs on the LOCAL machine. Wipes any previous hermes setup on the VPS,
# creates the hermes user, installs hermes-agent + systemd unit, and seeds
# /home/hermes/.hermes with config.yaml and .env from the repo.
#
# After this completes, `git push` (or `make deploy`) will handle all future
# deploys via the hermes-gateway systemd unit.
#
# Usage:  bash scripts/vps-bootstrap.sh
#         (VPS_HOST is read from .env)
set -euo pipefail

REPO_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "${REPO_DIR}"

[[ -f config.yaml ]] || { echo "ERROR: config.yaml not found" >&2; exit 1; }

if [[ ! -f .env ]]; then
  echo "→ No local .env — attempting to fetch from VPS"
  read -r -p "VPS host (ssh alias or tailscale name): " VPS_HOST
  [[ -n "${VPS_HOST}" ]] || { echo "ERROR: VPS host required" >&2; exit 1; }
  for remote in /home/hermes/.hermes/.env /opt/hermes/.env; do
    if scp "${VPS_HOST}:${remote}" .env 2>/dev/null; then
      echo "  ✓ fetched ${remote} → .env"
      break
    fi
  done
  [[ -f .env ]] || { echo "ERROR: could not fetch .env from VPS (tried /home/hermes/.hermes/.env and /opt/hermes/.env)" >&2; exit 1; }
fi

VPS_HOST="${VPS_HOST:-$(grep -E '^VPS_HOST=' .env | cut -d= -f2-)}"
[[ -n "${VPS_HOST}" ]] || { echo "ERROR: VPS_HOST not set in .env" >&2; exit 1; }

echo "→ Target VPS: ${VPS_HOST}"
read -r -p "This will WIPE the existing hermes setup on ${VPS_HOST}. Continue? [y/N] " ans
[[ "${ans}" == "y" || "${ans}" == "Y" ]] || { echo "Aborted."; exit 1; }

echo ""
echo "→ Staging bootstrap files on VPS"
ssh "${VPS_HOST}" 'sudo rm -rf /tmp/hermes-bootstrap && mkdir -p /tmp/hermes-bootstrap/scripts'
scp scripts/vps-reset.sh           "${VPS_HOST}:/tmp/hermes-bootstrap/scripts/"
scp scripts/vps-setup.sh           "${VPS_HOST}:/tmp/hermes-bootstrap/scripts/"
scp scripts/hermes-gateway.service "${VPS_HOST}:/tmp/hermes-bootstrap/scripts/"
scp config.yaml .env               "${VPS_HOST}:/tmp/hermes-bootstrap/"

echo ""
echo "→ Running vps-reset.sh (destructive)"
ssh "${VPS_HOST}" 'sudo bash /tmp/hermes-bootstrap/scripts/vps-reset.sh'

echo ""
echo "→ Running vps-setup.sh"
ssh "${VPS_HOST}" 'sudo bash /tmp/hermes-bootstrap/scripts/vps-setup.sh'

echo ""
echo "→ Cleaning up staged files"
ssh "${VPS_HOST}" 'sudo rm -rf /tmp/hermes-bootstrap'

echo ""
echo "✓ Bootstrap complete."
echo ""
echo "Next: git push (or \`make deploy\`) — CI will rsync the repo, bring up"
echo "the support stack, and start hermes-gateway."
