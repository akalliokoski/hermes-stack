#!/usr/bin/env python3
from __future__ import annotations

import argparse
import json
import subprocess
from pathlib import Path
from typing import Any

from video_scene_manifest import load_manifest, slugify

WIDTH = 1920
HEIGHT = 1080
HEADER_H = 120
FOOTER_H = 96
CARD_W = 560
CARD_H = 180
CARD_GAP = 36
CARD_ORIGIN_X = 110
CARD_ORIGIN_Y = 360
CARD_COLS = 3
FPS = 30

BG = (15, 23, 42)
HEADER = (30, 41, 59)
PANEL = (248, 250, 252)
PANEL_ALT = (226, 232, 240)
TEXT = (15, 23, 42)
TEXT_SOFT = (71, 85, 105)
ACCENT = (59, 130, 246)
ACCENT_ALT = (16, 185, 129)
GOLD = (245, 158, 11)
WHITE = (255, 255, 255)

FONT_5X7: dict[str, tuple[str, ...]] = {
    "A": ("01110", "10001", "10001", "11111", "10001", "10001", "10001"),
    "B": ("11110", "10001", "10001", "11110", "10001", "10001", "11110"),
    "C": ("01110", "10001", "10000", "10000", "10000", "10001", "01110"),
    "D": ("11110", "10001", "10001", "10001", "10001", "10001", "11110"),
    "E": ("11111", "10000", "10000", "11110", "10000", "10000", "11111"),
    "F": ("11111", "10000", "10000", "11110", "10000", "10000", "10000"),
    "G": ("01110", "10001", "10000", "10111", "10001", "10001", "01110"),
    "H": ("10001", "10001", "10001", "11111", "10001", "10001", "10001"),
    "I": ("11111", "00100", "00100", "00100", "00100", "00100", "11111"),
    "J": ("00111", "00010", "00010", "00010", "00010", "10010", "01100"),
    "K": ("10001", "10010", "10100", "11000", "10100", "10010", "10001"),
    "L": ("10000", "10000", "10000", "10000", "10000", "10000", "11111"),
    "M": ("10001", "11011", "10101", "10101", "10001", "10001", "10001"),
    "N": ("10001", "11001", "10101", "10011", "10001", "10001", "10001"),
    "O": ("01110", "10001", "10001", "10001", "10001", "10001", "01110"),
    "P": ("11110", "10001", "10001", "11110", "10000", "10000", "10000"),
    "Q": ("01110", "10001", "10001", "10001", "10101", "10010", "01101"),
    "R": ("11110", "10001", "10001", "11110", "10100", "10010", "10001"),
    "S": ("01111", "10000", "10000", "01110", "00001", "00001", "11110"),
    "T": ("11111", "00100", "00100", "00100", "00100", "00100", "00100"),
    "U": ("10001", "10001", "10001", "10001", "10001", "10001", "01110"),
    "V": ("10001", "10001", "10001", "10001", "10001", "01010", "00100"),
    "W": ("10001", "10001", "10001", "10101", "10101", "10101", "01010"),
    "X": ("10001", "10001", "01010", "00100", "01010", "10001", "10001"),
    "Y": ("10001", "10001", "01010", "00100", "00100", "00100", "00100"),
    "Z": ("11111", "00001", "00010", "00100", "01000", "10000", "11111"),
    "0": ("01110", "10001", "10011", "10101", "11001", "10001", "01110"),
    "1": ("00100", "01100", "00100", "00100", "00100", "00100", "01110"),
    "2": ("01110", "10001", "00001", "00010", "00100", "01000", "11111"),
    "3": ("11110", "00001", "00001", "01110", "00001", "00001", "11110"),
    "4": ("00010", "00110", "01010", "10010", "11111", "00010", "00010"),
    "5": ("11111", "10000", "10000", "11110", "00001", "00001", "11110"),
    "6": ("01110", "10000", "10000", "11110", "10001", "10001", "01110"),
    "7": ("11111", "00001", "00010", "00100", "01000", "01000", "01000"),
    "8": ("01110", "10001", "10001", "01110", "10001", "10001", "01110"),
    "9": ("01110", "10001", "10001", "01111", "00001", "00001", "01110"),
    "-": ("00000", "00000", "00000", "11111", "00000", "00000", "00000"),
    "/": ("00001", "00010", "00100", "01000", "10000", "00000", "00000"),
    ":": ("00000", "00100", "00100", "00000", "00100", "00100", "00000"),
    ".": ("00000", "00000", "00000", "00000", "00000", "00110", "00110"),
    ",": ("00000", "00000", "00000", "00000", "00110", "00100", "01000"),
    "'": ("00100", "00100", "00010", "00000", "00000", "00000", "00000"),
    "&": ("01100", "10010", "10100", "01000", "10101", "10010", "01101"),
    "(": ("00010", "00100", "01000", "01000", "01000", "00100", "00010"),
    ")": ("01000", "00100", "00010", "00010", "00010", "00100", "01000"),
    "!": ("00100", "00100", "00100", "00100", "00100", "00000", "00100"),
    "?": ("01110", "10001", "00001", "00010", "00100", "00000", "00100"),
    "+": ("00000", "00100", "00100", "11111", "00100", "00100", "00000"),
    "=": ("00000", "11111", "00000", "11111", "00000", "00000", "00000"),
    "_": ("00000", "00000", "00000", "00000", "00000", "00000", "11111"),
    " ": ("00000", "00000", "00000", "00000", "00000", "00000", "00000"),
}


