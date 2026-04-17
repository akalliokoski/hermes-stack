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
  sh -c "
    set -e
    mkdir -p /var/syncthing/config
    if [ -f /var/syncthing/config/config.xml ]; then
      sed -i 's#<address>[^<]*:8384</address>#<address>127.0.0.1:8384</address>#g' /var/syncthing/config/config.xml
      if grep -q '<insecureSkipHostcheck>' /var/syncthing/config/config.xml; then
        sed -i 's#<insecureSkipHostcheck>[^<]*</insecureSkipHostcheck>#<insecureSkipHostcheck>true</insecureSkipHostcheck>#g' /var/syncthing/config/config.xml
      else
        sed -i 's#</gui>#    <insecureSkipHostcheck>true</insecureSkipHostcheck>\n</gui>#' /var/syncthing/config/config.xml
      fi
    fi
    chown -R ${HERMES_UID}:${HERMES_GID} /var/syncthing
    chmod 700 /var/syncthing/config
  "
