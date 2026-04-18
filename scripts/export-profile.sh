#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(dirname "${SCRIPT_DIR}")"
CONFIG_RENDERER="${REPO_ROOT}/scripts/render-config.py"

PROFILE=""
ARCHIVE_PATH=""
ENV_ID="${HERMES_ENV_ID:-}"
SERVICE_MODE="${HERMES_SERVICE_MODE:-auto}"
HERMES_HOME="${HERMES_HOME:-$HOME/.hermes}"
TARGET_HOME="$(dirname "${HERMES_HOME}")"

usage() {
  cat <<'EOF'
Usage:
  scripts/export-profile.sh --profile <name> [--archive <path>] [--service-mode auto|local|remote]

Creates a portable tar.gz bundle under <sync_root>/exports/profiles/<name>/ by default.
The bundle contains profile metadata, shared SOUL sources, rendered profile context,
non-secret env templates, and references to the latest synced backups.
EOF
}

die() {
  printf 'ERROR: %s\n' "$*" >&2
  exit 1
}

profile_home() {
  local profile="$1"
  if [[ "${profile}" == "default" ]]; then
    printf '%s\n' "${HERMES_HOME}"
  else
    printf '%s\n' "${HERMES_HOME}/profiles/${profile}"
  fi
}

while [[ $# -gt 0 ]]; do
  case "$1" in
    --profile)
      PROFILE="${2:?missing profile}"
      shift 2
      ;;
    --archive)
      ARCHIVE_PATH="${2:?missing archive path}"
      shift 2
      ;;
    --env-id)
      ENV_ID="${2:?missing env id}"
      shift 2
      ;;
    --service-mode)
      SERVICE_MODE="${2:?missing service mode}"
      shift 2
      ;;
    -h|--help)
      usage
      exit 0
      ;;
    *)
      die "Unknown argument: $1"
      ;;
  esac
done

[[ -n "${PROFILE}" ]] || die "--profile is required"
if [[ -z "${ENV_ID}" ]]; then
  ENV_ID="$(bash "${REPO_ROOT}/scripts/detect-env.sh" --repo-root "${REPO_ROOT}")"
fi

PROFILE_HOME="$(profile_home "${PROFILE}")"
[[ -d "${PROFILE_HOME}" ]] || die "Profile home not found: ${PROFILE_HOME}"

SYNC_ROOT="$(python3 "${CONFIG_RENDERER}" --repo-root "${REPO_ROOT}" --env-id "${ENV_ID}" --target-home "${TARGET_HOME}" --print-meta env.sync_root)"
EXPORT_ROOT="${SYNC_ROOT}/exports/profiles/${PROFILE}"
TIMESTAMP="$(date -u +%Y-%m-%dT%H-%M-%SZ)"
if [[ -z "${ARCHIVE_PATH}" ]]; then
  mkdir -p "${EXPORT_ROOT}"
  ARCHIVE_PATH="${EXPORT_ROOT}/${PROFILE}_${ENV_ID}_${TIMESTAMP}.tar.gz"
else
  mkdir -p "$(dirname "${ARCHIVE_PATH}")"
fi

TMP_DIR="$(mktemp -d)"
trap 'rm -rf "${TMP_DIR}"' EXIT
BUNDLE_DIR="${TMP_DIR}/bundle"
mkdir -p "${BUNDLE_DIR}/profile" "${BUNDLE_DIR}/shared/soul/profiles" "${BUNDLE_DIR}/references"

copy_if_exists() {
  local source="$1"
  local dest="$2"
  if [[ -f "${source}" ]]; then
    mkdir -p "$(dirname "${dest}")"
    cp "${source}" "${dest}"
  fi
}

generate_env_template() {
  local source="$1"
  local dest="$2"
  if [[ ! -f "${source}" ]]; then
    return 0
  fi
  python3 - "${source}" "${dest}" <<'PY'
from pathlib import Path
import re
import sys
src = Path(sys.argv[1])
dst = Path(sys.argv[2])
lines = []
for raw in src.read_text().splitlines():
    if not raw or raw.lstrip().startswith('#') or '=' not in raw:
        continue
    key = raw.split('=', 1)[0].strip()
    if not re.fullmatch(r'[A-Za-z_][A-Za-z0-9_]*', key):
        continue
    lines.append(f'{key}=')
if lines:
    dst.write_text('\n'.join(lines) + '\n')
PY
}

copy_if_exists "${PROFILE_HOME}/config.yaml" "${BUNDLE_DIR}/profile/config.reference.yaml"
copy_if_exists "${PROFILE_HOME}/SOUL.md" "${BUNDLE_DIR}/profile/SOUL.rendered.md"
copy_if_exists "${PROFILE_HOME}/ENVIRONMENT.md" "${BUNDLE_DIR}/profile/ENVIRONMENT.rendered.md"
copy_if_exists "${PROFILE_HOME}/hindsight/config.json" "${BUNDLE_DIR}/profile/hindsight.config.json"
copy_if_exists "${PROFILE_HOME}/home/.gitconfig" "${BUNDLE_DIR}/profile/gitconfig.include"
generate_env_template "${PROFILE_HOME}/.env" "${BUNDLE_DIR}/profile/.env.template"

copy_if_exists "${HERMES_HOME}/shared/soul/base.md" "${BUNDLE_DIR}/shared/soul/base.md"
copy_if_exists "${HERMES_HOME}/shared/soul/profiles/${PROFILE}.md" "${BUNDLE_DIR}/shared/soul/profiles/${PROFILE}.md"

LATEST_TARBALL="$(find "${SYNC_ROOT}/backups" -maxdepth 1 -type f -name '*.tar.gz' | sort | tail -n1 || true)"
LATEST_HINDSIGHT_DUMP="$(find "${SYNC_ROOT}/backups/hindsight" -maxdepth 1 -type f -name '*.sql' | sort | tail -n1 || true)"

python3 - <<'PY' "${BUNDLE_DIR}/manifest.json" "${PROFILE}" "${ENV_ID}" "${SERVICE_MODE}" "${PROFILE_HOME}" "${ARCHIVE_PATH}" "${LATEST_TARBALL}" "${LATEST_HINDSIGHT_DUMP}" "${SYNC_ROOT}"
from pathlib import Path
import json
import os
import sys
from datetime import datetime, timezone
manifest_path = Path(sys.argv[1])
payload = {
    'profile': sys.argv[2],
    'bank_id': f'hermes-{sys.argv[2]}',
    'source_env_id': sys.argv[3],
    'service_mode': sys.argv[4],
    'profile_home': sys.argv[5],
    'archive_path': sys.argv[6],
    'latest_state_snapshot': sys.argv[7] or None,
    'latest_hindsight_dump': sys.argv[8] or None,
    'sync_root': sys.argv[9],
    'exported_at': datetime.now(timezone.utc).isoformat(),
    'exported_by_user': os.environ.get('USER') or os.environ.get('USERNAME') or 'unknown',
}
manifest_path.write_text(json.dumps(payload, indent=2, sort_keys=True) + '\n')
PY

printf '%s\n' "${LATEST_TARBALL}" > "${BUNDLE_DIR}/references/latest-state-snapshot.txt"
printf '%s\n' "${LATEST_HINDSIGHT_DUMP}" > "${BUNDLE_DIR}/references/latest-hindsight-dump.txt"

mkdir -p "$(dirname "${ARCHIVE_PATH}")"
tar -C "${BUNDLE_DIR}" -czf "${ARCHIVE_PATH}" .

echo "Exported profile bundle: ${ARCHIVE_PATH}"
