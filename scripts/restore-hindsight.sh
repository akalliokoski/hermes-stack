#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(dirname "${SCRIPT_DIR}")"
CONFIG_RENDERER="${REPO_ROOT}/scripts/render-config.py"

ENV_ID="${HERMES_ENV_ID:-}"
SERVICE_MODE="${HERMES_SERVICE_MODE:-auto}"
TARGET_HOME="$(dirname "${HERMES_HOME:-$HOME/.hermes}")"
COMPOSE_CMD=(docker compose -f "${REPO_ROOT}/docker-compose.yml" -f "${REPO_ROOT}/docker-compose.vps.yml")

usage() {
  cat <<'EOF'
Usage:
  scripts/restore-hindsight.sh list
  scripts/restore-hindsight.sh validate-bank <bank_id>
  scripts/restore-hindsight.sh restore-db <dump.sql>

Notes:
  - list: shows synced SQL dumps under <sync_root>/backups/hindsight
  - validate-bank: fetches /v1/default/banks/<bank>/stats from the selected hindsight endpoint
  - restore-db: maintenance operation that drops/recreates the hindsight DB inside the running container and pipes the SQL dump into psql
EOF
}

die() {
  printf 'ERROR: %s\n' "$*" >&2
  exit 1
}

if [[ -z "${ENV_ID}" ]]; then
  ENV_ID="$(bash "${REPO_ROOT}/scripts/detect-env.sh" --repo-root "${REPO_ROOT}")"
fi

SYNC_ROOT="$(python3 "${CONFIG_RENDERER}" --repo-root "${REPO_ROOT}" --env-id "${ENV_ID}" --target-home "${TARGET_HOME}" --print-meta env.sync_root)"
DUMP_ROOT="${SYNC_ROOT}/backups/hindsight"
HINDSIGHT_URL="$(python3 "${CONFIG_RENDERER}" --repo-root "${REPO_ROOT}" --env-id "${ENV_ID}" --target-home "${TARGET_HOME}" --print-service-url hindsight --service-mode "${SERVICE_MODE}")"

cmd="${1:-list}"
shift || true

case "${cmd}" in
  list)
    mkdir -p "${DUMP_ROOT}"
    find "${DUMP_ROOT}" -maxdepth 1 -type f -name '*.sql' -printf '%TY-%Tm-%Td %TH:%TM:%TS %p\n' | sort || true
    ;;

  validate-bank)
    bank_id="${1:-}"
    [[ -n "${bank_id}" ]] || die "Usage: restore-hindsight.sh validate-bank <bank_id>"
    python3 - <<'PY' "${HINDSIGHT_URL}" "${bank_id}"
import json
import sys
import urllib.error
import urllib.request
base = sys.argv[1].rstrip('/')
bank_id = sys.argv[2]
url = f"{base}/v1/default/banks/{bank_id}/stats"
try:
    with urllib.request.urlopen(url, timeout=15) as response:
        payload = json.load(response)
except urllib.error.HTTPError as exc:
    raise SystemExit(f"bank validation failed ({exc.code}) for {url}")
except Exception as exc:
    raise SystemExit(f"bank validation failed for {url}: {exc}")
print(json.dumps(payload, indent=2, sort_keys=True))
PY
    ;;

  restore-db)
    dump_path="${1:-}"
    [[ -n "${dump_path}" ]] || die "Usage: restore-hindsight.sh restore-db <dump.sql>"
    [[ -f "${dump_path}" ]] || die "Dump not found: ${dump_path}"
    container_id="$(${COMPOSE_CMD[@]} ps -q hindsight)"
    [[ -n "${container_id}" ]] || die "Could not find running hindsight container"

    echo "→ Restoring Hindsight DB from ${dump_path}"
    docker exec "${container_id}" psql -v ON_ERROR_STOP=1 -U hindsight postgres <<'SQL'
SELECT pg_terminate_backend(pid)
FROM pg_stat_activity
WHERE datname = 'hindsight' AND pid <> pg_backend_pid();
DROP DATABASE IF EXISTS hindsight;
CREATE DATABASE hindsight;
SQL
    cat "${dump_path}" | docker exec -i "${container_id}" psql -v ON_ERROR_STOP=1 -U hindsight hindsight
    echo "✓ Restore completed"
    ;;

  -h|--help)
    usage
    ;;

  *)
    die "Unknown command: ${cmd}"
    ;;
esac
