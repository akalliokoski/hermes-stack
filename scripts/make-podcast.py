#!/usr/bin/env python3
from __future__ import annotations

import argparse
import os
import re
import shlex
import subprocess
import sys
import tempfile
import textwrap
import urllib.parse
import urllib.request
from pathlib import Path

from audiobookshelf_api import ensure_library_and_scan
from podcast_pipeline_common import (
    DEFAULT_OUTPUT_DIR,
    DEFAULT_PODCASTFY_PYTHON,
    final_output_path,
    hermes_binary,
    resolve_tts_base_url,
    show_output_dir,
)
from run_podcastfy_pipeline import run_pipeline


def run(cmd: list[str], *, env: dict[str, str] | None = None, cwd: str | None = None) -> subprocess.CompletedProcess[str]:
    return subprocess.run(cmd, text=True, capture_output=True, env=env, cwd=cwd, check=False)



def ensure_file(path: Path) -> None:
    if not path.exists():
        raise SystemExit(f"Required file not found: {path}")



def duration_minutes_seconds(mp3_path: Path, podcastfy_python: str) -> str | None:
    probe = [
        podcastfy_python,
        "-c",
        textwrap.dedent(
            f"""
            from mutagen.mp3 import MP3
            audio = MP3(r'{mp3_path}')
            print(int(audio.info.length))
            """
        ),
    ]
    proc = run(probe)
    if proc.returncode != 0:
        return None
    try:
        total = int(proc.stdout.strip())
    except ValueError:
        return None
    return f"{total // 60}m {total % 60}s"



def send_telegram_notification(text: str) -> None:
    bot_token = os.environ.get("TELEGRAM_BOT_TOKEN", "")
    chat_id = os.environ.get("TELEGRAM_HOME_CHANNEL", "")
    if not bot_token or not chat_id:
        return
    data = urllib.parse.urlencode({"chat_id": chat_id, "text": text}).encode()
    req = urllib.request.Request(
        f"https://api.telegram.org/bot{bot_token}/sendMessage",
        data=data,
        method="POST",
    )
    try:
        with urllib.request.urlopen(req, timeout=20):
            return
    except Exception as exc:  # pragma: no cover - best effort notify helper
        print(f"warning: telegram notification failed: {exc}", file=sys.stderr)



def build_generation_prompt(title: str, files: list[Path], urls: list[str], topic: str | None, notes: str | None) -> str:
    file_lines = "\n".join(f"- {path}" for path in files) or "- none"
    url_lines = "\n".join(f"- {url}" for url in urls) or "- none"
    topic_line = topic or "none"
    notes_line = notes or "none"
    return textwrap.dedent(
        f"""
        Create a podcast dialogue transcript for the episode titled: {title}

        Use Hermes tools to read the listed local files and fetch any URLs if needed.

        Local files:
        {file_lines}

        URLs:
        {url_lines}

        Topic hint:
        {topic_line}

        Extra instructions:
        {notes_line}

        Requirements:
        - Return ONLY the transcript.
        - No markdown fences.
        - No preamble or commentary.
        - Format as alternating XML-like blocks only:
          <Person1>...</Person1>
          <Person2>...</Person2>
        - Make it sound like a polished two-host podcast.
        - Keep factual claims grounded in the provided sources.
        - Target roughly 6 to 12 minutes of spoken audio unless the source volume clearly justifies more.
        """
    ).strip()



def generate_transcript(title: str, files: list[Path], urls: list[str], topic: str | None, notes: str | None) -> str:
    prompt = build_generation_prompt(title, files, urls, topic, notes)
    cmd = [
        hermes_binary(),
        "chat",
        "-Q",
        "--source",
        "tool",
        "-s",
        "podcast-pipeline",
        "-q",
        prompt,
    ]
    proc = run(cmd)
    if proc.returncode != 0:
        raise SystemExit(f"Transcript generation failed:\nSTDOUT:\n{proc.stdout}\nSTDERR:\n{proc.stderr}")
    output = proc.stdout.strip()
    output = re.sub(r"^```(?:xml|text)?\s*", "", output)
    output = re.sub(r"\s*```$", "", output)
    if "<Person1>" not in output or "<Person2>" not in output:
        raise SystemExit(f"Transcript generation returned unexpected output:\n{output[:2000]}")
    return output.strip()



def scan_audiobookshelf() -> bool:
    try:
        ensure_library_and_scan()
        return True
    except Exception as exc:  # pragma: no cover - best effort operational helper
        print(f"warning: Audiobookshelf scan skipped: {exc}", file=sys.stderr)
        return False