def sanitize_scene_name(scene_id: str) -> str:
    return slugify(scene_id).replace("-", "_")


def new_canvas(width: int = WIDTH, height: int = HEIGHT, color: tuple[int, int, int] = BG) -> bytearray:
    return bytearray(color * width * height)


def fill_rect(canvas: bytearray, x: int, y: int, w: int, h: int, color: tuple[int, int, int], *, width: int = WIDTH, height: int = HEIGHT) -> None:
    x0 = max(0, x)
    y0 = max(0, y)
    x1 = min(width, x + max(w, 0))
    y1 = min(height, y + max(h, 0))
    if x0 >= x1 or y0 >= y1:
        return
    row_bytes = bytes(color * (x1 - x0))
    for yy in range(y0, y1):
        start = (yy * width + x0) * 3
        end = start + len(row_bytes)
        canvas[start:end] = row_bytes


def draw_progress_bar(canvas: bytearray, index: int, total: int) -> None:
    track_x = 110
    track_y = HEIGHT - 56
    track_w = WIDTH - 220
    track_h = 12
    fill_rect(canvas, track_x, track_y, track_w, track_h, PANEL_ALT)
    filled = max(track_h, int(track_w * index / max(total, 1)))
    fill_rect(canvas, track_x, track_y, filled, track_h, ACCENT_ALT)


def wrap_text(text: str, max_chars: int) -> list[str]:
    words = text.replace("\n", " ").split()
    if not words:
        return []
    lines: list[str] = []
    current = words[0]
    for word in words[1:]:
        if len(current) + 1 + len(word) <= max_chars:
            current = f"{current} {word}"
        else:
            lines.append(current)
            current = word
    lines.append(current)
    return lines


def draw_char(canvas: bytearray, x: int, y: int, ch: str, color: tuple[int, int, int], *, scale: int = 4) -> int:
    pattern = FONT_5X7.get(ch.upper(), FONT_5X7["?"])
    for row_idx, row in enumerate(pattern):
        for col_idx, pixel in enumerate(row):
            if pixel == "1":
                fill_rect(canvas, x + col_idx * scale, y + row_idx * scale, scale, scale, color)
    return (len(pattern[0]) + 1) * scale


def draw_text(canvas: bytearray, x: int, y: int, text: str, color: tuple[int, int, int], *, scale: int = 4, line_gap: int = 8) -> None:
    cursor_y = y
    for raw_line in text.splitlines() or [""]:
        cursor_x = x
        for ch in raw_line.upper():
            cursor_x += draw_char(canvas, cursor_x, cursor_y, ch, color, scale=scale)
        cursor_y += 7 * scale + line_gap


def slide_lines(scene: dict[str, Any]) -> list[str]:
    lines: list[str] = []
    motif = str(scene.get("visual_motif", "")).strip()
    if motif:
        lines.extend(wrap_text(motif, 32)[:2])
    bullets = [str(item).strip() for item in scene.get("visual_bullets", []) if str(item).strip()]
    for bullet in bullets[:6]:
        wrapped = wrap_text(bullet, 26)
        if not wrapped:
            continue
        lines.append(f"- {wrapped[0]}")
        for extra in wrapped[1:2]:
            lines.append(f"  {extra}")
    if not lines:
        lines = wrap_text(str(scene.get("goal", scene.get("scene_id", "Scene"))), 32)[:4]
    return lines[:8]


