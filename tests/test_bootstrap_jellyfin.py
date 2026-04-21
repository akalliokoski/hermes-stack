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
            db_path = Path(tmp) / "missing.db"
            with mock.patch.object(MODULE, "JELLYFIN_HOST_PROFILE_VIDEOS_ROOT", root), \
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

    def test_wait_for_server_polls_public_info_endpoint(self):
        with mock.patch.object(MODULE, "request", side_effect=[RuntimeError("not ready"), {"ServerName": "jellyfin"}]) as request_mock:
            MODULE.wait_for_server(timeout_seconds=0.01)
        self.assertEqual(request_mock.call_count, 2)
        request_mock.assert_called_with("/System/Info/Public", token="")


if __name__ == "__main__":
    unittest.main()
