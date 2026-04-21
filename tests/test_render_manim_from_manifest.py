import importlib.util
import json
import sys
import tempfile
import unittest
from pathlib import Path
from unittest import mock

ROOT = Path(__file__).resolve().parents[1]
SCRIPTS = ROOT / "scripts"
if str(SCRIPTS) not in sys.path:
    sys.path.insert(0, str(SCRIPTS))

SPEC = importlib.util.spec_from_file_location("render_infographic_from_manifest", SCRIPTS / "render_infographic_from_manifest.py")
MODULE = importlib.util.module_from_spec(SPEC)
assert SPEC and SPEC.loader
SPEC.loader.exec_module(MODULE)


class RenderInfographicFromManifestTests(unittest.TestCase):
    def test_render_assets_uses_visual_bullets_and_writes_concat_manifest(self):
        manifest = {
            "version": 1,
            "mode": "narrated",
            "title": "Demo",
            "fps": 30,
            "scenes": [
                {
                    "scene_id": "S1_request_to_pipeline",
                    "goal": "Show the request becoming a pipeline.",
                    "visual_motif": "Prompt card becomes a four-stage rail",
                    "visual_bullets": [
                        "Prompt card labeled How Hermes Builds Video Explainers",
                        "Stage tiles: Brief, Scaffold, Render, Deliver",
                    ],
                    "narration_text": "Hermes turns one request into a pipeline.",
                    "speech_offset_s": 0.8,
                    "audio_duration_s": 5.0,
                    "pause_after_s": 1.2,
                }
            ],
        }
        with tempfile.TemporaryDirectory() as tmp:
            root = Path(tmp)
            manifest_path = root / "scene_manifest.json"
            output_dir = root / "render"
            manifest_path.write_text(json.dumps(manifest), encoding="utf-8")
            with mock.patch.object(MODULE, "render_scene_clip") as render_scene_clip:
                metadata = MODULE.render_assets_from_manifest(manifest_path, output_dir)
                self.assertEqual(metadata["renderer"], "infographic")
                self.assertEqual(metadata["scenes"][0]["scene_name"], "s1_request_to_pipeline")
                slide_path = Path(metadata["scenes"][0]["slide_path"])
                self.assertTrue(slide_path.exists())
                self.assertTrue(slide_path.read_bytes().startswith(b"P6\n1920 1080\n255\n"))
                concat_text = Path(metadata["concat_path"]).read_text(encoding="utf-8")
                self.assertIn("s1_request_to_pipeline.mp4", concat_text)
                render_scene_clip.assert_called_once()
                args, _kwargs = render_scene_clip.call_args
                self.assertAlmostEqual(args[2], 7.0)

    def test_render_assets_can_skip_clip_generation(self):
        manifest = {
            "version": 1,
            "mode": "silent",
            "title": "Demo",
            "fps": 30,
            "scenes": [
                {
                    "scene_id": "S1_request: pipeline",
                    "goal": "Show the request becoming a pipeline.",
                    "visual_motif": "Prompt card becomes a rail",
                    "visual_bullets": ["Prompt card", "Stage rail"],
                    "narration_text": "",
                    "speech_offset_s": 0.8,
                    "audio_duration_s": 0.0,
                    "pause_after_s": 1.2,
                }
            ],
        }
        with tempfile.TemporaryDirectory() as tmp:
            root = Path(tmp)
            manifest_path = root / "scene_manifest.json"
            output_dir = root / "render"
            manifest_path.write_text(json.dumps(manifest), encoding="utf-8")
            metadata = MODULE.render_assets_from_manifest(manifest_path, output_dir, render_clips=False)
            self.assertEqual(metadata["scenes"][0]["scene_name"], "s1_request_pipeline")
            self.assertEqual(Path(metadata["concat_path"]).read_text(encoding="utf-8"), "")


if __name__ == "__main__":
    unittest.main()
