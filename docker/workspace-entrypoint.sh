#!/bin/bash
# Wrapper entrypoint: cd into the persistent workspace before starting hermes,
# so that os.getcwd() (used as fallback cwd for the local terminal backend)
# matches terminal.cwd in config.yaml rather than the image WORKDIR /opt/hermes.
set -e

WORKSPACE="${HERMES_HOME:-/opt/data}/workspace"
mkdir -p "$WORKSPACE"
cd "$WORKSPACE"

exec /opt/hermes/docker/entrypoint.sh "$@"
