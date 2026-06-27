from __future__ import annotations

import json
import tempfile
import unittest
from pathlib import Path
from unittest import mock

from meeting_assistant_cli.audio_processing import run_audio_normalization
from meeting_assistant_cli.workspace_contract import ContractError, create_session, load_session, register_artifact, session_directory, sha256_file


def wav_bytes(payload: bytes = b"\x00\x01") -> bytes:
    return (
        b"RIFF"
        + (36 + len(payload)).to_bytes(4, "little")
        + b"WAVE"
        + b"fmt "
        + (16).to_bytes(4, "little")
        + (1).to_bytes(2, "little")
        + (1).to_bytes(2, "little")
        + (8000).to_bytes(4, "little")
        + (16000).to_bytes(4, "little")
        + (2).to_bytes(2, "little")
        + (16).to_bytes(2, "little")
        + b"data"
        + len(payload).to_bytes(4, "little")
        + payload
    )


def non_pcm_wav_bytes(payload: bytes = b"\x00\x01") -> bytes:
    return (
        b"RIFF"
        + (36 + len(payload)).to_bytes(4, "little")
        + b"WAVE"
        + b"fmt "
        + (16).to_bytes(4, "little")
        + (3).to_bytes(2, "little")
        + (1).to_bytes(2, "little")
        + (8000).to_bytes(4, "little")
        + (32000).to_bytes(4, "little")
        + (4).to_bytes(2, "little")
        + (32).to_bytes(2, "little")
        + b"data"
        + len(payload).to_bytes(4, "little")
        + payload
    )


def create_audio_session(workspace: Path, artifacts: list[tuple[str, str, bytes]]) -> Path:
    create_session(workspace, source_type="native_recording", session_id="session-1")
    session_dir = session_directory(workspace, "session-1")
    for artifact_type, file_name, payload in artifacts:
        path = session_dir / "artifacts" / file_name
        path.write_bytes(payload)
        register_artifact(
            session_dir,
            artifact_type=artifact_type,
            path=Path("artifacts") / file_name,
            file_format=path.suffix.removeprefix("."),
            artifact_id=f"artifact-{artifact_type}",
        )
    return session_dir


def artifacts_by_type(session_dir: Path) -> dict[str, list[dict]]:
    session = load_session(session_dir)
    result: dict[str, list[dict]] = {}
    for artifact in session["artifacts"]:
        result.setdefault(str(artifact["artifact_type"]), []).append(artifact)
    return result


