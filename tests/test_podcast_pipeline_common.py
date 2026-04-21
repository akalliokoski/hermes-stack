import datetime as dt
import json
import sys
import tempfile
import unittest
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
SCRIPTS = ROOT / "scripts"
if str(SCRIPTS) not in sys.path:
    sys.path.insert(0, str(SCRIPTS))

import podcast_pipeline_common as ppc  # type: ignore


class PodcastPipelineCommonArchiveTests(unittest.TestCase):
    def test_archive_generated_json_writes_structured_transcript_path_and_provenance(self):
        with tempfile.TemporaryDirectory() as tmp:
            wiki_root = Path(tmp) / "wiki"
            wiki_root.mkdir()
            ppc.DEFAULT_WIKI_PATH = str(wiki_root)

            archived_path = ppc.archive_generated_json(
                category="podcasts",
                title="AI Research Weekly",
                data={"version": 1, "turns": []},
                artifact_label="transcript-structured",
                purpose="Archive canonical structured podcast transcript JSON.",
                pipeline_name="podcast-pipeline",
            )

            expected_name = f"{dt.date.today().isoformat()}_ai-research-weekly-transcript-structured.json"
            self.assertEqual(
                archived_path,
                wiki_root / "raw" / "transcripts" / "media" / "podcasts" / expected_name,
            )
            payload = json.loads(archived_path.read_text(encoding="utf-8"))

        self.assertEqual(payload["version"], 1)
        self.assertEqual(payload["provenance"]["pipeline_name"], "podcast-pipeline")
        self.assertEqual(payload["provenance"]["title"], "AI Research Weekly")
        self.assertEqual(payload["provenance"]["artifact_label"], "transcript-structured")

    def test_archive_generated_json_uses_audit_sidecar_naming(self):
        with tempfile.TemporaryDirectory() as tmp:
            wiki_root = Path(tmp) / "wiki"
            wiki_root.mkdir()
            ppc.DEFAULT_WIKI_PATH = str(wiki_root)

            archived_path = ppc.archive_generated_json(
                category="podcasts",
                title="AI Research Weekly",
                data={"ok": True, "issues": []},
                artifact_label="transcript-audit",
                purpose="Archive transcript audit results.",
                pipeline_name="podcast-pipeline",
            )

            self.assertEqual(
                archived_path.name,
                f"{dt.date.today().isoformat()}_ai-research-weekly-transcript-audit.json",
            )

    def test_archive_generated_text_uses_rendered_transcript_naming_and_provenance_block(self):
        with tempfile.TemporaryDirectory() as tmp:
            wiki_root = Path(tmp) / "wiki"
            wiki_root.mkdir()
            ppc.DEFAULT_WIKI_PATH = str(wiki_root)

            archived_path = ppc.archive_generated_text(
                category="podcasts",
                title="AI Research Weekly",
                content="<Person1>Hello</Person1>",
                artifact_label="transcript-rendered",
                purpose="Archive rendered transcript markdown for review.",
                pipeline_name="podcast-pipeline",
            )
            archived_text = archived_path.read_text(encoding="utf-8")

        self.assertEqual(
            archived_path.name,
            f"{dt.date.today().isoformat()}_ai-research-weekly-transcript-rendered.md",
        )
        self.assertIn("## Provenance", archived_text)
        self.assertIn("- Pipeline: `podcast-pipeline`", archived_text)
        self.assertIn("- Title: `AI Research Weekly`", archived_text)


if __name__ == "__main__":
    unittest.main()
