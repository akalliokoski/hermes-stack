import importlib.util
import io
import sys
import tempfile
import unittest
from contextlib import redirect_stderr, redirect_stdout
from pathlib import Path
from unittest import mock

ROOT = Path(__file__).resolve().parents[1]
SCRIPTS = ROOT / "scripts"
if str(SCRIPTS) not in sys.path:
    sys.path.insert(0, str(SCRIPTS))

SPEC = importlib.util.spec_from_file_location("bootstrap_audiobookshelf", SCRIPTS / "bootstrap-audiobookshelf.py")
MODULE = importlib.util.module_from_spec(SPEC)
assert SPEC and SPEC.loader
SPEC.loader.exec_module(MODULE)


class BootstrapAudiobookshelfTests(unittest.TestCase):
    def test_main_warns_and_succeeds_when_directory_setup_fails(self):
        with mock.patch.object(MODULE, "ensure_host_directories", side_effect=RuntimeError("no perms")):
            stdout = io.StringIO()
            stderr = io.StringIO()
            with redirect_stdout(stdout), redirect_stderr(stderr):
                exit_code = MODULE.main()

        self.assertEqual(exit_code, 0)
        self.assertIn("skipping library bootstrap", stderr.getvalue())

    def test_ensure_host_directories_creates_expected_roots(self):
        with tempfile.TemporaryDirectory() as tmp:
            root = Path(tmp) / "podcasts"
            projects = Path(tmp) / "projects"
            with mock.patch.object(MODULE, "HOST_PROFILE_PODCASTS_ROOT", root), \
                 mock.patch.object(MODULE, "HOST_PODCAST_PROJECTS_ROOT", projects):
                MODULE.ensure_host_directories()

                self.assertTrue(root.exists())
                self.assertTrue(projects.exists())

    def test_main_bootstraps_profile_libraries(self):
        with mock.patch.object(MODULE, "ensure_host_directories") as ensure_dirs, \
             mock.patch.object(MODULE, "wait_for_server", return_value={"isInit": True}), \
             mock.patch.object(MODULE, "ensure_initialized", return_value=False), \
             mock.patch.object(MODULE, "ensure_profile_libraries_and_scan", return_value=[{"profile": "default", "library": {"name": "Default Podcasts", "folders": []}}]) as bootstrap_mock:
            exit_code = MODULE.main()

        self.assertEqual(exit_code, 0)
        ensure_dirs.assert_called_once()
        bootstrap_mock.assert_called_once()


if __name__ == "__main__":
    unittest.main()
