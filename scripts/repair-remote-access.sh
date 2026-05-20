#!/usr/bin/env bash
set -euo pipefail

echo "[repair-remote-access] checking SSH and Tailscale access services"

restart_unit_if_failed_or_inactive() {
  local unit="$1"

  if ! systemctl cat "${unit}" >/dev/null 2>&1; then
    return 1
  fi

  if systemctl is-active --quiet "${unit}"; then
    echo "[repair-remote-access] ${unit} is active"
    return 0
  fi

  echo "[repair-remote-access] restarting inactive/failed ${unit}"
  sudo systemctl reset-failed "${unit}" || true
  sudo systemctl restart "${unit}"
  systemctl is-active "${unit}"
}

if ! restart_unit_if_failed_or_inactive ssh.service; then
  restart_unit_if_failed_or_inactive sshd.service || true
fi

if systemctl cat tailscaled.service >/dev/null 2>&1; then
  if systemctl is-active --quiet tailscaled.service; then
    echo "[repair-remote-access] tailscaled.service is active"
  else
    echo "[repair-remote-access] restarting inactive/failed tailscaled.service"
    sudo systemctl reset-failed tailscaled.service || true
    sudo systemctl restart tailscaled.service
    systemctl is-active tailscaled.service
  fi
fi

if command -v tailscale >/dev/null 2>&1; then
  tailscale status --self --peers=false || true
fi
