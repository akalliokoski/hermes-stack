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
DEFAULT_WIKI_PATH = os.environ.get("WIKI_PATH", "~/sync/wiki")


def repo_script(name: str) -> Path:
    return SCRIPT_DIR / name


def wiki_root() -> Path:
    return Path(DEFAULT_WIKI_PATH).expanduser()


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


def append_wiki_log(subject: str, file_path: Path) -> None:
    log_path = wiki_root() / "log.md"
    if not log_path.exists():
        return
    date_str = dt.date.today().isoformat()
    relative_path = file_path.relative_to(wiki_root())
    with log_path.open("a", encoding="utf-8") as fh:
        fh.write(
            f"\n## [{date_str}] ingest | {subject}\n"
            f"- Sources captured:\n"
            f"  - {relative_path.as_posix()}\n"
        )


def archive_generated_text(*, category: str, title: str, content: str, artifact_label: str, purpose: str, pipeline_name: str) -> Path:
    target_dir = wiki_root() / "raw" / "transcripts" / "media" / category
    target_dir.mkdir(parents=True, exist_ok=True)
    file_path = target_dir / f"{dt.date.today().isoformat()}_{slugify(title)}-{slugify(artifact_label)}.md"
    file_path.write_text(
        "\n".join(
            [
                f"# {title} {artifact_label.title()}",
                "",
                f"Captured: {dt.date.today().isoformat()}",
                f"Type: generated {artifact_label}",
                f"Purpose: {purpose}",
                "",
                "## Provenance",
                f"- Pipeline: `{pipeline_name}`",
                f"- Title: `{title}`",
                "",
                "## Content",
                content.rstrip(),
                "",
            ]
        ),
        encoding="utf-8",
    )
    append_wiki_log(f"Generated {artifact_label} | {title}", file_path)
    return file_path


def hermes_binary() -> str:
    return shutil.which("hermes") or "/home/hermes/.local/bin/hermes"
