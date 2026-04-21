#!/usr/bin/env python3
"""Run podcastfy with a prebuilt transcript and an OpenAI-compatible TTS backend."""

from __future__ import annotations

import argparse
import datetime as dt
import json
import os
import re
import shutil
import subprocess
import sys
import tempfile
from pathlib import Path

import yaml

from podcast_pipeline_common import DEFAULT_OUTPUT_DIR, resolve_tts_base_url, slugify
from podcast_transcript_schema import validate_transcript
from render_podcast_transcript import render_for_podcastfy


def _normalize_raw_transcript(text: str) -> str:
    if "<Person1>" in text or "<Person2>" in text:
        return text

    lines = [line.strip() for line in text.splitlines() if line.strip()]
    converted: list[str] = []
    for line in lines:
        if line.startswith("HOST_A:"):
            converted.append(f"<Person1>{line[len('HOST_A:'):].strip()}</Person1>")
        elif line.startswith("HOST_B:"):
            converted.append(f"<Person2>{line[len('HOST_B:'):].strip()}</Person2>")
        else:
            converted.append(line)
    return "\n".join(converted)


def normalize_transcript(text: str) -> str:
    stripped = text.strip()
    if not stripped:
        return ""
    if stripped.startswith("{"):
        try:
            data = json.loads(stripped)
        except json.JSONDecodeError:
            return _normalize_raw_transcript(text)
        if isinstance(data, dict) and "turns" in data:
            validated = validate_transcript(data)
            return render_for_podcastfy(validated)
    return _normalize_raw_transcript(text)


def newest_mp3(output_dir: Path) -> Path:
    files = sorted(output_dir.glob("*.mp3"), key=lambda p: p.stat().st_mtime, reverse=True)
    if not files:
        raise FileNotFoundError(f"No mp3 output found in {output_dir}")
    return files[0]


def build_command(*, python_executable: str, normalized_path: Path, conversation_config_path: Path) -> list[str]:
    return [
        python_executable,
        "-m",
        "podcastfy.client",
        "--transcript",
        str(normalized_path),
        "--tts-model",
        "openai",
        "--conversation-config",
        str(conversation_config_path),
    ]


def run_pipeline(
    *,
    title: str,
    transcript_path: Path,
    output_dir: Path,
    tts_base_url: str,
    python_executable: str = sys.executable,
    dry_run: bool = False,
    output_filename: str | None = None,
) -> Path:
    transcript_path = transcript_path.expanduser().resolve()
    if not transcript_path.exists():
        raise FileNotFoundError(f"Transcript not found: {transcript_path}")
    output_dir = output_dir.expanduser().resolve()
    output_dir.mkdir(parents=True, exist_ok=True)
    final_output = output_dir / (output_filename or f"{dt.date.today().isoformat()}_{slugify(title)}.mp3")

    normalized = normalize_transcript(transcript_path.read_text(encoding="utf-8"))

    with tempfile.TemporaryDirectory(prefix="podcastfy-") as tmp:
        tmpdir = Path(tmp)
        normalized_path = tmpdir / "transcript.txt"
        normalized_path.write_text(normalized, encoding="utf-8")

        conv_cfg = {
            "text_to_speech": {
                "default_tts_model": "openai",
                "output_directories": {
                    "audio": str(output_dir),
                    "transcripts": str(tmpdir / "transcripts"),
                },
                "temp_audio_dir": str(tmpdir / "tmp-audio"),
            }
        }
        conv_cfg_path = tmpdir / "conversation_config.yaml"
        conv_cfg_path.write_text(yaml.safe_dump(conv_cfg, sort_keys=False), encoding="utf-8")

        cmd = build_command(
            python_executable=python_executable,
            normalized_path=normalized_path,
            conversation_config_path=conv_cfg_path,
        )
        env = os.environ.copy()
        env["OPENAI_BASE_URL"] = tts_base_url
        env.setdefault("OPENAI_API_KEY", "dummy")

        print("Planned command:")
        print(" ".join(cmd))
        print(f"Output directory: {output_dir}")
        print(f"Final output path: {final_output}")

        if dry_run:
            return final_output

        before = {p.resolve() for p in output_dir.glob("*.mp3")}
        completed = subprocess.run(cmd, env=env, check=False)
        if completed.returncode != 0:
            raise RuntimeError(f"podcastfy exited with status {completed.returncode}")

        after = [p.resolve() for p in output_dir.glob("*.mp3") if p.resolve() not in before]
        generated = max(after, key=lambda p: p.stat().st_mtime) if after else newest_mp3(output_dir)
        generated_path = Path(generated)
        if generated_path != final_output:
            if final_output.exists():
                final_output.unlink()
            shutil.move(str(generated_path), str(final_output))

    print(f"Podcast ready: {final_output}")
    return final_output


def main() -> int:
    parser = argparse.ArgumentParser(description="Run podcastfy with a prepared transcript and OpenAI-compatible TTS")
    parser.add_argument("--title", required=True)
    parser.add_argument("--transcript", required=True, help="Path to transcript file")
    parser.add_argument("--output-dir", default=DEFAULT_OUTPUT_DIR)
    parser.add_argument(
        "--tts-base-url",
        default=os.environ.get("TTS_BASE_URL") or os.environ.get("CHATTERBOX_BASE_URL") or os.environ.get("KOKORO_BASE_URL", ""),
        help="OpenAI-compatible TTS base URL; defaults to Modal Chatterbox, but can point to any compatible backend.",
    )
    parser.add_argument("--kokoro-base-url", dest="legacy_kokoro_base_url", default="", help=argparse.SUPPRESS)
    parser.add_argument("--python", default=sys.executable, help="Python interpreter that has podcastfy installed")
    parser.add_argument("--dry-run", action="store_true")
    args = parser.parse_args()

    tts_base_url = resolve_tts_base_url(args.tts_base_url, args.legacy_kokoro_base_url)
    if not tts_base_url:
        raise SystemExit("TTS_BASE_URL/CHATTERBOX_BASE_URL or --tts-base-url is required")

    try:
        run_pipeline(
            title=args.title,
            transcript_path=Path(args.transcript),
            output_dir=Path(args.output_dir),
            tts_base_url=tts_base_url,
            python_executable=args.python,
            dry_run=args.dry_run,
        )
    except (FileNotFoundError, RuntimeError) as exc:
        raise SystemExit(str(exc)) from exc
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
