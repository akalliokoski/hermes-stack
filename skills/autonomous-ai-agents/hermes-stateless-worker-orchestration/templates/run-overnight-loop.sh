#!/usr/bin/env bash
set -euo pipefail

usage() {
  cat <<'EOF'
Usage:
  run-overnight-loop.sh [options] <session-name> <handoff-file> [goal-file]

Options:
  --profile NAME                   Hermes profile name (default: $HERMES_PROFILE or default)
  --sleep-seconds N                Normal sleep between passes (default: 10)
  --max-turns N                    Hermes max turns per bounded pass (default: 120)
  --rate-limit-mode MODE           fallback | wait | wait-429 (default: fallback)
  --rate-limit-sleep-seconds N     Sleep after a rate-limit in wait/wait-429 mode (default: 300)
  --stop-on-mode-stop              Exit when handoff contains 'recommended next mode: stop'
  --log-file PATH                  Append pass output to this log file
  -h, --help                       Show this help

Behavior:
  fallback  -> use the profile's normal config, including fallback_providers
  wait      -> alias for wait-429 (kept for backward compatibility)
  wait-429  -> first try with fallback_providers removed so a 429 waits for the
               primary model instead of switching immediately; if the failure
               looks like billing/auth/model-not-found instead of 429, rerun
               once with normal fallback_providers enabled
EOF
}

PROFILE="${HERMES_PROFILE:-default}"
SLEEP_SECONDS=10
MAX_TURNS=120
RATE_LIMIT_MODE="fallback"
RATE_LIMIT_SLEEP_SECONDS=300
STOP_ON_MODE_STOP=0
LOG_FILE=""

POSITIONAL=()
while [ $# -gt 0 ]; do
  case "$1" in
    --profile)
      PROFILE="${2:?missing value for --profile}"
      shift 2
      ;;
    --sleep-seconds)
      SLEEP_SECONDS="${2:?missing value for --sleep-seconds}"
      shift 2
      ;;
    --max-turns)
      MAX_TURNS="${2:?missing value for --max-turns}"
      shift 2
      ;;
    --rate-limit-mode)
      RATE_LIMIT_MODE="${2:?missing value for --rate-limit-mode}"
      shift 2
      ;;
    --rate-limit-sleep-seconds)
      RATE_LIMIT_SLEEP_SECONDS="${2:?missing value for --rate-limit-sleep-seconds}"
      shift 2
      ;;
    --stop-on-mode-stop)
      STOP_ON_MODE_STOP=1
      shift
      ;;
    --log-file)
      LOG_FILE="${2:?missing value for --log-file}"
      shift 2
      ;;
    -h|--help)
      usage
      exit 0
      ;;
    --)
      shift
      while [ $# -gt 0 ]; do POSITIONAL+=("$1"); shift; done
      ;;
    -*)
      echo "Unknown option: $1" >&2
      usage >&2
      exit 1
      ;;
    *)
      POSITIONAL+=("$1")
      shift
      ;;
  esac
done

set -- "${POSITIONAL[@]}"
if [ $# -lt 2 ]; then
  usage >&2
  exit 1
fi

SESSION_NAME="$1"
HANDOFF_FILE="$2"
GOAL_FILE="${3:-}"

case "$RATE_LIMIT_MODE" in
  fallback|wait|wait-429) ;;
  *)
    echo "Invalid --rate-limit-mode: $RATE_LIMIT_MODE" >&2
    exit 1
    ;;
esac

if [ "$RATE_LIMIT_MODE" = "wait" ]; then
  RATE_LIMIT_MODE="wait-429"
fi

if [ ! -f "$HANDOFF_FILE" ]; then
  echo "Missing handoff file: $HANDOFF_FILE" >&2
  exit 1
fi

if [ -n "$GOAL_FILE" ] && [ ! -f "$GOAL_FILE" ]; then
  echo "Missing goal file: $GOAL_FILE" >&2
  exit 1
fi

GOAL_TEXT=""
if [ -n "$GOAL_FILE" ]; then
  GOAL_TEXT="$(cat "$GOAL_FILE")"
