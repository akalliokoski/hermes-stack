#!/usr/bin/env bash
set -euo pipefail

HERMES_USER="${HERMES_USER:-hermes}"
HERMES_WEBUI_REPO_URL="${HERMES_WEBUI_REPO_URL:-https://github.com/nesquena/hermes-webui.git}"
HERMES_WEBUI_REF="${HERMES_WEBUI_REF:-latest-release}"
HERMES_WEBUI_INSTALL_DIR="${HERMES_WEBUI_INSTALL_DIR:-/opt/hermes-webui}"

log() {
  printf '%s\n' "$*"
}

resolve_requested_ref() {
  local requested_ref="$1"
  if [[ "$requested_ref" != "latest-release" ]]; then
    printf '%s\n' "$requested_ref"
    return 0
  fi

  local resolved_tag
  resolved_tag="$(run_as_hermes bash -lc '
    set -euo pipefail
    git -C "'"${HERMES_WEBUI_INSTALL_DIR}"'" tag --list "v*" --sort=-version:refname | head -n 1
  ')"

  if [[ -z "$resolved_tag" ]]; then
    echo "ERROR: unable to resolve latest Hermes WebUI release tag from ${HERMES_WEBUI_REPO_URL}" >&2
    exit 1
  fi

  printf '%s\n' "$resolved_tag"
}

run_as_hermes() {
  if [[ "$(id -un)" == "${HERMES_USER}" ]]; then
    "$@"
  else
    sudo -iu "${HERMES_USER}" "$@"
  fi
}

if ! command -v git >/dev/null 2>&1; then
  echo "ERROR: git is required to install Hermes WebUI" >&2
  exit 1
fi

install_root="$(dirname "${HERMES_WEBUI_INSTALL_DIR}")"
install -d -o "${HERMES_USER}" -g "${HERMES_USER}" -m 755 "${install_root}"

if [[ ! -d "${HERMES_WEBUI_INSTALL_DIR}/.git" ]]; then
  log "→ Cloning Hermes WebUI into ${HERMES_WEBUI_INSTALL_DIR}"
  run_as_hermes git clone "${HERMES_WEBUI_REPO_URL}" "${HERMES_WEBUI_INSTALL_DIR}"
else
  log "→ Refreshing Hermes WebUI checkout in ${HERMES_WEBUI_INSTALL_DIR}"
fi

run_as_hermes git -C "${HERMES_WEBUI_INSTALL_DIR}" remote set-url origin "${HERMES_WEBUI_REPO_URL}"
run_as_hermes git -C "${HERMES_WEBUI_INSTALL_DIR}" fetch --tags --prune origin
resolved_target_ref="$(resolve_requested_ref "${HERMES_WEBUI_REF}")"
log "→ Resolving Hermes WebUI ref ${HERMES_WEBUI_REF} -> ${resolved_target_ref}"
run_as_hermes git -C "${HERMES_WEBUI_INSTALL_DIR}" fetch --depth 1 origin "${resolved_target_ref}"
run_as_hermes git -C "${HERMES_WEBUI_INSTALL_DIR}" checkout --force FETCH_HEAD

resolved_ref="$(run_as_hermes git -C "${HERMES_WEBUI_INSTALL_DIR}" rev-parse --short HEAD)"
resolved_version="$(run_as_hermes git -C "${HERMES_WEBUI_INSTALL_DIR}" describe --tags --always --dirty 2>/dev/null || true)"
log "✓ Hermes WebUI checkout ready at ${resolved_ref} (${resolved_version:-no-tag})"

run_as_hermes bash -lc '
  set -euo pipefail
  export PATH="$HOME/.local/bin:$PATH"
  HERMES_BIN="$(command -v hermes)"
  HERMES_PY="$(head -n 1 "$HERMES_BIN" | sed "s/^#!//")"
  uv pip install --python "$HERMES_PY" --quiet --upgrade -r "'"${HERMES_WEBUI_INSTALL_DIR}"'"/requirements.txt
'

log "✓ Hermes WebUI Python dependencies installed into the Hermes runtime"
