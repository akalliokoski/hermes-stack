#!/usr/bin/env python3
from __future__ import annotations

import argparse
import datetime as dt
import os
import re
import subprocess
import sys
import tempfile
import textwrap
from pathlib import Path

from podcast_pipeline_common import (
    DEFAULT_ENV_FILES,
    archive_generated_text,
    hermes_binary,
    load_env_defaults,
    slugify,
)
from video_scene_manifest import create_initial_manifest, extract_scene_specs_from_brief, save_manifest

load_env_defaults(*DEFAULT_ENV_FILES)

DEFAULT_VIDEO_OUTPUT_DIR = os.environ.get("VIDEO_OUTPUT_DIR", "/data/jellyfin/videos/ai-generated")
DEFAULT_SERIES = os.environ.get("VIDEO_SERIES", "notebooklm-style-explainers")
DEFAULT_VIDEO_VENV = os.environ.get("VIDEO_PIPELINE_VENV", "/home/hermes/.venvs/video-pipeline")


def run(cmd: list[str], *, cwd: Path | None = None) -> subprocess.CompletedProcess[str]:
    return subprocess.run(cmd, text=True, capture_output=True, check=False, cwd=str(cwd) if cwd else None)


def ensure_file(path: Path) -> None:
    if not path.exists():
        raise SystemExit(f"Required file not found: {path}")


def build_brief_prompt(title: str, files: list[Path], urls: list[str], topic: str | None, notes: str | None) -> str:
    file_lines = "\n".join(f"- {path}" for path in files) or "- none"
    url_lines = "\n".join(f"- {url}" for url in urls) or "- none"
    topic_line = topic or "none"
    notes_line = notes or "none"
    return textwrap.dedent(
        f"""
        Create a production-ready brief for a NotebookLM-style explainer video titled: {title}

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
        - Return ONLY markdown.
        - No preamble or commentary.
        - Target a polished, conversational explainer pacing inspired by NotebookLM, but intended for visual execution in Manim.
        - Ground all claims in the provided sources.
        - Prefer one clear narrative thread over exhaustive coverage.
        - Include these sections exactly:
          # Overview
          # Audience
          # Core Takeaway
          # Source Notes
          # Narrative Arc
          # Scene Plan
          # Visual Language
          # Optional Narration Draft
          # Build Notes
        - In Scene Plan, provide 5 to 9 scenes with scene ids, goals, on-screen visuals, and narration beats.
        - In on-screen visuals, prefer short visual labels and noun phrases over long prose.
        - For each scene, prefer one hero object plus 2 to 3 supporting nodes or states, with explicit arrows, containment, or left-to-right flow where appropriate.
        - For high-density scenes, simplify into compact diagrams instead of stacking many text bullets.
        - In Visual Language, specify palette, typography, pacing, and reusable visual motifs.
        - In Build Notes, include practical instructions for a Manim implementation and mention where pauses should happen.
        """
    ).strip()


def generate_brief(title: str, files: list[Path], urls: list[str], topic: str | None, notes: str | None) -> str:
    prompt = build_brief_prompt(title, files, urls, topic, notes)
    cmd = [
        hermes_binary(),
        "chat",
        "-Q",
        "--source",
        "tool",
        "-s",
        "manim-video",
        "-q",
        prompt,
    ]
    proc = run(cmd)
    if proc.returncode != 0:
        raise SystemExit(f"Brief generation failed:\nSTDOUT:\n{proc.stdout}\nSTDERR:\n{proc.stderr}")
    output = proc.stdout.strip()
    output = re.sub(r"^```(?:md|markdown)?\s*", "", output)
    output = re.sub(r"\s*```$", "", output)
    if "# Overview" not in output or "# Scene Plan" not in output:
        raise SystemExit(f"Brief generation returned unexpected output:\n{output[:2000]}")
    return output.strip() + "\n"


def write_sources_packet(path: Path, *, source_files: list[Path], urls: list[str], topic: str | None, notes: str | None, inline_text: str | None) -> None:
    local_file_lines = [f"- {item}" for item in source_files] or ["- none"]
    url_lines = [f"- {item}" for item in urls] or ["- none"]
    blocks = [
        "# Source Packet",
        "",
        "## Local Files",
        *local_file_lines,
        "",
        "## URLs",
        *url_lines,
        "",
        "## Topic Hint",
        topic or "none",
        "",
        "## Extra Instructions",
        notes or "none",
        "",
        "## Inline Text",
        inline_text or "none",
        "",
    ]
    path.write_text("\n".join(blocks), encoding="utf-8")


