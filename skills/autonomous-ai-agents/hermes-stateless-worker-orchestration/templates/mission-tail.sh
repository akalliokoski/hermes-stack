#!/usr/bin/env bash
set -euo pipefail

usage() {
  cat <<'EOF'
Usage:
  mission-tail.sh [options] <mission-dir-or-log-file>

Options:
  -n, --lines N   Number of lines to show initially before following (default: 40)
  --no-follow     Print the tail and exit instead of following
  -h, --help      Show this help

Accepts either:
- a mission directory containing overnight.log
- a direct path to overnight.log
EOF
}

LINES=40
FOLLOW=1
POSITIONAL=()
while [ $# -gt 0 ]; do
  case "$1" in
    -n|--lines)
      LINES="${2:?missing value for $1}"
      shift 2
      ;;
    --no-follow)
      FOLLOW=0
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
if [ $# -ne 1 ]; then
  usage >&2
  exit 1
fi

INPUT="$1"
if [ -d "$INPUT" ]; then
  LOG_FILE="$INPUT/overnight.log"
else
  LOG_FILE="$INPUT"
fi

if [ ! -f "$LOG_FILE" ]; then
  echo "Missing log file: $LOG_FILE" >&2
  exit 1
fi

if [ "$FOLLOW" -eq 1 ]; then
  exec tail -n "$LINES" -f "$LOG_FILE"
else
  exec tail -n "$LINES" "$LOG_FILE"
fi
