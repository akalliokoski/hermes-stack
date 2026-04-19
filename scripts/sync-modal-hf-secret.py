#!/usr/bin/env python3
"""Sync HF_TOKEN from a dotenv file or environment into the Modal `hf-token` secret."""

from __future__ import annotations

import argparse
import os
import shlex
import subprocess
from pathlib import Path

from podcast_pipeline_common import DEFAULT_PODCASTFY_PYTHON


def load_dotenv(path: Path) -> dict[str, str]:
    values: dict[str, str] = {}
    for raw_line in path.read_text(encoding="utf-8").splitlines():
        line = raw_line.strip()
        if not line or line.startswith("#") or "=" not in line:
            continue
        key, value = line.split("=", 1)
        key = key.strip()
        value = value.strip()
        if value.startswith(("'", '"')) and value.endswith(("'", '"')) and len(value) >= 2:
            value = value[1:-1]
        values[key] = value
    return values


def resolve_hf_token(explicit: str, dotenv_path: Path | None) -> str:
    if explicit:
        return explicit
    if os.environ.get("HF_TOKEN"):
        return os.environ["HF_TOKEN"]
    if dotenv_path and dotenv_path.exists():
        return load_dotenv(dotenv_path).get("HF_TOKEN", "")
    return ""


def main() -> int:
    parser = argparse.ArgumentParser(description="Sync HF_TOKEN into the Modal hf-token secret")
    parser.add_argument("--hf-token", default="", help="Explicit HF token. Defaults to HF_TOKEN env or dotenv lookup.")
    parser.add_argument("--from-dotenv", default="/home/hermes/.hermes/.env", help="Dotenv file to read HF_TOKEN from if env is unset")
    parser.add_argument("--modal-env", default="", help="Optional Modal environment name")
    parser.add_argument("--podcastfy-python", default=DEFAULT_PODCASTFY_PYTHON, help="Python interpreter that has modal installed")
    args = parser.parse_args()

    dotenv_path = Path(args.from_dotenv).expanduser() if args.from_dotenv else None
    token = resolve_hf_token(args.hf_token, dotenv_path)
    if not token:
        raise SystemExit("HF_TOKEN not found. Set HF_TOKEN in the environment, pass --hf-token, or point --from-dotenv at a file that contains it.")
    if not Path(args.podcastfy_python).exists():
        raise SystemExit(f"modal/podcast python not found: {args.podcastfy_python}")

    cmd = [args.podcastfy_python, "-m", "modal", "secret", "create", "--force", "hf-token"]
    if args.modal_env:
        cmd.extend(["--env", args.modal_env])
    cmd.append(f"HF_TOKEN={token}")

    print("Running:")
    print(" ".join(shlex.quote(part if not part.startswith("HF_TOKEN=") else "HF_TOKEN=***") for part in cmd))
    completed = subprocess.run(cmd, check=False)
    if completed.returncode != 0:
        raise SystemExit(completed.returncode)
    print("Modal secret hf-token updated successfully.")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
