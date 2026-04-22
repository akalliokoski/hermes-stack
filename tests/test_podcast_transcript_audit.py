import sys
import unittest
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
SCRIPTS = ROOT / "scripts"
if str(SCRIPTS) not in sys.path:
    sys.path.insert(0, str(SCRIPTS))

import podcast_transcript_audit as pta  # type: ignore


class PodcastTranscriptAuditTests(unittest.TestCase):
    def make_valid_transcript(self):
        return {
            "version": 1,
            "title": "AI Research Weekly",
            "episode_slug": "2026-04-21_ai-research-weekly",
            "show_slug": "ai-research-weekly",
            "duration_hint": "short",
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
                    "emotion": 0.72,
                    "tags": ["chuckle"],
                },
                {
                    "turn_id": "t02",
                    "speaker": "HOST_B",
                    "text": "Now it feels infrastructural.",
                    "emotion": 0.78,
                    "tags": [],
                },
                {
                    "turn_id": "t03",
                    "speaker": "HOST_A",
                    "text": "And the strange part is how fast that happened.",
                    "emotion": 0.94,
                    "tags": [],
                },
                {
                    "turn_id": "t04",
                    "speaker": "HOST_B",
                    "text": "That acceleration is the whole story.",
                    "emotion": 0.81,
                    "tags": [],
                },
            ],
        }

    def get_messages(self, audit, code):
        return [issue for issue in audit["issues"] if issue["code"] == code]

    def test_validate_tag_placement_flags_unknown_tag_and_bad_positioning(self):
        messages = pta.validate_tag_placement("We cut straight in [boom] and keep going. [laugh][sigh]")
        joined = "\n".join(messages)
        self.assertIn("unsupported tag: boom", joined)
        self.assertIn("must follow completed clause or sentence", joined)
        self.assertIn("multiple inline tags in a row", joined)

    def test_audit_warns_on_gasp_overuse(self):
        transcript = self.make_valid_transcript()
        transcript["turns"][1]["text"] = "That shift is bigger than it looks. [gasp]"
        transcript["turns"][1]["tags"] = ["gasp"]
        transcript["turns"][2]["text"] = "And it happened in public view. [gasp]"
        transcript["turns"][2]["tags"] = ["gasp"]

        audit = pta.audit_transcript(transcript)

        messages = self.get_messages(audit, "gasp_overuse")
        self.assertEqual(messages[0]["severity"], "warning")
        self.assertIn("extremely rare", messages[0]["message"])

    def test_audit_warns_on_cough_usage_as_suspicious(self):
        transcript = self.make_valid_transcript()
        transcript["turns"][1]["text"] = "That transition feels forced. [cough]"
        transcript["turns"][1]["tags"] = ["cough"]

        audit = pta.audit_transcript(transcript)

        messages = self.get_messages(audit, "cough_suspicious")
        self.assertEqual(messages[0]["severity"], "warning")
        self.assertIn("suspicious", messages[0]["message"])

    def test_audit_warns_on_too_many_tags_for_short_episode(self):
        transcript = self.make_valid_transcript()
        transcript["turns"] = [
            {
                "turn_id": "t01",
                "speaker": "HOST_A",
                "text": "One thing breaks. [laugh]",
                "emotion": 0.72,
                "tags": ["laugh"],
            },
            {
                "turn_id": "t02",
                "speaker": "HOST_B",
                "text": "Then another thing breaks. [sigh]",
                "emotion": 0.77,
                "tags": ["sigh"],
            },
            {
                "turn_id": "t03",
                "speaker": "HOST_A",
                "text": "Then the framing breaks. [chuckle]",
                "emotion": 0.8,
                "tags": ["chuckle"],
            },
            {
                "turn_id": "t04",
                "speaker": "HOST_B",
                "text": "And now the room changes. [gasp]",
                "emotion": 0.95,
                "tags": ["gasp"],
            },
        ]

        audit = pta.audit_transcript(transcript)

        messages = self.get_messages(audit, "tag_density_short_episode")
        self.assertEqual(messages[0]["severity"], "warning")
        self.assertIn("short episode", messages[0]["message"])

    def test_speaker_balance_summary_warns_when_one_speaker_dominates(self):
        turns = [
            {"speaker": "HOST_A"},
            {"speaker": "HOST_A"},
            {"speaker": "HOST_A"},
            {"speaker": "HOST_A"},
            {"speaker": "HOST_B"},
        ]

        summary = pta.speaker_balance_summary(turns)

        self.assertEqual(summary["dominant_speaker"], "HOST_A")
        self.assertGreater(summary["dominant_share"], 0.75)
        self.assertTrue(summary["imbalanced"])

    def test_audit_warns_when_emotion_values_are_flat(self):
        transcript = self.make_valid_transcript()
        for turn in transcript["turns"]:
            turn["emotion"] = 0.8

        audit = pta.audit_transcript(transcript)

        messages = self.get_messages(audit, "flat_emotion_arc")
        self.assertEqual(messages[0]["severity"], "warning")
        self.assertIn("flat", messages[0]["message"])

    def test_audit_warns_when_emotion_arc_is_muted_but_not_flat(self):
        transcript = self.make_valid_transcript()
        transcript["turns"][0]["emotion"] = 0.68
        transcript["turns"][1]["emotion"] = 0.71
        transcript["turns"][2]["emotion"] = 0.82
        transcript["turns"][3]["emotion"] = 0.79

        audit = pta.audit_transcript(transcript)

        messages = self.get_messages(audit, "muted_emotion_arc")
        self.assertEqual(messages[0]["severity"], "warning")
        self.assertIn("plain", messages[0]["message"])

    def test_audit_warns_when_emotion_arc_never_releases(self):
        transcript = self.make_valid_transcript()
        transcript["turns"] = [
            {
                "turn_id": "t01",
                "speaker": "HOST_A",
                "text": "We start calm.",
                "emotion": 0.68,
                "tags": [],
            },
            {
                "turn_id": "t02",
                "speaker": "HOST_B",
                "text": "Then the stakes rise.",
                "emotion": 0.74,
                "tags": [],
            },
            {
                "turn_id": "t03",
                "speaker": "HOST_A",
                "text": "Now things get sharper.",
                "emotion": 0.81,
                "tags": [],
            },
            {
                "turn_id": "t04",
                "speaker": "HOST_B",
                "text": "This is the peak.",
                "emotion": 0.91,
                "tags": [],
            },
            {
                "turn_id": "t05",
                "speaker": "HOST_A",
                "text": "But it barely settles.",
                "emotion": 0.88,
                "tags": [],
            },
            {
                "turn_id": "t06",
                "speaker": "HOST_B",
                "text": "And it stays hot into the close.",
                "emotion": 0.87,
                "tags": [],
            },
        ]

        audit = pta.audit_transcript(transcript)

        messages = self.get_messages(audit, "missing_emotion_release")
        self.assertEqual(messages[0]["severity"], "warning")
        self.assertIn("drop enough", messages[0]["message"])

    def test_audit_does_not_warn_on_release_when_arc_cools_after_peak(self):
        transcript = self.make_valid_transcript()
        transcript["turns"] = [
            {
                "turn_id": "t01",
                "speaker": "HOST_A",
                "text": "We start calm.",
                "emotion": 0.68,
                "tags": [],
            },
            {
                "turn_id": "t02",
                "speaker": "HOST_B",
                "text": "Then the stakes rise.",
                "emotion": 0.74,
                "tags": [],
            },
            {
                "turn_id": "t03",
                "speaker": "HOST_A",
                "text": "Now things get sharper.",
                "emotion": 0.81,
                "tags": [],
            },
            {
                "turn_id": "t04",
                "speaker": "HOST_B",
                "text": "This is the peak.",
                "emotion": 0.91,
                "tags": [],
            },
            {
                "turn_id": "t05",
                "speaker": "HOST_A",
                "text": "Then it settles.",
                "emotion": 0.77,
                "tags": [],
            },
            {
                "turn_id": "t06",
                "speaker": "HOST_B",
                "text": "And it lands cleanly.",
                "emotion": 0.73,
                "tags": [],
            },
        ]

        audit = pta.audit_transcript(transcript)

        messages = self.get_messages(audit, "missing_emotion_release")
        self.assertEqual(messages, [])

    def test_audit_warns_when_arc_briefly_dips_then_reheats_after_peak(self):
        transcript = self.make_valid_transcript()
        transcript["turns"] = [
            {
                "turn_id": "t01",
                "speaker": "HOST_A",
                "text": "We start calm.",
                "emotion": 0.68,
                "tags": [],
            },
            {
                "turn_id": "t02",
                "speaker": "HOST_B",
                "text": "Then the stakes rise.",
                "emotion": 0.74,
                "tags": [],
            },
            {
                "turn_id": "t03",
                "speaker": "HOST_A",
                "text": "Now things get sharper.",
                "emotion": 0.81,
                "tags": [],
            },
            {
                "turn_id": "t04",
                "speaker": "HOST_B",
                "text": "This is the peak.",
                "emotion": 0.91,
                "tags": [],
            },
            {
                "turn_id": "t05",
                "speaker": "HOST_A",
                "text": "It dips for a second.",
                "emotion": 0.77,
                "tags": [],
            },
            {
                "turn_id": "t06",
                "speaker": "HOST_B",
                "text": "Then it heats back up into the ending.",
                "emotion": 0.9,
                "tags": [],
            },
        ]

        audit = pta.audit_transcript(transcript)

        messages = self.get_messages(audit, "missing_emotion_release")
        self.assertEqual(messages[0]["severity"], "warning")

    def test_emotion_arc_summary_flags_peak_too_early(self):
        turns = [
            {"emotion": 1.0},
            {"emotion": 0.7},
            {"emotion": 0.75},
            {"emotion": 0.8},
            {"emotion": 0.82},
        ]

        summary = pta.emotion_arc_summary(turns)

        self.assertEqual(summary["peak_turn_index"], 0)
        self.assertTrue(summary["peak_too_early"])
        self.assertFalse(summary["missing_peak"])

    def test_emotion_arc_summary_flags_missing_peak(self):
        turns = [
            {"emotion": 0.62},
            {"emotion": 0.66},
            {"emotion": 0.68},
            {"emotion": 0.69},
        ]

        summary = pta.emotion_arc_summary(turns)

        self.assertTrue(summary["missing_peak"])
        self.assertIsNone(summary["peak_turn_index"])

    def test_audit_hard_fails_on_structural_invalidity(self):
        transcript = self.make_valid_transcript()
        transcript["turns"][0]["speaker"] = "HOST_C"

        audit = pta.audit_transcript(transcript)

        messages = self.get_messages(audit, "structural_invalidity")
        self.assertEqual(messages[0]["severity"], "error")
        self.assertFalse(audit["ok"])


if __name__ == "__main__":
    unittest.main()
