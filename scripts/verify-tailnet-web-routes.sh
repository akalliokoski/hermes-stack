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
import base64, json, os, socket, ssl, sys, urllib.parse, urllib.request

domain = os.environ['CURRENT_TAILNET_DOMAIN']
status = json.loads(os.environ['SERVE_STATUS_JSON'])
web = status.get('Web') or {}
mode = os.environ.get('HERMES_COMPOSE_SERVICE_SET', 'core')
expected = {
    f'{domain}:443': {
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
        '/': 'http://127.0.0.1:9120',
    },
    f'{domain}:9445': {
        '/': 'http://127.0.0.1:8384',
    },
}
if mode == 'full':
    expected[f'{domain}:443']['/'] = 'http://127.0.0.1:8081'

for listener, paths in expected.items():
    actual_listener = web.get(listener)
    if not actual_listener:
        raise SystemExit(f'missing listener {listener}')
    handlers = actual_listener.get('Handlers') or {}
    for path, proxy in paths.items():
        actual = ((handlers.get(path) or {}).get('Proxy'))
        if actual != proxy:
            raise SystemExit(f'{listener}{path} expected {proxy} but found {actual}')

unexpected = sorted(k for k in web if k not in expected)
if unexpected:
    raise SystemExit('unexpected listeners present: ' + ', '.join(unexpected))

ctx = ssl._create_unverified_context()
checks = [
    (f'https://{domain}/memory/openapi.json', '"title":"Hindsight HTTP API"'),
    (f'https://{domain}/firecrawl/', 'Firecrawl API'),
    (f'https://{domain}:9443/', '<!DOCTYPE html>'),
    (f'https://{domain}:9444/', 'Hermes Agent - Dashboard'),
    (f'https://{domain}:9445/', '<!DOCTYPE html>'),
    (f'https://{domain}:9446/', '<!doctype html>'),
]
if mode == 'full':
    checks.append((f'https://{domain}/', '<title>Hermes Stack</title>'))

dashboard_html = ''
for url, needle in checks:
    req = urllib.request.Request(url, headers={'User-Agent': 'hermes-stack-tailnet-verifier/1.0'})
    with urllib.request.urlopen(req, context=ctx, timeout=20) as response:
        body = response.read(8192).decode('utf-8', 'replace')
        if response.status < 200 or response.status >= 400:
            raise SystemExit(f'{url} returned HTTP {response.status}')
        if needle not in body:
            raise SystemExit(f'{url} missing expected marker: {needle}')
        if url == f'https://{domain}:9444/':
            dashboard_html = body

marker = 'window.__HERMES_SESSION_TOKEN__="'
try:
    token = dashboard_html.split(marker, 1)[1].split('"', 1)[0]
except IndexError as exc:
    raise SystemExit('Hermes dashboard did not expose a session token for WebSocket verification') from exc

# Verify the WebSocket upgrade used by Hermes Desktop. A plain HTTP fetch can
# pass even when the proxy drops Upgrade/Connection and Desktop later reports
# "Could not connect to Hermes gateway".
ws_path = '/api/ws?token=' + urllib.parse.quote(token, safe='')
ws_key = base64.b64encode(os.urandom(16)).decode('ascii')
request = (
    f'GET {ws_path} HTTP/1.1\r\n'
    f'Host: {domain}:9444\r\n'
    'Upgrade: websocket\r\n'
    'Connection: Upgrade\r\n'
    f'Sec-WebSocket-Key: {ws_key}\r\n'
    'Sec-WebSocket-Version: 13\r\n'
    'Origin: https://hermes-stack-tailnet-verifier.invalid\r\n'
    'User-Agent: hermes-stack-tailnet-verifier/1.0\r\n'
    '\r\n'
).encode('ascii')
with socket.create_connection((domain, 9444), timeout=20) as raw:
    with ctx.wrap_socket(raw, server_hostname=domain) as sock:
        sock.sendall(request)
        response = sock.recv(4096).decode('iso-8859-1', 'replace')
        if not response.startswith('HTTP/1.1 101') and not response.startswith('HTTP/2 101'):
            first = response.splitlines()[0] if response else '<empty response>'
            raise SystemExit(f'Hermes dashboard WebSocket upgrade failed: {first}')
PY
  then
    echo "✓ Verified tailnet-served route mappings, live HTTP responses, and Hermes dashboard WebSocket on ${CURRENT_TAILNET_DOMAIN}"
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
