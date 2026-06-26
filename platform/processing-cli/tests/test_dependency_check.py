from __future__ import annotations

import contextlib
import io
import json
import os
import stat
import tempfile
import unittest
from pathlib import Path

from meeting_assistant_cli.cli import main
from meeting_assistant_cli.dependency_check import run_dependency_check


def _fake_executable(directory: Path, name: str) -> str:
    path = directory / name
    path.write_text("#!/usr/bin/env sh\nexit 0\n", encoding="utf-8")
    path.chmod(path.stat().st_mode | stat.S_IXUSR)
    return str(path)


class DependencyCheckTests(unittest.TestCase):
    def fake_env(self, bin_dir: Path) -> dict[str, str]:
        return {
            "PATH": str(bin_dir),
            "MEETING_ASSISTANT_OS_NAME": "Darwin",
            "MEETING_ASSISTANT_MACOS_VERSION": "26.5.1",
            "MEETING_ASSISTANT_CPU_ARCH": "arm64",
            "MEETING_ASSISTANT_TRANSCRIPTION_RUNTIME": "whisper-local",
            "MEETING_ASSISTANT_SCREEN_RECORDING_PERMISSION": "unknown",
            "MEETING_ASSISTANT_MICROPHONE_PERMISSION": "granted",
        }

    def test_success_response_reports_required_dependency_status(self) -> None:
        with tempfile.TemporaryDirectory() as tmp:
            root = Path(tmp)
            bin_dir = root / "bin"
            workspace = root / "workspace"
            bin_dir.mkdir()
            _fake_executable(bin_dir, "swift")
            _fake_executable(bin_dir, "ffmpeg")
            _fake_executable(bin_dir, "whisper-local")

            response = run_dependency_check(workspace, self.fake_env(bin_dir))

        self.assertTrue(response["ok"])
        self.assertEqual(response["command"], "check_dependencies")
        checks = {item["id"]: item for item in response["checks"]}
        self.assertEqual(checks["platform.os"]["status"], "supported")
        self.assertEqual(checks["media_tool.ffmpeg"]["status"], "available")
        self.assertEqual(checks["transcription.runtime"]["status"], "available")
        self.assertEqual(checks["speaker_labeling.runtime"]["status"], "missing")
        self.assertEqual(checks["dependency_downloads.automatic"]["status"], "not_attempted")
        self.assertIn("request_id", response)

    def test_missing_required_dependency_returns_ok_false(self) -> None:
        with tempfile.TemporaryDirectory() as tmp:
            root = Path(tmp)
            bin_dir = root / "bin"
            workspace = root / "workspace"
            bin_dir.mkdir()
            _fake_executable(bin_dir, "swift")
            env = self.fake_env(bin_dir)
            response = run_dependency_check(workspace, env)

        self.assertFalse(response["ok"])
        self.assertEqual(response["code"], "dependency_missing")
        checks = {item["id"]: item for item in response["checks"]}
        self.assertEqual(checks["media_tool.ffmpeg"]["status"], "missing")

    def test_cli_emits_json_and_nonzero_on_missing_dependency(self) -> None:
        with tempfile.TemporaryDirectory() as tmp:
            root = Path(tmp)
            bin_dir = root / "bin"
            workspace = root / "workspace"
            bin_dir.mkdir()
            _fake_executable(bin_dir, "swift")
            env = self.fake_env(bin_dir)
            old_env = os.environ.copy()
            os.environ.clear()
            os.environ.update(env)
            stdout = io.StringIO()
            try:
                with contextlib.redirect_stdout(stdout):
                    exit_code = main(["check_dependencies", "--workspace-dir", str(workspace)])
            finally:
                os.environ.clear()
                os.environ.update(old_env)

        self.assertEqual(exit_code, 1)
        payload = json.loads(stdout.getvalue())
        self.assertFalse(payload["ok"])
        self.assertEqual(payload["command"], "check_dependencies")


if __name__ == "__main__":
    unittest.main()
