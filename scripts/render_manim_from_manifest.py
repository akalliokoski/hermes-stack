#!/usr/bin/env python3
from __future__ import annotations

import argparse
import re
import textwrap
from pathlib import Path

from video_scene_manifest import load_manifest

HEADER = """from __future__ import annotations
from manim import *
import json
import re
from pathlib import Path

BG = \"#1C1C1C\"
PRIMARY = \"#58C4DD\"
SECONDARY = \"#83C167\"
ACCENT = \"#FFFF00\"
MUTED = \"#94A3B8\"
PANEL_FILL = \"#111827\"
PANEL_ALT = \"#0F172A\"
MONO = \"DejaVu Sans Mono\"
SANS = \"DejaVu Sans\"

MANIFEST = json.loads(Path(__file__).with_name(\"scene_manifest.json\").read_text(encoding=\"utf-8\"))
SCENES = {scene[\"scene_id\"]: scene for scene in MANIFEST[\"scenes\"]}
SCENE_ORDER = [scene[\"scene_id\"] for scene in MANIFEST[\"scenes\"]]


def fit_text(label, max_width):
    if label.width > max_width:
        label.scale_to_fit_width(max_width)
    return label


def clean_label(text, fallback):
    value = str(text or \"\").strip()
    return value or fallback


def short_text(text, limit=42):
    text = re.sub(r\"\\s+\", \" \", clean_label(text, \"Visual beat\"))
    if len(text) <= limit:
        return text
    cut = text[:limit].rstrip()
    if \" \" in cut:
        cut = cut.rsplit(\" \", 1)[0]
    return cut.rstrip(\",:;.-\") + \"…\"


def visual_parts(text):
    raw = clean_label(text, \"Visual beat\")
    normalized = re.sub(r\"`\", \"\", raw)
    if \":\" in normalized:
        lead, detail = normalized.split(\":\", 1)
        lead = short_text(lead, limit=24)
        detail = short_text(detail, limit=54)
        return lead, detail
    words = normalized.split()
    if len(words) <= 5:
        return short_text(normalized, limit=28), \"\"
    lead = short_text(" ".join(words[:4]), limit=26)
    detail = short_text(" ".join(words[4:]), limit=54)
    return lead, detail


def scene_step_label(scene_id):
    try:
        return f\"STEP {SCENE_ORDER.index(scene_id) + 1}\"
    except ValueError:
        return \"STEP\"


def build_title_block(scene):
    step = Text(scene_step_label(scene[\"scene_id\"]), font=MONO, font_size=18, color=ACCENT, weight=BOLD)
    title = fit_text(
        Text(clean_label(scene.get(\"goal\"), scene[\"scene_id\"]), font=SANS, font_size=28, color=PRIMARY, weight=BOLD),
        11.2,
    )
    motif = fit_text(
        Text(short_text(scene.get(\"visual_motif\"), limit=70), font=MONO, font_size=18, color=SECONDARY),
        9.6,
    )
    motif_badge = SurroundingRectangle(motif, color=SECONDARY, buff=0.16, corner_radius=0.14, stroke_width=1.4)
    motif_badge.set_fill(PANEL_FILL, opacity=0.65)
    motif_group = VGroup(motif_badge, motif)
    group = VGroup(step, title, motif_group).arrange(DOWN, buff=0.26, aligned_edge=LEFT)
    group.to_edge(UP, buff=0.42)
    return group


def build_visual_icon(text, accent=False):
    text = clean_label(text, \"Visual beat\").lower()
    color = ACCENT if accent else PRIMARY
    if \"folder\" in text or \"brief.md\" in text:
        icon = RoundedRectangle(corner_radius=0.08, width=0.44, height=0.3)
        icon.set_stroke(color, width=2.2)
        icon.set_fill(PANEL_ALT, opacity=1)
        tab = Rectangle(width=0.16, height=0.08, stroke_width=0)
        tab.set_fill(color, opacity=1)
        tab.move_to(icon.get_corner(UL) + RIGHT * 0.12 + DOWN * 0.04)
        return VGroup(icon, tab)
    if \"render\" in text or \"mp4\" in text:
        icon = Triangle(fill_opacity=1, fill_color=color, stroke_width=0).scale(0.13)
        frame = RoundedRectangle(corner_radius=0.08, width=0.42, height=0.3)
        frame.set_stroke(color, width=2.2)
        frame.set_fill(PANEL_ALT, opacity=1)
        icon.move_to(frame.get_center())
        return VGroup(frame, icon)
    if \"wiki\" in text or \"brief\" in text:
        page = RoundedRectangle(corner_radius=0.05, width=0.32, height=0.4)
        page.set_stroke(color, width=2)
        page.set_fill(PANEL_ALT, opacity=1)
        line1 = Line(LEFT * 0.09, RIGHT * 0.09, color=color, stroke_width=2).move_to(page.get_center() + UP * 0.07)
        line2 = Line(LEFT * 0.09, RIGHT * 0.09, color=color, stroke_width=2).move_to(page.get_center() - UP * 0.03)
        return VGroup(page, line1, line2)
    if \"venv\" in text or \"pipeline\" in text:
        shell = RoundedRectangle(corner_radius=0.14, width=0.44, height=0.32)
        shell.set_stroke(color, width=2.2)
        shell.set_fill(PANEL_ALT, opacity=1)
        core = Dot(radius=0.06, color=color)
        return VGroup(shell, core)
    if \"audio\" in text or \"wave\" in text:
        bars = VGroup(*[Rectangle(width=0.04, height=h, stroke_width=0, fill_opacity=1, fill_color=color) for h in (0.12, 0.22, 0.34, 0.18)])
        bars.arrange(RIGHT, buff=0.04)
        return bars
    return Dot(radius=0.09, color=color)


def build_visual_card(text, accent=False):
    lead, detail = visual_parts(text)
    lead_label = fit_text(Text(lead, font=MONO, font_size=25, color=WHITE, weight=BOLD), 3.45)
    detail_label = fit_text(Text(detail or \"Visual beat\", font=SANS, font_size=18, color=MUTED, line_spacing=0.84), 3.5)
    detail_label.align_to(lead_label, LEFT)
    text_group = VGroup(lead_label, detail_label).arrange(DOWN, buff=0.16, aligned_edge=LEFT)
    frame = RoundedRectangle(corner_radius=0.22, width=max(text_group.width + 0.9, 4.15), height=max(text_group.height + 0.9, 2.1))
    frame.set_stroke(ACCENT if accent else SECONDARY, width=2.4 if accent else 1.7, opacity=0.96)
    frame.set_fill(PANEL_ALT if accent else PANEL_FILL, opacity=0.95 if accent else 0.86)
    icon = build_visual_icon(text, accent=accent)
    icon.move_to(frame.get_corner(UL) + RIGHT * 0.34 + DOWN * 0.3)
    text_group.move_to(frame.get_center() + DOWN * 0.05)
    card = VGroup(frame, icon, text_group)
    card.set_z_index(3)
    return card


def build_runtime_diagram(scene):
    capsule = RoundedRectangle(corner_radius=0.3, width=3.35, height=1.1)
    capsule.set_stroke(ACCENT, width=2.6)
    capsule.set_fill(PANEL_ALT, opacity=0.95)
    capsule_text = Text(\"video venv\", font=MONO, font_size=24, color=WHITE, weight=BOLD).move_to(capsule.get_center())
    capsule_group = VGroup(capsule, capsule_text).move_to(LEFT * 2.6 + UP * 0.15)

    pkg_specs = [(\"manim\", PRIMARY), (\"cairo\", SECONDARY), (\"ffmpeg\", ACCENT)]
    pkg_boxes = []
    for label, color in pkg_specs:
        box = RoundedRectangle(corner_radius=0.16, width=1.5, height=0.62)
        box.set_stroke(color, width=2.0)
        box.set_fill(PANEL_FILL, opacity=0.9)
        txt = Text(label, font=MONO, font_size=18, color=WHITE)
        pkg_boxes.append(VGroup(box, txt.move_to(box.get_center())))
    pkg_row = VGroup(*pkg_boxes).arrange(RIGHT, buff=0.24).move_to(RIGHT * 1.75 + UP * 0.72)

    system_specs = [(\"build\", PRIMARY), (\"python\", PRIMARY), (\"pkg-config\", SECONDARY)]
    system_boxes = []
    for label, color in system_specs:
        box = RoundedRectangle(corner_radius=0.14, width=1.35, height=0.52)
        box.set_stroke(color, width=1.7)
        box.set_fill(PANEL_FILL, opacity=0.8)
        txt = Text(label, font=MONO, font_size=15, color=MUTED)
        system_boxes.append(VGroup(box, txt.move_to(box.get_center())))
    system_row = VGroup(*system_boxes).arrange(RIGHT, buff=0.18).move_to(RIGHT * 1.85 + DOWN * 0.18)

    arrows = VGroup(
        Arrow(pkg_row.get_left() + DOWN * 0.18, capsule_group.get_right() + UP * 0.22, buff=0.2, stroke_width=3, color=PRIMARY, max_tip_length_to_length_ratio=0.12),
        Arrow(system_row.get_left() + UP * 0.12, capsule_group.get_right() + DOWN * 0.18, buff=0.2, stroke_width=3, color=SECONDARY, max_tip_length_to_length_ratio=0.12),
    )
    baseline = Line(LEFT * 4.8, RIGHT * 4.8, color=MUTED, stroke_opacity=0.16, stroke_width=4).shift(DOWN * 1.05)
    layout = VGroup(baseline, capsule_group, pkg_row, system_row, arrows)
    return layout, [capsule_group, pkg_row, system_row]


def build_delivery_diagram(scene):
    mp4 = RoundedRectangle(corner_radius=0.18, width=1.9, height=0.82)
    mp4.set_stroke(ACCENT, width=2.4)
    mp4.set_fill(PANEL_ALT, opacity=0.95)
    mp4_text = Text(\"final mp4\", font=MONO, font_size=22, color=WHITE, weight=BOLD)
    mp4_group = VGroup(mp4, mp4_text.move_to(mp4.get_center())).move_to(LEFT * 3.0)

    brief = RoundedRectangle(corner_radius=0.16, width=1.7, height=0.78)
    brief.set_stroke(SECONDARY, width=2.0)
    brief.set_fill(PANEL_FILL, opacity=0.9)
    brief_text = Text(\"brief\", font=MONO, font_size=20, color=WHITE, weight=BOLD)
    brief_group = VGroup(brief, brief_text.move_to(brief.get_center())).move_to(LEFT * 3.0 + DOWN * 1.2)

    jellyfin = Circle(radius=0.42, color=PRIMARY, stroke_width=2.2)
    jellyfin.set_fill(PANEL_FILL, opacity=0.9)
    play = Triangle(fill_opacity=1, fill_color=PRIMARY, stroke_width=0).scale(0.18).rotate(-PI/2)
    jellyfin_group = VGroup(jellyfin, play.move_to(jellyfin.get_center() + RIGHT * 0.03)).move_to(RIGHT * 0.25 + UP * 0.18)
    jellyfin_label = Text(\"Jellyfin\", font=SANS, font_size=20, color=PRIMARY).next_to(jellyfin_group, DOWN, buff=0.18)

    wiki = RoundedRectangle(corner_radius=0.16, width=1.8, height=0.82)
    wiki.set_stroke(SECONDARY, width=2.0)
    wiki.set_fill(PANEL_FILL, opacity=0.9)
    wiki_text = Text(\"wiki archive\", font=MONO, font_size=19, color=WHITE, weight=BOLD)
    wiki_group = VGroup(wiki, wiki_text.move_to(wiki.get_center())).move_to(RIGHT * 3.0 + DOWN * 0.78)

    arrows = VGroup(
        Arrow(mp4_group.get_right(), jellyfin_group.get_left(), buff=0.22, stroke_width=3, color=ACCENT, max_tip_length_to_length_ratio=0.12),
        Arrow(brief_group.get_right(), wiki_group.get_left(), buff=0.22, stroke_width=3, color=SECONDARY, max_tip_length_to_length_ratio=0.12),
    )
    return VGroup(mp4_group, brief_group, jellyfin_group, jellyfin_label, wiki_group, arrows), [mp4_group, brief_group, jellyfin_group, wiki_group]


def build_visual_panel(scene):
    if scene.get(\"scene_id\") == \"S5_local_runtime_layer\":
        return build_runtime_diagram(scene)
    if scene.get(\"scene_id\") == \"S7_archive_and_delivery\":
        return build_delivery_diagram(scene)
    visual_bullets = scene.get(\"visual_bullets\") or []
    items = [clean_label(item, \"Visual beat\") for item in visual_bullets if str(item).strip()]
    if not items:
        items = [clean_label(scene.get(\"visual_motif\"), clean_label(scene.get(\"goal\"), scene[\"scene_id\"]))]
    cards = [build_visual_card(item, accent=index == 0) for index, item in enumerate(items[:3])]
    if len(cards) == 1:
        cards[0].scale(1.08)
        layout = VGroup(cards[0])
    else:
        lane = Line(LEFT * 4.7, RIGHT * 4.7, color=MUTED, stroke_opacity=0.2, stroke_width=4)
        positions = [LEFT * 3.25, ORIGIN, RIGHT * 3.25][:len(cards)]
        connectors = []
        for index, card in enumerate(cards):
            card.move_to(positions[index] + UP * 0.18)
            if index > 0:
                connectors.append(Arrow(cards[index - 1].get_right(), card.get_left(), buff=0.18, stroke_width=3, color=PRIMARY, max_tip_length_to_length_ratio=0.12))
        layout = VGroup(lane, *cards, *connectors)
    layout.move_to(ORIGIN + DOWN * 0.22)
    return layout, cards


def build_progress_indicator(scene_id):
    dots = []
    active_index = SCENE_ORDER.index(scene_id) if scene_id in SCENE_ORDER else 0
    for index, current_id in enumerate(SCENE_ORDER):
        radius = 0.12 if index == active_index else 0.1
        dot = Dot(radius=radius, color=ACCENT if index <= active_index else MUTED)
        dot.set_fill(ACCENT if index <= active_index else MUTED, opacity=1 if index <= active_index else 0.45)
        dots.append(dot)
    track = VGroup(*dots).arrange(RIGHT, buff=0.28)
    if len(track) > 1:
        line = Line(track[0].get_center(), track[-1].get_center(), color=MUTED, stroke_opacity=0.35, stroke_width=3)
        progress = VGroup(line, track)
    else:
        progress = VGroup(track)
    progress.to_edge(DOWN, buff=0.45)
    return progress


def build_scene_layout(scene):
    title_group = build_title_block(scene)
    visual_panel, cards = build_visual_panel(scene)
    progress = build_progress_indicator(scene[\"scene_id\"])
    composition = VGroup(title_group, visual_panel, progress)
    return composition, title_group, visual_panel, cards, progress
"""


