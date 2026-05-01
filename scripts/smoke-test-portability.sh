#!/usr/bin/env bash
set -euo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "${REPO_ROOT}"

TMP_PARENT="${REPO_ROOT}/.tmp"
mkdir -p "${TMP_PARENT}"
TMP_ROOT="$(mktemp -d "${TMP_PARENT}/portability.XXXXXX")"
trap 'rm -rf "${TMP_ROOT}"' EXIT

printf '== Syntax checks ==\n'
bash -n scripts/provision-profile.sh
bash -n scripts/bootstrap-machine.sh
bash -n scripts/verify-environment.sh
bash -n scripts/export-profile.sh
bash -n scripts/import-profile.sh
bash -n scripts/clone-profile-from-vps.sh
bash -n scripts/restore-hindsight.sh
bash -n scripts/setup-podcast-pipeline.sh

printf '\n== Python dependency/bootstrap checks ==\n'
bash scripts/ensure-python-yaml.sh
python3 -c 'import yaml'

printf '\n== Python compile checks ==\n'
python3 -m py_compile scripts/render-config.py scripts/render-environment-context.py

printf '\n== Renderer smoke tests ==\n'
python3 scripts/render-config.py --env-id vps --target-home /home/hermes --profile default >"${TMP_ROOT}/rendered-vps-default.yaml"
python3 scripts/render-config.py --env-id macbook --target-home "${TMP_ROOT}/mac-home" --profile default >"${TMP_ROOT}/rendered-mac-default.yaml"
python3 scripts/render-config.py --env-id macbook --target-home "${TMP_ROOT}/mac-home" --profile ai-lab >"${TMP_ROOT}/rendered-mac-ai-lab.yaml"
python3 - <<'PY' "${TMP_ROOT}/rendered-vps-default.yaml"
import sys, yaml
path = sys.argv[1]
with open(path) as f:
    cfg = yaml.safe_load(f)
terminal = cfg.get('terminal', {})
assert terminal.get('backend') == 'local', terminal
assert terminal.get('cwd') == '/home/hermes/work/default', terminal
assert terminal.get('docker_volumes') == [], terminal
PY
python3 - <<'PY' "${TMP_ROOT}/rendered-mac-default.yaml"
import sys, yaml
path = sys.argv[1]
with open(path) as f:
    cfg = yaml.safe_load(f)
terminal = cfg.get('terminal', {})
volumes = terminal.get('docker_volumes', [])
assert terminal.get('backend') == 'docker', terminal
assert terminal.get('cwd') == '/workspace', terminal
assert any(entry.endswith(':/workspace') for entry in volumes), volumes
PY
python3 - <<'PY' "${TMP_ROOT}/rendered-mac-ai-lab.yaml" "${TMP_ROOT}/mac-home"
import sys, yaml
path, home = sys.argv[1], sys.argv[2]
with open(path) as f:
    cfg = yaml.safe_load(f)
terminal = cfg.get('terminal', {})
assert terminal.get('backend') == 'local', terminal
assert terminal.get('cwd') == f'{home}/hermes-work/ai-lab', terminal
assert terminal.get('docker_volumes') == [], terminal
PY
python3 scripts/render-environment-context.py --env-id macbook --profile default --profile-home "${TMP_ROOT}/mac-home/.hermes" --config-path "${TMP_ROOT}/mac-home/.hermes/config.yaml" --service-mode auto --output "${TMP_ROOT}/ENVIRONMENT.md"

printf '\n== Podcast pipeline idempotence ==\n'
UV_CACHE_DIR="${TMP_ROOT}/uv-cache" PODCASTFY_VENV="${TMP_ROOT}/venvs/podcast" bash scripts/setup-podcast-pipeline.sh >"${TMP_ROOT}/podcast-run1.txt"
UV_CACHE_DIR="${TMP_ROOT}/uv-cache" PODCASTFY_VENV="${TMP_ROOT}/venvs/podcast" bash scripts/setup-podcast-pipeline.sh >"${TMP_ROOT}/podcast-run2.txt"
cmp -s "${TMP_ROOT}/podcast-run1.txt" "${TMP_ROOT}/podcast-run2.txt"

printf '\n== Local bootstrap + profile export/import smoke ==\n'
HOME="${TMP_ROOT}/home1" HERMES_HOME="${TMP_ROOT}/home1/.hermes" HERMES_ENV_ID=macbook bash scripts/bootstrap-machine.sh --service-mode remote
HOME="${TMP_ROOT}/home1" HERMES_HOME="${TMP_ROOT}/home1/.hermes" HERMES_ENV_ID=macbook bash scripts/verify-environment.sh --all-profiles --service-mode remote
ARCHIVE_PATH="$(HOME="${TMP_ROOT}/home1" HERMES_HOME="${TMP_ROOT}/home1/.hermes" HERMES_ENV_ID=macbook bash scripts/export-profile.sh --profile default | awk -F': ' '/Exported profile bundle/ {print $2}')"
[[ -f "${ARCHIVE_PATH}" ]]
HOME="${TMP_ROOT}/home2" HERMES_HOME="${TMP_ROOT}/home2/.hermes" HERMES_ENV_ID=macbook bash scripts/bootstrap-machine.sh --service-mode remote --skip-sync-profiles
HOME="${TMP_ROOT}/home2" HERMES_HOME="${TMP_ROOT}/home2/.hermes" HERMES_ENV_ID=macbook bash scripts/import-profile.sh --archive "${ARCHIVE_PATH}" --service-mode remote --gateway skip
HOME="${TMP_ROOT}/home2" HERMES_HOME="${TMP_ROOT}/home2/.hermes" HERMES_ENV_ID=macbook bash scripts/verify-environment.sh --all-profiles --service-mode remote

printf '\n== Diff check ==\n'
git diff --check

printf '\nAll portability smoke tests passed.\n'
