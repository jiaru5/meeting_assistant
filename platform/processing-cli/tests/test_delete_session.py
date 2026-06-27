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
from meeting_assistant_cli.delete_session import run_delete_session
from meeting_assistant_cli.export_transcript import run_export_transcript
from meeting_assistant_cli.workspace_contract import create_session, register_artifact, session_directory


def create_session_with_transcript(workspace: Path) -> Path:
    create_session(workspace, source_type="native_recording", session_id="session-1", status="transcribed")
    session_dir = session_directory(workspace, "session-1")
    transcript = {
        "id": "transcript-1",
        "session_id": "session-1",
        "source_artifact_id": "artifact-mixed_audio",
        "status": "succeeded",
        "segments": [{"segment_id": "segment-0001", "start_ms": 0, "end_ms": 1000, "text": "line"}],
        "created_at": "2026-06-27T00:00:00Z",
    }
    transcript_path = session_dir / "artifacts" / "transcript.json"
    transcript_path.write_text(json.dumps(transcript, ensure_ascii=False, indent=2, sort_keys=True) + "\n", encoding="utf-8")
    register_artifact(
        session_dir,
        artifact_type="transcript_text",
        path=Path("artifacts/transcript.json"),
        file_format="json",
        artifact_id="artifact-transcript_text",
    )
    return session_dir


class DeleteSessionTests(unittest.TestCase):
    def test_delete_session_removes_workspace_session_and_retains_external_export(self) -> None:
        with tempfile.TemporaryDirectory() as tmp:
            root = Path(tmp)
            workspace = root / "workspace"
            session_dir = create_session_with_transcript(workspace)
            external_export = root / "external-transcript.txt"
            export_response = run_export_transcript(
                "session-1",
                "plain_text",
                workspace=workspace,
                target_path=external_export,
            )

            response = run_delete_session("session-1", workspace=workspace, confirm=True)

            session_exists = session_dir.exists()
            external_exists = external_export.exists()

        self.assertTrue(export_response["ok"])
        self.assertTrue(response["ok"])
        self.assertTrue(response["deleted"])
        self.assertFalse(session_exists)
        self.assertTrue(external_exists)
        self.assertIn("session.json", response["deleted_items"])
        self.assertIn("artifacts/transcript.json", response["deleted_items"])
        self.assertEqual(response["retained_external_exports"], [str(external_export.resolve(strict=False))])

    def test_confirm_false_returns_invalid_input_without_deleting(self) -> None:
        with tempfile.TemporaryDirectory() as tmp:
            workspace = Path(tmp)
            session_dir = create_session_with_transcript(workspace)

            response = run_delete_session("session-1", workspace=workspace, confirm=False)

            session_exists = session_dir.exists()

        self.assertFalse(response["ok"])
        self.assertEqual(response["code"], "invalid_input")
        self.assertTrue(session_exists)

    def test_missing_session_returns_not_found(self) -> None:
        with tempfile.TemporaryDirectory() as tmp:
            workspace = Path(tmp)

            response = run_delete_session("missing-session", workspace=workspace, confirm=True)

        self.assertFalse(response["ok"])
        self.assertEqual(response["code"], "not_found")

    def test_session_root_symlink_escape_returns_path_conflict_without_deleting_target(self) -> None:
        with tempfile.TemporaryDirectory() as tmp:
            root = Path(tmp)
            workspace = root / "workspace"
            outside = root / "outside-session"
            outside.mkdir()
            (outside / "session.json").write_text("{}", encoding="utf-8")
            sessions_dir = workspace / "sessions"
            sessions_dir.mkdir(parents=True)
            (sessions_dir / "session-1").symlink_to(outside, target_is_directory=True)

            response = run_delete_session("session-1", workspace=workspace, confirm=True)

            outside_exists = outside.exists()
            symlink_exists = (sessions_dir / "session-1").exists()

        self.assertFalse(response["ok"])
        self.assertEqual(response["code"], "path_conflict")
        self.assertTrue(outside_exists)
        self.assertTrue(symlink_exists)

    def test_symlink_inside_session_is_unlinked_without_deleting_external_target(self) -> None:
        with tempfile.TemporaryDirectory() as tmp:
            root = Path(tmp)
            workspace = root / "workspace"
            session_dir = create_session_with_transcript(workspace)
            external_target = root / "outside.txt"
            external_target.write_text("keep", encoding="utf-8")
            (session_dir / "artifacts" / "outside-link.txt").symlink_to(external_target)

            response = run_delete_session("session-1", workspace=workspace, confirm=True)

            external_text = external_target.read_text(encoding="utf-8")

        self.assertTrue(response["ok"])
        self.assertEqual(external_text, "keep")

    def test_permission_error_returns_permission_denied(self) -> None:
        with tempfile.TemporaryDirectory() as tmp:
            workspace = Path(tmp)
            session_dir = create_session_with_transcript(workspace)

            with mock.patch("meeting_assistant_cli.delete_session.shutil.rmtree", side_effect=PermissionError("denied")):
                response = run_delete_session("session-1", workspace=workspace, confirm=True)

            session_exists = session_dir.exists()

        self.assertFalse(response["ok"])
        self.assertEqual(response["code"], "permission_denied")
        self.assertTrue(session_exists)

    def test_cli_delete_session_success_and_confirm_exit_codes(self) -> None:
        with tempfile.TemporaryDirectory() as tmp:
            workspace = Path(tmp)
            create_session_with_transcript(workspace)
            stdout = io.StringIO()
            with contextlib.redirect_stdout(stdout):
                exit_code = main(
                    [
                        "delete_session",
                        "--session-id",
                        "session-1",
                        "--workspace-dir",
                        str(workspace),
                        "--confirm",
                        "true",
                    ]
                )

            payload = json.loads(stdout.getvalue())

        self.assertEqual(exit_code, 0)
        self.assertTrue(payload["ok"])
        self.assertTrue(payload["deleted"])

    def test_cli_delete_session_confirm_false_uses_invalid_input_exit_code(self) -> None:
        with tempfile.TemporaryDirectory() as tmp:
            workspace = Path(tmp)
            create_session_with_transcript(workspace)
            stdout = io.StringIO()
            with contextlib.redirect_stdout(stdout):
                exit_code = main(
                    [
                        "delete_session",
                        "--session-id",
                        "session-1",
                        "--workspace-dir",
                        str(workspace),
                        "--confirm",
                        "false",
                    ]
                )

            payload = json.loads(stdout.getvalue())

        self.assertEqual(exit_code, 2)
        self.assertFalse(payload["ok"])
        self.assertEqual(payload["code"], "invalid_input")

    def test_cli_delete_session_unknown_arg_emits_contract_json(self) -> None:
        stdout = io.StringIO()
        with contextlib.redirect_stdout(stdout):
            exit_code = main(["delete_session", "--session-id", "session-1", "--confirm", "true", "--unknown-field", "value"])

        payload = json.loads(stdout.getvalue())

        self.assertEqual(exit_code, 2)
        self.assertFalse(payload["ok"])
        self.assertEqual(payload["command"], "delete_session")
        self.assertEqual(payload["code"], "invalid_input")


if __name__ == "__main__":
    unittest.main()