def render_slide(scene: dict[str, Any], *, title: str, index: int, total: int, output_path: Path) -> Path:
    canvas = new_canvas()
    fill_rect(canvas, 0, 0, WIDTH, HEADER_H, HEADER)
    fill_rect(canvas, 0, HEIGHT - FOOTER_H, WIDTH, FOOTER_H, HEADER)
    fill_rect(canvas, 90, 170, WIDTH - 180, 110, PANEL)
    fill_rect(canvas, 90, 320, WIDTH - 180, 560, PANEL_ALT)

    draw_text(canvas, 120, 34, title[:48], WHITE, scale=6)
    draw_text(canvas, WIDTH - 430, 38, f"SCENE {index}/{total}", WHITE, scale=5)

    goal_lines = wrap_text(str(scene.get("goal", scene.get("scene_id", "Scene"))), 34)[:2]
    draw_text(canvas, 130, 195, "\n".join(goal_lines), TEXT, scale=7)

    scene_id = str(scene.get("scene_id", f"scene-{index}"))
    draw_text(canvas, 130, 245, scene_id[:48], ACCENT, scale=4)

    lines = slide_lines(scene)
    card_count = min(max(len(lines), 1), 6)
    for bullet_index in range(card_count):
        row = bullet_index // CARD_COLS
        col = bullet_index % CARD_COLS
        card_x = CARD_ORIGIN_X + col * (CARD_W + CARD_GAP)
        card_y = CARD_ORIGIN_Y + row * (CARD_H + CARD_GAP)
        fill_rect(canvas, card_x, card_y, CARD_W, CARD_H, PANEL)
        fill_rect(canvas, card_x, card_y, 18, CARD_H, ACCENT if bullet_index % 2 == 0 else GOLD)
        draw_text(canvas, card_x + 38, card_y + 26, lines[bullet_index], TEXT, scale=5)

    narration = str(scene.get("narration_text", "")).strip()
    footer_text = "OPTIONAL NARRATION PRESENT" if narration else "SILENT INFOGRAPHIC SCENE"
    draw_text(canvas, 120, HEIGHT - 78, footer_text, WHITE, scale=4)
    draw_progress_bar(canvas, index, total)

    output_path.parent.mkdir(parents=True, exist_ok=True)
    with output_path.open("wb") as handle:
        handle.write(f"P6\n{WIDTH} {HEIGHT}\n255\n".encode("ascii"))
        handle.write(canvas)
    return output_path


def render_scene_clip(image_path: Path, output_path: Path, duration_s: float, fps: int) -> Path:
    output_path.parent.mkdir(parents=True, exist_ok=True)
    cmd = [
        "ffmpeg",
        "-y",
        "-hide_banner",
        "-loglevel",
        "error",
        "-loop",
        "1",
        "-framerate",
        str(fps),
        "-t",
        f"{max(duration_s, 0.5):.3f}",
        "-i",
        str(image_path),
        "-vf",
        f"fps={fps},format=yuv420p,scale={WIDTH}:{HEIGHT}",
        "-c:v",
        "libx264",
        "-pix_fmt",
        "yuv420p",
        str(output_path),
    ]
    proc = subprocess.run(cmd, text=True, capture_output=True, check=False)
    if proc.returncode != 0:
        raise RuntimeError(f"ffmpeg scene render failed for {image_path}: {proc.stderr}")
    return output_path


def render_assets_from_manifest(manifest_path: Path, output_dir: Path, *, render_clips: bool = True) -> dict[str, Any]:
    manifest = load_manifest(manifest_path)
    output_dir.mkdir(parents=True, exist_ok=True)
    slides_dir = output_dir / "slides"
    clips_dir = output_dir / "clips"
    scene_records: list[dict[str, Any]] = []
    concat_entries: list[str] = []
    total = len(manifest.get("scenes", []))
    fps = int(manifest.get("fps", FPS) or FPS)

    for index, scene in enumerate(manifest.get("scenes", []), start=1):
        scene_name = sanitize_scene_name(str(scene.get("scene_id", f"scene-{index}")))
        slide_path = render_slide(scene, title=str(manifest.get("title", "Explainer")), index=index, total=total, output_path=slides_dir / f"{scene_name}.ppm")
        clip_path = clips_dir / f"{scene_name}.mp4"
        if render_clips:
            render_scene_clip(slide_path, clip_path, float(scene.get("scene_duration_s", 4.0) or 4.0), fps)
            concat_entries.append(f"file '{clip_path.resolve().as_posix()}'")
        scene_records.append(
            {
                "scene_id": scene.get("scene_id"),
                "scene_name": scene_name,
                "goal": scene.get("goal"),
                "slide_path": slide_path.resolve().as_posix(),
                "clip_path": clip_path.resolve().as_posix(),
                "scene_duration_s": scene.get("scene_duration_s"),
            }
        )

    concat_path = output_dir / "concat-scenes.txt"
    concat_path.write_text("\n".join(concat_entries) + ("\n" if concat_entries else ""), encoding="utf-8")
    metadata = {
        "renderer": "infographic",
        "manifest_path": manifest_path.resolve().as_posix(),
        "concat_path": concat_path.resolve().as_posix(),
        "slides_dir": slides_dir.resolve().as_posix(),
        "clips_dir": clips_dir.resolve().as_posix(),
        "scenes": scene_records,
    }
    metadata_path = output_dir / "render-manifest.json"
    metadata_path.write_text(json.dumps(metadata, indent=2) + "\n", encoding="utf-8")
    return metadata


def main() -> int:
    parser = argparse.ArgumentParser(description="Render infographic-style scene slides and video clips from a scene manifest")
    parser.add_argument("--manifest", required=True)
    parser.add_argument("--output-dir", required=True)
    parser.add_argument("--skip-clips", action="store_true", help="Only render slide images and metadata")
    args = parser.parse_args()

    metadata = render_assets_from_manifest(Path(args.manifest).resolve(), Path(args.output_dir).resolve(), render_clips=not args.skip_clips)
    print(json.dumps(metadata, indent=2))
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
