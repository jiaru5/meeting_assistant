from __future__ import annotations

import json
import os
import tempfile
import unittest
from datetime import datetime, timezone
from pathlib import Path

from meeting_assistant_cli.workspace_contract import (
    ContractError,
    acquire_session_lock,
    create_session,
    load_session,
    register_artifact,
    session_directory,
    sha256_file,
    verify_registered_artifacts,
)


def fixed_clock() -> datetime:
    return datetime(2026, 6, 26, 8, 30, 0, tzinfo=timezone.utc)


class WorkspaceContractTests(unittest.TestCase):
    def test_create_session_writes_metadata_and_directories(self) -> None:
        with tempfile.TemporaryDirectory() as tmp:
            workspace = Path(tmp) / "MeetingAssistant"

            session = create_session(
                workspace,
                source_type="imported_media",
                title="Planning",
                session_id="session-test",
                clock=fixed_clock,
            )

            session_dir = session_directory(workspace, "session-test")
            metadata = json.loads((session_dir / "session.json").read_text(encoding="utf-8"))
            artifacts_dir_exists = (session_dir / "artifacts").is_dir()
            logs_dir_exists = (session_dir / "logs").is_dir()

        self.assertEqual(session["id"], "session-test")
        self.assertEqual(metadata["source_type"], "imported_media")
        self.assertEqual(metadata["status"], "created")
        self.assertEqual(metadata["started_at"], "2026-06-26T08:30:00Z")
        self.assertEqual(metadata["workspace_dir"], str(session_dir))
        self.assertEqual(metadata["artifacts"], [])
        self.assertTrue(artifacts_dir_exists)
        self.assertTrue(logs_dir_exists)

    def test_create_session_rejects_existing_session_directory(self) -> None:
        with tempfile.TemporaryDirectory() as tmp:
            workspace = Path(tmp)
            create_session(workspace, source_type="native_recording", session_id="session-1")

            with self.assertRaises(ContractError) as raised:
                create_session(workspace, source_type="native_recording", session_id="session-1")

        self.assertEqual(raised.exception.code, "path_conflict")

    def test_session_id_cannot_escape_workspace(self) -> None:
        with tempfile.TemporaryDirectory() as tmp:
            workspace = Path(tmp)

            with self.assertRaises(ContractError) as raised:
                session_directory(workspace, "../outside")

        self.assertEqual(raised.exception.code, "invalid_input")

    def test_register_artifact_adds_checksum_and_updates_session(self) -> None:
        with tempfile.TemporaryDirectory() as tmp:
            workspace = Path(tmp)
            create_session(workspace, source_type="native_recording", session_id="session-1", clock=fixed_clock)
            session_dir = workspace / "sessions" / "session-1"
            audio_path = session_dir / "artifacts" / "mixed_audio.wav"
            audio_path.write_bytes(b"audio")

            artifact = register_artifact(
                session_dir,
                artifact_type="mixed_audio",
                path=Path("artifacts/mixed_audio.wav"),
                file_format="wav",
                duration_ms=1200,
                clock=fixed_clock,
            )
            expected_checksum = sha256_file(audio_path)
            session = load_session(session_dir)

        self.assertEqual(artifact["session_id"], "session-1")
        self.assertEqual(artifact["artifact_type"], "mixed_audio")
        self.assertEqual(artifact["capture_status"], "available")
        self.assertEqual(artifact["checksum"], expected_checksum)
        self.assertEqual(session["artifacts"], [artifact])
        self.assertEqual(session["updated_at"], "2026-06-26T08:30:00Z")

    def test_register_artifact_rejects_path_outside_session(self) -> None:
        with tempfile.TemporaryDirectory() as tmp:
            workspace = Path(tmp)
            create_session(workspace, source_type="native_recording", session_id="session-1")
            session_dir = workspace / "sessions" / "session-1"
            outside = workspace / "outside.wav"
            outside.write_bytes(b"outside")

            with self.assertRaises(ContractError) as raised:
                register_artifact(session_dir, "mixed_audio", outside, "wav")

        self.assertEqual(raised.exception.code, "path_conflict")

    def test_register_artifact_rejects_hardlink_to_external_file(self) -> None:
        with tempfile.TemporaryDirectory() as tmp:
            workspace = Path(tmp) / "workspace"
            root = Path(tmp)
            create_session(workspace, source_type="native_recording", session_id="session-1")
            session_dir = workspace / "sessions" / "session-1"
            outside = root / "outside.wav"
            outside.write_bytes(b"outside")
            hardlink = session_dir / "artifacts" / "mixed_audio.wav"
            os.link(outside, hardlink)

            with self.assertRaises(ContractError) as raised:
                register_artifact(session_dir, "mixed_audio", Path("artifacts/mixed_audio.wav"), "wav")

            outside_text = outside.read_bytes()

        self.assertEqual(raised.exception.code, "path_conflict")
        self.assertEqual(outside_text, b"outside")

    def test_register_artifact_rejects_symlink_to_external_file(self) -> None:
        with tempfile.TemporaryDirectory() as tmp:
            workspace = Path(tmp) / "workspace"
            root = Path(tmp)
            create_session(workspace, source_type="native_recording", session_id="session-1")
            session_dir = workspace / "sessions" / "session-1"
            outside = root / "outside.wav"
            outside.write_bytes(b"outside")
            symlink = session_dir / "artifacts" / "mixed_audio.wav"
            symlink.symlink_to(outside)

            with self.assertRaises(ContractError) as raised:
                register_artifact(session_dir, "mixed_audio", Path("artifacts/mixed_audio.wav"), "wav")

            outside_text = outside.read_bytes()
            link_is_symlink = symlink.is_symlink()

        self.assertEqual(raised.exception.code, "path_conflict")
        self.assertEqual(outside_text, b"outside")
        self.assertTrue(link_is_symlink)

    def test_original_media_artifacts_are_append_only_per_type(self) -> None:
        with tempfile.TemporaryDirectory() as tmp:
            workspace = Path(tmp)
            create_session(workspace, source_type="native_recording", session_id="session-1")
            session_dir = workspace / "sessions" / "session-1"
            first = session_dir / "artifacts" / "mixed_audio.wav"
            second = session_dir / "artifacts" / "mixed_audio_retry.wav"
            first.write_bytes(b"first")
            second.write_bytes(b"second")
            register_artifact(session_dir, "mixed_audio", first, "wav")

            with self.assertRaises(ContractError) as raised:
                register_artifact(session_dir, "mixed_audio", second, "wav")

        self.assertEqual(raised.exception.code, "path_conflict")

    def test_unavailable_artifact_requires_degradation_reason(self) -> None:
        with tempfile.TemporaryDirectory() as tmp:
            workspace = Path(tmp)
            create_session(workspace, source_type="native_recording", session_id="session-1")
            session_dir = workspace / "sessions" / "session-1"

            with self.assertRaises(ContractError) as raised:
                register_artifact(
                    session_dir,
                    "system_audio",
                    Path("artifacts/system_audio.m4a"),
                    "m4a",
                    capture_status="missing",
                )

            artifact = register_artifact(
                session_dir,
                "microphone_audio",
                Path("artifacts/microphone_audio.m4a"),
                "m4a",
                capture_status="missing",
                degradation_reason="Microphone permission denied.",
            )

        self.assertEqual(raised.exception.code, "invalid_input")
        self.assertEqual(artifact["capture_status"], "missing")
        self.assertEqual(artifact["degradation_reason"], "Microphone permission denied.")

    def test_checksum_drift_is_detected_for_registered_original_media(self) -> None:
        with tempfile.TemporaryDirectory() as tmp:
            workspace = Path(tmp)
            create_session(workspace, source_type="native_recording", session_id="session-1")
            session_dir = workspace / "sessions" / "session-1"
            audio_path = session_dir / "artifacts" / "system_audio.wav"
            audio_path.write_bytes(b"original")
            register_artifact(session_dir, "system_audio", audio_path, "wav")

            audio_path.write_bytes(b"mutated")

            with self.assertRaises(ContractError) as raised:
                verify_registered_artifacts(session_dir)

        self.assertEqual(raised.exception.code, "path_conflict")

    def test_load_session_returns_contract_error_for_invalid_json(self) -> None:
        with tempfile.TemporaryDirectory() as tmp:
            workspace = Path(tmp)
            create_session(workspace, source_type="native_recording", session_id="session-1")
            session_dir = workspace / "sessions" / "session-1"
            (session_dir / "session.json").write_text("{not json", encoding="utf-8")

            with self.assertRaises(ContractError) as raised:
                load_session(session_dir)

        self.assertEqual(raised.exception.code, "processing_failed")

    def test_session_lock_rejects_concurrent_writer_and_releases(self) -> None:
        with tempfile.TemporaryDirectory() as tmp:
            workspace = Path(tmp)
            create_session(workspace, source_type="native_recording", session_id="session-1")
            session_dir = workspace / "sessions" / "session-1"

            with acquire_session_lock(session_dir):
                with self.assertRaises(ContractError) as raised:
                    with acquire_session_lock(session_dir):
                        pass

            with acquire_session_lock(session_dir):
                pass

        self.assertEqual(raised.exception.code, "path_conflict")


if __name__ == "__main__":
    unittest.main()
