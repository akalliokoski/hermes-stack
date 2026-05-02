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

START_TS="$(date +%s)"

while true; do
  SERVE_STATUS_JSON="$(${TAILSCALE_BIN} serve status --json)"

  if CURRENT_TAILNET_DOMAIN="${CURRENT_TAILNET_DOMAIN}" SERVE_STATUS_JSON="${SERVE_STATUS_JSON}" python3 - <<'PY'
import json, os, sys

domain = os.environ['CURRENT_TAILNET_DOMAIN']
status = json.loads(os.environ['SERVE_STATUS_JSON'])
web = status.get('Web') or {}
expected = {
    f'{domain}:443': {
        '/': 'http://127.0.0.1:8081',
        '/memory/': 'http://127.0.0.1:8888',
        '/firecrawl/': 'http://127.0.0.1:3002',
    },
    f'{domain}:9443': {
        '/': 'http://127.0.0.1:9999',
    },
    f'{domain}:9446': {
        '/': 'http://127.0.0.1:8787',
    },
    f'{domain}:9444': {
        '/': 'http://127.0.0.1:9119',
    },
    f'{domain}:9445': {
        '/': 'http://127.0.0.1:8384',
    },
    f'{domain}:13378': {
        '/': 'http://127.0.0.1:13378',
    },
    f'{domain}:8096': {
        '/': 'http://127.0.0.1:8096',
    },
}

for listener, paths in expected.items():
    actual_listener = web.get(listener)
    if not actual_listener:
        raise SystemExit(f'missing listener {listener}')
    handlers = actual_listener.get('Handlers') or {}
    for path, proxy in paths.items():
        actual = ((handlers.get(path) or {}).get('Proxy'))
        if actual != proxy:
            raise SystemExit(f'{listener}{path} expected {proxy} but found {actual}')

unexpected = sorted(k for k in web if not k.startswith(f'{domain}:'))
if unexpected:
    raise SystemExit('stale listeners present: ' + ', '.join(unexpected))
PY
  then
    echo "✓ Verified tailnet-served route mappings on ${CURRENT_TAILNET_DOMAIN}"
    exit 0
  fi

  now="$(date +%s)"
  if (( now - START_TS >= WAIT_SECONDS )); then
    echo "Timed out waiting for expected Tailscale Serve routes on ${CURRENT_TAILNET_DOMAIN}" >&2
    printf '%s\n' "${SERVE_STATUS_JSON}" >&2
    exit 1
  fi

  sleep 2
done
