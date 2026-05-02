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

CURRENT_TAILNET_DOMAIN="$(${TAILSCALE_CMD[@]} status --json | python3 -c '
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

echo "→ Configuring Tailscale Serve for ${CURRENT_TAILNET_DOMAIN}"

"${TAILSCALE_CMD[@]}" serve reset
"${TAILSCALE_CMD[@]}" serve --bg --https=443 http://127.0.0.1:8081
"${TAILSCALE_CMD[@]}" serve --bg --https=9446 http://127.0.0.1:8787
"${TAILSCALE_CMD[@]}" serve --bg --https=9444 http://127.0.0.1:9119
"${TAILSCALE_CMD[@]}" serve --bg --https=9445 http://127.0.0.1:8384
"${TAILSCALE_CMD[@]}" serve --bg --https=443 --set-path /memory/ http://127.0.0.1:8888
"${TAILSCALE_CMD[@]}" serve --bg --https=9443 http://127.0.0.1:9999
"${TAILSCALE_CMD[@]}" serve --bg --https=443 --set-path /firecrawl/ http://127.0.0.1:3002

SERVE_STATUS_JSON="$(${TAILSCALE_CMD[@]} serve status --json)"
printf '%s\n' "$SERVE_STATUS_JSON"

export CURRENT_TAILNET_DOMAIN SERVE_STATUS_JSON
python3 -c '
import json, os, sys

domain = os.environ["CURRENT_TAILNET_DOMAIN"]
status = json.loads(os.environ["SERVE_STATUS_JSON"])
web = status.get("Web") or {}
expected = {f"{domain}:443", f"{domain}:9443", f"{domain}:9444", f"{domain}:9445", f"{domain}:9446"}
missing = sorted(expected - set(web))
unexpected = sorted(k for k in web if k not in expected)
if missing or unexpected:
    if missing:
        print("Missing expected serve listeners:", ", ".join(missing), file=sys.stderr)
    if unexpected:
        print("Unexpected serve listeners still present:", ", ".join(unexpected), file=sys.stderr)
    raise SystemExit(1)
'

echo "✓ Tailscale Serve now published at:"
echo "  https://${CURRENT_TAILNET_DOMAIN}/"
echo "  https://${CURRENT_TAILNET_DOMAIN}:9446/"
echo "  https://${CURRENT_TAILNET_DOMAIN}:9444/"
echo "  https://${CURRENT_TAILNET_DOMAIN}:9445/"
echo "  https://${CURRENT_TAILNET_DOMAIN}/memory/"
echo "  https://${CURRENT_TAILNET_DOMAIN}/firecrawl/"
echo "  https://${CURRENT_TAILNET_DOMAIN}:9443/"
