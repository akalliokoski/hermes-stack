#!/usr/bin/env python3
from __future__ import annotations

import json
import re
from pathlib import Path
from typing import Any


def slugify(value: str) -> str:
    value = value.strip().lower()
    value = re.sub(r"[^a-z0-9]+", "-", value)
    return value.strip("-") or "scene"


def snap_time(value: float, fps: int) -> float:
    if fps <= 0:
        raise ValueError("fps must be positive")
    frame = 1.0 / fps
    return round(round(value / frame) * frame, 9)


def count_words(text: str) -> int:
    return len(re.findall(r"\b\w+[\w'-]*\b", text or ""))


def compute_scene_duration(scene: dict[str, Any]) -> float:
    offset = float(scene.get("speech_offset_s", 0.0) or 0.0)
    audio = float(scene.get("audio_duration_s", 0.0) or 0.0)
    pause = float(scene.get("pause_after_s", 0.0) or 0.0)
    explicit = scene.get("scene_duration_s")
    computed = offset + audio + pause
    if explicit is not None:
        return max(float(explicit), computed)
    return computed


def recompute_manifest(manifest: dict[str, Any]) -> dict[str, Any]:
    fps = int(manifest.get("fps", 30) or 30)
    timeline = 0.0
    for scene in manifest.get("scenes", []):
        duration = compute_scene_duration(scene)
        scene["scene_duration_s"] = snap_time(duration, fps)
        scene["timeline_offset_s"] = snap_time(timeline, fps)
        scene.setdefault("speech_offset_s", 0.8)
        scene.setdefault("pause_after_s", 1.2)
        scene.setdefault("beats", [])
        scene.setdefault("visual_bullets", [])
        timeline += scene["scene_duration_s"]
    manifest["total_duration_s"] = snap_time(timeline, fps)
    return manifest


def validate_manifest(manifest: dict[str, Any]) -> dict[str, Any]:
    if not isinstance(manifest, dict):
        raise ValueError("manifest must be a dict")
    scenes = manifest.get("scenes")
    if not isinstance(scenes, list) or not scenes:
        raise ValueError("manifest.scenes must be a non-empty list")
    for idx, scene in enumerate(scenes, start=1):
        if not scene.get("scene_id"):
            raise ValueError(f"scene {idx} missing scene_id")
        if not scene.get("goal"):
            raise ValueError(f"scene {scene['scene_id']} missing goal")
        if "narration_text" not in scene:
            raise ValueError(f"scene {scene['scene_id']} missing narration_text")
    return manifest


def save_manifest(path: Path, manifest: dict[str, Any]) -> None:
    path.write_text(json.dumps(recompute_manifest(validate_manifest(manifest)), indent=2) + "\n", encoding="utf-8")


def load_manifest(path: Path) -> dict[str, Any]:
    manifest = json.loads(path.read_text(encoding="utf-8"))
    return recompute_manifest(validate_manifest(manifest))


def scene_spec(
    scene_id: str,
    goal: str,
    narration_text: str = "",
    visual_motif: str = "",
    visual_bullets: list[str] | None = None,
) -> dict[str, Any]:
    return {
        "scene_id": scene_id,
        "goal": goal,
        "visual_motif": visual_motif or goal,
        "visual_bullets": list(visual_bullets or []),
        "narration_text": narration_text,
        "speech_offset_s": 0.8,
        "pause_after_s": 1.2,
        "audio_duration_s": 0.0,
        "beats": [
            {"beat_id": f"{scene_id}-intro", "start_s": 0.0, "kind": "visual"},
            {"beat_id": f"{scene_id}-speech", "start_s": 0.8, "kind": "speech-anchor"},
        ],
        "word_count": count_words(narration_text),
    }


def create_initial_manifest(
    *,
    title: str,
    narrated: bool,
    scene_specs: list[dict[str, Any]],
    fps: int = 30,
    calibrated_wps: float = 2.05,
) -> dict[str, Any]:
    scenes: list[dict[str, Any]] = []
    for raw in scene_specs:
        spec = scene_spec(
            raw["scene_id"],
            raw.get("goal", raw["scene_id"]),
            raw.get("narration_text", ""),
            raw.get("visual_motif", ""),
            raw.get("visual_bullets") or [],
        )
        if raw.get("speech_offset_s") is not None:
            spec["speech_offset_s"] = float(raw["speech_offset_s"])
        if raw.get("pause_after_s") is not None:
            spec["pause_after_s"] = float(raw["pause_after_s"])
        if raw.get("audio_duration_s") is not None:
            spec["audio_duration_s"] = float(raw["audio_duration_s"])
        if raw.get("beats"):
            spec["beats"] = raw["beats"]
        scenes.append(spec)
    manifest = {
        "version": 1,
        "mode": "narrated" if narrated else "silent",
        "title": title,
        "fps": fps,
        "voice": {
            "backend": "openai-compatible",
            "voice_id": "default",
            "calibrated_wps": calibrated_wps,
        },
        "audio": {
            "target_lufs": -16,
            "max_small_atempo": 1.08,
        },
        "scenes": scenes,
    }
    return recompute_manifest(validate_manifest(manifest))


def _strip_scene_heading(raw: str) -> tuple[str, str]:
    cleaned = raw.strip()
    backticked = re.match(r"Scene\s+`([^`]+)`\s*(?:[:-]\s*(.*))?$", cleaned, flags=re.IGNORECASE)
    if backticked:
        scene_id = backticked.group(1).strip()
        title = (backticked.group(2) or "").strip()
        return scene_id, title

    plain = re.match(r"Scene\s+([A-Za-z0-9_]+)\s*(?:[:-]\s*(.*))?$", cleaned, flags=re.IGNORECASE)
    if plain:
        scene_id = plain.group(1).strip()
        title = (plain.group(2) or "").strip()
        return scene_id, title

    fallback = cleaned.strip("` ")
    return fallback, ""


