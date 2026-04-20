#!/usr/bin/env python3
from __future__ import annotations

import argparse
import json
import subprocess
import urllib.request
from pathlib import Path
from typing import Any

from podcast_pipeline_common import resolve_tts_base_url
from video_scene_manifest import count_words, load_manifest, save_manifest, snap_time


def run(cmd: list[str]) -> subprocess.CompletedProcess[str]:
    return subprocess.run(cmd, text=True, capture_output=True, check=False)


def ffprobe_duration(path: Path) -> float:
    proc = run([
        "ffprobe",
        "-v",
        "error",
        "-show_entries",
        "format=duration",
        "-of",
        "default=nk=1:nw=1",
        str(path),
    ])
    if proc.returncode != 0:
        raise RuntimeError(proc.stderr.strip() or proc.stdout.strip() or f"ffprobe failed for {path}")
    return float(proc.stdout.strip())


def words_per_second(text: str, seconds: float) -> float:
    if seconds <= 0:
        raise ValueError("seconds must be positive")
    return count_words(text) / seconds


def repair_scene_overrun(
    *,
    scene: dict[str, Any],
    target_duration_s: float,
    measured_duration_s: float,
    max_atempo: float,
    available_pause_slack_s: float,
) -> dict[str, Any]:
    overrun = measured_duration_s - target_duration_s
    if overrun <= 0:
        return {"action": "fits", "overrun_s": round(overrun, 3)}
    if overrun <= 0.18:
        return {"action": "trim_filler", "overrun_s": round(overrun, 3)}
    ratio = measured_duration_s / target_duration_s if target_duration_s > 0 else 999
    if ratio <= max_atempo:
        return {"action": "atempo", "atempo": round(ratio, 4), "overrun_s": round(overrun, 3)}
    if available_pause_slack_s >= overrun:
        return {"action": "spend_pause_slack", "pause_to_spend_s": round(overrun, 3), "overrun_s": round(overrun, 3)}
    if ratio <= max_atempo * 1.08:
        return {"action": "rewrite", "overrun_s": round(overrun, 3)}
    return {"action": "extend_scene", "extend_by_s": round(overrun, 3), "overrun_s": round(overrun, 3)}


def seconds_to_srt(seconds: float) -> str:
    millis = int(round(seconds * 1000))
    hours, rem = divmod(millis, 3_600_000)
    minutes, rem = divmod(rem, 60_000)
    secs, millis = divmod(rem, 1000)
    return f"{hours:02d}:{minutes:02d}:{secs:02d},{millis:03d}"


def generate_scene_srt(manifest: dict[str, Any]) -> str:
    blocks: list[str] = []
    emitted = 0
    for scene in manifest.get("scenes", []):
        text = str(scene.get("narration_text", "")).strip()
        if not text:
            continue
        start = float(scene.get("timeline_offset_s", 0.0)) + float(scene.get("speech_offset_s", 0.0))
        end = start + float(scene.get("audio_duration_s", 0.0))
        emitted += 1
        blocks.extend([
            str(emitted),
            f"{seconds_to_srt(start)} --> {seconds_to_srt(end)}",
            text,
            "",
        ])
    return "\n".join(blocks).strip() + ("\n" if blocks else "")


def build_concat_plan(workdir: Path, manifest: dict[str, Any]) -> list[dict[str, Any]]:
    plan: list[dict[str, Any]] = []
    cursor = 0.0
    for scene in manifest.get("scenes", []):
        clip_source = scene.get("audio_clip_path")
        audio_duration = float(scene.get("audio_duration_s", 0.0) or 0.0)
        if not clip_source or audio_duration <= 0:
            scene_end = float(scene.get("timeline_offset_s", 0.0)) + float(scene.get("scene_duration_s", 0.0))
            cursor = max(cursor, scene_end)
            continue
        speech_start = float(scene.get("timeline_offset_s", 0.0)) + float(scene.get("speech_offset_s", 0.0))
        if speech_start > cursor:
            plan.append({"type": "silence", "duration_s": round(speech_start - cursor, 3)})
            cursor = speech_start
        plan.append({"type": "clip", "source": clip_source, "duration_s": audio_duration})
        cursor += audio_duration
        scene_end = float(scene.get("timeline_offset_s", 0.0)) + float(scene.get("scene_duration_s", 0.0))
        if scene_end > cursor:
            plan.append({"type": "silence", "duration_s": round(scene_end - cursor, 3)})
            cursor = scene_end
    return plan


def ensure_wav_from_clip(source: Path, target: Path, target_lufs: float) -> None:
    proc = subprocess.run(
        [
            "ffmpeg", "-y", "-nostdin", "-hide_banner", "-loglevel", "error",
            "-i", str(source),
            "-af", f"loudnorm=I={target_lufs}:TP=-1.5:LRA=11",
            "-ar", "44100",
            "-ac", "1",
            "-c:a", "pcm_s16le",
            str(target),
        ],
        text=True,
        capture_output=True,
        check=False,
    )
    if proc.returncode != 0:
        raise RuntimeError(proc.stderr.strip() or proc.stdout.strip() or f"ffmpeg normalize failed for {source}")


def create_silence(target: Path, duration_s: float) -> None:
    proc = subprocess.run(
        [
            "ffmpeg", "-y", "-nostdin", "-hide_banner", "-loglevel", "error",
            "-f", "lavfi", "-t", str(duration_s), "-i", "anullsrc=r=44100:cl=mono",
            str(target),
        ],
        text=True,
        capture_output=True,
        check=False,
    )
    if proc.returncode != 0:
        raise RuntimeError(proc.stderr.strip() or proc.stdout.strip() or f"ffmpeg silence failed for {target}")


