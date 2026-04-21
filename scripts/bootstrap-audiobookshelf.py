#!/usr/bin/env python3
"""Initialize Audiobookshelf and ensure per-profile podcast libraries exist.

Deploy-time bootstrap is intentionally best-effort: if Audiobookshelf auth is not
configured yet, this script warns and exits successfully instead of failing the
entire stack deploy.
"""

from __future__ import annotations

import os
import sys
from pathlib import Path

from audiobookshelf_api import ensure_initialized, ensure_profile_libraries_and_scan, wait_for_server

HOST_PROFILE_PODCASTS_ROOT = Path(os.environ.get("PODCAST_LIBRARY_ROOT", "/data/audiobookshelf/podcasts/profiles"))
HOST_PODCAST_PROJECTS_ROOT = Path(os.environ.get("PODCAST_PROJECTS_DIR", "/data/audiobookshelf/projects"))


def ensure_host_directories() -> None:
    HOST_PROFILE_PODCASTS_ROOT.mkdir(parents=True, exist_ok=True)
    HOST_PODCAST_PROJECTS_ROOT.mkdir(parents=True, exist_ok=True)


def main() -> int:
    try:
        ensure_host_directories()
        status = wait_for_server()
        ensure_initialized(status)
        summaries = ensure_profile_libraries_and_scan()
        for summary in summaries:
            library = summary.get("library", {})
            print(
                f"[bootstrap-audiobookshelf] profile={summary.get('profile')} "
                f"library={library.get('name')} folders={library.get('folders', [])}"
            )
    except RuntimeError as exc:
        print(f"[bootstrap-audiobookshelf] warning: skipping library bootstrap: {exc}", file=sys.stderr)
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