def _collect_nested_bullets(lines: list[str], start_index: int, parent_indent: int) -> tuple[list[str], int]:
    items: list[str] = []
    index = start_index
    while index < len(lines):
        raw = lines[index]
        stripped = raw.strip()
        indent = len(raw) - len(raw.lstrip())
        if not stripped:
            index += 1
            continue
        if indent <= parent_indent:
            break
        bullet = re.match(r"[-*]\s+(.+)", stripped)
        if bullet:
            items.append(bullet.group(1).strip())
        index += 1
    return items, index


def _parse_structured_scene_specs(scene_plan_lines: list[str]) -> list[dict[str, Any]]:
    specs: list[dict[str, Any]] = []
    current: dict[str, Any] | None = None
    index = 0
    while index < len(scene_plan_lines):
        raw = scene_plan_lines[index]
        stripped = raw.strip()
        if not stripped:
            index += 1
            continue
        heading = re.match(r"##+\s+(.+)", stripped)
        if heading:
            if current:
                specs.append(current)
            scene_id, heading_title = _strip_scene_heading(heading.group(1))
            current = {
                "scene_id": scene_id,
                "goal": heading_title or scene_id,
                "visual_motif": "",
                "visual_bullets": [],
                "narration_text": "",
            }
            index += 1
            continue
        if current is None:
            index += 1
            continue
        bullet = re.match(r"-\s+([^:]+):\s*(.*)", stripped)
        if not bullet:
            index += 1
            continue
        key = bullet.group(1).strip().lower()
        value = bullet.group(2).strip()
        indent = len(raw) - len(raw.lstrip())
        if key == "goal":
            current["goal"] = value or current["goal"]
            index += 1
            continue
        if key in {"visual motif", "visuals", "on-screen visuals", "on screen visuals"}:
            items, next_index = _collect_nested_bullets(scene_plan_lines, index + 1, indent)
            bullets = ([value] if value else []) + items
            bullets = [item for item in bullets if item]
            if bullets:
                current["visual_bullets"] = bullets
                current["visual_motif"] = bullets[0]
            index = next_index
            continue
        if key in {"narration", "narration beats", "narration beat"}:
            items, next_index = _collect_nested_bullets(scene_plan_lines, index + 1, indent)
            beats = ([value] if value else []) + items
            beats = [item for item in beats if item]
            if beats:
                current["narration_text"] = " ".join(beats)
            index = next_index
            continue
        index += 1
    if current:
        specs.append(current)
    return [spec for spec in specs if spec.get("scene_id")]


def _extract_scene_plan_lines(brief_text: str) -> list[str]:
    lines = brief_text.splitlines()
    scene_plan_lines: list[str] = []
    in_scene_plan = False
    scene_plan_level: int | None = None
    for line in lines:
        stripped = line.strip()
        heading_match = re.match(r"(#+)\s+(.*)", stripped)
        heading_text = heading_match.group(2).strip().lower() if heading_match else ""
        heading_level = len(heading_match.group(1)) if heading_match else None
        if heading_text == "scene plan":
            in_scene_plan = True
            scene_plan_level = heading_level
            continue
        if in_scene_plan and heading_match and scene_plan_level is not None and heading_level <= scene_plan_level:
            break
        if in_scene_plan:
            scene_plan_lines.append(line)
    return scene_plan_lines


def extract_scene_specs_from_brief(brief_text: str) -> list[dict[str, Any]]:
    scene_plan_lines = _extract_scene_plan_lines(brief_text)
    structured_specs = _parse_structured_scene_specs(scene_plan_lines)
    if structured_specs:
        return structured_specs

    collected: list[dict[str, Any]] = []
    for line in scene_plan_lines:
        stripped = line.strip()
        if not stripped:
            continue
        if line[: len(line) - len(line.lstrip())]:
            continue
        match = re.match(r"(?:[-*]|\d+[.)])\s*(.+)", stripped)
        if not match:
            continue
        item = match.group(1).strip()
        goal = re.sub(r"^[Ss]cene\s*\d+\s*[:\-]?\s*", "", item).strip()
        goal = goal or item
        scene_id = f"scene-{len(collected)+1:02d}-{slugify(goal)[:40]}"
        collected.append({
            "scene_id": scene_id,
            "goal": goal,
            "visual_motif": goal,
            "visual_bullets": [goal],
            "narration_text": "",
        })
    if collected:
        return collected
    return [
        {"scene_id": "scene-01-intro", "goal": "Intro", "visual_motif": "Intro", "visual_bullets": ["Intro"], "narration_text": ""},
        {"scene_id": "scene-02-core-idea", "goal": "Core idea", "visual_motif": "Core idea", "visual_bullets": ["Core idea"], "narration_text": ""},
        {"scene_id": "scene-03-mechanism", "goal": "Mechanism", "visual_motif": "Mechanism", "visual_bullets": ["Mechanism"], "narration_text": ""},
        {"scene_id": "scene-04-outro", "goal": "Outro", "visual_motif": "Outro", "visual_bullets": ["Outro"], "narration_text": ""},
    ]


__all__ = [
    "compute_scene_duration",
    "count_words",
    "create_initial_manifest",
    "extract_scene_specs_from_brief",
    "load_manifest",
    "recompute_manifest",
    "save_manifest",
    "scene_spec",
    "slugify",
    "snap_time",
    "validate_manifest",
]
