import importlib.util
import json
import sys
import tempfile
import unittest
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
SCRIPTS = ROOT / "scripts"
if str(SCRIPTS) not in sys.path:
    sys.path.insert(0, str(SCRIPTS))

SPEC = importlib.util.spec_from_file_location("render_manim_from_manifest", SCRIPTS / "render_manim_from_manifest.py")
MODULE = importlib.util.module_from_spec(SPEC)
assert SPEC and SPEC.loader
SPEC.loader.exec_module(MODULE)


class RenderManimFromManifestTests(unittest.TestCase):
    def test_render_script_uses_visual_bullets_and_hides_raw_narration_body(self):
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
            manifest_path = Path(tmp) / "scene_manifest.json"
            output_path = Path(tmp) / "script.py"
            manifest_path.write_text(json.dumps(manifest), encoding="utf-8")
            MODULE.render_script_from_manifest(manifest_path, output_path)
            script = output_path.read_text(encoding="utf-8")

        self.assertIn('def build_visual_panel(scene):', script)
        self.assertIn('progress = build_progress_indicator', script)
        self.assertIn('class S1RequestToPipeline(Scene):', script)
        self.assertIn('self.play(FadeIn(visual_panel, shift=UP * 0.18), run_time=beat_run)', script)
        self.assertIn('elapsed_intro = intro_title_run + beat_run', script)
        self.assertIn('remaining = max(scene_duration - elapsed_intro - pre_speech_wait - fade_out, 0.1)', script)
        self.assertNotIn('Text(scene.get("narration_text", "")', script)
        self.assertIn('self.add_subcaption(narration, duration=remaining)', script)

    def test_render_script_sanitizes_scene_ids_with_punctuation(self):
        manifest = {
            "version": 1,
            "mode": "narrated",
            "title": "Demo",
            "fps": 30,
            "scenes": [
                {
                    "scene_id": "S1_request: pipeline",
                    "goal": "Show the request becoming a pipeline.",
                    "visual_motif": "Prompt card becomes a four-stage rail",
                    "visual_bullets": ["Prompt card", "Stage rail"],
                    "narration_text": "Hermes turns one request into a pipeline.",
                    "speech_offset_s": 0.8,
                    "audio_duration_s": 5.0,
                    "pause_after_s": 1.2,
                }
            ],
        }
        with tempfile.TemporaryDirectory() as tmp:
            manifest_path = Path(tmp) / "scene_manifest.json"
            output_path = Path(tmp) / "script.py"
            manifest_path.write_text(json.dumps(manifest), encoding="utf-8")
            MODULE.render_script_from_manifest(manifest_path, output_path)
            script = output_path.read_text(encoding="utf-8")

        self.assertIn('class S1RequestPipeline(Scene):', script)


if __name__ == "__main__":
    unittest.main()
