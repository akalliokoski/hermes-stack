#!/usr/bin/env python3
from __future__ import annotations

import argparse
import json
from pathlib import Path

from video_audio_timeline import calibrate_voice
from video_scene_manifest import load_manifest, save_manifest
from podcast_pipeline_common import resolve_tts_base_url


def main() -> int:
    parser = argparse.ArgumentParser(description="Calibrate narrated explainer voice speed and optionally write it into a scene manifest")
    parser.add_argument("--output", required=True, help="Where to write the calibration sample audio")
    parser.add_argument("--tts-base-url", default="")
    parser.add_argument("--voice", default="Lucy")
    parser.add_argument("--manifest", help="Optional manifest to update with calibration metadata")
    args = parser.parse_args()

    result = calibrate_voice(resolve_tts_base_url(args.tts_base_url), Path(args.output), voice=args.voice)
    if args.manifest:
        manifest_path = Path(args.manifest)
        manifest = load_manifest(manifest_path)
        manifest.setdefault("voice", {}).update(result)
        save_manifest(manifest_path, manifest)
    print(json.dumps(result, indent=2))
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
