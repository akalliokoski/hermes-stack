#!/usr/bin/env bash
set -euo pipefail

WAIT_SECONDS="${WAIT_SECONDS:-60}"
TAILSCALE_BIN="${TAILSCALE_BIN:-tailscale}"

CURRENT_TAILNET_DOMAIN="$(${TAILSCALE_BIN} status --json | python3 -c '
import json, sys

data = json.load(sys.stdin)
domains = data.get("CertDomains") or []
if domains:
    print(domains[0])
    raise SystemExit(0)
self_dns = (((data.get("Self") or {}).get("DNSName")) or "").rstrip(".")
if self_dns:
    print(self_dns)
    raise SystemExit(0)
raise SystemExit("Unable to determine current Tailscale DNS name")
')"

check_url() {
  local url="$1"
  local elapsed=0
  while true; do
    if curl --fail --silent --show-error --max-time 20 \
      --resolve "${CURRENT_TAILNET_DOMAIN}:443:127.0.0.1" \
      "$url" >/dev/null; then
      return 0
    fi

    if (( elapsed >= WAIT_SECONDS )); then
      echo "Timed out waiting for ${url}" >&2
      return 1
    fi

    sleep 2
    elapsed=$((elapsed + 2))
  done
}

check_url "https://${CURRENT_TAILNET_DOMAIN}/"
check_url "https://${CURRENT_TAILNET_DOMAIN}/dashboard/"
check_url "https://${CURRENT_TAILNET_DOMAIN}/syncthing/"
check_url "https://${CURRENT_TAILNET_DOMAIN}/memory/openapi.json"
check_url "https://${CURRENT_TAILNET_DOMAIN}/firecrawl/"

local_hindsight_elapsed=0
while true; do
  if curl --fail --silent --show-error --max-time 20 \
    --resolve "${CURRENT_TAILNET_DOMAIN}:9443:127.0.0.1" \
    "https://${CURRENT_TAILNET_DOMAIN}:9443/" >/dev/null; then
    break
  fi

  if (( local_hindsight_elapsed >= WAIT_SECONDS )); then
    echo "Timed out waiting for https://${CURRENT_TAILNET_DOMAIN}:9443/" >&2
    exit 1
  fi

  sleep 2
  local_hindsight_elapsed=$((local_hindsight_elapsed + 2))
done

echo "✓ Verified tailnet-served routes on ${CURRENT_TAILNET_DOMAIN}"
