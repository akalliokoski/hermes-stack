#!/usr/bin/env bash
set -euo pipefail

if python3 -c 'import yaml' >/dev/null 2>&1; then
  exit 0
fi

if python3 -m pip install --user pyyaml >/dev/null 2>&1; then
  python3 -c 'import yaml' >/dev/null 2>&1
  exit 0
fi

if command -v apt-get >/dev/null 2>&1; then
  if [[ ${EUID:-$(id -u)} -eq 0 ]]; then
    apt-get update -qq
    apt-get install -y -qq python3-yaml
    python3 -c 'import yaml' >/dev/null 2>&1
    exit 0
  elif command -v sudo >/dev/null 2>&1; then
    sudo apt-get update -qq
    sudo apt-get install -y -qq python3-yaml
    python3 -c 'import yaml' >/dev/null 2>&1
    exit 0
  fi
fi

echo 'ERROR: PyYAML is required. Install python3-yaml or run: python3 -m pip install --user pyyaml' >&2
exit 1
