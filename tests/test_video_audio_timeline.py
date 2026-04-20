import sys
import tempfile
import unittest
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
SCRIPTS = ROOT / "scripts"
if str(SCRIPTS) not in sys.path:
    sys.path.insert(0, str(SCRIPTS))

import video_audio_timeline as vat  # type: ignore


class VideoAudioTimelineTests(unittest.TestCase):
    def test_words_per_second(self):
        self.assertAlmostEqual(vat.words_per_second("one two three four", 2.0), 2.0)

    def test_repair_scene_overrun_uses_atempo_for_small_overrun(self):
        decision = vat.repair_scene_overrun(
            scene={"scene_id": "scene-1", "pause_after_s": 0.2},
            target_duration_s=5.0,
            measured_duration_s=5.25,
            max_atempo=1.08,
            available_pause_slack_s=0.1,
        )
        self.assertEqual(decision["action"], "atempo")
        self.assertGreater(decision["atempo"], 1.0)

    def test_repair_scene_overrun_spends_pause_slack_before_rewrite(self):
        decision = vat.repair_scene_overrun(
            scene={"scene_id": "scene-2", "pause_after_s": 1.0},
            target_duration_s=5.0,
            measured_duration_s=5.4,
            max_atempo=1.04,
            available_pause_slack_s=0.5,
        )
        self.assertEqual(decision["action"], "spend_pause_slack")

    def test_generate_scene_srt_uses_manifest_offsets(self):
        manifest = {
            "fps": 30,
            "scenes": [
                {
                    "scene_id": "scene-1",
                    "narration_text": "Hello world.",
                    "timeline_offset_s": 1.0,
                    "speech_offset_s": 0.5,
                    "audio_duration_s": 2.25,
                    "scene_duration_s": 3.5,
                }
            ],
        }
        srt = vat.generate_scene_srt(manifest)
        self.assertIn("00:00:01,500 --> 00:00:03,750", srt)
        self.assertIn("Hello world.", srt)

    def test_build_concat_plan_creates_silence_and_clip_sequence(self):
        manifest = {
            "fps": 30,
            "scenes": [
                {"scene_id": "scene-1", "timeline_offset_s": 0.0, "speech_offset_s": 0.5, "audio_duration_s": 2.0, "audio_clip_path": "audio/scene-1.mp3"},
                {"scene_id": "scene-2", "timeline_offset_s": 4.0, "speech_offset_s": 0.25, "audio_duration_s": 1.5, "audio_clip_path": "audio/scene-2.mp3"},
            ],
        }
        with tempfile.TemporaryDirectory() as tmp:
            plan = vat.build_concat_plan(Path(tmp), manifest)
        self.assertGreaterEqual(len(plan), 4)
        self.assertEqual(plan[1]["type"], "clip")
        self.assertEqual(plan[1]["source"], "audio/scene-1.mp3")

    def test_build_concat_plan_skips_scenes_without_audio(self):
        manifest = {
            "fps": 30,
            "scenes": [
                {"scene_id": "scene-1", "timeline_offset_s": 0.0, "speech_offset_s": 0.5, "audio_duration_s": 0.0, "scene_duration_s": 3.0},
                {"scene_id": "scene-2", "timeline_offset_s": 3.0, "speech_offset_s": 0.25, "audio_duration_s": 1.5, "audio_clip_path": "audio/scene-2.mp3", "scene_duration_s": 3.0},
            ],
        }
        with tempfile.TemporaryDirectory() as tmp:
            plan = vat.build_concat_plan(Path(tmp), manifest)
        self.assertEqual([item["type"] for item in plan], ["silence", "clip", "silence"])


if __name__ == "__main__":
    unittest.main()