def scene_class_text(scene_id: str) -> str:
    sanitized_parts = [part for part in re.split(r"[^A-Za-z0-9]+", scene_id) if part]
    class_name = "".join(part.title() for part in sanitized_parts) or "Scene"
    if class_name and class_name[0].isdigit():
        class_name = f"Scene{class_name}"
    return textwrap.dedent(
        f"""
        class {class_name}(Scene):
            def construct(self):
                self.camera.background_color = BG
                scene = SCENES[{scene_id!r}]
                composition, title_group, visual_panel, cards, progress = build_scene_layout(scene)
                speech_offset = float(scene.get(\"speech_offset_s\", 0.8))
                scene_duration = float(scene.get(\"scene_duration_s\", 6.0))
                narration = str(scene.get(\"narration_text\", \"\")).strip()
                fade_in = min(1.2, max(scene_duration * 0.18, 0.35))
                fade_out = min(0.6, max(scene_duration * 0.12, 0.18))
                intro_run = min(fade_in, max(scene_duration * 0.22, 0.45))
                intro_title_run = max(intro_run * 0.55, 0.3)
                self.play(FadeIn(title_group, shift=DOWN * 0.15), FadeIn(progress), run_time=intro_title_run)
                beat_run = max(intro_run * 0.45, 0.3)
                self.play(FadeIn(visual_panel, shift=UP * 0.18), run_time=beat_run)
                elapsed_intro = intro_title_run + beat_run
                pre_speech_wait = max(speech_offset - elapsed_intro, 0.0)
                if pre_speech_wait > 0:
                    self.wait(pre_speech_wait)
                remaining = max(scene_duration - elapsed_intro - pre_speech_wait - fade_out, 0.1)
                if narration:
                    self.add_subcaption(narration, duration=remaining)
                self.wait(remaining)
                self.play(FadeOut(composition), run_time=fade_out)
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
