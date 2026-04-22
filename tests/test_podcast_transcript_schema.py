import json
import sys
import tempfile
import unittest
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
SCRIPTS = ROOT / "scripts"
if str(SCRIPTS) not in sys.path:
    sys.path.insert(0, str(SCRIPTS))

import podcast_transcript_schema as pts  # type: ignore


class PodcastTranscriptSchemaTests(unittest.TestCase):
    def make_valid_transcript(self):
        return {
            "version": 1,
            "title": "AI Research Weekly",
            "episode_slug": "2026-04-21_ai-research-weekly",
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
                    "text": "The weird thing is that memory used to feel like a feature. [chuckle]",
                    "emotion": 0.82,
                    "tags": ["chuckle"],
                    "notes": ["cold_open", "topic_intro"],
                },
                {
                    "turn_id": "t02",
                    "speaker": "HOST_B",
                    "text": "Right, and now it feels like infrastructure.",
                    "emotion": 0.76,
                    "tags": [],
                    "notes": ["reframe"],
                },
            ],
        }

    def test_validate_and_load_valid_transcript_json(self):
        transcript = self.make_valid_transcript()
        with tempfile.TemporaryDirectory() as tmp:
            path = Path(tmp) / "transcript.json"
            path.write_text(json.dumps(transcript), encoding="utf-8")
            loaded = pts.load_transcript_json(path)

        self.assertEqual(loaded["title"], "AI Research Weekly")
        self.assertEqual(len(loaded["turns"]), 2)
        self.assertEqual(loaded["turns"][0]["speaker"], "HOST_A")

    def test_validate_rejects_missing_turns(self):
        transcript = self.make_valid_transcript()
        transcript.pop("turns")

        with self.assertRaises(ValueError):
            pts.validate_transcript(transcript)

    def test_validate_rejects_missing_required_tags_field(self):
        transcript = self.make_valid_transcript()
        transcript["turns"][0].pop("tags")

        with self.assertRaises(ValueError):
            pts.validate_transcript(transcript)

    def test_validate_rejects_missing_required_top_level_fields(self):
        transcript = self.make_valid_transcript()
        transcript.pop("title")

        with self.assertRaises(ValueError):
            pts.validate_transcript(transcript)

    def test_validate_rejects_unknown_speaker(self):
        transcript = self.make_valid_transcript()
        transcript["turns"][0]["speaker"] = "HOST_C"

        with self.assertRaises(ValueError):
            pts.validate_transcript(transcript)

    def test_validate_rejects_extra_host_entries(self):
        transcript = self.make_valid_transcript()
        transcript["hosts"]["HOST_C"] = {"role": "narrator"}

        with self.assertRaises(ValueError):
            pts.validate_transcript(transcript)

    def test_validate_rejects_turns_that_do_not_use_both_hosts(self):
        transcript = self.make_valid_transcript()
        transcript["turns"][1]["speaker"] = "HOST_A"

        with self.assertRaises(ValueError):
            pts.validate_transcript(transcript)

    def test_validate_rejects_invalid_emotion_values(self):
        transcript = self.make_valid_transcript()
        transcript["turns"][0]["emotion"] = "high"
        with self.assertRaises(ValueError):
            pts.validate_transcript(transcript)

        transcript = self.make_valid_transcript()
        transcript["turns"][0]["emotion"] = -0.1
        with self.assertRaises(ValueError):
            pts.validate_transcript(transcript)

    def test_extract_inline_tags(self):
        text = "That is the whole problem, honestly. [laugh] Then you realize it compounds. [sigh]"
        self.assertEqual(pts.extract_inline_tags(text), ["laugh", "sigh"])

    def test_validate_rejects_inline_tag_without_matching_tags_field(self):
        transcript = self.make_valid_transcript()
        transcript["turns"][0]["tags"] = []

        with self.assertRaises(ValueError):
            pts.validate_transcript(transcript)

    def test_validate_rejects_unsupported_or_malformed_inline_tags(self):
        transcript = self.make_valid_transcript()
        transcript["turns"][0]["text"] = "That point lands harder than it should. [boom]"
        transcript["turns"][0]["tags"] = ["boom"]
        with self.assertRaises(ValueError):
            pts.validate_transcript(transcript)

        transcript = self.make_valid_transcript()
        transcript["turns"][0]["text"] = "That point lands harder than it should. [Laugh]"
        transcript["turns"][0]["tags"] = []
        with self.assertRaises(ValueError):
            pts.validate_transcript(transcript)

    def test_save_transcript_json_uses_deterministic_ordering(self):
        transcript = self.make_valid_transcript()
        shuffled = {
            "turns": transcript["turns"],
            "hosts": transcript["hosts"],
            "generation_mode": transcript["generation_mode"],
            "title": transcript["title"],
            "show_slug": transcript["show_slug"],
            "episode_slug": transcript["episode_slug"],
            "version": transcript["version"],
            "duration_hint": transcript["duration_hint"],
        }

        with tempfile.TemporaryDirectory() as tmp:
            path = Path(tmp) / "transcript.json"
            pts.save_transcript_json(path, shuffled)
            saved = path.read_text(encoding="utf-8")

        self.assertTrue(saved.endswith("\n"))
        self.assertLess(saved.index('"duration_hint"'), saved.index('"episode_slug"'))
        self.assertLess(saved.index('"episode_slug"'), saved.index('"generation_mode"'))
        self.assertLess(saved.index('"generation_mode"'), saved.index('"hosts"'))
        self.assertLess(saved.index('"hosts"'), saved.index('"show_slug"'))
        self.assertLess(saved.index('"show_slug"'), saved.index('"title"'))
        self.assertLess(saved.index('"title"'), saved.index('"turns"'))
        self.assertLess(saved.index('"turns"'), saved.index('"version"'))

    def test_episode_slug_for_title(self):
        self.assertEqual(
            pts.episode_slug_for_title("AI Research Weekly!!!"),
            "ai-research-weekly",
        )


if __name__ == "__main__":
    unittest.main()
