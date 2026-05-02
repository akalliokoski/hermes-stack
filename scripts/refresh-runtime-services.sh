#!/usr/bin/env bash
set -euo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "${REPO_ROOT}"

COMPOSE=(docker compose -f docker-compose.yml -f docker-compose.vps.yml)

log_step() {
  printf '\n==> %s\n' "$1"
}

log_step "update hermes agent"
hermes update

log_step "refresh compose images"
"${COMPOSE[@]}" pull --quiet --ignore-buildable

log_step "reconcile compose services"
HERMES_UID="$(id -u)" HERMES_GID="$(id -g)" "${COMPOSE[@]}" up -d --remove-orphans

log_step "prune unused docker images"
docker image prune -f

log_step "verify runtime"
systemctl is-active hermes-gateway >/dev/null
systemctl is-active hermes-dashboard >/dev/null
systemctl is-active hermes-webui >/dev/null
"${COMPOSE[@]}" ps
bash scripts/verify-local-web-bindings.sh

echo
echo "✓ Runtime refresh completed"