def write_script_template(path: Path, title: str) -> None:
    class_name = "Scene1_Introduction"
    content = textwrap.dedent(
        f"""
        from manim import *

        BG = "#1C1C1C"
        PRIMARY = "#58C4DD"
        SECONDARY = "#83C167"
        ACCENT = "#FFFF00"
        MONO = "DejaVu Sans Mono"


        class {class_name}(Scene):
            def construct(self):
                self.camera.background_color = BG
                title = Text({title!r}, font=MONO, font_size=42, color=PRIMARY, weight=BOLD)
                subtitle = Text(
                    "Replace this scaffold with scenes from brief.md or scene_manifest.json",
                    font=MONO,
                    font_size=24,
                    color=SECONDARY,
                ).next_to(title, DOWN, buff=0.6)
                self.add_subcaption({title!r}, duration=2)
                self.play(Write(title), run_time=1.5)
                self.wait(1.0)
                self.play(FadeIn(subtitle, shift=UP * 0.2), run_time=0.8)
                self.wait(1.5)
                self.play(FadeOut(VGroup(title, subtitle)), run_time=0.5)
                self.wait(0.5)
        """
    ).strip() + "\n"
    path.write_text(content, encoding="utf-8")


def build_narration_script(scene_specs: list[dict[str, str]]) -> str:
    lines = ["# Narration Script", "", "Narration is the timing authority for narrated explainers.", ""]
    for spec in scene_specs:
        lines.extend(
            [
                f"## {spec['scene_id']}",
                "",
                f"Goal: {spec['goal']}",
                "",
                "Narration:",
                f"{spec.get('narration_text', '').strip()}",
                "",
            ]
        )
    return "\n".join(lines).rstrip() + "\n"


def write_narrated_project_artifacts(project_dir: Path, title: str, brief_text: str) -> tuple[Path, Path]:
    scene_specs = extract_scene_specs_from_brief(brief_text)
    narration_script = build_narration_script(scene_specs)
    narration_path = project_dir / "narration-script.md"
    narration_path.write_text(narration_script, encoding="utf-8")

    manifest = create_initial_manifest(title=title, narrated=True, scene_specs=scene_specs)
    manifest_path = project_dir / "scene_manifest.json"
    save_manifest(manifest_path, manifest)
    return manifest_path, narration_path


