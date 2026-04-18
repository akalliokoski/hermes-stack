#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(dirname "${SCRIPT_DIR}")"
CONFIG_RENDERER="${REPO_ROOT}/scripts/render-config.py"
PROVISION_SCRIPT="${REPO_ROOT}/scripts/provision-profile.sh"

ARCHIVE_PATH=""
PROFILE=""
ENV_ID="${HERMES_ENV_ID:-}"
SERVICE_MODE="${HERMES_SERVICE_MODE:-auto}"
GATEWAY_MODE="skip"
OVERWRITE_SHARED_BASE=0
RESTORE_ENV_TEMPLATE=1
HERMES_HOME="${HERMES_HOME:-$HOME/.hermes}"
TARGET_HOME="$(dirname "${HERMES_HOME}")"

usage() {
  cat <<'EOF'
Usage:
  scripts/import-profile.sh --archive <bundle.tar.gz> [--profile <name>]
                            [--service-mode auto|local|remote]
                            [--gateway auto|skip|required]
                            [--overwrite-shared-base] [--skip-env-template]

Import behavior:
  - unpacks a portable profile bundle created by scripts/export-profile.sh
  - restores shared/profile SOUL sources
  - rerenders config/hindsight/SOUL for the current machine via provision-profile.sh
  - writes a non-secret .env.template into the target profile home
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
    --archive)
      ARCHIVE_PATH="${2:?missing archive path}"
      shift 2
      ;;
    --profile)
      PROFILE="${2:?missing profile}"
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
    --gateway)
      GATEWAY_MODE="${2:?missing gateway mode}"
      shift 2
      ;;
    --overwrite-shared-base)
      OVERWRITE_SHARED_BASE=1
      shift
      ;;
    --skip-env-template)
      RESTORE_ENV_TEMPLATE=0
      shift
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

[[ -n "${ARCHIVE_PATH}" ]] || die "--archive is required"
[[ -f "${ARCHIVE_PATH}" ]] || die "Archive not found: ${ARCHIVE_PATH}"
if [[ -z "${ENV_ID}" ]]; then
  ENV_ID="$(bash "${REPO_ROOT}/scripts/detect-env.sh" --repo-root "${REPO_ROOT}")"
fi

bash "${REPO_ROOT}/scripts/ensure-python-yaml.sh" >/dev/null
WORK_ROOT="$(python3 "${CONFIG_RENDERER}" --repo-root "${REPO_ROOT}" --env-id "${ENV_ID}" --target-home "${TARGET_HOME}" --print-meta env.work_root)"
HINDSIGHT_API_URL="$(python3 "${CONFIG_RENDERER}" --repo-root "${REPO_ROOT}" --env-id "${ENV_ID}" --target-home "${TARGET_HOME}" --print-service-url hindsight --service-mode "${SERVICE_MODE}")"

TMP_DIR="$(mktemp -d)"
trap 'rm -rf "${TMP_DIR}"' EXIT

tar -C "${TMP_DIR}" -xzf "${ARCHIVE_PATH}"
MANIFEST_PATH="${TMP_DIR}/manifest.json"
[[ -f "${MANIFEST_PATH}" ]] || die "Bundle manifest missing from ${ARCHIVE_PATH}"

if [[ -z "${PROFILE}" ]]; then
  PROFILE="$(python3 - <<'PY' "${MANIFEST_PATH}"
import json, sys
print(json.load(open(sys.argv[1]))['profile'])
PY
)"
fi

PROFILE_HOME="$(profile_home "${PROFILE}")"
mkdir -p "${HERMES_HOME}/shared/soul/profiles" "${HERMES_HOME}/shared/skills" "${WORK_ROOT}/${PROFILE}"

if [[ -f "${TMP_DIR}/shared/soul/base.md" ]]; then
  if [[ ${OVERWRITE_SHARED_BASE} -eq 1 || ! -f "${HERMES_HOME}/shared/soul/base.md" ]]; then
    cp "${TMP_DIR}/shared/soul/base.md" "${HERMES_HOME}/shared/soul/base.md"
    echo "✓ Installed shared soul base"
  else
    echo "• Preserved existing shared soul base: ${HERMES_HOME}/shared/soul/base.md"
  fi
fi

if [[ -f "${TMP_DIR}/shared/soul/profiles/${PROFILE}.md" ]]; then
  cp "${TMP_DIR}/shared/soul/profiles/${PROFILE}.md" "${HERMES_HOME}/shared/soul/profiles/${PROFILE}.md"
  echo "✓ Installed profile soul override for ${PROFILE}"
fi

HERMES_ENV_ID="${ENV_ID}" \
HERMES_SERVICE_MODE="${SERVICE_MODE}" \
HERMES_HOME="${HERMES_HOME}" \
HERMES_USER="$(id -un)" \
WORK_ROOT="${WORK_ROOT}" \
HINDSIGHT_API_URL="${HINDSIGHT_API_URL}" \
bash "${PROVISION_SCRIPT}" --profile "${PROFILE}" --gateway "${GATEWAY_MODE}"

if [[ ${RESTORE_ENV_TEMPLATE} -eq 1 && -f "${TMP_DIR}/profile/.env.template" ]]; then
  mkdir -p "${PROFILE_HOME}"
  cp "${TMP_DIR}/profile/.env.template" "${PROFILE_HOME}/.env.template"
  echo "✓ Restored ${PROFILE_HOME}/.env.template"
fi

mkdir -p "${PROFILE_HOME}/imports/$(basename "${ARCHIVE_PATH}" .tar.gz)"
cp -f "${MANIFEST_PATH}" "${PROFILE_HOME}/imports/$(basename "${ARCHIVE_PATH}" .tar.gz)/manifest.json"
for file in config.reference.yaml SOUL.rendered.md ENVIRONMENT.rendered.md hindsight.config.json gitconfig.include; do
  if [[ -f "${TMP_DIR}/profile/${file}" ]]; then
    cp -f "${TMP_DIR}/profile/${file}" "${PROFILE_HOME}/imports/$(basename "${ARCHIVE_PATH}" .tar.gz)/${file}"
  fi
done

cat <<EOF
Imported profile bundle.
- Profile: ${PROFILE}
- Target env: ${ENV_ID}
- Service mode: ${SERVICE_MODE}
- Profile home: ${PROFILE_HOME}
- Workspace: ${WORK_ROOT}/${PROFILE}

Reference artifacts copied under:
  ${PROFILE_HOME}/imports/$(basename "${ARCHIVE_PATH}" .tar.gz)
EOF
