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
from meeting_assistant_cli.export_transcript import run_export_transcript
from meeting_assistant_cli.workspace_contract import create_session, load_session, register_artifact, session_directory, sha256_file


def create_transcript_session(workspace: Path) -> Path:
    create_session(workspace, source_type="native_recording", session_id="session-1", status="transcribed")
    session_dir = session_directory(workspace, "session-1")
    audio_path = session_dir / "artifacts" / "mixed_audio.wav"
    audio_path.write_bytes(b"audio")
    register_artifact(
        session_dir,
        artifact_type="mixed_audio",
        path=Path("artifacts/mixed_audio.wav"),
        file_format="wav",
        artifact_id="artifact-mixed_audio",
    )
    transcript = {
        "id": "transcript-1",
        "session_id": "session-1",
        "source_artifact_id": "artifact-mixed_audio",
        "status": "succeeded",
        "segments": [
            {"segment_id": "segment-0001", "start_ms": 0, "end_ms": 1000, "text": "first line"},
            {"segment_id": "segment-0002", "start_ms": 1000, "end_ms": 2400, "text": "second line"},
        ],
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


class TranscriptExportTests(unittest.TestCase):
    def test_plain_text_export_returns_copyable_content_without_file_target(self) -> None:
        with tempfile.TemporaryDirectory() as tmp:
            workspace = Path(tmp)
            session_dir = create_transcript_session(workspace)
            original_transcript_checksum = sha256_file(session_dir / "artifacts" / "transcript.json")
            original_audio_checksum = sha256_file(session_dir / "artifacts" / "mixed_audio.wav")

            response = run_export_transcript("session-1", "plain_text", workspace=workspace)

            final_transcript_checksum = sha256_file(session_dir / "artifacts" / "transcript.json")
            final_audio_checksum = sha256_file(session_dir / "artifacts" / "mixed_audio.wav")

        self.assertTrue(response["ok"])
        self.assertEqual(response["command"], "export_transcript")
        self.assertEqual(response["export_type"], "plain_text")
        self.assertIn("[00:00.000-00:01.000] first line", response["content"])
        self.assertNotIn("target_path", response)
        self.assertEqual(final_transcript_checksum, original_transcript_checksum)
        self.assertEqual(final_audio_checksum, original_audio_checksum)

    def test_markdown_export_writes_target_and_records_export_package(self) -> None:
        with tempfile.TemporaryDirectory() as tmp:
            root = Path(tmp)
            workspace = root / "workspace"
            session_dir = create_transcript_session(workspace)
            target = root / "exports" / "transcript.md"
            target.parent.mkdir()

            response = run_export_transcript("session-1", "markdown", workspace=workspace, target_path=target)

            session = load_session(session_dir)
            target_text = target.read_text(encoding="utf-8")

        self.assertTrue(response["ok"])
        self.assertEqual(response["target_path"], str(target.resolve(strict=False)))
        self.assertTrue(target_text.startswith("# Transcript"))
        self.assertIn("- [00:00.000-00:01.000] first line", target_text)
        self.assertEqual(session["exports"][0]["id"], response["export_package_id"])
        self.assertEqual(session["exports"][0]["export_type"], "markdown")
        self.assertEqual(session["exports"][0]["path"], str(target.resolve(strict=False)))

    def test_json_export_content_is_structured_transcript_payload(self) -> None:
        with tempfile.TemporaryDirectory() as tmp:
            workspace = Path(tmp)
            create_transcript_session(workspace)

            response = run_export_transcript("session-1", "json", workspace=workspace)

            payload = json.loads(str(response["content"]))

        self.assertTrue(response["ok"])
        self.assertEqual(payload["id"], "transcript-1")
        self.assertEqual(payload["segments"][0]["text"], "first line")

    def test_existing_export_target_returns_path_conflict_without_overwrite(self) -> None:
        with tempfile.TemporaryDirectory() as tmp:
            root = Path(tmp)
            workspace = root / "workspace"
            create_transcript_session(workspace)
            target = root / "transcript.txt"
            target.write_text("keep me", encoding="utf-8")

            response = run_export_transcript("session-1", "plain_text", workspace=workspace, target_path=target)

            target_text = target.read_text(encoding="utf-8")

        self.assertFalse(response["ok"])
        self.assertEqual(response["code"], "path_conflict")
        self.assertEqual(target_text, "keep me")

    def test_target_export_is_removed_when_session_metadata_recording_fails(self) -> None:
        with tempfile.TemporaryDirectory() as tmp:
            root = Path(tmp)
            workspace = root / "workspace"
            create_transcript_session(workspace)
            target = root / "transcript.txt"

            with mock.patch("meeting_assistant_cli.export_transcript.write_session", side_effect=OSError("metadata failed")):
                response = run_export_transcript("session-1", "plain_text", workspace=workspace, target_path=target)

            target_exists = target.exists()

        self.assertFalse(response["ok"])
        self.assertEqual(response["code"], "internal_error")
        self.assertFalse(target_exists)

    def test_missing_transcript_returns_artifact_missing(self) -> None:
        with tempfile.TemporaryDirectory() as tmp:
            workspace = Path(tmp)
            create_session(workspace, source_type="native_recording", session_id="session-1", status="recorded")

            response = run_export_transcript("session-1", "plain_text", workspace=workspace)

        self.assertFalse(response["ok"])
        self.assertEqual(response["code"], "artifact_missing")

    def test_invalid_export_type_returns_invalid_input(self) -> None:
        with tempfile.TemporaryDirectory() as tmp:
            workspace = Path(tmp)
            create_transcript_session(workspace)

            response = run_export_transcript("session-1", "html", workspace=workspace)

        self.assertFalse(response["ok"])
        self.assertEqual(response["code"], "invalid_input")

    def test_cli_export_transcript_writes_json_response_and_target(self) -> None:
        with tempfile.TemporaryDirectory() as tmp:
            root = Path(tmp)
            workspace = root / "workspace"
            create_transcript_session(workspace)
            target = root / "transcript.txt"
            old_env = os.environ.copy()
            os.environ["MEETING_ASSISTANT_WORKSPACE"] = str(workspace)
            stdout = io.StringIO()
            try:
                with contextlib.redirect_stdout(stdout):
                    exit_code = main(
                        [
                            "export_transcript",
                            "--session-id",
                            "session-1",
                            "--export-type",
                            "plain_text",
                            "--target-path",
                            str(target),
                            "--format",
                            "json",
                        ]
                    )
            finally:
                os.environ.clear()
                os.environ.update(old_env)

            payload = json.loads(stdout.getvalue())
            target_text = target.read_text(encoding="utf-8")

        self.assertEqual(exit_code, 0)
        self.assertTrue(payload["ok"])
        self.assertEqual(payload["command"], "export_transcript")
        self.assertEqual(payload["target_path"], str(target.resolve(strict=False)))
        self.assertIn("first line", target_text)

    def test_cli_invalid_export_enum_emits_contract_json(self) -> None:
        stdout = io.StringIO()
        with contextlib.redirect_stdout(stdout):
            exit_code = main(["export_transcript", "--session-id", "session-1", "--export-type", "html"])

        payload = json.loads(stdout.getvalue())

        self.assertEqual(exit_code, 2)
        self.assertFalse(payload["ok"])
        self.assertEqual(payload["command"], "export_transcript")
        self.assertEqual(payload["code"], "invalid_input")
        self.assertIn("invalid choice", payload["details"]["error"])

    def test_cli_unknown_argument_emits_contract_json(self) -> None:
        stdout = io.StringIO()
        with contextlib.redirect_stdout(stdout):
            exit_code = main(
                [
                    "export_transcript",
                    "--session-id",
                    "session-1",
                    "--export-type",
                    "plain_text",
                    "--unknown-field",
                    "value",
                ]
            )

        payload = json.loads(stdout.getvalue())

        self.assertEqual(exit_code, 2)
        self.assertFalse(payload["ok"])
        self.assertEqual(payload["command"], "export_transcript")
        self.assertEqual(payload["code"], "invalid_input")
        self.assertIn("unrecognized arguments", payload["details"]["error"])


if __name__ == "__main__":
    unittest.main()
