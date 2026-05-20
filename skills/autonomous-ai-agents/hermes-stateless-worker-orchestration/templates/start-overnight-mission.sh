#!/usr/bin/env bash
set -euo pipefail

usage() {
  cat <<'EOF'
Usage:
  start-overnight-mission.sh [options] <mission-dir> <session-name>

Options:
  --profile NAME                   Hermes profile name (default: $HERMES_PROFILE or default)
  --goal-file PATH                 Use an existing goal file instead of creating mission-dir/goal.txt
  --tmux-session NAME              tmux session name (default: <session-name>)
  --rate-limit-mode MODE           fallback | wait | wait-429 (default: fallback)
  --rate-limit-sleep-seconds N     Sleep after a rate-limit in wait/wait-429 mode (default: 300)
  --sleep-seconds N                Normal sleep between passes (default: 10)
  --max-turns N                    Hermes max turns per pass (default: 120)
  --stop-on-mode-stop              Exit loop when handoff says recommended next mode: stop
  -h, --help                       Show this help

Creates if missing:
  <mission-dir>/handoff.md
  <mission-dir>/goal.txt
  <mission-dir>/overnight.log
EOF
}

PROFILE="${HERMES_PROFILE:-default}"
GOAL_FILE=""
TMUX_SESSION=""
RATE_LIMIT_MODE="fallback"
RATE_LIMIT_SLEEP_SECONDS=300
SLEEP_SECONDS=10
MAX_TURNS=120
STOP_ON_MODE_STOP=0

POSITIONAL=()
while [ $# -gt 0 ]; do
  case "$1" in
    --profile)
      PROFILE="${2:?missing value for --profile}"
      shift 2
      ;;
    --goal-file)
      GOAL_FILE="${2:?missing value for --goal-file}"
      shift 2
      ;;
    --tmux-session)
      TMUX_SESSION="${2:?missing value for --tmux-session}"
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
    --sleep-seconds)
      SLEEP_SECONDS="${2:?missing value for --sleep-seconds}"
      shift 2
      ;;
    --max-turns)
      MAX_TURNS="${2:?missing value for --max-turns}"
      shift 2
      ;;
    --stop-on-mode-stop)
      STOP_ON_MODE_STOP=1
      shift
      ;;
    -h|--help)
      usage
      exit 0
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

MISSION_DIR="$1"
SESSION_NAME="$2"
TMUX_SESSION="${TMUX_SESSION:-$SESSION_NAME}"

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
HANDOFF_TEMPLATE="$SCRIPT_DIR/overnight-handoff.md"
LOOP_SCRIPT="$SCRIPT_DIR/run-overnight-loop.sh"

mkdir -p "$MISSION_DIR"
HANDOFF_FILE="$MISSION_DIR/handoff.md"
LOG_FILE="$MISSION_DIR/overnight.log"

if [ ! -f "$HANDOFF_FILE" ]; then
  cp "$HANDOFF_TEMPLATE" "$HANDOFF_FILE"
fi

if [ -z "$GOAL_FILE" ]; then
  GOAL_FILE="$MISSION_DIR/goal.txt"
  if [ ! -f "$GOAL_FILE" ]; then
    : > "$GOAL_FILE"
  fi
fi

CMD=("$LOOP_SCRIPT" --profile "$PROFILE" --rate-limit-mode "$RATE_LIMIT_MODE" --rate-limit-sleep-seconds "$RATE_LIMIT_SLEEP_SECONDS" --sleep-seconds "$SLEEP_SECONDS" --max-turns "$MAX_TURNS" --log-file "$LOG_FILE")
if [ "$STOP_ON_MODE_STOP" -eq 1 ]; then
  CMD+=(--stop-on-mode-stop)
fi
CMD+=("$SESSION_NAME" "$HANDOFF_FILE" "$GOAL_FILE")

printf 'Starting tmux session %s\n' "$TMUX_SESSION"
printf 'Mission dir: %s\n' "$MISSION_DIR"
printf 'Profile: %s\n' "$PROFILE"
printf 'Rate limit mode: %s\n' "$RATE_LIMIT_MODE"
printf 'Handoff: %s\n' "$HANDOFF_FILE"
printf 'Goal: %s\n' "$GOAL_FILE"
printf 'Log: %s\n' "$LOG_FILE"

if tmux has-session -t "$TMUX_SESSION" 2>/dev/null; then
  echo "tmux session already exists: $TMUX_SESSION" >&2
  exit 1
fi

tmux new-session -d -s "$TMUX_SESSION" "$(printf '%q ' "${CMD[@]}")"

echo "Attached later with: tmux attach -t $TMUX_SESSION"