def main() -> int:
    parser = argparse.ArgumentParser(description="Generate a podcast episode and publish it to Audiobookshelf")
    parser.add_argument("--title", required=True)
    parser.add_argument("--transcript", help="Existing transcript file with <Person1>/<Person2> tags or HOST_A/HOST_B lines")
    parser.add_argument("--source-file", action="append", default=[], help="Local source text/markdown files for Hermes to read")
    parser.add_argument("--url", action="append", default=[], help="Source URLs for Hermes to fetch")
    parser.add_argument("--topic", help="Optional topic hint for transcript generation")
    parser.add_argument("--notes", help="Optional additional instructions for transcript generation")
    parser.add_argument("--text", help="Inline source text; stored in a temp file and provided to Hermes")
    parser.add_argument(
        "--tts-base-url",
        default=os.environ.get("TTS_BASE_URL") or os.environ.get("CHATTERBOX_BASE_URL") or os.environ.get("KOKORO_BASE_URL", ""),
        help="OpenAI-compatible TTS base URL; defaults to Modal-hosted Chatterbox, but can point to any compatible backend.",
    )
    parser.add_argument("--kokoro-base-url", dest="legacy_kokoro_base_url", default="", help=argparse.SUPPRESS)
    parser.add_argument("--podcastfy-python", default=DEFAULT_PODCASTFY_PYTHON)
    parser.add_argument("--output-dir", default=DEFAULT_OUTPUT_DIR)
    parser.add_argument("--dry-run", action="store_true", help="Generate transcript and show planned audio command without running TTS")
    parser.add_argument("--skip-notify", action="store_true")
    args = parser.parse_args()

    podcastfy_python = args.podcastfy_python
    tts_base_url = resolve_tts_base_url(args.tts_base_url, args.legacy_kokoro_base_url)
    if not Path(podcastfy_python).exists():
        raise SystemExit(f"podcastfy python not found: {podcastfy_python}. Run scripts/setup-podcast-pipeline.sh first.")

    output_dir = Path(args.output_dir).expanduser().resolve()
    output_dir.mkdir(parents=True, exist_ok=True)
    episode_output_dir = show_output_dir(args.title, output_dir)
    episode_output_dir.mkdir(parents=True, exist_ok=True)

    source_files = [Path(p).expanduser().resolve() for p in args.source_file]
    for path in source_files:
        ensure_file(path)

    with tempfile.TemporaryDirectory(prefix="make-podcast-") as tmp:
        tmpdir = Path(tmp)
        if args.text:
            inline_path = tmpdir / "inline-source.txt"
            inline_path.write_text(args.text, encoding="utf-8")
            source_files.append(inline_path)

        if args.transcript:
            transcript_path = Path(args.transcript).expanduser().resolve()
            ensure_file(transcript_path)
            transcript_text = transcript_path.read_text(encoding="utf-8")
        else:
            if not source_files and not args.url and not args.topic:
                raise SystemExit("Provide --transcript or at least one source via --source-file, --url, --topic, or --text")
            transcript_text = generate_transcript(args.title, source_files, args.url, args.topic, args.notes)
            transcript_path = tmpdir / "generated-transcript.txt"
            transcript_path.write_text(transcript_text, encoding="utf-8")

        print(f"Transcript ready: {transcript_path}")

        if not tts_base_url:
            raise SystemExit("TTS_BASE_URL/CHATTERBOX_BASE_URL or --tts-base-url is required")

        print("Running audio pipeline:")
        print(
            " ".join(
                shlex.quote(part)
                for part in [
                    podcastfy_python,
                    str(Path(__file__).resolve().parent / "run_podcastfy_pipeline.py"),
                    "--title",
                    args.title,
                    "--transcript",
                    str(transcript_path),
                    "--output-dir",
                    str(episode_output_dir),
                    "--tts-base-url",
                    tts_base_url,
                    "--python",
                    podcastfy_python,
                ]
            )
        )

        try:
            final_mp3 = run_pipeline(
                title=args.title,
                transcript_path=transcript_path,
                output_dir=episode_output_dir,
                tts_base_url=tts_base_url,
                python_executable=podcastfy_python,
                dry_run=args.dry_run,
            )
        except (FileNotFoundError, RuntimeError) as exc:
            raise SystemExit(f"Audio pipeline failed: {exc}") from exc

        if args.dry_run:
            return 0

        expected_mp3 = final_output_path(args.title, output_dir)
        if final_mp3 != expected_mp3 or not expected_mp3.exists():
            raise SystemExit(f"Expected output not found: {expected_mp3}")

        scan_audiobookshelf()
        duration = duration_minutes_seconds(final_mp3, podcastfy_python)
        msg = f"🎙️ Podcast ready: {args.title}"
        if duration:
            msg += f" ({duration})"
        msg += "\nOpen Plappa or Audiobookshelf to listen."
        if not args.skip_notify:
            send_telegram_notification(msg)
        print(msg)
        print(f"Output file: {final_mp3}")
        return 0


if __name__ == "__main__":
    raise SystemExit(main())
