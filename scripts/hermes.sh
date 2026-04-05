#!/usr/bin/env bash
# scripts/hermes.sh – run any hermes CLI command inside the running container
#
# Usage (from repo root on VPS):
#   bash scripts/hermes.sh                    # interactive chat
#   bash scripts/hermes.sh chat               # interactive chat (explicit)
#   bash scripts/hermes.sh skills             # browse / manage skills
#   bash scripts/hermes.sh profile list       # list profiles
#   bash scripts/hermes.sh profile switch work
#   bash scripts/hermes.sh sessions           # browse session history
#   bash scripts/hermes.sh doctor             # diagnose config issues
#   bash scripts/hermes.sh update             # update hermes to latest
#
# Pass PROFILE= to override active profile for a single command:
#   PROFILE=work bash scripts/hermes.sh chat
#
set -euo pipefail

CONTAINER="${CONTAINER:-hermes_agent}"

if ! docker ps --format '{{.Names}}' | grep -q "^${CONTAINER}$"; then
  echo "Error: container '${CONTAINER}' is not running." >&2
  echo "Start the stack first: docker compose up -d" >&2
  exit 1
fi

# If PROFILE is set, override HERMES_PROFILE for this invocation
PROFILE_ARGS=()
if [[ -n "${PROFILE:-}" ]]; then
  PROFILE_ARGS=(--env "HERMES_PROFILE=${PROFILE}")
fi

exec docker exec -it "${PROFILE_ARGS[@]}" "${CONTAINER}" hermes "$@"
