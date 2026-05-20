#!/usr/bin/env bash
set -euo pipefail

HERMES_USER="${HERMES_USER:-hermes}"
HERMES_HOME="${HERMES_HOME:-/home/hermes}"
CONFIG_DIR="${SYNCTHING_CONFIG_DIR:-${HERMES_HOME}/.config/syncthing}"
SYNC_ROOT="${SYNCTHING_SYNC_ROOT:-${HERMES_HOME}/sync}"
CODEO_SYNC_ROOT="${CODEO_SYNC_ROOT:-${HERMES_HOME}/codeo-sync}"

if [[ ${EUID} -ne 0 ]]; then
  echo "ERROR: setup-syncthing-host.sh must run as root" >&2
  exit 1
fi

if ! id "${HERMES_USER}" >/dev/null 2>&1; then
  echo "ERROR: user not found: ${HERMES_USER}" >&2
  exit 1
fi

if ! command -v syncthing >/dev/null 2>&1; then
  if command -v apt-get >/dev/null 2>&1; then
    export DEBIAN_FRONTEND=noninteractive
    apt-get update -qq
    apt-get install -y -qq syncthing
  else
    echo "ERROR: syncthing is not installed and apt-get is unavailable" >&2
    exit 1
  fi
fi

install -d -o "${HERMES_USER}" -g "${HERMES_USER}" -m 755 "${SYNC_ROOT}" "${CODEO_SYNC_ROOT}"
install -d -o "${HERMES_USER}" -g "${HERMES_USER}" -m 700 "${CONFIG_DIR}"

if [[ ! -f "${CONFIG_DIR}/config.xml" ]] && docker volume inspect hermes_syncthing_config >/dev/null 2>&1; then
  docker run --rm \
    -v hermes_syncthing_config:/from:ro \
    -v "${CONFIG_DIR}:/to" \
    alpine sh -c 'cp -a /from/config/. /to/ 2>/dev/null || cp -a /from/. /to/' >/dev/null
  chown -R "${HERMES_USER}:${HERMES_USER}" "${CONFIG_DIR}"
  echo "✓ Migrated Syncthing config from Docker volume"
fi

if [[ -f "${CONFIG_DIR}/config.xml" ]]; then
  python3 - "${CONFIG_DIR}/config.xml" <<'PY'
from pathlib import Path
import sys
import xml.etree.ElementTree as ET

path = Path(sys.argv[1])
tree = ET.parse(path)
root = tree.getroot()

gui = root.find('gui')
if gui is not None:
    address = gui.find('address')
    if address is None:
        address = ET.SubElement(gui, 'address')
    address.text = '127.0.0.1:8384'
    skip = gui.find('insecureSkipHostcheck')
    if skip is None:
        skip = ET.SubElement(gui, 'insecureSkipHostcheck')
    skip.text = 'true'

for folder in root.findall('folder'):
    folder_path = folder.get('path')
    if not folder_path:
        continue
    if folder_path == '/sync':
        folder.set('path', '/home/hermes/sync')
    elif folder_path.startswith('/sync/'):
        folder.set('path', '/home/hermes/sync/' + folder_path.removeprefix('/sync/'))
    elif folder_path == '/codeo-sync':
        folder.set('path', '/home/hermes/codeo-sync')
    elif folder_path.startswith('/codeo-sync/'):
        folder.set('path', '/home/hermes/codeo-sync/' + folder_path.removeprefix('/codeo-sync/'))

tree.write(path, encoding='utf-8', xml_declaration=True)
PY
  chown "${HERMES_USER}:${HERMES_USER}" "${CONFIG_DIR}/config.xml"
fi

SYNCTHING_BIN="$(command -v syncthing)"
cat >/etc/systemd/system/syncthing@.service <<EOF
[Unit]
Description=Syncthing - Open Source Continuous File Synchronization for %i
Documentation=man:syncthing(1)
After=network.target

[Service]
User=%i
Environment=STGUIADDRESS=127.0.0.1:8384
ExecStart=${SYNCTHING_BIN} -home=${CONFIG_DIR} -no-browser -no-restart -logflags=0
Restart=on-failure
RestartSec=5
SuccessExitStatus=3 4
RestartForceExitStatus=3 4

[Install]
WantedBy=multi-user.target
EOF

systemctl daemon-reload
systemctl enable --now "syncthing@${HERMES_USER}.service"

for _ in $(seq 1 30); do
  if ss -ltnH '( sport = :8384 )' | awk '{print $4}' | grep -qx '127.0.0.1:8384'; then
    echo "✓ Syncthing is running host-native on 127.0.0.1:8384"
    exit 0
  fi
  sleep 1
done

echo "ERROR: Syncthing did not bind to 127.0.0.1:8384" >&2
systemctl status "syncthing@${HERMES_USER}.service" --no-pager >&2 || true
exit 1
