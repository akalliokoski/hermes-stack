#!/usr/bin/env python3
from __future__ import annotations

import json
import math
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


def scene_spec(scene_id: str, goal: str, narration_text: str = "", visual_motif: str = "") -> dict[str, Any]:
    return {
        "scene_id": scene_id,
        "goal": goal,
        "visual_motif": visual_motif or goal,
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


def extract_scene_specs_from_brief(brief_text: str) -> list[dict[str, Any]]:
    lines = brief_text.splitlines()
    in_scene_plan = False
    collected: list[dict[str, Any]] = []
    for line in lines:
        stripped = line.strip()
        if stripped.startswith("# ") and stripped.lower() == "# scene plan":
            in_scene_plan = True
            continue
        if in_scene_plan and stripped.startswith("# ") and stripped.lower() != "# scene plan":
            break
        if not in_scene_plan or not stripped:
            continue
        if line[: len(line) - len(line.lstrip())]:
            continue
        m = re.match(r"(?:[-*]|\d+[.)])\s*(.+)", stripped)
        if not m:
            continue
        item = m.group(1).strip()
        goal = re.sub(r"^[Ss]cene\s*\d+\s*[:\-]?\s*", "", item).strip()
        goal = goal or item
        scene_id = f"scene-{len(collected)+1:02d}-{slugify(goal)[:40]}"
        collected.append({"scene_id": scene_id, "goal": goal, "narration_text": ""})
    if collected:
        return collected
    return [
        {"scene_id": "scene-01-intro", "goal": "Intro", "narration_text": ""},
        {"scene_id": "scene-02-core-idea", "goal": "Core idea", "narration_text": ""},
        {"scene_id": "scene-03-mechanism", "goal": "Mechanism", "narration_text": ""},
        {"scene_id": "scene-04-outro", "goal": "Outro", "narration_text": ""},
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
