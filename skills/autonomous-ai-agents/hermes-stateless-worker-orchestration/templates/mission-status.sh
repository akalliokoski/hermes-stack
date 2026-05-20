#!/usr/bin/env bash
set -euo pipefail

usage() {
  cat <<'EOF'
Usage:
  mission-status.sh <mission-dir-or-handoff-file>

Reads the mission handoff and prints a compact status summary:
- current status summary
- phase
- confidence
- blockers
- next exact action
- recommended next mode
- recent log tail when overnight.log exists
EOF
}

if [ $# -ne 1 ]; then
  usage >&2
  exit 1
fi

INPUT="$1"
if [ -d "$INPUT" ]; then
  HANDOFF_FILE="$INPUT/handoff.md"
  LOG_FILE="$INPUT/overnight.log"
else
  HANDOFF_FILE="$INPUT"
  LOG_FILE="$(dirname "$INPUT")/overnight.log"
fi

if [ ! -f "$HANDOFF_FILE" ]; then
  echo "Missing handoff file: $HANDOFF_FILE" >&2
  exit 1
fi

python3 - "$HANDOFF_FILE" "$LOG_FILE" <<'PY'
from pathlib import Path
import re
import sys

handoff = Path(sys.argv[1])
log_file = Path(sys.argv[2])
text = handoff.read_text(encoding='utf-8')


def section(name: str):
    pattern = rf"(?ms)^##\s+{re.escape(name)}\s*\n(.*?)(?=^##\s+|\Z)"
    m = re.search(pattern, text)
    return m.group(1).strip() if m else ""


def field(block: str, key: str):
    m = re.search(rf"(?im)^-\s*{re.escape(key)}\s*:\s*(.+)$", block)
    return m.group(1).strip() if m else ""

status = section("Current status")
blockers = section("Blockers")
next_action = section("Next exact action")

recommended = ""
m = re.search(r"(?im)^recommended\s+next\s+mode\s*:\s*(\S.+)$", text)
if m:
    recommended = m.group(1).strip()
else:
    m = re.search(r"(?im)^-\s*recommended\s+next\s+mode\s*:\s*(\S.+)$", text)
    if m:
        recommended = m.group(1).strip()

if next_action:
    next_action = re.sub(r"(?im)^-?\s*recommended\s+next\s+mode\s*:\s*.*$", "", next_action).strip()

print(f"Mission: {handoff.parent}")
print(f"Handoff: {handoff}")
print()
print("Status")
print(f"  summary:    {field(status, 'summary') or '-'}")
print(f"  phase:      {field(status, 'phase') or '-'}")
print(f"  confidence: {field(status, 'confidence') or '-'}")
print()
print("Blockers")
print(blockers or "- none")
print()
print("Next exact action")
print(next_action or "- none recorded")
print()
print(f"Recommended next mode: {recommended or '-'}")

if log_file.exists():
    print()
    print(f"Recent log tail: {log_file}")
    lines = log_file.read_text(encoding='utf-8', errors='ignore').splitlines()
    tail = lines[-12:]
    if tail:
        for line in tail:
            print(f"  {line}")
PY
