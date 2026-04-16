#!/usr/bin/env bash
set -euo pipefail

# Repair the Syncthing config volume so it matches the live hermes UID/GID.
# This fixes upgrades/migrations where older runs created /var/syncthing/config
# under a different numeric owner.

HERMES_UID="${HERMES_UID:?set HERMES_UID}"
HERMES_GID="${HERMES_GID:?set HERMES_GID}"
VOLUME_NAME="${SYNCTHING_CONFIG_VOLUME:-hermes_syncthing_config}"

DOCKER_BIN="${DOCKER_BIN:-docker}"

"${DOCKER_BIN}" volume create "${VOLUME_NAME}" >/dev/null
"${DOCKER_BIN}" run --rm \
  -v "${VOLUME_NAME}:/var/syncthing" \
  alpine:latest \
  sh -c "mkdir -p /var/syncthing/config && chown -R ${HERMES_UID}:${HERMES_GID} /var/syncthing && chmod 700 /var/syncthing/config"

