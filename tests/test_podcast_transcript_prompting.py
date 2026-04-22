import json
import sys
import unittest
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
SCRIPTS = ROOT / "scripts"
if str(SCRIPTS) not in sys.path:
    sys.path.insert(0, str(SCRIPTS))

import podcast_transcript_prompting as ptp  # type: ignore


class PodcastTranscriptPromptingTests(unittest.TestCase):
    def test_build_draft_prompt_includes_host_profiles_and_source_references(self):
        source_packet = ptp.build_source_packet(
            files=[Path("/tmp/source-a.md"), Path("/tmp/source-b.txt")],
            urls=["https://example.com/alpha"],
            topic="Why agent memory matters",
            notes="Keep it grounded and skip boilerplate.",
        )

        prompt = ptp.build_draft_prompt(title="Memory Infrastructure Weekly", source_packet=source_packet)

        self.assertIn("HOST_A — The Connector", prompt)
        self.assertIn("HOST_B — The Interrogator", prompt)
        self.assertIn("spoken cadence", prompt)
        self.assertIn("Write for spoken delivery, not essay prose", prompt)
        self.assertIn("/tmp/source-a.md", prompt)
        self.assertIn("https://example.com/alpha", prompt)
        self.assertIn("Why agent memory matters", prompt)
        self.assertIn("Return ONLY canonical JSON", prompt)
        self.assertIn("Prioritize vocal texture", prompt)
        self.assertIn('"speaker": "HOST_A"', prompt)

    def test_build_revision_prompt_includes_audit_rubric_and_draft_json(self):
        draft = {
            "version": 1,
            "title": "Memory Infrastructure Weekly",
            "episode_slug": "memory-infrastructure-weekly",
            "show_slug": "memory-infrastructure-weekly",
            "duration_hint": "medium",
            "generation_mode": "podcastfy_compat",
            "hosts": {
                "HOST_A": {"role": "connector", "default_emotion": 0.8, "podcastfy_speaker": "Person1"},
                "HOST_B": {"role": "interrogator", "default_emotion": 0.75, "podcastfy_speaker": "Person2"},
            },
            "turns": [
                {
                    "turn_id": "t01",
                    "speaker": "HOST_A",
                    "text": "Memory used to feel optional.",
                    "emotion": 0.8,
                    "tags": [],
                }
            ],
        }
        source_packet = ptp.build_source_packet(files=[], urls=[], topic="Why agent memory matters", notes=None)

        prompt = ptp.build_revision_prompt(title="Memory Infrastructure Weekly", source_packet=source_packet, draft_transcript=draft)

        self.assertIn("make speakers more distinct", prompt)
        self.assertIn("smooth emotion arc", prompt)
        self.assertIn("create stronger emotional contrast", prompt)
        self.assertIn("spoken rhythm", prompt)
        self.assertIn("reduce tag overuse", prompt)
        self.assertIn(json.dumps(draft, indent=2, sort_keys=True), prompt)
        self.assertIn("Return ONLY revised canonical JSON", prompt)


if __name__ == "__main__":
    unittest.main()
