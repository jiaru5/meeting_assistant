from __future__ import annotations

import contextlib
import io
import json
import os
import tempfile
import unittest
from pathlib import Path

from meeting_assistant_cli.cli import main
from meeting_assistant_cli.speaker_labeling import run_generate_speaker_labels
from meeting_assistant_cli.workspace_contract import create_session, load_session, register_artifact, session_directory


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
                            "--format",
                            "json",
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
            exit_code = main(["generate_speaker_labels", "--session-id", "session-1", "--format", "json"])

        payload = json.loads(stdout.getvalue())

        self.assertEqual(exit_code, 2)
        self.assertFalse(payload["ok"])
        self.assertEqual(payload["command"], "generate_speaker_labels")
        self.assertEqual(payload["code"], "invalid_input")
        self.assertIn("--transcript-id", payload["details"]["error"])

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