class AudioProcessingTests(unittest.TestCase):
    def test_default_audio_source_prefers_mixed_audio(self) -> None:
        with tempfile.TemporaryDirectory() as tmp:
            workspace = Path(tmp)
            session_dir = create_audio_session(
                workspace,
                [
                    ("system_audio", "system_audio.wav", wav_bytes(b"system")),
                    ("mixed_audio", "mixed_audio.wav", wav_bytes(b"mixed")),
                ],
            )
            original_mixed_checksum = sha256_file(session_dir / "artifacts" / "mixed_audio.wav")
            original_system_checksum = sha256_file(session_dir / "artifacts" / "system_audio.wav")

            response = run_audio_normalization("session-1", workspace=workspace)

            normalized_path = session_dir / "artifacts" / "normalized_audio.wav"
            normalized_bytes = normalized_path.read_bytes()
            indexed = artifacts_by_type(session_dir)
            final_mixed_checksum = sha256_file(session_dir / "artifacts" / "mixed_audio.wav")
            final_system_checksum = sha256_file(session_dir / "artifacts" / "system_audio.wav")

        self.assertTrue(response["ok"])
        self.assertEqual(response["stage"], "audio_normalization")
        self.assertEqual(response["source_artifact_id"], "artifact-mixed_audio")
        self.assertTrue(normalized_bytes.startswith(b"RIFF"))
        self.assertEqual(normalized_bytes[8:12], b"WAVE")
        self.assertEqual(indexed["normalized_audio"][0]["format"], "wav")
        self.assertEqual(indexed["normalized_audio"][0]["path"], str(normalized_path))
        self.assertEqual(final_mixed_checksum, original_mixed_checksum)
        self.assertEqual(final_system_checksum, original_system_checksum)

    def test_missing_mixed_audio_selects_explicit_available_audio(self) -> None:
        with tempfile.TemporaryDirectory() as tmp:
            workspace = Path(tmp)
            session_dir = create_audio_session(
                workspace,
                [
                    ("system_audio", "system_audio.wav", wav_bytes(b"system")),
                    ("microphone_audio", "microphone_audio.wav", wav_bytes(b"microphone")),
                ],
            )

            response = run_audio_normalization("session-1", workspace=workspace, source_artifact_id="artifact-system_audio")

            normalized_path = session_dir / "artifacts" / "normalized_audio.wav"
            normalized_bytes = normalized_path.read_bytes()

        self.assertTrue(response["ok"])
        self.assertEqual(response["source_artifact_id"], "artifact-system_audio")
        self.assertTrue(normalized_bytes.startswith(b"RIFF"))

    def test_missing_mixed_audio_can_select_microphone_audio(self) -> None:
        with tempfile.TemporaryDirectory() as tmp:
            workspace = Path(tmp)
            session_dir = create_audio_session(workspace, [("microphone_audio", "microphone_audio.wav", wav_bytes(b"microphone"))])

            response = run_audio_normalization(
                "session-1",
                workspace=workspace,
                source_artifact_id="artifact-microphone_audio",
            )

            normalized_bytes = (session_dir / "artifacts" / "normalized_audio.wav").read_bytes()

        self.assertTrue(response["ok"])
        self.assertEqual(response["source_artifact_id"], "artifact-microphone_audio")
        self.assertTrue(normalized_bytes.startswith(b"RIFF"))

    def test_mixed_audio_prevents_explicit_non_mixed_source(self) -> None:
        with tempfile.TemporaryDirectory() as tmp:
            workspace = Path(tmp)
            session_dir = create_audio_session(
                workspace,
                [
                    ("mixed_audio", "mixed_audio.wav", wav_bytes(b"mixed")),
                    ("system_audio", "system_audio.wav", wav_bytes(b"system")),
                ],
            )

            response = run_audio_normalization("session-1", workspace=workspace, source_artifact_id="artifact-system_audio")

            normalized_exists = (session_dir / "artifacts" / "normalized_audio.wav").exists()

        self.assertFalse(response["ok"])
        self.assertEqual(response["code"], "path_conflict")
        self.assertFalse(normalized_exists)

    def test_missing_mixed_audio_without_explicit_source_returns_artifact_missing(self) -> None:
        with tempfile.TemporaryDirectory() as tmp:
            workspace = Path(tmp)
            session_dir = create_audio_session(workspace, [("system_audio", "system_audio.wav", wav_bytes(b"system"))])

            response = run_audio_normalization("session-1", workspace=workspace)

            normalized_exists = (session_dir / "artifacts" / "normalized_audio.wav").exists()

        self.assertFalse(response["ok"])
        self.assertEqual(response["code"], "artifact_missing")
        self.assertIn("mixed_audio", response["message"])
        self.assertFalse(normalized_exists)

    def test_no_audio_artifact_returns_artifact_missing(self) -> None:
        with tempfile.TemporaryDirectory() as tmp:
            workspace = Path(tmp)
            session_dir = create_audio_session(workspace, [("screen_video", "screen_video.mp4", b"video")])

            response = run_audio_normalization("session-1", workspace=workspace, request_id="local-no-audio")

            log_path = session_dir / "logs" / "processing.log"
            log_exists = log_path.is_file()
            log_text = log_path.read_text(encoding="utf-8")

        self.assertFalse(response["ok"])
        self.assertEqual(response["code"], "artifact_missing")
        self.assertIn("mixed_audio", response["message"])
        self.assertTrue(log_exists)
        self.assertIn("local-no-audio", log_text)

    def test_repeated_normalization_reuses_derived_artifact_and_preserves_original(self) -> None:
        with tempfile.TemporaryDirectory() as tmp:
            workspace = Path(tmp)
            session_dir = create_audio_session(workspace, [("mixed_audio", "mixed_audio.wav", wav_bytes(b"mixed"))])
            original_checksum = sha256_file(session_dir / "artifacts" / "mixed_audio.wav")

            first = run_audio_normalization("session-1", workspace=workspace)
            second = run_audio_normalization("session-1", workspace=workspace)

            indexed = artifacts_by_type(session_dir)
            final_checksum = sha256_file(session_dir / "artifacts" / "mixed_audio.wav")

        self.assertTrue(first["ok"])
        self.assertTrue(second["ok"])
        self.assertTrue(second["reused"])
        self.assertEqual(len(indexed["normalized_audio"]), 1)
        self.assertEqual(final_checksum, original_checksum)

    def test_explicit_source_after_existing_normalized_audio_returns_path_conflict(self) -> None:
        with tempfile.TemporaryDirectory() as tmp:
            workspace = Path(tmp)
            session_dir = create_audio_session(
                workspace,
                [
                    ("mixed_audio", "mixed_audio.wav", wav_bytes(b"mixed")),
                    ("system_audio", "system_audio.wav", wav_bytes(b"system")),
                ],
            )

            first = run_audio_normalization("session-1", workspace=workspace)
            second = run_audio_normalization("session-1", workspace=workspace, source_artifact_id="artifact-system_audio")

            indexed = artifacts_by_type(session_dir)

        self.assertTrue(first["ok"])
        self.assertFalse(second["ok"])
        self.assertEqual(second["code"], "path_conflict")
        self.assertEqual(len(indexed["normalized_audio"]), 1)

    def test_reuse_with_explicit_default_source_checks_original_media_drift(self) -> None:
        with tempfile.TemporaryDirectory() as tmp:
            workspace = Path(tmp)
            session_dir = create_audio_session(workspace, [("mixed_audio", "mixed_audio.wav", wav_bytes(b"mixed"))])

            first = run_audio_normalization("session-1", workspace=workspace)
            (session_dir / "artifacts" / "mixed_audio.wav").write_bytes(wav_bytes(b"mutated"))
            second = run_audio_normalization("session-1", workspace=workspace, source_artifact_id="artifact-mixed_audio")

        self.assertTrue(first["ok"])
        self.assertFalse(second["ok"])
        self.assertEqual(second["code"], "path_conflict")

    def test_existing_normalized_reuses_same_single_explicit_source(self) -> None:
        with tempfile.TemporaryDirectory() as tmp:
            workspace = Path(tmp)
            create_audio_session(workspace, [("system_audio", "system_audio.wav", wav_bytes(b"system"))])

            first = run_audio_normalization("session-1", workspace=workspace, source_artifact_id="artifact-system_audio")
            second = run_audio_normalization("session-1", workspace=workspace, source_artifact_id="artifact-system_audio")

        self.assertTrue(first["ok"])
        self.assertTrue(second["ok"])
        self.assertTrue(second["reused"])

    def test_non_wav_source_fails_without_registering_normalized_audio(self) -> None:
        with tempfile.TemporaryDirectory() as tmp:
            workspace = Path(tmp)
            session_dir = create_audio_session(workspace, [("mixed_audio", "mixed_audio.mp3", b"mp3-bytes")])

            response = run_audio_normalization("session-1", workspace=workspace)

            normalized_exists = (session_dir / "artifacts" / "normalized_audio.wav").exists()
            artifact_types = {artifact["artifact_type"] for artifact in load_session(session_dir)["artifacts"]}

        self.assertFalse(response["ok"])
        self.assertEqual(response["code"], "processing_failed")
        self.assertIn("WAV/PCM", response["message"])
        self.assertFalse(normalized_exists)
        self.assertNotIn("normalized_audio", artifact_types)

    def test_non_pcm_wav_source_fails_without_registering_normalized_audio(self) -> None:
        with tempfile.TemporaryDirectory() as tmp:
            workspace = Path(tmp)
            session_dir = create_audio_session(workspace, [("mixed_audio", "mixed_audio.wav", non_pcm_wav_bytes(b"float"))])

            response = run_audio_normalization("session-1", workspace=workspace)

            normalized_exists = (session_dir / "artifacts" / "normalized_audio.wav").exists()
            artifact_types = {artifact["artifact_type"] for artifact in load_session(session_dir)["artifacts"]}

        self.assertFalse(response["ok"])
        self.assertEqual(response["code"], "processing_failed")
        self.assertFalse(normalized_exists)
        self.assertNotIn("normalized_audio", artifact_types)

    def test_missing_session_returns_not_found_without_creating_session_directory(self) -> None:
        with tempfile.TemporaryDirectory() as tmp:
            workspace = Path(tmp)

            response = run_audio_normalization("missing-session", workspace=workspace)

            sessions_exists = (workspace / "sessions").exists()

        self.assertFalse(response["ok"])
        self.assertEqual(response["code"], "not_found")
        self.assertFalse(sessions_exists)

    def test_failed_normalization_preserves_original_and_writes_processing_evidence(self) -> None:
        def failing_normalizer(source: Path, destination: Path) -> None:
            destination.write_bytes(b"partial")
            raise OSError("adapter failed")

        with tempfile.TemporaryDirectory() as tmp:
            workspace = Path(tmp)
            session_dir = create_audio_session(workspace, [("mixed_audio", "mixed_audio.wav", wav_bytes(b"mixed"))])
            original_checksum = sha256_file(session_dir / "artifacts" / "mixed_audio.wav")

            response = run_audio_normalization(
                "session-1",
                workspace=workspace,
                request_id="local-failure",
                normalizer=failing_normalizer,
            )

            log_path = session_dir / "logs" / "processing.log"
            normalized_path = session_dir / "artifacts" / "normalized_audio.wav"
            session_payload = json.loads((session_dir / "session.json").read_text(encoding="utf-8"))
            normalized_exists = normalized_path.exists()
            final_checksum = sha256_file(session_dir / "artifacts" / "mixed_audio.wav")
            log_exists = log_path.is_file()
            log_text = log_path.read_text(encoding="utf-8")
            artifact_types = {artifact["artifact_type"] for artifact in session_payload["artifacts"]}

        self.assertFalse(response["ok"])
        self.assertEqual(response["code"], "processing_failed")
        self.assertFalse(normalized_exists)
        self.assertEqual(final_checksum, original_checksum)
        self.assertTrue(log_exists)
        self.assertIn("local-failure", log_text)
        self.assertIn("adapter failed", log_text)
        self.assertIn("adapter failed", response["message"])
        self.assertNotIn("normalized_audio", artifact_types)

    def test_unexpected_adapter_exception_preserves_evidence_and_removes_temp_file(self) -> None:
        def failing_normalizer(source: Path, destination: Path) -> None:
            destination.write_bytes(wav_bytes(b"partial"))
            raise ValueError("unexpected adapter failure")

        with tempfile.TemporaryDirectory() as tmp:
            workspace = Path(tmp)
            session_dir = create_audio_session(workspace, [("mixed_audio", "mixed_audio.wav", wav_bytes(b"mixed"))])

            response = run_audio_normalization(
                "session-1",
                workspace=workspace,
                request_id="local-unexpected",
                normalizer=failing_normalizer,
            )

            temp_exists = (session_dir / "artifacts" / ".normalized_audio.wav.tmp").exists()
            log_text = (session_dir / "logs" / "processing.log").read_text(encoding="utf-8")

        self.assertFalse(response["ok"])
        self.assertEqual(response["code"], "processing_failed")
        self.assertFalse(temp_exists)
        self.assertIn("unexpected adapter failure", response["message"])
        self.assertIn("local-unexpected", log_text)

    def test_post_registration_original_drift_rolls_back_normalized_artifact(self) -> None:
        with tempfile.TemporaryDirectory() as tmp:
            workspace = Path(tmp)
            session_dir = create_audio_session(workspace, [("mixed_audio", "mixed_audio.wav", wav_bytes(b"mixed"))])
            drift_error = ContractError("path_conflict", "Registered artifact checksum changed.", artifact_id="artifact-mixed_audio")

            with mock.patch(
                "meeting_assistant_cli.audio_processing.verify_registered_artifacts",
                side_effect=[True, drift_error],
            ):
                response = run_audio_normalization("session-1", workspace=workspace)

            normalized_exists = (session_dir / "artifacts" / "normalized_audio.wav").exists()
            artifact_types = {artifact["artifact_type"] for artifact in load_session(session_dir)["artifacts"]}

        self.assertFalse(response["ok"])
        self.assertEqual(response["code"], "path_conflict")
        self.assertFalse(normalized_exists)
        self.assertNotIn("normalized_audio", artifact_types)


if __name__ == "__main__":
    unittest.main()
