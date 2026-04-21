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

SPEC = importlib.util.spec_from_file_location("make_podcast", SCRIPTS / "make-podcast.py")
MODULE = importlib.util.module_from_spec(SPEC)
assert SPEC and SPEC.loader
SPEC.loader.exec_module(MODULE)


class MakePodcastStructuredTranscriptTests(unittest.TestCase):
    def make_valid_transcript(self, *, title: str = "AI Research Weekly"):
        return {
            "version": 1,
            "title": title,
            "episode_slug": "ai-research-weekly",
            "show_slug": "ai-research-weekly",
            "duration_hint": "medium",
            "generation_mode": "podcastfy_compat",
            "hosts": {
                "HOST_A": {
                    "role": "connector",
                    "default_emotion": 0.8,
                    "podcastfy_speaker": "Person1",
                },
                "HOST_B": {
                    "role": "interrogator",
                    "default_emotion": 0.75,
                    "podcastfy_speaker": "Person2",
                },
            },
            "turns": [
                {
                    "turn_id": "t01",
                    "speaker": "HOST_A",
                    "text": "Memory used to feel optional. [chuckle]",
                    "emotion": 0.82,
                    "tags": ["chuckle"],
                },
                {
                    "turn_id": "t02",
                    "speaker": "HOST_B",
                    "text": "Now it feels infrastructural.",
                    "emotion": 0.79,
                    "tags": [],
                },
            ],
        }

    def test_generate_structured_transcript_artifacts_writes_files_and_archives(self):
        draft = self.make_valid_transcript(title="Upgrade Dry Run")
        final = self.make_valid_transcript(title="Upgrade Dry Run")
        final["turns"][1]["text"] = "Now it feels like infrastructure, not a feature."

        with tempfile.TemporaryDirectory() as tmp:
            output_dir = Path(tmp)
            with mock.patch.object(MODULE, "archive_generated_json") as archive_json, mock.patch.object(
                MODULE, "archive_generated_text"
            ) as archive_text:
                artifacts = MODULE.generate_structured_transcript_artifacts(
                    title="Upgrade Dry Run",
                    files=[Path("/tmp/source.md")],
                    urls=["https://example.com/story"],
                    topic="Why agent memory matters",
                    notes="Keep it sharp.",
                    artifact_dir=output_dir,
                    hermes_runner=mock.Mock(side_effect=[json.dumps(draft), json.dumps(final)]),
                )

                self.assertEqual(artifacts["draft_path"].name, "transcript-draft.json")
                self.assertEqual(artifacts["transcript_path"].name, "transcript.json")
                self.assertEqual(artifacts["audit_path"].name, "transcript-audit.json")
                self.assertEqual(artifacts["rendered_path"].name, "transcript.txt")
                self.assertTrue(artifacts["draft_path"].exists())
                self.assertTrue(artifacts["transcript_path"].exists())
                self.assertTrue(artifacts["audit_path"].exists())
                self.assertTrue(artifacts["rendered_path"].exists())
                self.assertIn("<Person1>", artifacts["rendered_path"].read_text(encoding="utf-8"))
                self.assertGreaterEqual(archive_json.call_count, 2)
                archive_text.assert_called_once()
                archived_labels = [call.kwargs["artifact_label"] for call in archive_json.call_args_list]
                self.assertIn("transcript-structured", archived_labels)
                self.assertIn("transcript-audit", archived_labels)
                self.assertEqual(archive_text.call_args.kwargs["artifact_label"], "transcript-rendered")

    def test_main_dry_run_generates_artifacts_and_skips_tts(self):
        with tempfile.TemporaryDirectory() as tmp:
            output_dir = Path(tmp) / "podcasts"
            podcastfy_python = Path(tmp) / "python"
            podcastfy_python.write_text("#!/bin/sh\n", encoding="utf-8")
            expected_episode_dir = output_dir / "upgrade-dry-run"

            fake_artifacts = {
                "draft_path": expected_episode_dir / "transcript-draft.json",
                "transcript_path": expected_episode_dir / "transcript.json",
                "audit_path": expected_episode_dir / "transcript-audit.json",
                "rendered_path": expected_episode_dir / "transcript.txt",
                "audit": {"ok": True, "issues": [{"severity": "info", "code": "audit_clean", "message": "ok"}]},
            }
            expected_episode_dir.mkdir(parents=True)
            fake_artifacts["rendered_path"].write_text("<Person1>Hello</Person1>\n", encoding="utf-8")
            fake_artifacts["transcript_path"].write_text("{}\n", encoding="utf-8")

            argv = [
                "make-podcast.py",
                "--title",
                "Upgrade Dry Run",
                "--topic",
                "Why agent memory matters",
                "--dry-run",
                "--output-dir",
                str(output_dir),
                "--podcastfy-python",
                str(podcastfy_python),
            ]

            with mock.patch.object(MODULE, "generate_structured_transcript_artifacts", return_value=fake_artifacts) as generate_mock, mock.patch.object(
                MODULE, "run_pipeline"
            ) as run_pipeline_mock, mock.patch.object(MODULE.sys, "argv", argv):
                result = MODULE.main()

        self.assertEqual(result, 0)
        generate_mock.assert_called_once()
        run_pipeline_mock.assert_not_called()

    def test_main_with_canonical_transcript_archives_rendered_text(self):
        transcript = self.make_valid_transcript(title="Canonical Input Test")

        with tempfile.TemporaryDirectory() as tmp:
            output_dir = Path(tmp) / "podcasts"
            output_dir.mkdir()
            podcastfy_python = Path(tmp) / "python"
            podcastfy_python.write_text("#!/bin/sh\n", encoding="utf-8")
            transcript_path = Path(tmp) / "transcript.json"
            transcript_path.write_text(json.dumps(transcript), encoding="utf-8")

            argv = [
                "make-podcast.py",
                "--title",
                "Canonical Input Test",
                "--transcript",
                str(transcript_path),
                "--dry-run",
                "--output-dir",
                str(output_dir),
                "--podcastfy-python",
                str(podcastfy_python),
            ]

            with mock.patch.object(MODULE, "archive_generated_text") as archive_text, mock.patch.object(
                MODULE, "run_pipeline"
            ) as run_pipeline_mock, mock.patch.object(MODULE.sys, "argv", argv):
                result = MODULE.main()

        self.assertEqual(result, 0)
        archive_text.assert_called_once()
        self.assertEqual(archive_text.call_args.kwargs["artifact_label"], "transcript-rendered")
        self.assertIn("<Person1>", archive_text.call_args.kwargs["content"])
        self.assertNotIn('"hosts"', archive_text.call_args.kwargs["content"])
        run_pipeline_mock.assert_not_called()

    def test_main_with_legacy_transcript_archives_original_rendered_text(self):
        with tempfile.TemporaryDirectory() as tmp:
            output_dir = Path(tmp) / "podcasts"
            output_dir.mkdir()
            podcastfy_python = Path(tmp) / "python"
            podcastfy_python.write_text("#!/bin/sh\n", encoding="utf-8")
            transcript_path = Path(tmp) / "transcript.txt"
            transcript_path.write_text("HOST_A: Hello there.\nHOST_B: General Kenobi.\n", encoding="utf-8")

            argv = [
                "make-podcast.py",
                "--title",
                "Legacy Input Test",
                "--transcript",
                str(transcript_path),
                "--dry-run",
                "--output-dir",
                str(output_dir),
                "--podcastfy-python",
                str(podcastfy_python),
            ]

            with mock.patch.object(MODULE, "archive_generated_text") as archive_text, mock.patch.object(
                MODULE, "run_pipeline"
            ) as run_pipeline_mock, mock.patch.object(MODULE.sys, "argv", argv):
                result = MODULE.main()

        self.assertEqual(result, 0)
        archive_text.assert_called_once()
        self.assertIn("HOST_A: Hello there.", archive_text.call_args.kwargs["content"])
        run_pipeline_mock.assert_not_called()


if __name__ == "__main__":
    unittest.main()
