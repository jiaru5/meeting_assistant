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
from meeting_assistant_cli.workspace_contract import acquire_session_lock, create_session, register_artifact, session_directory


@contextlib.contextmanager
def external_side_effect_sentinels():
    with contextlib.ExitStack() as stack:
        stack.enter_context(mock.patch("socket.create_connection", side_effect=AssertionError("unexpected external side effect")))
        stack.enter_context(mock.patch("urllib.request.urlopen", side_effect=AssertionError("unexpected external side effect")))
        stack.enter_context(mock.patch("subprocess.run", side_effect=AssertionError("unexpected external side effect")))
        yield


def create_session_with_transcript(workspace: Path) -> Path:
    create_session(workspace, source_type="native_recording", session_id="session-1", status="transcribed")
    session_dir = session_directory(workspace, "session-1")
    transcript = {
        "id": "transcript-1",
        "session_id": "session-1",
        "source_artifact_id": "artifact-mixed_audio",
        "status": "succeeded",
        "segments": [{"segment_id": "segment-0001", "start_ms": 0, "end_ms": 1000, "text": "private transcript phrase"}],
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
            event_path = workspace.resolve(strict=False) / "events" / "meeting_session.deleted.v1.jsonl"
            event = json.loads(event_path.read_text(encoding="utf-8").splitlines()[-1])
            response_json = json.dumps(response, ensure_ascii=False, sort_keys=True)
            event_json = json.dumps(event, ensure_ascii=False, sort_keys=True)

        self.assertTrue(export_response["ok"])
        self.assertTrue(response["ok"])
        self.assertTrue(response["deleted"])
        self.assertFalse(session_exists)
        self.assertTrue(external_exists)
        self.assertIn("session.json", response["deleted_items"])
        self.assertIn("artifacts/transcript.json", response["deleted_items"])
        for item in response["deleted_items"]:
            item_path = Path(item)
            self.assertFalse(item_path.is_absolute())
            self.assertNotIn("..", item_path.parts)
        self.assertEqual(response["retained_external_exports"], [str(external_export.resolve(strict=False))])
        self.assertEqual(event["event_name"], "meeting_session.deleted.v1")
        self.assertEqual(event["session_id"], "session-1")
        self.assertTrue(event["result"]["deleted"])
        self.assertEqual(event["result"]["deleted_items"], response["deleted_items"])
        self.assertEqual(event["result"]["retained_external_exports"], [str(external_export.resolve(strict=False))])
        self.assertNotIn("private transcript phrase", response_json)
        self.assertNotIn("private transcript phrase", event_json)

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

    def test_delete_success_does_not_use_external_process_or_network_helpers(self) -> None:
        with tempfile.TemporaryDirectory() as tmp:
            workspace = Path(tmp)
            create_session_with_transcript(workspace)

            with external_side_effect_sentinels():
                response = run_delete_session("session-1", workspace=workspace, confirm=True)

        self.assertTrue(response["ok"])
        self.assertTrue(response["deleted"])

    def test_locked_session_returns_path_conflict_without_deleting(self) -> None:
        with tempfile.TemporaryDirectory() as tmp:
            workspace = Path(tmp)
            session_dir = create_session_with_transcript(workspace)

            with acquire_session_lock(session_dir):
                response = run_delete_session("session-1", workspace=workspace, confirm=True)

            session_exists = session_dir.exists()

        self.assertFalse(response["ok"])
        self.assertEqual(response["code"], "path_conflict")
        self.assertTrue(session_exists)

    def test_invalid_session_json_returns_stable_processing_error_without_deleting(self) -> None:
        with tempfile.TemporaryDirectory() as tmp:
            workspace = Path(tmp)
            session_dir = create_session_with_transcript(workspace)
            (session_dir / "session.json").write_text("{invalid json", encoding="utf-8")

            response = run_delete_session("session-1", workspace=workspace, confirm=True)

            session_exists = session_dir.exists()

        self.assertFalse(response["ok"])
        self.assertEqual(response["code"], "processing_failed")
        self.assertTrue(session_exists)

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

    def test_session_root_symlink_to_workspace_sibling_returns_path_conflict_without_deleting_target(self) -> None:
        with tempfile.TemporaryDirectory() as tmp:
            root = Path(tmp)
            workspace = root / "workspace"
            target_session = create_session_with_transcript(workspace)
            sessions_dir = workspace / "sessions"
            link_path = sessions_dir / "link-session"
            link_path.symlink_to(target_session, target_is_directory=True)

            response = run_delete_session("link-session", workspace=workspace, confirm=True)

            target_exists = target_session.exists()
            link_is_symlink = link_path.is_symlink()

        self.assertFalse(response["ok"])
        self.assertEqual(response["code"], "path_conflict")
        self.assertTrue(target_exists)
        self.assertTrue(link_is_symlink)

    def test_sessions_directory_symlink_returns_path_conflict_without_deleting_target(self) -> None:
        with tempfile.TemporaryDirectory() as tmp:
            root = Path(tmp)
            workspace = root / "workspace"
            real_sessions = root / "real-sessions"
            real_sessions.mkdir()
            (workspace).mkdir()
            (workspace / "sessions").symlink_to(real_sessions, target_is_directory=True)
            target_session = real_sessions / "session-1"
            target_session.mkdir()
            (target_session / "session.json").write_text("{}", encoding="utf-8")

            response = run_delete_session("session-1", workspace=workspace, confirm=True)

            target_exists = target_session.exists()
            sessions_is_symlink = (workspace / "sessions").is_symlink()

        self.assertFalse(response["ok"])
        self.assertEqual(response["code"], "path_conflict")
        self.assertTrue(target_exists)
        self.assertTrue(sessions_is_symlink)

    def test_workspace_events_symlink_returns_path_conflict_without_deleting_or_writing_external_event(self) -> None:
        with tempfile.TemporaryDirectory() as tmp:
            root = Path(tmp)
            workspace = root / "workspace"
            session_dir = create_session_with_transcript(workspace)
            external_events = root / "external-events"
            external_events.mkdir()
            events_dir = workspace / "events"
            events_dir.symlink_to(external_events, target_is_directory=True)

            response = run_delete_session("session-1", workspace=workspace, confirm=True)

            session_exists = session_dir.exists()
            external_event_path = external_events / "meeting_session.deleted.v1.jsonl"

        self.assertFalse(response["ok"])
        self.assertEqual(response["code"], "path_conflict")
        self.assertTrue(session_exists)
        self.assertFalse(external_event_path.exists())

    def test_delete_event_file_symlink_returns_path_conflict_without_deleting_or_writing_external_event(self) -> None:
        with tempfile.TemporaryDirectory() as tmp:
            root = Path(tmp)
            workspace = root / "workspace"
            session_dir = create_session_with_transcript(workspace)
            outside_event = root / "outside-events.jsonl"
            outside_event.write_text("", encoding="utf-8")
            events_dir = workspace / "events"
            events_dir.mkdir()
            (events_dir / "meeting_session.deleted.v1.jsonl").symlink_to(outside_event)

            response = run_delete_session("session-1", workspace=workspace, confirm=True)

            session_exists = session_dir.exists()
            outside_event_text = outside_event.read_text(encoding="utf-8")

        self.assertFalse(response["ok"])
        self.assertEqual(response["code"], "path_conflict")
        self.assertTrue(session_exists)
        self.assertEqual(outside_event_text, "")

    def test_delete_event_file_hardlink_returns_path_conflict_without_deleting_or_writing_external_event(self) -> None:
        with tempfile.TemporaryDirectory() as tmp:
            root = Path(tmp)
            workspace = root / "workspace"
            session_dir = create_session_with_transcript(workspace)
            outside_event = root / "outside-events.jsonl"
            outside_event.write_text("", encoding="utf-8")
            events_dir = workspace / "events"
            events_dir.mkdir()
            os.link(outside_event, events_dir / "meeting_session.deleted.v1.jsonl")

            response = run_delete_session("session-1", workspace=workspace, confirm=True)

            session_exists = session_dir.exists()
            outside_event_text = outside_event.read_text(encoding="utf-8")

        self.assertFalse(response["ok"])
        self.assertEqual(response["code"], "path_conflict")
        self.assertTrue(session_exists)
        self.assertEqual(outside_event_text, "")

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

    def test_cli_missing_session_uses_not_found_exit_code_and_single_json(self) -> None:
        with tempfile.TemporaryDirectory() as tmp:
            workspace = Path(tmp)
            stdout = io.StringIO()
            stderr = io.StringIO()
            with contextlib.redirect_stdout(stdout), contextlib.redirect_stderr(stderr):
                exit_code = main(
                    [
                        "delete_session",
                        "--session-id",
                        "missing-session",
                        "--workspace-dir",
                        str(workspace),
                        "--confirm",
                        "true",
                    ]
                )

            output = stdout.getvalue().strip()
            payload = json.loads(output)

        self.assertEqual(exit_code, 3)
        self.assertEqual(len(output.splitlines()), 1)
        self.assertEqual(stderr.getvalue(), "")
        self.assertFalse(payload["ok"])
        self.assertEqual(payload["command"], "delete_session")
        self.assertEqual(payload["code"], "not_found")

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
