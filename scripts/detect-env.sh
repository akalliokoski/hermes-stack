#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(dirname "${SCRIPT_DIR}")"
ENV_DIR="${REPO_ROOT}/config/env"

if [[ "${1:-}" == "--repo-root" ]]; then
  REPO_ROOT="${2:?missing repo root}"
  ENV_DIR="${REPO_ROOT}/config/env"
  shift 2
fi

if [[ -n "${HERMES_ENV_ID:-}" ]]; then
  printf '%s\n' "${HERMES_ENV_ID}"
  exit 0
fi

HOSTNAME_SHORT="$(hostname -s 2>/dev/null || hostname 2>/dev/null || true)"
UNAME_S="$(uname -s)"

if [[ -f "${ENV_DIR}/${HOSTNAME_SHORT}.yaml" ]]; then
  printf '%s\n' "${HOSTNAME_SHORT}"
  exit 0
fi

case "${UNAME_S}" in
  Darwin)
    if [[ -f "${ENV_DIR}/macbook.yaml" ]]; then
      printf '%s\n' "macbook"
      exit 0
    fi
    ;;
  Linux)
    if [[ -f /opt/hermes/docker-compose.yml || -d /home/hermes/.hermes || "${HOSTNAME_SHORT}" == "vps" ]]; then
      if [[ -f "${ENV_DIR}/vps.yaml" ]]; then
        printf '%s\n' "vps"
        exit 0
      fi
    fi
    ;;
esac

printf 'ERROR: could not detect Hermes environment. Set HERMES_ENV_ID or add %s/<hostname>.yaml\n' "${ENV_DIR}" >&2
exit 1
