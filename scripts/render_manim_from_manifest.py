#!/usr/bin/env python3
from __future__ import annotations

import argparse
import json
import textwrap
from pathlib import Path

from video_scene_manifest import load_manifest

HEADER = """from __future__ import annotations
from manim import *
import json
from pathlib import Path

BG = \"#1C1C1C\"
PRIMARY = \"#58C4DD\"
SECONDARY = \"#83C167\"
ACCENT = \"#FFFF00\"
MONO = \"Menlo\"

MANIFEST = json.loads(Path(__file__).with_name(\"scene_manifest.json\").read_text(encoding=\"utf-8\"))
SCENES = {scene[\"scene_id\"]: scene for scene in MANIFEST[\"scenes\"]}


def build_scene_card(scene):
    title = Text(scene[\"goal\"], font=MONO, font_size=38, color=PRIMARY, weight=BOLD)
    subtitle = Text(scene.get(\"visual_motif\") or scene[\"scene_id\"], font=MONO, font_size=22, color=SECONDARY)
    body = Text(scene.get(\"narration_text\", \"\") or \"Add narration text here.\", font=MONO, font_size=22, color=WHITE, line_spacing=0.8)
    subtitle.next_to(title, DOWN, buff=0.4)
    body.next_to(subtitle, DOWN, buff=0.6)
    return VGroup(title, subtitle, body).arrange(DOWN, buff=0.35).scale_to_fit_width(11)
"""


def scene_class_text(scene_id: str) -> str:
    class_name = "".join(part.title() for part in scene_id.replace("_", "-").split("-")) or "Scene"
    return textwrap.dedent(
        f"""
        class {class_name}(Scene):
            def construct(self):
                self.camera.background_color = BG
                scene = SCENES[{scene_id!r}]
                card = build_scene_card(scene)
                speech_offset = float(scene.get(\"speech_offset_s\", 0.8))
                scene_duration = float(scene.get(\"scene_duration_s\", 6.0))
                narration = str(scene.get(\"narration_text\", \"\")).strip()
                fade_in = min(0.8, max(scene_duration * 0.2, 0.1))
                fade_out = min(0.5, max(scene_duration * 0.12, 0.1))
                self.play(FadeIn(card, shift=UP * 0.25), run_time=fade_in)
                pre_speech_wait = max(speech_offset - fade_in, 0.0)
                if pre_speech_wait > 0:
                    self.wait(pre_speech_wait)
                remaining = max(scene_duration - fade_in - pre_speech_wait - fade_out, 0.1)
                if narration:
                    self.add_subcaption(narration, duration=remaining)
                self.wait(remaining)
                self.play(FadeOut(card), run_time=fade_out)
        """
    ).strip()


def render_script_from_manifest(manifest_path: Path, output_path: Path) -> Path:
    manifest = load_manifest(manifest_path)
    blocks = [HEADER.strip()]
    for scene in manifest.get("scenes", []):
        blocks.append(scene_class_text(scene["scene_id"]))
    output_path.write_text("\n\n\n".join(blocks) + "\n", encoding="utf-8")
    return output_path


def main() -> int:
    parser = argparse.ArgumentParser(description="Generate Manim scene module from narrated scene manifest")
    parser.add_argument("--manifest", required=True)
    parser.add_argument("--output", required=True)
    args = parser.parse_args()
    render_script_from_manifest(Path(args.manifest), Path(args.output))
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
