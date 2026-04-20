import importlib.util
import sys
import tempfile
import unittest
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
SCRIPTS = ROOT / "scripts"
if str(SCRIPTS) not in sys.path:
    sys.path.insert(0, str(SCRIPTS))

SPEC = importlib.util.spec_from_file_location("make_manim_video", SCRIPTS / "make-manim-video.py")
MODULE = importlib.util.module_from_spec(SPEC)
assert SPEC and SPEC.loader
SPEC.loader.exec_module(MODULE)


class MakeManimVideoScaffoldTests(unittest.TestCase):
    def test_write_narrated_project_artifacts(self):
        with tempfile.TemporaryDirectory() as tmp:
            project_dir = Path(tmp) / "project"
            project_dir.mkdir()
            brief = """# Overview\n\nDemo\n\n# Scene Plan\n\n1. Intro: explain the first idea.\n2. Outro: explain the second idea.\n"""
            MODULE.write_narrated_project_artifacts(project_dir, "Demo Title", brief)

            manifest_path = project_dir / "scene_manifest.json"
            narration_path = project_dir / "narration-script.md"
            self.assertTrue(manifest_path.exists())
            self.assertTrue(narration_path.exists())
            manifest_text = manifest_path.read_text(encoding="utf-8")
            narration_text = narration_path.read_text(encoding="utf-8")
            self.assertIn('"mode": "narrated"', manifest_text)
            self.assertIn("## scene-01-intro", narration_text)
            self.assertIn("## scene-02-outro", narration_text)

    def test_render_script_uses_manifest_aware_defaults(self):
        with tempfile.TemporaryDirectory() as tmp:
            project_dir = Path(tmp) / "project"
            project_dir.mkdir()
            render_path = project_dir / "render.sh"
            MODULE.write_render_script(render_path, project_dir, "Demo Title")
            render_text = render_path.read_text(encoding="utf-8")
            self.assertIn('SCENES=()', render_text)
            self.assertIn('STITCHED_OUTPUT=0', render_text)
            self.assertIn('NARRATED_OUTPUT=0', render_text)
            self.assertIn('"$MANIM_BIN" -"$QUALITY" -a script.py', render_text)
            self.assertIn('video_audio_timeline.py synthesize', render_text)
            self.assertIn('render_manim_from_manifest.py --manifest scene_manifest.json --output script.py', render_text)
            self.assertIn('CONCAT_LIST="$PROJECT_DIR/concat-scenes.txt"', render_text)
            self.assertIn('case "$QUALITY" in', render_text)
            self.assertIn('QUALITY_SUBDIR="480p15"', render_text)
            self.assertIn('def normalized_name(value: str) -> str:', render_text)
            self.assertIn('ffmpeg -y -hide_banner -loglevel error -f concat -safe 0 -i "$CONCAT_LIST" -c copy "$FINAL_OUTPUT"', render_text)
            self.assertIn('ffmpeg -y -hide_banner -loglevel error -i "$FINAL_OUTPUT" -i audio/master-narration.mp3 -c:v copy -c:a aac -b:a 192k -shortest "$FINAL_NARRATED_OUTPUT"', render_text)
            self.assertLess(render_text.index('video_audio_timeline.py synthesize'), render_text.index('render_manim_from_manifest.py --manifest scene_manifest.json --output script.py'))


if __name__ == "__main__":
    unittest.main()
