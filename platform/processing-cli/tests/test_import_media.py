from __future__ import annotations

import contextlib
import io
import json
import os
import tempfile
import unittest
from pathlib import Path
from unittest import mock

from meeting_assistant_cli.cli import main
from meeting_assistant_cli.import_media import import_media
from meeting_assistant_cli.workspace_contract import load_session


DERIVED_ARTIFACT_TYPES = {"normalized_audio", "transcript_text", "speaker_labels"}


class ImportMediaTests(unittest.TestCase):
    def assert_no_session_created(self, workspace: Path) -> None:
        self.assertFalse((workspace / "sessions").exists())

    def assert_invalid_input(self, response: dict, workspace: Path) -> None:
        self.assertFalse(response["ok"])
        self.assertEqual(response["command"], "import_media")
        self.assertEqual(response["code"], "invalid_input")
        self.assertIn("request_id", response)
        self.assertEqual(response["warnings"], [])
        self.assert_no_session_created(workspace)

    def test_wav_import_creates_imported_session_and_mixed_audio_artifact(self) -> None:
        with tempfile.TemporaryDirectory() as tmp:
            root = Path(tmp)
            workspace = root / "workspace"
            source = root / "meeting.wav"
            source.write_bytes(b"wav-source")

            response = import_media(source, workspace=workspace, title="Planning")

            session_dir = (workspace / "sessions" / response["session_id"]).resolve(strict=False)
            session = load_session(session_dir)
            artifact = response["artifacts"][0]
            artifact_path = Path(str(artifact["path"]))
            artifact_files = sorted(path.name for path in (session_dir / "artifacts").iterdir())
            artifact_bytes = artifact_path.read_bytes()
            source_bytes = source.read_bytes()
            normalized_exists = (session_dir / "artifacts" / "normalized_audio.wav").exists()
            transcript_exists = (session_dir / "artifacts" / "transcript.json").exists()
            speaker_labels_exists = (session_dir / "artifacts" / "speaker_labels.json").exists()

        self.assertTrue(response["ok"])
        self.assertEqual(response["command"], "import_media")
        self.assertIn("request_id", response)
        self.assertEqual(response["source_type"], "imported_media")
        self.assertEqual(session["source_type"], "imported_media")
        self.assertEqual(session["title"], "Planning")
        self.assertEqual(artifact["artifact_type"], "mixed_audio")
        self.assertEqual(artifact["format"], "wav")
        self.assertEqual(artifact["capture_status"], "available")
        self.assertEqual(artifact_path.parent, session_dir / "artifacts")
        self.assertNotEqual(artifact_path, source.resolve(strict=False))
        self.assertEqual(artifact_bytes, b"wav-source")
        self.assertEqual(source_bytes, b"wav-source")
        self.assertEqual({item["artifact_type"] for item in session["artifacts"]} & DERIVED_ARTIFACT_TYPES, set())
        self.assertEqual(artifact_files, ["mixed_audio.wav"])
        self.assertFalse(normalized_exists)
        self.assertFalse(transcript_exists)
        self.assertFalse(speaker_labels_exists)

    def test_mp4_import_maps_to_screen_video_artifact(self) -> None:
        with tempfile.TemporaryDirectory() as tmp:
            root = Path(tmp)
            workspace = root / "workspace"
            source = root / "screen.mp4"
            source.write_bytes(b"mp4-source")

            response = import_media(source, workspace=workspace)

            artifact = response["artifacts"][0]
            artifact_path = Path(str(artifact["path"]))
            artifact_bytes = artifact_path.read_bytes()
            source_bytes = source.read_bytes()

        self.assertTrue(response["ok"])
        self.assertEqual(artifact["artifact_type"], "screen_video")
        self.assertEqual(artifact["format"], "mp4")
        self.assertEqual(artifact_path.name, "screen_video.mp4")
        self.assertEqual(artifact_bytes, b"mp4-source")
        self.assertEqual(source_bytes, b"mp4-source")

    def test_source_symlink_copies_resolved_regular_file_without_registering_link(self) -> None:
        with tempfile.TemporaryDirectory() as tmp:
            root = Path(tmp)
            workspace = root / "workspace"
            real_source = root / "real-meeting.wav"
            real_source.write_bytes(b"real-wav-source")
            source_link = root / "meeting-link.wav"
            source_link.symlink_to(real_source)

            response = import_media(source_link, workspace=workspace)

            session_dir = (workspace / "sessions" / response["session_id"]).resolve(strict=False)
            artifact = response["artifacts"][0]
            artifact_path = Path(str(artifact["path"]))
            artifact_bytes = artifact_path.read_bytes()
            source_bytes = real_source.read_bytes()
            artifact_is_symlink = artifact_path.is_symlink()

        self.assertTrue(response["ok"])
        self.assertEqual(artifact["artifact_type"], "mixed_audio")
        self.assertEqual(artifact_bytes, b"real-wav-source")
        self.assertEqual(source_bytes, b"real-wav-source")
        self.assertEqual(artifact_path.parent, session_dir / "artifacts")
        self.assertFalse(artifact_is_symlink)

    def test_cli_import_media_emits_json_success_response(self) -> None:
        with tempfile.TemporaryDirectory() as tmp:
            root = Path(tmp)
            workspace = root / "workspace"
            source = root / "cli.wav"
            source.write_bytes(b"cli-source")
            old_env = os.environ.copy()
            os.environ["MEETING_ASSISTANT_WORKSPACE"] = str(workspace)
            stdout = io.StringIO()
            try:
                with contextlib.redirect_stdout(stdout):
                    exit_code = main(["import_media", "--path", str(source), "--title", "CLI", "--format", "json"])
            finally:
                os.environ.clear()
                os.environ.update(old_env)

            payload = json.loads(stdout.getvalue())
            session_dir = (workspace / "sessions" / payload["session_id"]).resolve(strict=False)
            session = load_session(session_dir)
            artifact_path = Path(str(payload["artifacts"][0]["path"]))
            artifact_exists = artifact_path.is_file()
            artifact_bytes = artifact_path.read_bytes()

        self.assertEqual(exit_code, 0)
        self.assertTrue(payload["ok"])
        self.assertEqual(payload["command"], "import_media")
        self.assertEqual(payload["source_type"], "imported_media")
        self.assertEqual(session["source_type"], "imported_media")
        self.assertEqual(session["title"], "CLI")
        self.assertTrue(artifact_exists)
        self.assertEqual(artifact_bytes, b"cli-source")

    def test_cli_import_media_invalid_input_uses_contract_exit_code(self) -> None:
        with tempfile.TemporaryDirectory() as tmp:
            root = Path(tmp)
            workspace = root / "workspace"
            old_env = os.environ.copy()
            os.environ["MEETING_ASSISTANT_WORKSPACE"] = str(workspace)
            stdout = io.StringIO()
            try:
                with contextlib.redirect_stdout(stdout):
                    exit_code = main(["import_media", "--path", str(root / "missing.wav"), "--format", "json"])
            finally:
                os.environ.clear()
                os.environ.update(old_env)

            payload = json.loads(stdout.getvalue())

        self.assertEqual(exit_code, 2)
        self.assertFalse(payload["ok"])
        self.assertEqual(payload["code"], "invalid_input")
        self.assertEqual(payload["details"]["path"], str(root / "missing.wav"))

    def test_cli_missing_required_argument_emits_contract_json(self) -> None:
        stdout = io.StringIO()
        with contextlib.redirect_stdout(stdout):
            exit_code = main(["import_media", "--format", "json"])

        payload = json.loads(stdout.getvalue())

        self.assertEqual(exit_code, 2)
        self.assertFalse(payload["ok"])
        self.assertEqual(payload["command"], "import_media")
        self.assertEqual(payload["code"], "invalid_input")
        self.assertIn("--path", payload["details"]["error"])

    def test_cli_unknown_argument_emits_contract_json(self) -> None:
        stdout = io.StringIO()
        with contextlib.redirect_stdout(stdout):
            exit_code = main(["generate_transcript", "--session-id", "session-1", "--unknown-field", "value"])

        payload = json.loads(stdout.getvalue())

        self.assertEqual(exit_code, 2)
        self.assertFalse(payload["ok"])
        self.assertEqual(payload["command"], "generate_transcript")
        self.assertEqual(payload["code"], "invalid_input")
        self.assertIn("--unknown-field", payload["details"]["error"])

    def test_cli_illegal_enum_emits_contract_json(self) -> None:
        stdout = io.StringIO()
        with contextlib.redirect_stdout(stdout):
            exit_code = main(["check_dependencies", "--format", "yaml"])

        payload = json.loads(stdout.getvalue())

        self.assertEqual(exit_code, 2)
        self.assertFalse(payload["ok"])
        self.assertEqual(payload["command"], "check_dependencies")
        self.assertEqual(payload["code"], "invalid_input")
        self.assertIn("invalid choice", payload["details"]["error"])

    def test_unsupported_suffix_returns_invalid_input_without_session(self) -> None:
        with tempfile.TemporaryDirectory() as tmp:
            root = Path(tmp)
            workspace = root / "workspace"
            source = root / "notes.txt"
            source.write_text("not media", encoding="utf-8")

            response = import_media(source, workspace=workspace)

            self.assert_invalid_input(response, workspace)

    def test_missing_path_returns_invalid_input_without_session(self) -> None:
        with tempfile.TemporaryDirectory() as tmp:
            root = Path(tmp)
            workspace = root / "workspace"

            response = import_media(root / "missing.wav", workspace=workspace)

            self.assert_invalid_input(response, workspace)

    def test_directory_input_returns_invalid_input_without_session(self) -> None:
        with tempfile.TemporaryDirectory() as tmp:
            root = Path(tmp)
            workspace = root / "workspace"
            source = root / "media.mp4"
            source.mkdir()

            response = import_media(source, workspace=workspace)

            self.assert_invalid_input(response, workspace)

    def test_copy_failure_removes_created_session_directory(self) -> None:
        with tempfile.TemporaryDirectory() as tmp:
            root = Path(tmp)
            workspace = root / "workspace"
            source = root / "meeting.wav"
            source.write_bytes(b"wav-source")

            with mock.patch("meeting_assistant_cli.import_media.shutil.copy2", side_effect=OSError("copy failed")):
                response = import_media(source, workspace=workspace)

            session_dirs = list((workspace / "sessions").iterdir()) if (workspace / "sessions").exists() else []

        self.assertFalse(response["ok"])
        self.assertEqual(response["command"], "import_media")
        self.assertEqual(response["code"], "internal_error")
        self.assertEqual(session_dirs, [])


if __name__ == "__main__":
    unittest.main()
