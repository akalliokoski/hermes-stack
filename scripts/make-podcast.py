#!/usr/bin/env python3
from __future__ import annotations

import argparse
import json
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
    archive_generated_json,
    archive_generated_text,
    final_output_path,
    hermes_binary,
    resolve_tts_base_url,
    show_output_dir,
)
from podcast_transcript_audit import audit_transcript
from podcast_transcript_prompting import build_draft_prompt, build_revision_prompt, build_source_packet
from podcast_transcript_schema import save_transcript_json, validate_transcript
from render_podcast_transcript import render_for_podcastfy
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



def _strip_code_fences(output: str) -> str:
    cleaned = output.strip()
    cleaned = re.sub(r"^```(?:json|xml|text)?\s*", "", cleaned)
    cleaned = re.sub(r"\s*```$", "", cleaned)
    return cleaned.strip()


def run_hermes_prompt(prompt: str) -> str:
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
        raise SystemExit(f"Hermes generation failed:\nSTDOUT:\n{proc.stdout}\nSTDERR:\n{proc.stderr}")
    return _strip_code_fences(proc.stdout)


def _load_canonical_transcript(raw_output: str, *, artifact_path: Path | None = None) -> dict[str, object]:
    cleaned = _strip_code_fences(raw_output)
    if artifact_path is not None:
        artifact_path.parent.mkdir(parents=True, exist_ok=True)
        artifact_path.write_text(cleaned + "\n", encoding="utf-8")
    try:
        payload = json.loads(cleaned)
    except json.JSONDecodeError as exc:
        raise SystemExit(f"Hermes returned invalid transcript JSON: {exc}") from exc
    try:
        transcript = validate_transcript(payload)
    except ValueError as exc:
        raise SystemExit(f"Hermes returned invalid transcript structure: {exc}") from exc
    return transcript


def maybe_render_canonical_transcript_text(raw_text: str) -> str:
    cleaned = _strip_code_fences(raw_text)
    if not cleaned.startswith("{"):
        return raw_text.strip()
    try:
        payload = json.loads(cleaned)
    except json.JSONDecodeError:
        return raw_text.strip()
    if not isinstance(payload, dict) or "turns" not in payload:
        return raw_text.strip()
    validated = validate_transcript(payload)
    return render_for_podcastfy(validated)


def generate_structured_transcript_artifacts(
    *,
    title: str,
    files: list[Path],
    urls: list[str],
    topic: str | None,
    notes: str | None,
    artifact_dir: Path,
    hermes_runner=None,
) -> dict[str, object]:
    runner = hermes_runner or run_hermes_prompt
    artifact_dir.mkdir(parents=True, exist_ok=True)

    source_packet = build_source_packet(files=files, urls=urls, topic=topic, notes=notes)
    draft_prompt = build_draft_prompt(title=title, source_packet=source_packet)
    draft_raw = runner(draft_prompt)
    draft_debug_path = artifact_dir / "transcript-draft-response.txt"
    draft = _load_canonical_transcript(draft_raw, artifact_path=draft_debug_path)

    draft_path = artifact_dir / "transcript-draft.json"
    save_transcript_json(draft_path, draft)

    revision_prompt = build_revision_prompt(
        title=title,
        source_packet=source_packet,
        draft_transcript=draft,
    )
    final_raw = runner(revision_prompt)
    final_debug_path = artifact_dir / "transcript-response.txt"
    transcript = _load_canonical_transcript(final_raw, artifact_path=final_debug_path)

    transcript_path = artifact_dir / "transcript.json"
    save_transcript_json(transcript_path, transcript)

    audit = audit_transcript(transcript)
    audit_path = artifact_dir / "transcript-audit.json"
    audit_path.write_text(json.dumps(audit, indent=2, sort_keys=True) + "\n", encoding="utf-8")

    rendered_text = render_for_podcastfy(transcript)
    rendered_path = artifact_dir / "transcript.txt"
    rendered_path.write_text(rendered_text + "\n", encoding="utf-8")

    archive_generated_json(
        category="podcasts",
        title=title,
        data=transcript,
        artifact_label="transcript-structured",
        purpose="Archive canonical structured podcast transcript JSON.",
        pipeline_name="podcast-pipeline",
    )
    archive_generated_json(
        category="podcasts",
        title=title,
        data=audit,
        artifact_label="transcript-audit",
        purpose="Archive transcript audit results.",
        pipeline_name="podcast-pipeline",
    )
    archive_generated_text(
        category="podcasts",
        title=title,
        content=rendered_text,
        artifact_label="transcript-rendered",
        purpose="Archive rendered podcast transcripts in the shared wiki so they are easy to find and reuse.",
        pipeline_name="podcast-pipeline",
    )

    return {
        "draft_path": draft_path,
        "transcript_path": transcript_path,
        "audit_path": audit_path,
        "rendered_path": rendered_path,
        "audit": audit,
    }



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

        generated_artifacts: dict[str, object] | None = None

        if args.transcript:
            transcript_path = Path(args.transcript).expanduser().resolve()
            ensure_file(transcript_path)
            transcript_text = maybe_render_canonical_transcript_text(transcript_path.read_text(encoding="utf-8"))
        else:
            if not source_files and not args.url and not args.topic:
                raise SystemExit("Provide --transcript or at least one source via --source-file, --url, --topic, or --text")
            generated_artifacts = generate_structured_transcript_artifacts(
                title=args.title,
                files=source_files,
                urls=args.url,
                topic=args.topic,
                notes=args.notes,
                artifact_dir=episode_output_dir,
            )
            transcript_path = Path(generated_artifacts["transcript_path"])
            transcript_text = Path(generated_artifacts["rendered_path"]).read_text(encoding="utf-8").strip()
            wiki_transcript_path = None

        if generated_artifacts is None:
            wiki_transcript_path = archive_generated_text(
                category="podcasts",
                title=args.title,
                content=transcript_text,
                artifact_label="transcript-rendered",
                purpose="Archive rendered podcast transcripts in the shared wiki so they are easy to find and reuse.",
                pipeline_name="podcast-pipeline",
            )

        print(f"Transcript ready: {transcript_path}")
        if wiki_transcript_path is not None:
            print(f"Wiki transcript archive: {wiki_transcript_path}")
        if generated_artifacts is not None:
            print(f"Draft transcript: {generated_artifacts['draft_path']}")
            print(f"Structured transcript: {generated_artifacts['transcript_path']}")
            print(f"Transcript audit: {generated_artifacts['audit_path']}")
            print(f"Rendered transcript: {generated_artifacts['rendered_path']}")
            audit = generated_artifacts["audit"]
            if isinstance(audit, dict):
                issue_count = len(audit.get("issues", [])) if isinstance(audit.get("issues"), list) else 0
                print(f"Audit ok: {audit.get('ok')} ({issue_count} issues)")

        if args.dry_run:
            print("Dry run complete; skipped audio synthesis.")
            return 0

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
