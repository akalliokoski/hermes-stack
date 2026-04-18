#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(dirname "${SCRIPT_DIR}")"
CONFIG_RENDERER="${REPO_ROOT}/scripts/render-config.py"

ENV_ID="${HERMES_ENV_ID:-}"
SERVICE_MODE="${HERMES_SERVICE_MODE:-auto}"
HERMES_HOME="${HERMES_HOME:-$HOME/.hermes}"
TARGET_HOME="$(dirname "${HERMES_HOME}")"
ALL_PROFILES=0
PROFILE="default"
CHECK_SERVICES=0
STRICT=0

usage() {
  cat <<'EOF'
Usage:
  scripts/verify-environment.sh [--profile <name> | --all-profiles]
                                [--service-mode auto|local|remote]
                                [--check-services] [--strict]

Checks:
  - rendered config.yaml / ENVIRONMENT.md / SOUL.md presence
  - shared skills wiring in config.yaml
  - Hindsight bank_id and api_url for each profile
  - selected service endpoints for the current environment
EOF
}

log() { printf '%s\n' "$*"; }
warn() { printf 'WARN: %s\n' "$*" >&2; }
die() { printf 'ERROR: %s\n' "$*" >&2; exit 1; }

while [[ $# -gt 0 ]]; do
  case "$1" in
    --env-id)
      ENV_ID="${2:?missing env id}"
      shift 2
      ;;
    --service-mode)
      SERVICE_MODE="${2:?missing service mode}"
      shift 2
      ;;
    --profile)
      PROFILE="${2:?missing profile}"
      shift 2
      ;;
    --all-profiles)
      ALL_PROFILES=1
      shift
      ;;
    --check-services)
      CHECK_SERVICES=1
      shift
      ;;
    --strict)
      STRICT=1
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

if [[ -z "${ENV_ID}" ]]; then
  ENV_ID="$(bash "${REPO_ROOT}/scripts/detect-env.sh" --repo-root "${REPO_ROOT}")"
fi

bash "${REPO_ROOT}/scripts/ensure-python-yaml.sh" >/dev/null

SHARED_SKILLS_ROOT="${HERMES_HOME}/shared/skills"
SYNC_ROOT="$(python3 "${CONFIG_RENDERER}" --repo-root "${REPO_ROOT}" --env-id "${ENV_ID}" --target-home "${TARGET_HOME}" --print-meta env.sync_root)"

profiles=("${PROFILE}")
if [[ ${ALL_PROFILES} -eq 1 ]]; then
  profiles=(default)
  if [[ -d "${HERMES_HOME}/profiles" ]]; then
    while IFS= read -r path; do
      profiles+=("$(basename "$path")")
    done < <(find "${HERMES_HOME}/profiles" -mindepth 1 -maxdepth 1 -type d | sort)
  fi
fi

python3 - "${REPO_ROOT}" "${ENV_ID}" "${HERMES_HOME}" "${SHARED_SKILLS_ROOT}" "${SYNC_ROOT}" "${SERVICE_MODE}" "${STRICT}" "${profiles[@]}" <<'PY'
import json
import os
import sys
from pathlib import Path

import yaml

repo_root = Path(sys.argv[1])
env_id = sys.argv[2]
hermes_home = Path(sys.argv[3])
shared_skills_root = sys.argv[4]
sync_root = Path(sys.argv[5])
service_mode = sys.argv[6]
strict = sys.argv[7] == '1'
profiles = sys.argv[8:]

failures = []


def profile_home(profile: str) -> Path:
    return hermes_home if profile == 'default' else hermes_home / 'profiles' / profile

for profile in profiles:
    home = profile_home(profile)
    config_path = home / 'config.yaml'
    env_path = home / 'ENVIRONMENT.md'
    soul_path = home / 'SOUL.md'
    hindsight_path = home / 'hindsight' / 'config.json'
    gitconfig_path = home / 'home' / '.gitconfig'

    if not home.exists():
        failures.append(f"profile home missing for {profile}: {home}")
        continue

    for path in (config_path, env_path, soul_path, hindsight_path, gitconfig_path):
        if not path.exists():
            failures.append(f"missing {path}")

    if config_path.exists():
        config = yaml.safe_load(config_path.read_text()) or {}
        skills = config.get('skills') or {}
        external_dirs = skills.get('external_dirs') or []
        if isinstance(external_dirs, str):
            external_dirs = [external_dirs]
        if shared_skills_root not in [str(x) for x in external_dirs]:
            failures.append(f"shared skills path missing from {config_path}")

    if hindsight_path.exists():
        payload = json.loads(hindsight_path.read_text())
        expected_bank = f"hermes-{profile}"
        if payload.get('bank_id') != expected_bank:
            failures.append(f"unexpected bank_id for {profile}: {payload.get('bank_id')} != {expected_bank}")
        if not payload.get('api_url'):
            failures.append(f"missing hindsight api_url for {profile}")

    if env_path.exists():
        rendered = env_path.read_text()
        if f'Environment ID: `{env_id}`' not in rendered:
            failures.append(f"ENVIRONMENT.md for {profile} does not mention env_id {env_id}")
        if f'Service mode preference: `{service_mode}`' not in rendered:
            failures.append(f"ENVIRONMENT.md for {profile} does not mention service mode {service_mode}")

if not sync_root.exists():
    failures.append(f"sync_root missing: {sync_root}")
else:
    for rel in ('backups', 'backups/hindsight', 'exports', 'envs'):
        path = sync_root / rel
        if not path.exists():
            failures.append(f"sync_root subdir missing: {path}")

if failures:
    print('Verification failed:')
    for failure in failures:
        print(f' - {failure}')
    raise SystemExit(1)

print(f'Verified {len(profiles)} profile(s) for env={env_id} service_mode={service_mode}')
for profile in profiles:
    print(f' - {profile}')
PY

log "✓ Profile wiring verified"

if [[ ${CHECK_SERVICES} -eq 1 ]]; then
  while IFS= read -r service; do
    [[ -n "${service}" ]] || continue
    url="$(python3 "${CONFIG_RENDERER}" --repo-root "${REPO_ROOT}" --env-id "${ENV_ID}" --target-home "${TARGET_HOME}" --print-service-url "${service}" --service-mode "${SERVICE_MODE}")"
    log "• ${service} => ${url}"
    if command -v curl >/dev/null 2>&1; then
      if curl -fsSIL --max-time 10 "${url}" >/dev/null 2>&1 || curl -fsS --max-time 10 "${url}" >/dev/null 2>&1; then
        log "  ✓ reachable"
      else
        if [[ ${STRICT} -eq 1 ]]; then
          die "service check failed for ${service}: ${url}"
        fi
        warn "service check failed for ${service}: ${url}"
      fi
    else
      warn "curl not found; skipping reachability check for ${service}"
    fi
  done < <(python3 - "${REPO_ROOT}" "${ENV_ID}" <<'PY'
from pathlib import Path
import sys
import yaml
repo_root = Path(sys.argv[1])
env_id = sys.argv[2]
manifest = yaml.safe_load((repo_root / 'config' / 'env' / f'{env_id}.yaml').read_text()) or {}
services = (manifest.get('env') or {}).get('services') or {}
for name in sorted(services):
    if name == 'tailscale':
        continue
    print(name)
PY
)
fi

log "Environment verification complete."