def write_render_script(path: Path, project_dir: Path, title: str) -> None:
    output_name = f"{dt.date.today().isoformat()}_{slugify(title)}.mp4"
    narrated_name = f"{dt.date.today().isoformat()}_{slugify(title)}-narrated.mp4"
    content = textwrap.dedent(
        f"""
        #!/usr/bin/env bash
        set -euo pipefail

        PROJECT_DIR="$(cd "$(dirname "$0")" && pwd)"
        VIDEO_VENV="${{VIDEO_PIPELINE_VENV:-{DEFAULT_VIDEO_VENV}}}"
        PYTHON_BIN="${{VIDEO_PIPELINE_PYTHON:-${{VIDEO_VENV}}/bin/python}}"
        MANIM_BIN="${{MANIM_BIN:-${{VIDEO_VENV}}/bin/manim}}"
        QUALITY="${{QUALITY:-ql}}"
        TTS_BASE_URL="${{TTS_BASE_URL:-${{CHATTERBOX_BASE_URL:-}}}}"
        VOICE="${{VIDEO_NARRATION_VOICE:-Lucy}}"
        AUDIO_TIMELINE_PY="${{VIDEO_AUDIO_TIMELINE_PY:-/home/hermes/work/hermes-stack/scripts/video_audio_timeline.py}}"
        if [[ ! -f "$AUDIO_TIMELINE_PY" ]]; then
          AUDIO_TIMELINE_PY="/opt/hermes/scripts/video_audio_timeline.py"
        fi
        RENDER_FROM_MANIFEST_PY="${{RENDER_FROM_MANIFEST_PY:-/home/hermes/work/hermes-stack/scripts/render_manim_from_manifest.py}}"
        if [[ ! -f "$RENDER_FROM_MANIFEST_PY" ]]; then
          RENDER_FROM_MANIFEST_PY="/opt/hermes/scripts/render_manim_from_manifest.py"
        fi
        CLEAN_INTERMEDIATES="${{VIDEO_CLEAN_INTERMEDIATES:-1}}"
        ARTIFACT_ARCHIVE_ROOT="${{VIDEO_RENDER_ARTIFACT_ARCHIVE_ROOT:-/home/hermes/archive/jellyfin-render-artifacts}}"
        FINAL_OUTPUT="{project_dir / output_name}"
        FINAL_NARRATED_OUTPUT="{project_dir / narrated_name}"
        STITCHED_OUTPUT=0
        NARRATED_OUTPUT=0
        if [[ "$#" -eq 0 ]]; then
          SCENES=()
        else
          SCENES=("$@")
        fi

        cd "$PROJECT_DIR"
        if [[ ! -x "$MANIM_BIN" ]]; then
          echo "manim not found at $MANIM_BIN" >&2
          echo "Bootstrap the local video pipeline first, for example: bash /opt/hermes/scripts/setup-video-pipeline.sh" >&2
          exit 1
        fi

        HAS_MANIFEST=0
        HAS_NARRATION=0
        if [[ -f scene_manifest.json ]]; then
          HAS_MANIFEST=1
          HAS_NARRATION=$("$PYTHON_BIN" - <<'PY'
import json
from pathlib import Path
manifest = json.loads(Path('scene_manifest.json').read_text(encoding='utf-8'))
print(sum(1 for scene in manifest.get('scenes', []) if str(scene.get('narration_text', '')).strip()))
PY
)
        fi

        if [[ "$HAS_MANIFEST" -eq 1 && -n "$TTS_BASE_URL" && "$HAS_NARRATION" -gt 0 ]]; then
          mkdir -p audio captions
          "$PYTHON_BIN" "$AUDIO_TIMELINE_PY" synthesize --manifest scene_manifest.json --tts-base-url "$TTS_BASE_URL" --voice "$VOICE"
          "$PYTHON_BIN" "$AUDIO_TIMELINE_PY" assemble --manifest scene_manifest.json --output audio/master-narration.mp3
          "$PYTHON_BIN" "$AUDIO_TIMELINE_PY" srt --manifest scene_manifest.json --output captions/final.srt
        elif [[ "$HAS_MANIFEST" -eq 1 && -n "$TTS_BASE_URL" && "$HAS_NARRATION" -eq 0 ]]; then
          echo "scene_manifest.json exists but narration_text is empty; skipping TTS and assembly until narration-script.md is filled in." >&2
        fi

        if [[ "$HAS_MANIFEST" -eq 1 ]]; then
          "$PYTHON_BIN" "$RENDER_FROM_MANIFEST_PY" --manifest scene_manifest.json --output script.py
        fi

        if [[ "${{#SCENES[@]}}" -eq 0 ]]; then
          "$MANIM_BIN" -"$QUALITY" -a script.py
        else
          "$MANIM_BIN" -"$QUALITY" script.py "${{SCENES[@]}}"
        fi

        if [[ "$HAS_MANIFEST" -eq 1 ]]; then
          case "$QUALITY" in
            ql|l) QUALITY_SUBDIR="480p15" ;;
            qm|m) QUALITY_SUBDIR="720p30" ;;
            qh|h) QUALITY_SUBDIR="1080p60" ;;
            qp|p) QUALITY_SUBDIR="1440p60" ;;
            qk|k) QUALITY_SUBDIR="2160p60" ;;
            *) QUALITY_SUBDIR="" ;;
          esac
          QUALITY_DIR="$PROJECT_DIR/media/videos/script"
          if [[ -n "$QUALITY_SUBDIR" ]]; then
            QUALITY_DIR="$QUALITY_DIR/$QUALITY_SUBDIR"
          fi
          if [[ -d "$QUALITY_DIR" ]]; then
            CONCAT_LIST="$PROJECT_DIR/concat-scenes.txt"
            "$PYTHON_BIN" - "$QUALITY_DIR" "${{SCENES[@]}}" <<'PY' > "$CONCAT_LIST"
import json
import re
import sys
from pathlib import Path

quality_dir = Path(sys.argv[1])
selected = sys.argv[2:]
manifest = json.loads(Path('scene_manifest.json').read_text(encoding='utf-8'))

def class_name(scene_id: str) -> str:
    parts = [part for part in re.split(r'[^A-Za-z0-9]+', scene_id) if part]
    name = ''.join(part.title() for part in parts) or 'Scene'
    if name and name[0].isdigit():
        name = f'Scene{{name}}'
    return name

def normalized_name(value: str) -> str:
    candidate = (quality_dir / f"{{value}}.mp4").resolve()
    if candidate.exists():
        return value
    return class_name(value)

scene_names = [normalized_name(value) for value in selected] if selected else [class_name(scene['scene_id']) for scene in manifest.get('scenes', [])]
for scene_name in scene_names:
    clip_path = (quality_dir / f"{{scene_name}}.mp4").resolve()
    if not clip_path.exists():
        raise SystemExit(f"missing rendered scene: {{clip_path}}")
    print(f"file '{{clip_path.as_posix()}}'")
PY
            ffmpeg -y -hide_banner -loglevel error -f concat -safe 0 -i "$CONCAT_LIST" -c copy "$FINAL_OUTPUT"
            STITCHED_OUTPUT=1
            if [[ "$HAS_NARRATION" -gt 0 && -f audio/master-narration.mp3 ]]; then
              ffmpeg -y -hide_banner -loglevel error -i "$FINAL_OUTPUT" -i audio/master-narration.mp3 -c:v copy -c:a aac -b:a 192k -shortest "$FINAL_NARRATED_OUTPUT"
              NARRATED_OUTPUT=1
            fi
            if [[ "$CLEAN_INTERMEDIATES" == "1" ]]; then
              ARCHIVE_TARGET="$ARTIFACT_ARCHIVE_ROOT/$(basename "$PROJECT_DIR")"
              mkdir -p "$ARCHIVE_TARGET"
              for artifact in media __pycache__; do
                if [[ -e "$PROJECT_DIR/$artifact" ]]; then
                  rm -rf "$ARCHIVE_TARGET/$artifact"
                  mv "$PROJECT_DIR/$artifact" "$ARCHIVE_TARGET/$artifact"
                fi
              done
            fi
          fi
        fi
        echo
        if [[ "$STITCHED_OUTPUT" -eq 1 && -f "$FINAL_OUTPUT" ]]; then
          echo "Final stitched MP4:"
          echo "  $FINAL_OUTPUT"
        else
          echo "Rendered scene files are available under media/videos/script; no stitched MP4 was produced."
        fi

        if [[ "$NARRATED_OUTPUT" -eq 1 && -f "$FINAL_NARRATED_OUTPUT" ]]; then
          echo
          echo "Narrated MP4:"
          echo "  $FINAL_NARRATED_OUTPUT"
        fi
        """
    ).strip() + "\n"
    path.write_text(content, encoding="utf-8")
    path.chmod(0o755)


