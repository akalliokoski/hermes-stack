#!/usr/bin/env bash
set -euo pipefail

VENV_DIR="${VIDEO_PIPELINE_VENV:-/home/hermes/.venvs/video-pipeline}"
PYTHON_BIN="${VENV_DIR}/bin/python"

mkdir -p "$(dirname "$VENV_DIR")"
uv venv --allow-existing "$VENV_DIR" >/dev/null

if [[ ! -x "$PYTHON_BIN" ]]; then
  echo "video pipeline python missing at $PYTHON_BIN" >&2
  exit 1
fi

"$PYTHON_BIN" -m ensurepip --upgrade >/dev/null 2>&1 || true
uv pip install --python "$PYTHON_BIN" --quiet --upgrade pip setuptools wheel >/dev/null

if ! command -v ffmpeg >/dev/null 2>&1; then
  echo "ffmpeg is required for infographic video rendering but was not found on PATH" >&2
  exit 1
fi

"$PYTHON_BIN" - <<'PY'
import importlib.util
required = ["json", "subprocess", "pathlib"]
missing = [name for name in required if importlib.util.find_spec(name) is None]
if missing:
    raise SystemExit(f"Missing Python modules after setup: {', '.join(missing)}")
PY

ffmpeg -version >/dev/null

echo "VIDEO_PIPELINE_PYTHON=${PYTHON_BIN}"
echo "VIDEO_PIPELINE_RENDERER=infographic"
