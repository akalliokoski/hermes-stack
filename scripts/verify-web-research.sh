#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(dirname "${SCRIPT_DIR}")"
USER_HOME="$(getent passwd "$(id -un)" | cut -d: -f6)"
HERMES_BASE_HOME="${HERMES_BASE_HOME:-$USER_HOME/.hermes}"
HERMES_AGENT_ROOT="${HERMES_AGENT_ROOT:-$HERMES_BASE_HOME/hermes-agent}"
HERMES_PYTHON="${HERMES_PYTHON:-$HERMES_AGENT_ROOT/venv/bin/python}"

BUSINESS_QUERY="${BUSINESS_QUERY:-Business Finland Sprint funding 2026}"
REGULATORY_QUERY="${REGULATORY_QUERY:-Findata secondary use health data Finland permit}"
EXTRACT_URL="${EXTRACT_URL:-https://www.businessfinland.fi/en/services/funding}"

list_profiles() {
  local profiles_dir="$HERMES_BASE_HOME/profiles"
  python3 - "$HERMES_BASE_HOME" "$profiles_dir" <<'PY'
from pathlib import Path
import sys
base_home = Path(sys.argv[1])
profiles_dir = Path(sys.argv[2])
if (base_home / '.env').exists():
    print('default')
if profiles_dir.is_dir():
    for child in sorted(profiles_dir.iterdir()):
        if child.is_dir() and (child / '.env').exists():
            print(child.name)
PY
}

usage() {
  cat <<'EOF'
Usage:
  scripts/verify-web-research.sh [--profile <name>] [--all-profiles]

Runs profile-scoped Hermes web_search/web_extract checks without printing secrets.
Checks:
  - Business Finland current-facts search query returns at least one result
  - Regulatory current-facts search query returns at least one result
  - Firecrawl extraction of a known Business Finland page returns non-empty content

Environment overrides:
  HERMES_BASE_HOME   Base Hermes home (default: ~/.hermes)
  HERMES_AGENT_ROOT  Hermes Agent checkout with venv (default: $HERMES_BASE_HOME/hermes-agent)
  HERMES_PYTHON      Python executable for Hermes Agent venv
  BUSINESS_QUERY     Override the funding query
  REGULATORY_QUERY   Override the regulatory query
  EXTRACT_URL        Override the extraction URL
EOF
}

selected_profiles=()
while [[ $# -gt 0 ]]; do
  case "$1" in
    --profile)
      selected_profiles+=("${2:?missing profile}")
      shift 2
      ;;
    --all-profiles)
      while IFS= read -r profile; do
        [[ -n "$profile" ]] && selected_profiles+=("$profile")
      done < <(list_profiles)
      shift
      ;;
    -h|--help)
      usage
      exit 0
      ;;
    *)
      echo "Unknown argument: $1" >&2
      usage >&2
      exit 1
      ;;
  esac
done

if [[ ${#selected_profiles[@]} -eq 0 ]]; then
  while IFS= read -r profile; do
    [[ -n "$profile" ]] && selected_profiles+=("$profile")
  done < <(list_profiles)
fi

if [[ ${#selected_profiles[@]} -eq 0 ]]; then
  echo "No profile directories with .env files found under $HERMES_BASE_HOME/profiles" >&2
  exit 1
fi

if [[ ! -x "$HERMES_PYTHON" ]]; then
  echo "Hermes Python not found or not executable: $HERMES_PYTHON" >&2
  exit 1
fi

status=0
for profile in "${selected_profiles[@]}"; do
  if [[ "$profile" == "default" ]]; then
    hermes_home="$HERMES_BASE_HOME"
  else
    hermes_home="$HERMES_BASE_HOME/profiles/$profile"
  fi
  env_path="$hermes_home/.env"

  if [[ ! -d "$hermes_home" ]]; then
    echo "[$profile] FAIL profile home missing: $hermes_home" >&2
    status=1
    continue
  fi
  if [[ ! -f "$env_path" ]]; then
    echo "[$profile] FAIL env missing: $env_path" >&2
    status=1
    continue
  fi

  tmp_json="$(mktemp)"
  (
    set -a
    # shellcheck disable=SC1090
    . "$env_path"
    set +a
    export HERMES_HOME="$hermes_home"
    export HERMES_AGENT_ROOT
    export PROFILE_NAME="$profile"
    export BUSINESS_QUERY REGULATORY_QUERY EXTRACT_URL TMP_JSON="$tmp_json"
    "$HERMES_PYTHON" - <<'PY'
import asyncio
import json
import os
import sys
from pathlib import Path

sys.path.insert(0, str(Path(os.environ.get("HERMES_AGENT_ROOT", Path.home() / ".hermes" / "hermes-agent"))))
from tools.web_tools import web_search_tool, web_extract_tool

profile = os.environ["PROFILE_NAME"]
queries = [
    ("business_finland", os.environ["BUSINESS_QUERY"]),
    ("regulatory", os.environ["REGULATORY_QUERY"]),
]
summary = {"profile": profile, "queries": {}, "extract": {"url": os.environ["EXTRACT_URL"]}}

for label, query in queries:
    raw = web_search_tool(query, limit=3)
    payload = json.loads(raw)
    results = ((payload.get("data") or {}).get("web") or []) if isinstance(payload, dict) else []
    first_url = ""
    if results:
        first = results[0] or {}
        first_url = first.get("url") or first.get("link") or ""
    summary["queries"][label] = {
        "query": query,
        "count": len(results),
        "first_url": first_url,
        "success": len(results) > 0,
        "error": payload.get("error") if isinstance(payload, dict) else None,
    }

async def main() -> None:
    raw = await web_extract_tool([os.environ["EXTRACT_URL"]], use_llm_processing=False)
    payload = json.loads(raw)
    results = payload.get("results") or []
    first = results[0] if results else {}
    content = first.get("content") or ""
    summary["extract"] = {
        "url": os.environ["EXTRACT_URL"],
        "title": first.get("title") or "",
        "content_length": len(content),
        "success": len(content.strip()) > 0,
        "error": first.get("error"),
    }

asyncio.run(main())
Path(os.environ["TMP_JSON"]).write_text(json.dumps(summary), encoding="utf-8")
PY
  )

  PROFILE_JSON="$tmp_json" "$HERMES_PYTHON" - <<'PY' || status=1
import json, os, sys
from pathlib import Path
summary = json.loads(Path(os.environ['PROFILE_JSON']).read_text())
profile = summary['profile']
q1 = summary['queries']['business_finland']
q2 = summary['queries']['regulatory']
extract = summary['extract']
print(f"[{profile}] business_finland={q1['count']} regulatory={q2['count']} extract_len={extract['content_length']}")
if q1['first_url']:
    print(f"  business_first={q1['first_url']}")
if q2['first_url']:
    print(f"  regulatory_first={q2['first_url']}")
if extract['title']:
    print(f"  extract_title={extract['title']}")
problems = []
if not q1['success']:
    problems.append('business_finland search returned 0 results')
if not q2['success']:
    problems.append('regulatory search returned 0 results')
if not extract['success']:
    problems.append('Firecrawl extract returned empty content')
if problems:
    for problem in problems:
        print(f"  FAIL {problem}")
    sys.exit(1)
print("  OK")
PY
  rm -f "$tmp_json"
done

exit "$status"
