#!/usr/bin/env python3
from __future__ import annotations

import datetime as dt
import os
import re
import shutil
from pathlib import Path

SCRIPT_DIR = Path(__file__).resolve().parent
DEFAULT_ENV_FILES = (Path("/home/hermes/.hermes/.env"), Path("/opt/hermes/.env"))


def load_env_defaults(*paths: Path) -> None:
    for path in paths:
        if not path.exists():
            continue
        for raw_line in path.read_text(encoding="utf-8").splitlines():
            line = raw_line.strip()
            if not line or line.startswith("#") or "=" not in line:
                continue
            key, value = line.split("=", 1)
            key = key.strip()
            if key in os.environ:
                continue
            value = value.strip()
            if value.startswith(("'", '"')) and value.endswith(("'", '"')) and len(value) >= 2:
                value = value[1:-1]
            os.environ[key] = value


load_env_defaults(*DEFAULT_ENV_FILES)

DEFAULT_PODCASTFY_PYTHON = os.environ.get("PODCASTFY_PYTHON", "/home/hermes/.venvs/podcast-pipeline/bin/python")
DEFAULT_OUTPUT_DIR = os.environ.get("PODCAST_OUTPUT_DIR", "/data/audiobookshelf/podcasts/ai-generated")
DEFAULT_AUDIOBOOKSHELF_BASE_URL = os.environ.get("AUDIOBOOKSHELF_BASE_URL", "http://127.0.0.1:13378")


def repo_script(name: str) -> Path:
    return SCRIPT_DIR / name


def slugify(value: str) -> str:
    value = value.strip().lower()
    value = re.sub(r"[^a-z0-9]+", "-", value)
    return value.strip("-") or "episode"


def show_output_dir(title: str, output_dir: Path) -> Path:
    return output_dir / slugify(title)


def final_output_path(title: str, output_dir: Path) -> Path:
    return show_output_dir(title, output_dir) / f"{dt.date.today().isoformat()}_{slugify(title)}.mp3"


def resolve_tts_base_url(explicit: str = "", legacy: str = "") -> str:
    return (
        explicit
        or os.environ.get("TTS_BASE_URL", "")
        or os.environ.get("CHATTERBOX_BASE_URL", "")
        or legacy
        or os.environ.get("KOKORO_BASE_URL", "")
    )


def hermes_binary() -> str:
    return shutil.which("hermes") or "/home/hermes/.local/bin/hermes"
