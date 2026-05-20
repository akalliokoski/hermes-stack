#!/usr/bin/env python3
"""Disable Hermes cron jobs retired by hermes-stack."""

from __future__ import annotations

import json
from pathlib import Path


RETIRED_NAMES = {
    "Hindsight Backup",
    "Hermes Hindsight Backup",
    "hermes-hindsight-backup",
}


def disable_jobs(path: Path) -> bool:
    if not path.exists():
        return False
    try:
        payload = json.loads(path.read_text())
    except json.JSONDecodeError as exc:
        print(f"skip {path}: invalid json: {exc}")
        return False

    jobs = payload.get("jobs")
    if not isinstance(jobs, list):
        return False

    changed = False
    for job in jobs:
        if not isinstance(job, dict):
            continue
        name = str(job.get("name") or "")
        prompt = str(job.get("prompt") or "")
        name_lower = name.lower()
        prompt_lower = prompt.lower()
        if name in RETIRED_NAMES or ("hindsight" in name_lower and "backup" in name_lower):
            if job.get("enabled") is not False:
                job["enabled"] = False
                job["state"] = "paused"
                job["paused_reason"] = "Retired: Hetzner VPS backups are canonical."
                changed = True
        elif "hindsight-backup" in prompt_lower or "backup-hindsight" in prompt_lower:
            if job.get("enabled") is not False:
                job["enabled"] = False
                job["state"] = "paused"
                job["paused_reason"] = "Retired: Hetzner VPS backups are canonical."
                changed = True

    if changed:
        path.write_text(json.dumps(payload, indent=2, sort_keys=False) + "\n")
        print(f"disabled retired cron jobs in {path}")
    return changed


def main() -> int:
    root = Path("/home/hermes/.hermes")
    paths = [root / "cron" / "jobs.json"]
    profiles = root / "profiles"
    if profiles.exists():
        paths.extend(sorted(profiles.glob("*/cron/jobs.json")))

    changed = False
    for path in paths:
        changed = disable_jobs(path) or changed
    if not changed:
        print("no retired Hermes cron jobs enabled")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
