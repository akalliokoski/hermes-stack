#!/usr/bin/env python3
"""Initialize Audiobookshelf and ensure the podcast library exists.

This wrapper stays intentionally thin. The reusable API logic lives in
`scripts/audiobookshelf_api.py` so the same functionality can be reused by
bootstrap flows, the podcast pipeline, and ad hoc operator commands.

Deploy-time bootstrap is intentionally best-effort: if Audiobookshelf auth is not
configured yet, this script warns and exits successfully instead of failing the
entire stack deploy.
"""

from __future__ import annotations

import sys

from audiobookshelf_api import ensure_initialized, ensure_library_and_scan, wait_for_server


def main() -> int:
    status = wait_for_server()
    try:
        ensure_initialized(status)
        ensure_library_and_scan()
    except RuntimeError as exc:
        print(f"[bootstrap-audiobookshelf] warning: skipping library bootstrap: {exc}", file=sys.stderr)
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