def assemble_master_track(manifest_path: Path, output_path: Path) -> Path:
    manifest = load_manifest(manifest_path)
    output_path.parent.mkdir(parents=True, exist_ok=True)
    workdir = (output_path.parent / ".audio-work").resolve()
    workdir.mkdir(parents=True, exist_ok=True)
    plan = build_concat_plan(workdir, manifest)
    if not any(item["type"] == "clip" for item in plan):
        raise RuntimeError("No synthesized scene clips found. Fill narration-script.md / scene_manifest.json and run synthesize first.")
    concat_entries: list[str] = []
    for idx, item in enumerate(plan, start=1):
        if item["type"] == "silence":
            seg = workdir / f"segment-{idx:03d}-silence.wav"
            create_silence(seg, float(item["duration_s"]))
        else:
            seg = workdir / f"segment-{idx:03d}-clip.wav"
            ensure_wav_from_clip((manifest_path.parent / item["source"]).resolve(), seg, float(manifest.get("audio", {}).get("target_lufs", -16)))
        concat_entries.append(f"file '{seg.resolve().as_posix()}'")
    concat_path = workdir / "concat.txt"
    concat_path.write_text("\n".join(concat_entries) + "\n", encoding="utf-8")
    proc = subprocess.run(
        [
            "ffmpeg", "-y", "-nostdin", "-hide_banner", "-loglevel", "error",
            "-f", "concat", "-safe", "0", "-i", str(concat_path),
            "-c:a", "libmp3lame", "-b:a", "192k",
            str(output_path.resolve() if not output_path.is_absolute() else output_path),
        ],
        text=True,
        capture_output=True,
        check=False,
    )
    if proc.returncode != 0:
        raise RuntimeError(proc.stderr.strip() or proc.stdout.strip() or f"ffmpeg concat failed for {output_path}")
    return output_path


def synthesize_openai_compatible(base_url: str, text: str, output_path: Path, voice: str = "Lucy") -> Path:
    url = base_url.rstrip("/") + "/audio/speech"
    payload = json.dumps({"input": text, "voice": voice, "response_format": "mp3"}).encode("utf-8")
    request = urllib.request.Request(url, data=payload, headers={"Content-Type": "application/json"}, method="POST")
    output_path.parent.mkdir(parents=True, exist_ok=True)
    with urllib.request.urlopen(request) as response:
        output_path.write_bytes(response.read())
    return output_path


def synthesize_scene_clips(manifest_path: Path, base_url: str, voice: str = "Lucy") -> dict[str, Any]:
    manifest = load_manifest(manifest_path)
    audio_dir = manifest_path.parent / "audio"
    audio_dir.mkdir(parents=True, exist_ok=True)
    for scene in manifest.get("scenes", []):
        text = str(scene.get("narration_text", "")).strip()
        if not text:
            scene.pop("audio_clip_path", None)
            scene["audio_duration_s"] = 0.0
            continue
        clip_rel = Path("audio") / f"{scene['scene_id']}.mp3"
        clip_path = manifest_path.parent / clip_rel
        synthesize_openai_compatible(base_url, text, clip_path, voice=voice)
        scene["audio_clip_path"] = clip_rel.as_posix()
        scene["audio_duration_s"] = snap_time(ffprobe_duration(clip_path), int(manifest.get("fps", 30)))
    save_manifest(manifest_path, manifest)
    return manifest


def calibrate_voice(base_url: str, output_path: Path, voice: str = "Lucy") -> dict[str, Any]:
    text = (
        "Hermes explains technical systems carefully, leaving room for each visual reveal to land before the next idea begins. "
        "This calibration sample measures the actual speaking rate of the configured production voice."
    )
    synthesize_openai_compatible(base_url, text, output_path, voice=voice)
    duration = ffprobe_duration(output_path)
    return {
        "voice_id": voice,
        "calibrated_wps": round(words_per_second(text, duration), 4),
        "sample_path": str(output_path),
        "duration_s": round(duration, 4),
    }


def main() -> int:
    parser = argparse.ArgumentParser(description="Narrated explainer audio helpers")
    sub = parser.add_subparsers(dest="command", required=True)

    calib = sub.add_parser("calibrate")
    calib.add_argument("--output", required=True)
    calib.add_argument("--tts-base-url", default="")
    calib.add_argument("--voice", default="Lucy")

    synth = sub.add_parser("synthesize")
    synth.add_argument("--manifest", required=True)
    synth.add_argument("--tts-base-url", default="")
    synth.add_argument("--voice", default="Lucy")

    assemble = sub.add_parser("assemble")
    assemble.add_argument("--manifest", required=True)
    assemble.add_argument("--output", required=True)

    srt = sub.add_parser("srt")
    srt.add_argument("--manifest", required=True)
    srt.add_argument("--output", required=True)

    args = parser.parse_args()
    if args.command == "calibrate":
        base_url = resolve_tts_base_url(args.tts_base_url)
        result = calibrate_voice(base_url, Path(args.output), voice=args.voice)
        print(json.dumps(result, indent=2))
        return 0
    if args.command == "synthesize":
        base_url = resolve_tts_base_url(args.tts_base_url)
        synthesize_scene_clips(Path(args.manifest), base_url, voice=args.voice)
        return 0
    if args.command == "assemble":
        assemble_master_track(Path(args.manifest), Path(args.output))
        return 0
    if args.command == "srt":
        manifest = load_manifest(Path(args.manifest))
        Path(args.output).write_text(generate_scene_srt(manifest), encoding="utf-8")
        return 0
    return 1


if __name__ == "__main__":
    raise SystemExit(main())
