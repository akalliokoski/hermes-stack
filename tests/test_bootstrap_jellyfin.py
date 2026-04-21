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

SPEC = importlib.util.spec_from_file_location("bootstrap_jellyfin", SCRIPTS / "bootstrap-jellyfin.py")
MODULE = importlib.util.module_from_spec(SPEC)
assert SPEC and SPEC.loader
SPEC.loader.exec_module(MODULE)


class BootstrapJellyfinTests(unittest.TestCase):
    def test_main_warns_and_succeeds_without_token(self):
        with tempfile.TemporaryDirectory() as tmp:
            root = Path(tmp) / "videos"
            legacy_root = root / "ai-generated"
            db_path = Path(tmp) / "missing.db"
            with mock.patch.object(MODULE, "JELLYFIN_HOST_PROFILE_VIDEOS_ROOT", root), \
                 mock.patch.object(MODULE, "JELLYFIN_HOST_LEGACY_VIDEOS_ROOT", legacy_root), \
                 mock.patch.object(MODULE, "JELLYFIN_DB_PATH", db_path), \
                 mock.patch.object(MODULE, "wait_for_server", return_value=None), \
                 mock.patch.object(sys, "argv", ["bootstrap-jellyfin.py"]):
                stdout = io.StringIO()
                stderr = io.StringIO()
                with redirect_stdout(stdout), redirect_stderr(stderr):
                    exit_code = MODULE.main()

                self.assertEqual(exit_code, 0)
                self.assertIn("skipping library bootstrap", stderr.getvalue())
                self.assertTrue((root / "default").exists())
                self.assertTrue(legacy_root.exists())

    def test_wait_for_server_polls_public_info_endpoint(self):
        with mock.patch.object(MODULE, "request", side_effect=[RuntimeError("not ready"), {"ServerName": "jellyfin"}]) as request_mock:
            MODULE.wait_for_server(timeout_seconds=0.01)
        self.assertEqual(request_mock.call_count, 2)
        request_mock.assert_called_with("/System/Info/Public", token="")

    def test_ensure_virtual_folder_recreates_wrong_legacy_path(self):
        with mock.patch.object(
            MODULE,
            "get_virtual_folders",
            return_value=[{"Name": "AI Generated Videos", "Locations": ["/media/videos"]}],
        ), mock.patch.object(MODULE, "remove_virtual_folder") as remove_mock, mock.patch.object(MODULE, "request") as request_mock:
            changed = MODULE.ensure_virtual_folder(
                token="token",
                name="AI Generated Videos",
                container_path="/media/videos/ai-generated",
            )

        self.assertTrue(changed)
        remove_mock.assert_called_once_with(token="token", name="AI Generated Videos")
        request_mock.assert_called_once()


if __name__ == "__main__":
    unittest.main()
