#!/usr/bin/env python3
from __future__ import annotations

import json
import os
import sys
from pathlib import Path
from typing import Any


def process_start_time(pid: int) -> int | None:
    try:
        return int(Path(f"/proc/{pid}/stat").read_text().split()[21])
    except (FileNotFoundError, PermissionError, OSError, IndexError, ValueError):
        return None


def load_json(path: Path) -> dict[str, Any] | int | None:
    try:
        raw = path.read_text().strip()
    except OSError:
        return None
    if not raw:
        return None
    try:
        return json.loads(raw)
    except json.JSONDecodeError:
        try:
            return int(raw)
        except ValueError:
            return None


def extract_pid(payload: dict[str, Any] | int | None) -> int | None:
    if isinstance(payload, int):
        return payload
    if isinstance(payload, dict):
        try:
            return int(payload["pid"])
        except (KeyError, TypeError, ValueError):
            return None
    return None


def recorded_start_time(payload: dict[str, Any] | int | None) -> int | None:
    if isinstance(payload, dict):
        value = payload.get("start_time")
        try:
            return int(value) if value is not None else None
        except (TypeError, ValueError):
            return None
    return None


def stale_reason(payload: dict[str, Any] | int | None) -> str | None:
    pid = extract_pid(payload)
    if pid is None:
        return "missing-or-invalid-pid"

    try:
        os.kill(pid, 0)
    except ProcessLookupError:
        return f"dead-pid:{pid}"
    except PermissionError:
        return None

    current_start = process_start_time(pid)
    recorded_start = recorded_start_time(payload)
    if recorded_start is not None and current_start is not None and current_start != recorded_start:
        return f"pid-reused:{pid}"

    return None


def remove_if_stale(path: Path, *, label: str) -> tuple[bool, str | None]:
    if not path.exists():
        return False, None
    payload = load_json(path)
    reason = stale_reason(payload)
    if reason is None:
        return False, None
    try:
        path.unlink(missing_ok=True)
    except OSError as exc:
        return False, f"{label}:{path}:unlink-failed:{exc}"
    return True, f"{label}:{path}:{reason}"


def main() -> int:
    home = Path(os.environ.get("HERMES_HOME") or (Path.home() / ".hermes"))
    xdg_state_home = Path(os.environ.get("XDG_STATE_HOME") or (Path.home() / ".local" / "state"))
    lock_dir = Path(os.environ.get("HERMES_GATEWAY_LOCK_DIR") or (xdg_state_home / "hermes" / "gateway-locks"))

    removed: list[str] = []

    changed, detail = remove_if_stale(home / "gateway.pid", label="pid")
    if detail:
        removed.append(detail)

    takeover = home / ".gateway-takeover.json"
    changed_takeover, detail_takeover = remove_if_stale(takeover, label="takeover")
    if detail_takeover:
        removed.append(detail_takeover)

    if lock_dir.exists():
        for lock_path in sorted(lock_dir.glob("*.lock")):
            changed_lock, detail_lock = remove_if_stale(lock_path, label="lock")
            if detail_lock:
                removed.append(detail_lock)

    if removed:
        for item in removed:
            print(f"cleanup-hermes-gateway-state: removed stale {item}")
    else:
        print(f"cleanup-hermes-gateway-state: no stale gateway state under {home}")

    return 0


if __name__ == "__main__":
    sys.exit(main())
