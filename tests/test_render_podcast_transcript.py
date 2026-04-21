import json
import subprocess
import sys
import tempfile
import unittest
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
SCRIPTS = ROOT / "scripts"
if str(SCRIPTS) not in sys.path:
    sys.path.insert(0, str(SCRIPTS))

import render_podcast_transcript as rpt  # type: ignore
import run_podcastfy_pipeline as rpp  # type: ignore


class RenderPodcastTranscriptTests(unittest.TestCase):
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
                },
                {
                    "turn_id": "t02",
                    "speaker": "HOST_B",
                    "text": " Right, and now it feels like infrastructure.  ",
                    "emotion": 0.76,
                    "tags": [],
                },
            ],
        }

    def test_render_for_podcastfy_maps_hosts_to_person_blocks(self):
        rendered = rpt.render_for_podcastfy(self.make_valid_transcript())

        self.assertEqual(
            rendered,
            "<Person1>The weird thing is that memory used to feel like a feature. [chuckle]</Person1>\n"
            "<Person2>Right, and now it feels like infrastructure.</Person2>",
        )

    def test_render_turn_preserves_inline_tags(self):
        transcript = self.make_valid_transcript()
        turn = transcript["turns"][0]

        rendered = rpt.render_turn(turn, transcript["hosts"])

        self.assertEqual(
            rendered,
            "<Person1>The weird thing is that memory used to feel like a feature. [chuckle]</Person1>",
        )

    def test_render_for_podcastfy_skips_empty_turns(self):
        transcript = self.make_valid_transcript()
        transcript["turns"].insert(
            1,
            {
                "turn_id": "t01b",
                "speaker": "HOST_B",
                "text": "   ",
                "emotion": 0.7,
                "tags": [],
            },
        )

        rendered = rpt.render_for_podcastfy(transcript)

        self.assertNotIn("t01b", rendered)
        self.assertEqual(rendered.count("<Person"), 2)

    def test_render_for_podcastfy_normalizes_internal_whitespace_cleanly(self):
        transcript = self.make_valid_transcript()
        transcript["turns"][1]["text"] = "Right,  and now\nit feels\tlike infrastructure."

        rendered = rpt.render_for_podcastfy(transcript)

        self.assertIn(
            "<Person2>Right, and now it feels like infrastructure.</Person2>",
            rendered,
        )

    def test_write_rendered_outputs_writes_text_and_sidecar_metadata(self):
        transcript = self.make_valid_transcript()
        with tempfile.TemporaryDirectory() as tmp:
            output_path = Path(tmp) / "transcript.txt"
            metadata_path = Path(tmp) / "transcript.render.json"

            rpt.write_rendered_outputs(
                transcript,
                output_path=output_path,
                metadata_path=metadata_path,
            )

            self.assertEqual(
                output_path.read_text(encoding="utf-8"),
                "<Person1>The weird thing is that memory used to feel like a feature. [chuckle]</Person1>\n"
                "<Person2>Right, and now it feels like infrastructure.</Person2>\n",
            )
            metadata = json.loads(metadata_path.read_text(encoding="utf-8"))

        self.assertEqual(metadata["turn_count"], 2)
        self.assertEqual(metadata["speakers"], ["Person1", "Person2"])

    def test_cli_reads_json_and_emits_rendered_text(self):
        transcript = self.make_valid_transcript()
        with tempfile.TemporaryDirectory() as tmp:
            transcript_path = Path(tmp) / "transcript.json"
            output_path = Path(tmp) / "transcript.txt"
            transcript_path.write_text(json.dumps(transcript), encoding="utf-8")

            completed = subprocess.run(
                [
                    sys.executable,
                    str(SCRIPTS / "render_podcast_transcript.py"),
                    "--input",
                    str(transcript_path),
                    "--output",
                    str(output_path),
                ],
                check=False,
                capture_output=True,
                text=True,
            )

            self.assertEqual(completed.returncode, 0, completed.stderr)
            self.assertEqual(
                output_path.read_text(encoding="utf-8"),
                "<Person1>The weird thing is that memory used to feel like a feature. [chuckle]</Person1>\n"
                "<Person2>Right, and now it feels like infrastructure.</Person2>\n",
            )

    def test_run_podcastfy_pipeline_auto_renders_canonical_json(self):
        transcript = self.make_valid_transcript()

        normalized = rpp.normalize_transcript(json.dumps(transcript))

        self.assertEqual(
            normalized,
            "<Person1>The weird thing is that memory used to feel like a feature. [chuckle]</Person1>\n"
            "<Person2>Right, and now it feels like infrastructure.</Person2>",
        )

    def test_run_podcastfy_pipeline_rejects_structurally_incomplete_canonical_json(self):
        transcript = self.make_valid_transcript()
        transcript.pop("title")

        with self.assertRaises(ValueError):
            rpp.normalize_transcript(json.dumps(transcript))

    def test_run_podcastfy_pipeline_keeps_backward_compatible_raw_transcript_text(self):
        raw = "HOST_A: Hello there.\n\nHOST_B: General Kenobi."

        normalized = rpp.normalize_transcript(raw)

        self.assertEqual(
            normalized,
            "<Person1>Hello there.</Person1>\n<Person2>General Kenobi.</Person2>",
        )


if __name__ == "__main__":
    unittest.main()