fi

USER_HOME="$(getent passwd "$(id -un)" | cut -d: -f6)"
if [ -z "$USER_HOME" ]; then
  USER_HOME="$HOME"
fi

BASE_HERMES_HOME="$USER_HOME/.hermes"
if [ "$PROFILE" = "default" ] || [ -z "$PROFILE" ]; then
  ACTUAL_HERMES_HOME="$BASE_HERMES_HOME"
else
  ACTUAL_HERMES_HOME="$BASE_HERMES_HOME/profiles/$PROFILE"
fi

if [ ! -d "$ACTUAL_HERMES_HOME" ]; then
  echo "Missing Hermes home for profile '$PROFILE': $ACTUAL_HERMES_HOME" >&2
  exit 1
fi

mkdir -p "$(dirname "$HANDOFF_FILE")"
if [ -n "$LOG_FILE" ]; then
  mkdir -p "$(dirname "$LOG_FILE")"
fi

should_stop_from_handoff() {
  [ "$STOP_ON_MODE_STOP" -eq 1 ] || return 1
  python3 - "$HANDOFF_FILE" <<'PY'
import re, sys
path = sys.argv[1]
text = open(path, encoding='utf-8').read()
match = re.search(r"^\s*recommended\s+next\s+mode\s*:\s*(\w+)\s*$", text, re.I | re.M)
if match and match.group(1).strip().lower() == "stop":
    raise SystemExit(0)
raise SystemExit(1)
PY
}

make_runtime_home() {
  local runtime_home="$1"
  local actual_home="$2"
  local rate_mode="$3"

  if [ "$rate_mode" = "fallback" ]; then
    printf '%s\n' "$actual_home"
    return 0
  fi

  python3 - "$actual_home" "$runtime_home" <<'PY'
import os
import shutil
import sys
from pathlib import Path

import yaml

actual = Path(sys.argv[1]).expanduser().resolve()
runtime = Path(sys.argv[2]).expanduser().resolve()
runtime.mkdir(parents=True, exist_ok=True)

for child in actual.iterdir():
    if child.name == 'config.yaml':
        continue
    target = runtime / child.name
    try:
        if target.exists() or target.is_symlink():
            if target.is_dir() and not target.is_symlink():
                shutil.rmtree(target)
            else:
                target.unlink()
    except FileNotFoundError:
        pass
    target.symlink_to(child, target_is_directory=child.is_dir())

config_path = actual / 'config.yaml'
if config_path.exists():
    cfg = yaml.safe_load(config_path.read_text(encoding='utf-8')) or {}
else:
    cfg = {}
cfg.pop('fallback_providers', None)
cfg.pop('fallback_model', None)
runtime.joinpath('config.yaml').write_text(yaml.safe_dump(cfg, sort_keys=False), encoding='utf-8')
PY

  printf '%s\n' "$runtime_home"
}

is_rate_limit_output() {
  local text_file="$1"
  python3 - "$text_file" <<'PY'
import re, sys
text = open(sys.argv[1], encoding='utf-8', errors='ignore').read().lower()
patterns = [
    r'rate[ -]?limit',
    r'too many requests',
    r'throttl',
    r'resource_exhausted',
    r'please wait',
    r'try again in',
    r'usage limit has been reached',
    r'429',
]
if any(re.search(p, text) for p in patterns):
    raise SystemExit(0)
raise SystemExit(1)
PY
}

is_fallback_worthy_output() {
  local text_file="$1"
  python3 - "$text_file" <<'PY'
import re, sys
text = open(sys.argv[1], encoding='utf-8', errors='ignore').read().lower()
patterns = [
    r'payment required',
    r'insufficient[_ ]quota',
    r'insufficient credits',
    r'credit balance',
    r'billing hard limit',
    r'authentication',
    r'unauthorized',
    r'forbidden',
    r'invalid api key',
    r'invalid token',
    r'token expired',
    r'model not found',
    r'invalid model',
    r'unsupported model',
    r'no such model',
    r'does not exist',
    r'404',
    r'401',
    r'402',
    r'403',
]
if any(re.search(p, text) for p in patterns):
    raise SystemExit(0)
raise SystemExit(1)
PY
}

