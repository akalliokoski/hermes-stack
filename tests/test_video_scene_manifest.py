import json
import sys
import tempfile
import unittest
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
SCRIPTS = ROOT / "scripts"
if str(SCRIPTS) not in sys.path:
    sys.path.insert(0, str(SCRIPTS))

import video_scene_manifest as vsm  # type: ignore


class VideoSceneManifestTests(unittest.TestCase):
    def test_snap_time_to_frame_boundary(self):
        self.assertAlmostEqual(vsm.snap_time(0.333, 30), 0.3333333333333333)
        self.assertAlmostEqual(vsm.snap_time(1.01, 10), 1.0)

    def test_compute_scene_duration(self):
        scene = {
            "scene_id": "scene-1",
            "speech_offset_s": 0.8,
            "audio_duration_s": 6.25,
            "pause_after_s": 1.2,
        }
        duration = vsm.compute_scene_duration(scene)
        self.assertAlmostEqual(duration, 8.25)

    def test_recompute_timeline_offsets(self):
        manifest = {
            "fps": 30,
            "scenes": [
                {"scene_id": "scene-1", "speech_offset_s": 0.5, "audio_duration_s": 4.0, "pause_after_s": 1.0},
                {"scene_id": "scene-2", "speech_offset_s": 0.75, "audio_duration_s": 5.0, "pause_after_s": 1.25},
            ],
        }
        updated = vsm.recompute_manifest(manifest)
        self.assertAlmostEqual(updated["scenes"][0]["timeline_offset_s"], 0.0)
        self.assertAlmostEqual(updated["scenes"][0]["scene_duration_s"], 5.5)
        self.assertAlmostEqual(updated["scenes"][1]["timeline_offset_s"], 5.5)
        self.assertAlmostEqual(updated["scenes"][1]["scene_duration_s"], 7.0)

    def test_validate_rejects_missing_scene_id(self):
        manifest = {"fps": 30, "scenes": [{"speech_offset_s": 0.5, "audio_duration_s": 1.0, "pause_after_s": 0.5}]}
        with self.assertRaises(ValueError):
            vsm.validate_manifest(manifest)

    def test_save_and_load_manifest_roundtrip(self):
        manifest = vsm.create_initial_manifest(
            title="Demo",
            narrated=True,
            scene_specs=[
                {"scene_id": "scene-1", "goal": "Intro", "narration_text": "Hello world."},
                {"scene_id": "scene-2", "goal": "Outro", "narration_text": "Goodbye world."},
            ],
        )
        with tempfile.TemporaryDirectory() as tmp:
            path = Path(tmp) / "scene_manifest.json"
            vsm.save_manifest(path, manifest)
            loaded = vsm.load_manifest(path)
        self.assertEqual(loaded["title"], "Demo")
        self.assertEqual(len(loaded["scenes"]), 2)
        self.assertEqual(loaded["scenes"][0]["scene_id"], "scene-1")

    def test_extract_scene_specs_ignores_nested_scene_bullets(self):
        brief = """# Overview\n\nDemo\n\n# Scene Plan\n\n1. Intro\n   - Goal: set context\n   - Visuals: blocks\n   - Narration beats: keep it short\n2. Outro\n   - Goal: wrap up\n\n# Build Notes\n\nDone.\n"""
        specs = vsm.extract_scene_specs_from_brief(brief)
        self.assertEqual([spec["scene_id"] for spec in specs], ["scene-01-intro", "scene-02-outro"])

    def test_extract_scene_specs_from_structured_scene_sections(self):
        brief = """# Overview

Demo.

# Scene Plan

## Scene `S1_request_to_pipeline`
- Goal: Introduce the user-facing promise.
- On-screen visuals:
  - A single prompt card labeled \"How Hermes Builds Video Explainers\"
  - Four stage tiles: Brief, Scaffold, Render, Deliver
- Narration beats:
  - Hermes treats the request as a pipeline.
  - Each stage lights up in order.

## Scene `S2_sources_become_brief`
- Goal: Show sources condensing into a brief.
- On-screen visuals:
  - Source cards collapse into `brief.md`
- Narration beats:
  - Hermes reads the files first.

# Build Notes

Done.
"""
        specs = vsm.extract_scene_specs_from_brief(brief)
        self.assertEqual([spec["scene_id"] for spec in specs], ["S1_request_to_pipeline", "S2_sources_become_brief"])
        self.assertEqual(specs[0]["goal"], "Introduce the user-facing promise.")
        self.assertEqual(
            specs[0]["visual_motif"],
            'A single prompt card labeled "How Hermes Builds Video Explainers"',
        )
        self.assertEqual(
            specs[0]["visual_bullets"],
            [
                'A single prompt card labeled "How Hermes Builds Video Explainers"',
                "Four stage tiles: Brief, Scaffold, Render, Deliver",
            ],
        )
        self.assertEqual(
            specs[0]["narration_text"],
            "Hermes treats the request as a pipeline. Each stage lights up in order.",
        )

    def test_extract_scene_specs_from_plain_scene_sections(self):
        brief = """# Scene Plan

## Scene S1_request_to_pipeline: Request becomes pipeline
- Goal: Show the prompt becoming a flow.
- On-screen visuals:
  - Prompt card
  - Stage rail

## Scene S2_sources_become_brief - Sources collapse into brief
- Goal: Compress sources.
- On-screen visuals:
  - Source cards
  - brief.md card
"""
        specs = vsm.extract_scene_specs_from_brief(brief)
        self.assertEqual([spec["scene_id"] for spec in specs], ["S1_request_to_pipeline", "S2_sources_become_brief"])
        self.assertEqual(specs[0]["goal"], "Show the prompt becoming a flow.")
        self.assertEqual(specs[1]["visual_bullets"], ["Source cards", "brief.md card"])


if __name__ == "__main__":
    unittest.main()
