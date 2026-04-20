#!/usr/bin/env bash
set -euo pipefail

VENV_DIR="${VIDEO_PIPELINE_VENV:-/home/hermes/.venvs/video-pipeline}"
PYTHON_BIN="${VENV_DIR}/bin/python"
MANIM_BIN="${VENV_DIR}/bin/manim"

mkdir -p "$(dirname "$VENV_DIR")"
uv venv --allow-existing "$VENV_DIR" >/dev/null

if [[ ! -x "$PYTHON_BIN" ]]; then
  echo "video pipeline python missing at $PYTHON_BIN" >&2
  exit 1
fi

"$PYTHON_BIN" -m ensurepip --upgrade >/dev/null 2>&1 || true

uv pip install --python "$PYTHON_BIN" --quiet --upgrade \
  pip \
  setuptools \
  wheel \
  'manim==0.20.1' >/dev/null

"$PYTHON_BIN" - <<'PY'
import importlib
modules = ["manim", "cairo"]
missing = [name for name in modules if importlib.util.find_spec(name) is None]
if missing:
    raise SystemExit(f"Missing Python modules after setup: {', '.join(missing)}")
PY

if [[ ! -x "$MANIM_BIN" ]]; then
  echo "manim executable missing at $MANIM_BIN" >&2
  exit 1
fi

"$MANIM_BIN" --version >/dev/null

echo "VIDEO_PIPELINE_PYTHON=${PYTHON_BIN}"
echo "VIDEO_PIPELINE_MANIM=${MANIM_BIN}"
echo "MANIM_BIN=${MANIM_BIN}"
