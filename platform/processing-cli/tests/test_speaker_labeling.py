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
from meeting_assistant_cli.speaker_labeling import SpeakerLabelAdapter, run_generate_speaker_labels
from meeting_assistant_cli.workspace_contract import (
    ContractError,
    create_session,
    load_session,
    register_artifact,
    session_directory,
    sha256_file,
    write_session,
)


def create_transcript_session(workspace: Path) -> Path:
    create_session(workspace, source_type="native_recording", session_id="session-1", status="recorded")
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
            {
                "segment_id": "segment-0001",
                "start_ms": 0,
                "end_ms": 1000,
                "text": "hello world",
            },
            {
                "segment_id": "segment-0002",
                "start_ms": 1000,
                "end_ms": 2400,
                "text": "second speaker",
            },
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


def speaker_payload(response: dict) -> dict:
    return json.loads(Path(str(response["artifacts"][0]["path"])).read_text(encoding="utf-8"))


class SpeakerLabelingTests(unittest.TestCase):
    def test_speaker_label_adapter_type_alias_imports_on_standard_python(self) -> None:
        self.assertIsNotNone(SpeakerLabelAdapter)

    def test_transcript_only_fallback_writes_degraded_speaker_label_artifact(self) -> None:
        with tempfile.TemporaryDirectory() as tmp:
            workspace = Path(tmp)
            session_dir = create_transcript_session(workspace)
            original_transcript = (session_dir / "artifacts" / "transcript.json").read_text(encoding="utf-8")

            response = run_generate_speaker_labels(
                "session-1",
                "transcript-1",
                workspace=workspace,
                allow_transcript_only_fallback=True,
            )

            payload = speaker_payload(response)
            final_transcript = (session_dir / "artifacts" / "transcript.json").read_text(encoding="utf-8")
            artifact = response["artifacts"][0]

        self.assertTrue(response["ok"])
        self.assertEqual(response["command"], "generate_speaker_labels")
        self.assertEqual(response["label_status"], "transcript_only")
        self.assertEqual(response["speaker_labels_artifact_id"], artifact["id"])
        self.assertEqual(artifact["artifact_type"], "speaker_labels")
        self.assertEqual(artifact["capture_status"], "degraded")
        self.assertIn("degradation_reason", response)
        self.assertEqual(payload["labels"], [])
        self.assertEqual(payload["segment_mapping"], [])
        self.assertEqual(payload["transcript_id"], "transcript-1")
        self.assertEqual(final_transcript, original_transcript)

    def test_fake_adapter_success_uses_anonymous_speaker_labels(self) -> None:
        def fake_adapter(transcript: dict, audio_path: Path | None) -> dict:
            return {
                "label_status": "labeled",
                "labels": [
                    {
                        "label": "SPEAKER_01",
                        "session_id": transcript["session_id"],
                        "is_verified_identity": False,
                    }
                ],
                "segment_mapping": [
                    {"segment_id": "segment-0001", "label": "SPEAKER_01"},
                    {"segment_id": "segment-0002", "label": "SPEAKER_01"},
                ],
                "engine": {"type": "fake_speaker_adapter", "available": True},
            }

        with tempfile.TemporaryDirectory() as tmp:
            workspace = Path(tmp)
            create_transcript_session(workspace)

            response = run_generate_speaker_labels(
                "session-1",
                "transcript-1",
                workspace=workspace,
                allow_transcript_only_fallback=True,
                adapter=fake_adapter,
            )

            payload = speaker_payload(response)

        self.assertTrue(response["ok"])
        self.assertEqual(response["label_status"], "labeled")
        self.assertEqual(payload["labels"][0]["label"], "SPEAKER_01")
        self.assertIs(payload["labels"][0]["is_verified_identity"], False)
        self.assertEqual(payload["segment_mapping"][0]["segment_id"], "segment-0001")

    def test_unsafe_adapter_identity_claim_degrades_to_transcript_only(self) -> None:
        def unsafe_adapter(transcript: dict, audio_path: Path | None) -> dict:
            return {
                "label_status": "labeled",
                "labels": [
                    {
                        "label": "SPEAKER_01",
                        "session_id": transcript["session_id"],
                        "is_verified_identity": True,
                    }
                ],
                "segment_mapping": [{"segment_id": "segment-0001", "label": "SPEAKER_01"}],
            }

        with tempfile.TemporaryDirectory() as tmp:
            workspace = Path(tmp)
            create_transcript_session(workspace)

            response = run_generate_speaker_labels(
                "session-1",
                "transcript-1",
                workspace=workspace,
                allow_transcript_only_fallback=True,
                adapter=unsafe_adapter,
            )

            payload = speaker_payload(response)

        self.assertTrue(response["ok"])
        self.assertEqual(response["label_status"], "transcript_only")
        self.assertEqual(payload["labels"], [])
        self.assertIn("adapter failed", response["degradation_reason"])

    def test_adapter_mapping_unknown_segment_degrades_without_unsafe_payload(self) -> None:
        def bad_mapping_adapter(transcript: dict, audio_path: Path | None) -> dict:
            return {
                "label_status": "labeled",
                "labels": [{"label": "SPEAKER_01", "session_id": transcript["session_id"], "is_verified_identity": False}],
                "segment_mapping": [{"segment_id": "segment-outside", "label": "SPEAKER_01"}],
            }

        with tempfile.TemporaryDirectory() as tmp:
            workspace = Path(tmp)
            create_transcript_session(workspace)

            response = run_generate_speaker_labels(
                "session-1",
                "transcript-1",
                workspace=workspace,
                allow_transcript_only_fallback=True,
                adapter=bad_mapping_adapter,
            )

            payload = speaker_payload(response)

        self.assertTrue(response["ok"])
        self.assertEqual(payload["label_status"], "transcript_only")
        self.assertEqual(payload["segment_mapping"], [])

    def test_adapter_failure_degradation_reason_is_sanitized(self) -> None:
        sensitive_phrase = "private transcript phrase"
        secret_value = "sk-speakersecret123456"
        sensitive_path = "/Users/jerry/.local/share/ai-models/speaker/model.bin"

        def sensitive_failure_adapter(transcript: dict, audio_path: Path | None) -> dict:
            raise RuntimeError(
                f"{sensitive_phrase} api_token={secret_value} Bearer abcdefghijklmnop {sensitive_path}"
            )

        with tempfile.TemporaryDirectory() as tmp:
            workspace = Path(tmp)
            create_transcript_session(workspace)

            response = run_generate_speaker_labels(
                "session-1",
                "transcript-1",
                workspace=workspace,
                allow_transcript_only_fallback=True,
                adapter=sensitive_failure_adapter,
            )

            payload = speaker_payload(response)
            response_json = json.dumps(response, ensure_ascii=False, sort_keys=True)
            payload_json = json.dumps(payload, ensure_ascii=False, sort_keys=True)

        self.assertTrue(response["ok"])
        self.assertEqual(response["label_status"], "transcript_only")
        self.assertIn("adapter failed", response["degradation_reason"])
        self.assertNotIn(sensitive_phrase, response_json)
        self.assertNotIn(secret_value, response_json)
        self.assertNotIn(sensitive_path, response_json)
        self.assertNotIn(sensitive_phrase, payload_json)
        self.assertNotIn(secret_value, payload_json)
        self.assertNotIn(sensitive_path, payload_json)

    def test_adapter_contract_error_text_is_not_written_to_fallback_payload(self) -> None:
        sensitive_phrase = "private transcript phrase from speaker adapter"
        secret_value = "sk-speakercontract123456"
        sensitive_path = "/Users/jerry/Meetings/private-diarization.log"

        def sensitive_failure_adapter(transcript: dict, audio_path: Path | None) -> dict:
            raise ContractError(
                "processing_failed",
                f"{sensitive_phrase} auth_token={secret_value} {sensitive_path}",
                transcript_path="/Users/jerry/Meetings/private-transcript.json",
            )

        with tempfile.TemporaryDirectory() as tmp:
            workspace = Path(tmp)
            create_transcript_session(workspace)

            response = run_generate_speaker_labels(
                "session-1",
                "transcript-1",
                workspace=workspace,
                allow_transcript_only_fallback=True,
                adapter=sensitive_failure_adapter,
            )

            payload = speaker_payload(response)
            response_json = json.dumps(response, ensure_ascii=False, sort_keys=True)
            payload_json = json.dumps(payload, ensure_ascii=False, sort_keys=True)

        self.assertTrue(response["ok"])
        self.assertEqual(response["label_status"], "transcript_only")
        self.assertIn("adapter failed", response["degradation_reason"])
        self.assertNotIn(sensitive_phrase, response_json)
        self.assertNotIn(secret_value, response_json)
        self.assertNotIn(sensitive_path, response_json)
        self.assertNotIn("private-transcript.json", response_json)
        self.assertNotIn(sensitive_phrase, payload_json)
        self.assertNotIn(secret_value, payload_json)
        self.assertNotIn(sensitive_path, payload_json)
        self.assertNotIn("private-transcript.json", payload_json)

    def test_adapter_contract_error_text_is_not_returned_when_fallback_disabled(self) -> None:
        sensitive_phrase = "private transcript phrase from speaker adapter"
        secret_value = "sk-speakerdisabled123456"
        sensitive_path = "/Users/jerry/Meetings/private-speaker.log"

        def sensitive_failure_adapter(transcript: dict, audio_path: Path | None) -> dict:
            raise ContractError(
                "processing_failed",
                f"{sensitive_phrase} auth_token={secret_value} {sensitive_path}",
                path=sensitive_path,
                transcript_id=transcript["id"],
                transcript_path="/Users/jerry/Meetings/private-transcript.json",
                stderr=f"{sensitive_phrase} stderr {secret_value}",
            )

        with tempfile.TemporaryDirectory() as tmp:
            workspace = Path(tmp)
            session_dir = create_transcript_session(workspace)

            response = run_generate_speaker_labels(
                "session-1",
                "transcript-1",
                workspace=workspace,
                allow_transcript_only_fallback=False,
                adapter=sensitive_failure_adapter,
            )
            response_json = json.dumps(response, ensure_ascii=False, sort_keys=True)
            log_text = (session_dir / "logs" / "processing.log").read_text(encoding="utf-8")

        self.assertFalse(response["ok"])
        self.assertEqual(response["code"], "processing_failed")
        self.assertEqual(response["message"], "Speaker labeling failed.")
        self.assertNotIn("path", response["details"])
        self.assertEqual(response["details"]["transcript_id"], "transcript-1")
        self.assertEqual(response["details"]["log_path"], str(session_dir / "logs" / "processing.log"))
        self.assertNotIn("private-speaker.log", response_json)
        self.assertNotIn(sensitive_phrase, response_json)
        self.assertNotIn(secret_value, response_json)
        self.assertNotIn(sensitive_path, response_json)
        self.assertNotIn("private-transcript.json", response_json)
        self.assertNotIn("private-speaker.log", log_text)
        self.assertNotIn(sensitive_phrase, log_text)
        self.assertNotIn(secret_value, log_text)
        self.assertNotIn(sensitive_path, log_text)
        self.assertNotIn("private-transcript.json", log_text)

    def test_adapter_supplied_degradation_reason_is_sanitized(self) -> None:
        explanation = "diarization confidence below threshold"
        secret_value = "ghp_speakersecret123456"
        sensitive_path = "/Users/jerry/.local/share/ai-models/speaker/model.bin"

        def transcript_only_adapter(transcript: dict, audio_path: Path | None) -> dict:
            return {
                "label_status": "transcript_only",
                "labels": [],
                "segment_mapping": [],
                "degradation_reason": (
                    f"{explanation}; secret={secret_value}; model={sensitive_path}"
                ),
            }

        with tempfile.TemporaryDirectory() as tmp:
            workspace = Path(tmp)
            create_transcript_session(workspace)

            response = run_generate_speaker_labels(
                "session-1",
                "transcript-1",
                workspace=workspace,
                allow_transcript_only_fallback=True,
                adapter=transcript_only_adapter,
            )

            payload = speaker_payload(response)
            combined_json = json.dumps({"response": response, "payload": payload}, ensure_ascii=False, sort_keys=True)

        self.assertTrue(response["ok"])
        self.assertEqual(response["label_status"], "transcript_only")
        self.assertIn(explanation, response["degradation_reason"])
        self.assertIn(explanation, combined_json)
        self.assertNotIn(secret_value, combined_json)
        self.assertNotIn(sensitive_path, combined_json)
        self.assertIn("secret=<redacted>", combined_json)
        self.assertIn("model=<path>", combined_json)

    def test_missing_transcript_returns_artifact_missing_without_speaker_file(self) -> None:
        with tempfile.TemporaryDirectory() as tmp:
            workspace = Path(tmp)
            session_dir = create_transcript_session(workspace)

            response = run_generate_speaker_labels(
                "session-1",
                "transcript-missing",
                workspace=workspace,
                allow_transcript_only_fallback=True,
            )

            speaker_exists = (session_dir / "artifacts" / "speaker_labels.json").exists()

        self.assertFalse(response["ok"])
        self.assertEqual(response["code"], "artifact_missing")
        self.assertFalse(speaker_exists)

    def test_fallback_disabled_returns_processing_failed(self) -> None:
        with tempfile.TemporaryDirectory() as tmp:
            workspace = Path(tmp)
            session_dir = create_transcript_session(workspace)

            response = run_generate_speaker_labels(
                "session-1",
                "transcript-1",
                workspace=workspace,
                allow_transcript_only_fallback=False,
            )

            speaker_exists = (session_dir / "artifacts" / "speaker_labels.json").exists()

        self.assertFalse(response["ok"])
        self.assertEqual(response["code"], "processing_failed")
        self.assertFalse(speaker_exists)

    def test_speaker_labels_symlink_destination_returns_path_conflict_without_external_write(self) -> None:
        with tempfile.TemporaryDirectory() as tmp:
            root = Path(tmp)
            workspace = root / "workspace"
            session_dir = create_transcript_session(workspace)
            outside = root / "outside-speaker-labels.json"
            outside.write_text('{"outside": true}\n', encoding="utf-8")
            speaker_path = session_dir / "artifacts" / "speaker_labels.json"
            speaker_path.symlink_to(outside)

            response = run_generate_speaker_labels(
                "session-1",
                "transcript-1",
                workspace=workspace,
                allow_transcript_only_fallback=True,
            )

            outside_text = outside.read_text(encoding="utf-8")
            speaker_is_symlink = speaker_path.is_symlink()
            artifact_types = {artifact["artifact_type"] for artifact in load_session(session_dir)["artifacts"]}

        self.assertFalse(response["ok"])
        self.assertEqual(response["code"], "path_conflict")
        self.assertEqual(outside_text, '{"outside": true}\n')
        self.assertTrue(speaker_is_symlink)
        self.assertNotIn("speaker_labels", artifact_types)

    def test_speaker_labels_broken_symlink_destination_returns_path_conflict_without_external_write(self) -> None:
        with tempfile.TemporaryDirectory() as tmp:
            root = Path(tmp)
            workspace = root / "workspace"
            session_dir = create_transcript_session(workspace)
            missing_target = root / "missing" / "speaker_labels.json"
            speaker_path = session_dir / "artifacts" / "speaker_labels.json"
            speaker_path.symlink_to(missing_target)

            response = run_generate_speaker_labels(
                "session-1",
                "transcript-1",
                workspace=workspace,
                allow_transcript_only_fallback=True,
            )

            target_exists = missing_target.exists()
            speaker_is_symlink = speaker_path.is_symlink()
            artifact_types = {artifact["artifact_type"] for artifact in load_session(session_dir)["artifacts"]}

        self.assertFalse(response["ok"])
        self.assertEqual(response["code"], "path_conflict")
        self.assertFalse(target_exists)
        self.assertTrue(speaker_is_symlink)
        self.assertNotIn("speaker_labels", artifact_types)

    def test_speaker_labels_hardlink_destination_returns_path_conflict_without_external_write(self) -> None:
        with tempfile.TemporaryDirectory() as tmp:
            root = Path(tmp)
            workspace = root / "workspace"
            session_dir = create_transcript_session(workspace)
            outside = root / "outside-speaker-labels.json"
            outside.write_text('{"outside": true}\n', encoding="utf-8")
            speaker_path = session_dir / "artifacts" / "speaker_labels.json"
            os.link(outside, speaker_path)

            response = run_generate_speaker_labels(
                "session-1",
                "transcript-1",
                workspace=workspace,
                allow_transcript_only_fallback=True,
            )

            outside_text = outside.read_text(encoding="utf-8")
            artifact_types = {artifact["artifact_type"] for artifact in load_session(session_dir)["artifacts"]}

        self.assertFalse(response["ok"])
        self.assertEqual(response["code"], "path_conflict")
        self.assertEqual(outside_text, '{"outside": true}\n')
        self.assertNotIn("speaker_labels", artifact_types)

    def test_speaker_labels_temp_symlink_returns_path_conflict_without_external_write(self) -> None:
        with tempfile.TemporaryDirectory() as tmp:
            root = Path(tmp)
            workspace = root / "workspace"
            session_dir = create_transcript_session(workspace)
            outside = root / "outside-temp-speaker-labels.json"
            outside.write_text('{"outside": true}\n', encoding="utf-8")
            temp_path = session_dir / "artifacts" / ".speaker_labels.json.tmp"
            temp_path.symlink_to(outside)

            response = run_generate_speaker_labels(
                "session-1",
                "transcript-1",
                workspace=workspace,
                allow_transcript_only_fallback=True,
            )

            outside_text = outside.read_text(encoding="utf-8")
            temp_is_symlink = temp_path.is_symlink()
            speaker_exists = (session_dir / "artifacts" / "speaker_labels.json").exists()
            artifact_types = {artifact["artifact_type"] for artifact in load_session(session_dir)["artifacts"]}

        self.assertFalse(response["ok"])
        self.assertEqual(response["code"], "path_conflict")
        self.assertEqual(outside_text, '{"outside": true}\n')
        self.assertTrue(temp_is_symlink)
        self.assertFalse(speaker_exists)
        self.assertNotIn("speaker_labels", artifact_types)

    def test_speaker_labels_temp_hardlink_returns_path_conflict_without_external_write(self) -> None:
        with tempfile.TemporaryDirectory() as tmp:
            root = Path(tmp)
            workspace = root / "workspace"
            session_dir = create_transcript_session(workspace)
            outside = root / "outside-temp-speaker-labels.json"
            outside.write_text('{"outside": true}\n', encoding="utf-8")
            temp_path = session_dir / "artifacts" / ".speaker_labels.json.tmp"
            os.link(outside, temp_path)

            response = run_generate_speaker_labels(
                "session-1",
                "transcript-1",
                workspace=workspace,
                allow_transcript_only_fallback=True,
            )

            outside_text = outside.read_text(encoding="utf-8")
            speaker_exists = (session_dir / "artifacts" / "speaker_labels.json").exists()
            artifact_types = {artifact["artifact_type"] for artifact in load_session(session_dir)["artifacts"]}

        self.assertFalse(response["ok"])
        self.assertEqual(response["code"], "path_conflict")
        self.assertEqual(outside_text, '{"outside": true}\n')
        self.assertFalse(speaker_exists)
        self.assertNotIn("speaker_labels", artifact_types)

    def test_registration_failure_rolls_back_speaker_file_and_temp(self) -> None:
        with tempfile.TemporaryDirectory() as tmp:
            workspace = Path(tmp)
            session_dir = create_transcript_session(workspace)

            with mock.patch(
                "meeting_assistant_cli.speaker_labeling.register_artifact",
                side_effect=ContractError("processing_failed", "registration failed"),
            ):
                response = run_generate_speaker_labels(
                    "session-1",
                    "transcript-1",
                    workspace=workspace,
                    allow_transcript_only_fallback=True,
                )

            speaker_exists = (session_dir / "artifacts" / "speaker_labels.json").exists()
            temp_exists = (session_dir / "artifacts" / ".speaker_labels.json.tmp").exists()
            artifact_types = {artifact["artifact_type"] for artifact in load_session(session_dir)["artifacts"]}

        self.assertFalse(response["ok"])
        self.assertEqual(response["code"], "processing_failed")
        self.assertFalse(speaker_exists)
        self.assertFalse(temp_exists)
        self.assertNotIn("speaker_labels", artifact_types)

    def test_repeated_speaker_labeling_reuses_existing_artifact(self) -> None:
        with tempfile.TemporaryDirectory() as tmp:
            workspace = Path(tmp)
            create_transcript_session(workspace)

            first = run_generate_speaker_labels(
                "session-1",
                "transcript-1",
                workspace=workspace,
                allow_transcript_only_fallback=True,
            )
            second = run_generate_speaker_labels(
                "session-1",
                "transcript-1",
                workspace=workspace,
                allow_transcript_only_fallback=True,
            )

            session = load_session(session_directory(workspace, "session-1"))
            speaker_artifacts = [artifact for artifact in session["artifacts"] if artifact["artifact_type"] == "speaker_labels"]

        self.assertTrue(first["ok"])
        self.assertTrue(second["ok"])
        self.assertTrue(second["reused"])
        self.assertEqual(len(speaker_artifacts), 1)

    def test_existing_speaker_labels_are_revalidated_against_current_transcript_segments(self) -> None:
        def fake_adapter(transcript: dict, audio_path: Path | None) -> dict:
            return {
                "label_status": "labeled",
                "labels": [{"label": "SPEAKER_01", "session_id": transcript["session_id"], "is_verified_identity": False}],
                "segment_mapping": [{"segment_id": "segment-0001", "label": "SPEAKER_01"}],
            }

        with tempfile.TemporaryDirectory() as tmp:
            workspace = Path(tmp)
            session_dir = create_transcript_session(workspace)
            first = run_generate_speaker_labels(
                "session-1",
                "transcript-1",
                workspace=workspace,
                allow_transcript_only_fallback=True,
                adapter=fake_adapter,
            )
            speaker_path = Path(str(first["artifacts"][0]["path"]))
            payload = json.loads(speaker_path.read_text(encoding="utf-8"))
            payload["segment_mapping"] = [{"segment_id": "segment-outside", "label": "SPEAKER_01"}]
            speaker_path.write_text(json.dumps(payload, ensure_ascii=False, indent=2, sort_keys=True) + "\n", encoding="utf-8")
            session = load_session(session_dir)
            for artifact in session["artifacts"]:
                if artifact["artifact_type"] == "speaker_labels":
                    artifact["checksum"] = sha256_file(speaker_path)
            write_session(session_dir, session)

            second = run_generate_speaker_labels(
                "session-1",
                "transcript-1",
                workspace=workspace,
                allow_transcript_only_fallback=True,
            )

        self.assertTrue(first["ok"])
        self.assertFalse(second["ok"])
        self.assertEqual(second["code"], "processing_failed")
        self.assertIn("unknown transcript segment", second["message"])

    def test_cli_generate_speaker_labels_success_and_exit_code(self) -> None:
        with tempfile.TemporaryDirectory() as tmp:
            workspace = Path(tmp)
            create_transcript_session(workspace)
            old_env = os.environ.copy()
            os.environ["MEETING_ASSISTANT_WORKSPACE"] = str(workspace)
            stdout = io.StringIO()
            try:
                with contextlib.redirect_stdout(stdout):
                    exit_code = main(
                        [
                            "generate_speaker_labels",
                            "--session-id",
                            "session-1",
                            "--transcript-id",
                            "transcript-1",
                            "--allow-transcript-only-fallback",
                            "true",
                        ]
                    )
            finally:
                os.environ.clear()
                os.environ.update(old_env)

            payload = json.loads(stdout.getvalue())

        self.assertEqual(exit_code, 0)
        self.assertTrue(payload["ok"])
        self.assertEqual(payload["command"], "generate_speaker_labels")
        self.assertEqual(payload["label_status"], "transcript_only")

    def test_cli_missing_required_argument_emits_contract_json(self) -> None:
        stdout = io.StringIO()
        with contextlib.redirect_stdout(stdout):
            exit_code = main(["generate_speaker_labels", "--session-id", "session-1"])

        payload = json.loads(stdout.getvalue())

        self.assertEqual(exit_code, 2)
        self.assertFalse(payload["ok"])
        self.assertEqual(payload["command"], "generate_speaker_labels")
        self.assertEqual(payload["code"], "invalid_input")
        self.assertIn("--transcript-id", payload["details"]["error"])

    def test_cli_unknown_argument_emits_contract_json(self) -> None:
        stdout = io.StringIO()
        with contextlib.redirect_stdout(stdout):
            exit_code = main(
                [
                    "generate_speaker_labels",
                    "--session-id",
                    "session-1",
                    "--transcript-id",
                    "transcript-1",
                    "--allow-transcript-only-fallback",
                    "true",
                    "--unknown-field",
                    "value",
                ]
            )

        payload = json.loads(stdout.getvalue())

        self.assertEqual(exit_code, 2)
        self.assertFalse(payload["ok"])
        self.assertEqual(payload["command"], "generate_speaker_labels")
        self.assertEqual(payload["code"], "invalid_input")
        self.assertIn("unrecognized arguments", payload["details"]["error"])

    def test_cli_invalid_fallback_enum_emits_contract_json(self) -> None:
        stdout = io.StringIO()
        with contextlib.redirect_stdout(stdout):
            exit_code = main(
                [
                    "generate_speaker_labels",
                    "--session-id",
                    "session-1",
                    "--transcript-id",
                    "transcript-1",
                    "--allow-transcript-only-fallback",
                    "yes",
                ]
            )

        payload = json.loads(stdout.getvalue())

        self.assertEqual(exit_code, 2)
        self.assertFalse(payload["ok"])
        self.assertEqual(payload["code"], "invalid_input")
        self.assertIn("invalid choice", payload["details"]["error"])


if __name__ == "__main__":
    unittest.main()
