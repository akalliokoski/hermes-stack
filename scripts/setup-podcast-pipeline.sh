#!/usr/bin/env bash
set -euo pipefail

VENV_DIR="${PODCASTFY_VENV:-/home/hermes/.venvs/podcast-pipeline}"
PYTHON_BIN="${VENV_DIR}/bin/python"

mkdir -p "$(dirname "$VENV_DIR")"
uv venv "$VENV_DIR" >/dev/null
uv pip install --python "$PYTHON_BIN" --quiet --upgrade \
  podcastfy==0.4.3 \
  playwright \
  mutagen \
  pyyaml >/dev/null

echo "PODCASTFY_PYTHON=${PYTHON_BIN}"