def main() -> int:
    parser = argparse.ArgumentParser(description="Create a NotebookLM-style Manim explainer project scaffold for Jellyfin")
    parser.add_argument("--title", required=True)
    parser.add_argument("--brief-file", help="Existing markdown brief to copy into the project")
    parser.add_argument("--source-file", action="append", default=[], help="Local source text/markdown files")
    parser.add_argument("--url", action="append", default=[], help="Source URLs")
    parser.add_argument("--topic", help="Optional topic hint")
    parser.add_argument("--notes", help="Optional additional instructions")
    parser.add_argument("--text", help="Inline source text stored in source-packet.md")
    parser.add_argument("--series", default=DEFAULT_SERIES)
    parser.add_argument("--output-dir", default=DEFAULT_VIDEO_OUTPUT_DIR)
    parser.add_argument("--skip-brief", action="store_true", help="Do not call Hermes to generate brief.md")
    parser.add_argument("--with-audio", action="store_true", help="Mark the project as intending to add narration/audio later; silent video remains the default")
    args = parser.parse_args()

    output_dir = Path(args.output_dir).expanduser().resolve()
    source_files = [Path(p).expanduser().resolve() for p in args.source_file]
    for path in source_files:
        ensure_file(path)

    series_dir = output_dir / slugify(args.series)
    project_slug = f"{dt.date.today().isoformat()}_{slugify(args.title)}"
    project_dir = series_dir / project_slug
    project_dir.mkdir(parents=True, exist_ok=True)

    with tempfile.TemporaryDirectory(prefix="make-manim-video-") as tmp:
        if args.text:
            inline_path = Path(tmp) / "inline-source.txt"
            inline_path.write_text(args.text, encoding="utf-8")
            source_files.append(inline_path)

        if args.brief_file:
            brief_text = Path(args.brief_file).expanduser().read_text(encoding="utf-8")
        elif args.skip_brief:
            brief_text = textwrap.dedent(
                f"""
                # Overview

                Placeholder brief for {args.title}.

                # Audience

                Fill this in.

                # Core Takeaway

                Fill this in.

                # Source Notes

                Fill this in.

                # Narrative Arc

                Fill this in.

                # Scene Plan

                Fill this in.

                # Visual Language

                Fill this in.

                # Optional Narration Draft

                Leave this blank if the video should stay silent.

                # Build Notes

                Fill this in.
                """
            ).strip() + "\n"
        else:
            brief_text = generate_brief(args.title, source_files, args.url, args.topic, args.notes)

    wiki_brief_path = archive_generated_text(
        category="video-explainers",
        title=args.title,
        content=brief_text,
        artifact_label="brief",
        purpose="Archive explainer briefs in the shared wiki so they are easy to find and reuse.",
        pipeline_name="video-explainer-pipeline",
    )

    (project_dir / "brief.md").write_text(brief_text, encoding="utf-8")
    write_sources_packet(
        project_dir / "source-packet.md",
        source_files=source_files,
        urls=args.url,
        topic=args.topic,
        notes=args.notes,
        inline_text=args.text,
    )
    write_script_template(project_dir / "script.py", args.title)
    narration_archive_path: Path | None = None
    manifest_path: Path | None = None
    narration_path: Path | None = None
    if args.with_audio:
        manifest_path, narration_path = write_narrated_project_artifacts(project_dir, args.title, brief_text)
        narration_archive_path = archive_generated_text(
            category="video-explainers",
            title=args.title,
            content=narration_path.read_text(encoding="utf-8"),
            artifact_label="narration-script",
            purpose="Archive narrated explainer scripts in the shared wiki so timing-authoritative narration specs are easy to find and reuse.",
            pipeline_name="video-explainer-pipeline",
        )
    write_render_script(project_dir / "render.sh", project_dir, args.title)

    plan_path = project_dir / "plan.md"
    plan_path.write_text(
        textwrap.dedent(
            f"""
            # {args.title}

            - Read `brief.md` first.
            - Silent mode: translate the Scene Plan into Manim scene classes or refine `script.py`.
            - Narrated mode: treat `scene_manifest.json` and `narration-script.md` as the timing authority.
            - If narration is enabled, calibrate the production voice, synthesize one clip per scene, and let Manim conform to the measured scene timings.
            - Keep final renders under this project directory.
            - Default mode is silent video; add narration only if explicitly desired.
            - Audio intent: {'narration-spec-first narrated explainer' if args.with_audio else 'no audio by default'}.
            - Publish the finished MP4 into this Jellyfin-backed library root:
              `{series_dir}`
            """
        ).strip()
        + "\n",
        encoding="utf-8",
    )

    print(f"Created Manim explainer project: {project_dir}")
    print(f"Brief: {project_dir / 'brief.md'}")
    print(f"Wiki brief archive: {wiki_brief_path}")
    if manifest_path:
        print(f"Scene manifest: {manifest_path}")
    if narration_path:
        print(f"Narration script: {narration_path}")
    if narration_archive_path:
        print(f"Wiki narration archive: {narration_archive_path}")
    print(f"Source packet: {project_dir / 'source-packet.md'}")
    print(f"Render helper: {project_dir / 'render.sh'}")
    print(f"Jellyfin library root: {output_dir}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
