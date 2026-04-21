import importlib.util
import sys
import unittest
from pathlib import Path
from unittest import mock

ROOT = Path(__file__).resolve().parents[1]
SCRIPTS = ROOT / "scripts"
if str(SCRIPTS) not in sys.path:
    sys.path.insert(0, str(SCRIPTS))

SPEC = importlib.util.spec_from_file_location("audiobookshelf_api", SCRIPTS / "audiobookshelf_api.py")
MODULE = importlib.util.module_from_spec(SPEC)
assert SPEC and SPEC.loader
SPEC.loader.exec_module(MODULE)


class AudiobookshelfApiTests(unittest.TestCase):
    def test_profile_library_helpers(self):
        self.assertEqual(MODULE.profile_library_path("default"), "/podcasts/profiles/default")
        self.assertEqual(MODULE.profile_library_path("gemma"), "/podcasts/profiles/gemma")

    def test_ensure_profile_library_uses_profile_specific_name_and_path(self):
        with mock.patch.object(MODULE, "ensure_library", return_value={"id": "lib1"}) as ensure_mock:
            library = MODULE.ensure_profile_library("token", "gemma")

        self.assertEqual(library, {"id": "lib1"})
        ensure_mock.assert_called_once_with(
            "token",
            name="Gemma Podcasts",
            podcasts_path="/podcasts/profiles/gemma",
        )

    def test_ensure_profile_libraries_and_scan_scans_each_profile(self):
        with mock.patch.object(MODULE, "login", return_value="token"), \
             mock.patch.object(MODULE, "discover_profiles", return_value=["default", "gemma"]), \
             mock.patch.object(MODULE, "ensure_profile_library", side_effect=[{"id": "lib-default", "name": "Default Podcasts"}, {"id": "lib-gemma", "name": "Gemma Podcasts"}]), \
             mock.patch.object(MODULE, "scan_library", side_effect=[{"ok": True}, {"ok": True}]):
            summaries = MODULE.ensure_profile_libraries_and_scan()

        self.assertEqual([summary["profile"] for summary in summaries], ["default", "gemma"])
        self.assertEqual(summaries[0]["library"]["name"], "Default Podcasts")
        self.assertEqual(summaries[1]["library"]["name"], "Gemma Podcasts")


if __name__ == "__main__":
    unittest.main()
