#!/usr/bin/env bash
set -euo pipefail

# Configure tailnet-only access to local Hermes stack UIs.
# Uses imperative `tailscale serve` commands because `set-config` now manages
# Tailscale Services config, not the node-local Serve routes we want here.

TAILSCALE_BIN="${TAILSCALE_BIN:-tailscale}"
TAILSCALE_CMD=("${TAILSCALE_BIN}")
if [[ ${EUID:-$(id -u)} -ne 0 ]] && command -v sudo >/dev/null 2>&1 && sudo -n true >/dev/null 2>&1; then
  TAILSCALE_CMD=(sudo "${TAILSCALE_BIN}")
fi

"${TAILSCALE_CMD[@]}" serve reset
"${TAILSCALE_CMD[@]}" serve --bg --https=443 http://127.0.0.1:8081
"${TAILSCALE_CMD[@]}" serve --bg --https=443 --set-path /dashboard/ http://127.0.0.1:9119
"${TAILSCALE_CMD[@]}" serve --bg --https=443 --set-path /syncthing/ http://127.0.0.1:8384
"${TAILSCALE_CMD[@]}" serve --bg --https=443 --set-path /memory/ http://127.0.0.1:8888
"${TAILSCALE_CMD[@]}" serve --bg --https=9443 http://127.0.0.1:9999
"${TAILSCALE_CMD[@]}" serve --bg --https=443 --set-path /firecrawl/ http://127.0.0.1:3002

"${TAILSCALE_CMD[@]}" serve status --json
