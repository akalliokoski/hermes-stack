import sys
import tempfile
import unittest
from pathlib import Path
from unittest import mock

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

    def test_assemble_master_track_writes_absolute_concat_entries_when_output_is_relative(self):
        manifest = {
            "audio": {"target_lufs": -16},
            "scenes": [
                {
                    "scene_id": "scene-1",
                    "timeline_offset_s": 0.0,
                    "speech_offset_s": 0.5,
                    "audio_duration_s": 1.0,
                    "audio_clip_path": "audio/scene-1.mp3",
                    "scene_duration_s": 2.0,
                }
            ],
        }
        with tempfile.TemporaryDirectory() as tmp:
            root = Path(tmp)
            manifest_path = root / "scene_manifest.json"
            manifest_path.write_text("{}", encoding="utf-8")
            output_path = Path("audio") / "master.mp3"
            expected_workdir = (Path.cwd() / output_path.parent / ".audio-work").resolve()

            def fake_run(cmd, text=True, capture_output=True, check=False):
                concat_path = Path(cmd[cmd.index("-i") + 1])
                concat_text = concat_path.read_text(encoding="utf-8")
                self.assertIn((expected_workdir / "segment-001-silence.wav").as_posix(), concat_text)
                self.assertIn((expected_workdir / "segment-002-clip.wav").as_posix(), concat_text)
                return mock.Mock(returncode=0, stderr="", stdout="")

            with mock.patch.object(vat, "load_manifest", return_value=manifest), \
                mock.patch.object(vat, "create_silence"), \
                mock.patch.object(vat, "ensure_wav_from_clip"), \
                mock.patch.object(vat.subprocess, "run", side_effect=fake_run):
                result = vat.assemble_master_track(manifest_path, output_path)

            self.assertEqual(result, output_path)

    def test_ensure_wav_from_clip_forces_concat_safe_pcm_format(self):
        calls = []

        def fake_run(cmd, text=True, capture_output=True, check=False):
            calls.append(cmd)
            return mock.Mock(returncode=0, stderr="", stdout="")

        with tempfile.TemporaryDirectory() as tmp:
            source = Path(tmp) / "scene.mp3"
            target = Path(tmp) / "scene.wav"
            source.write_bytes(b"fake")
            with mock.patch.object(vat.subprocess, "run", side_effect=fake_run):
                vat.ensure_wav_from_clip(source, target, -16)

        cmd = calls[0]
        self.assertIn("-ar", cmd)
        self.assertEqual(cmd[cmd.index("-ar") + 1], "44100")
        self.assertIn("-ac", cmd)
        self.assertEqual(cmd[cmd.index("-ac") + 1], "1")
        self.assertIn("-c:a", cmd)
        self.assertEqual(cmd[cmd.index("-c:a") + 1], "pcm_s16le")

    def test_synthesize_openai_compatible_creates_output_parent(self):
        with tempfile.TemporaryDirectory() as tmp:
            output_path = Path(tmp) / "nested" / "audio" / "clip.mp3"

            class FakeResponse:
                def __enter__(self):
                    return self

                def __exit__(self, exc_type, exc, tb):
                    return False

                def read(self):
                    return b"mp3-bytes"

            with mock.patch.object(vat.urllib.request, "urlopen", return_value=FakeResponse()):
                vat.synthesize_openai_compatible("https://example.com", "hello world", output_path, voice="Lucy")

            self.assertTrue(output_path.exists())
            self.assertEqual(output_path.read_bytes(), b"mp3-bytes")


if __name__ == "__main__":
    unittest.main()
