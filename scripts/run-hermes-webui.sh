#!/usr/bin/env bash
set -euo pipefail

export PATH="$HOME/.local/bin:/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin"

HERMES_WEBUI_INSTALL_DIR="${HERMES_WEBUI_INSTALL_DIR:-/opt/hermes-webui}"
SERVER_PATH="${HERMES_WEBUI_INSTALL_DIR}/server.py"

if [[ ! -f "${SERVER_PATH}" ]]; then
  echo "ERROR: Hermes WebUI server not found at ${SERVER_PATH}" >&2
  exit 1
fi

HERMES_BIN="$(command -v hermes || true)"
if [[ -z "${HERMES_BIN}" ]]; then
  echo "ERROR: hermes CLI not found in PATH" >&2
  exit 1
fi

HERMES_PY="$(head -n 1 "${HERMES_BIN}" | sed 's/^#!//')"
exec "${HERMES_PY}" "${SERVER_PATH}"