run_pass() {
  local effective_home="$1"
  local output_file="$2"
  local prompt="$3"
  set +e
  HERMES_HOME="$effective_home" hermes chat \
    --skills hermes-stateless-worker-orchestration \
    --max-turns "$MAX_TURNS" \
    --quiet \
    -q "$prompt" >"$output_file" 2>&1
  local exit_code=$?
  set -e
  return "$exit_code"
}

PASS_COUNT=0
while true; do
  if should_stop_from_handoff; then
    echo "Stopping because handoff requested: recommended next mode: stop"
    break
  fi

  PASS_COUNT=$((PASS_COUNT + 1))
  RUNTIME_HOME="$(mktemp -d)"
  OUTPUT_FILE="$(mktemp)"
  cleanup() {
    rm -f "$OUTPUT_FILE"
    rm -rf "$RUNTIME_HOME"
  }
  trap cleanup EXIT

  PROMPT="Read '$HANDOFF_FILE' first. ${GOAL_TEXT:+Overall goal: $GOAL_TEXT }Then continue the mission using the overnight bounded-pass pattern from the hermes-stateless-worker-orchestration skill. Do one meaningful chunk of work. Before ending, update '$HANDOFF_FILE' with status, artifacts changed, blockers, next exact action, and recommended next mode."

  echo "[$(date -Is)] pass=$PASS_COUNT profile=$PROFILE mode=$RATE_LIMIT_MODE session=$SESSION_NAME"

  PRIMARY_HOME="$ACTUAL_HERMES_HOME"
  if [ "$RATE_LIMIT_MODE" = "wait-429" ]; then
    PRIMARY_HOME="$(make_runtime_home "$RUNTIME_HOME" "$ACTUAL_HERMES_HOME" "$RATE_LIMIT_MODE")"
  fi

  EXIT_CODE=0
  run_pass "$PRIMARY_HOME" "$OUTPUT_FILE" "$PROMPT" || EXIT_CODE=$?

  cat "$OUTPUT_FILE"
  if [ -n "$LOG_FILE" ]; then
    {
      echo "[$(date -Is)] pass=$PASS_COUNT exit=$EXIT_CODE profile=$PROFILE mode=$RATE_LIMIT_MODE attempt=primary"
      cat "$OUTPUT_FILE"
      echo
    } >> "$LOG_FILE"
  fi

  if [ "$RATE_LIMIT_MODE" = "wait-429" ] && is_rate_limit_output "$OUTPUT_FILE"; then
    echo "429-like rate limit detected in wait-429 mode. Sleeping $RATE_LIMIT_SLEEP_SECONDS seconds before retrying the primary model."
    cleanup
    trap - EXIT
    sleep "$RATE_LIMIT_SLEEP_SECONDS"
    continue
  fi

  if [ "$RATE_LIMIT_MODE" = "wait-429" ] && [ "$EXIT_CODE" -ne 0 ] && is_fallback_worthy_output "$OUTPUT_FILE"; then
    echo "Non-429 failure looks fallback-worthy. Re-running this pass once with normal fallback providers enabled."
    : > "$OUTPUT_FILE"
    FALLBACK_EXIT=0
    run_pass "$ACTUAL_HERMES_HOME" "$OUTPUT_FILE" "$PROMPT" || FALLBACK_EXIT=$?
    cat "$OUTPUT_FILE"
    if [ -n "$LOG_FILE" ]; then
      {
        echo "[$(date -Is)] pass=$PASS_COUNT exit=$FALLBACK_EXIT profile=$PROFILE mode=fallback attempt=rerun-after-wait-429"
        cat "$OUTPUT_FILE"
        echo
      } >> "$LOG_FILE"
    fi
  fi

  cleanup
  trap - EXIT
  sleep "$SLEEP_SECONDS"
done
