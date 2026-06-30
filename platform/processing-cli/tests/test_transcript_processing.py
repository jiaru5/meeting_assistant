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
from meeting_assistant_cli.transcript_processing import run_generate_transcript
from meeting_assistant_cli.workspace_contract import ContractError, create_session, load_session, register_artifact, session_directory


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


def fake_whisper_cli(directory: Path, mode: str = "valid") -> str:
    path = directory / "whisper-cli"
    path.write_text(
        f"""#!/usr/bin/env python3
import json
import os
import sys
from pathlib import Path

MODE = {mode!r}
args = sys.argv[1:]
log_path = os.environ.get("MEETING_ASSISTANT_FAKE_WHISPER_ARGS_LOG")
if log_path:
    Path(log_path).write_text(json.dumps(args, ensure_ascii=False), encoding="utf-8")
output_prefix = None
for index, arg in enumerate(args):
    if arg in {"--output-file", "-of"} and index + 1 < len(args):
        output_prefix = args[index + 1]
        break
if output_prefix:
    output_path = Path(output_prefix + ".json")
    if MODE == "invalid_json":
        output_path.write_text("not-json", encoding="utf-8")
    elif MODE == "invalid_utf8_token_json":
        payload = {{
            "transcription": [{{"offsets": {{"from": 0, "to": 1200}}, "text": "中文 HTTP LLM clean architecture EDA"}}],
            "tokens": [{{"text": "token-placeholder"}}],
        }}
        output_path.write_bytes(
            json.dumps(payload, ensure_ascii=False).encode("utf-8").replace(b'"token-placeholder"', b'"\\xe8\\xae"')
        )
    elif MODE == "empty_segments":
        output_path.write_text(json.dumps({{"transcription": []}}, ensure_ascii=False), encoding="utf-8")
    elif MODE == "bad_offsets":
        payload = {{"transcription": [{{"offsets": {{"from": 2000, "to": 1000}}, "text": "bad"}}]}}
        output_path.write_text(json.dumps(payload, ensure_ascii=False), encoding="utf-8")
    else:
        payload = {{
            "transcription": [
                {{"offsets": {{"from": 1000, "to": 2200}}, "text": "第二段 EDA"}},
                {{"offsets": {{"from": 0, "to": 900}}, "text": "中文 HTTP LLM clean architecture"}},
            ]
        }}
        output_path.write_text(json.dumps(payload, ensure_ascii=False), encoding="utf-8")
raise SystemExit(int(os.environ.get("MEETING_ASSISTANT_FAKE_WHISPER_EXIT_CODE", "0")))
""",
        encoding="utf-8",
    )
    path.chmod(0o755)
    return str(path)


def fake_model(directory: Path, name: str = "ggml-large-v3-turbo.bin") -> str:
    path = directory / name
    path.write_bytes(b"fake-whisper-model")
    return str(path)


def create_audio_session(workspace: Path, artifacts: list[tuple[str, str, bytes]]) -> Path:
    create_session(workspace, source_type="native_recording", session_id="session-1", status="recorded")
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


def transcript_payload(response: dict) -> dict:
    artifact = response["artifacts"][0]
    return json.loads(Path(str(artifact["path"])).read_text(encoding="utf-8"))


def write_registered_transcript(
    session_dir: Path,
    *,
    source_artifact_id: str,
    language: str | None = None,
    segments: list[dict] | None = None,
) -> dict:
    payload: dict[str, object] = {
        "id": "transcript-existing",
        "session_id": "session-1",
        "source_artifact_id": source_artifact_id,
        "status": "succeeded",
        "segments": segments
        or [
            {
                "segment_id": "segment-0001",
                "start_ms": 0,
                "end_ms": 1000,
                "text": "existing transcript",
            }
        ],
        "created_at": "2026-01-01T00:00:00Z",
    }
    if language:
        payload["language"] = language
    path = session_dir / "artifacts" / "transcript.json"
    path.write_text(json.dumps(payload, ensure_ascii=False, indent=2, sort_keys=True) + "\n", encoding="utf-8")
    return register_artifact(
        session_dir,
        artifact_type="transcript_text",
        path=Path("artifacts/transcript.json"),
        file_format="json",
        artifact_id="artifact-transcript_text",
    )


class TranscriptProcessingTests(unittest.TestCase):
    def test_generate_transcript_normalizes_default_mixed_audio_and_writes_transcript_artifact(self) -> None:
        with tempfile.TemporaryDirectory() as tmp:
            workspace = Path(tmp)
            session_dir = create_audio_session(workspace, [("mixed_audio", "mixed_audio.wav", wav_bytes(b"mixed"))])

            response = run_generate_transcript("session-1", workspace=workspace, language="en")

            session = load_session(session_dir)
            artifact_types = {artifact["artifact_type"] for artifact in session["artifacts"]}
            normalized_id = next(artifact["id"] for artifact in session["artifacts"] if artifact["artifact_type"] == "normalized_audio")
            payload = transcript_payload(response)
            normalized_exists = (session_dir / "artifacts" / "normalized_audio.wav").is_file()

        self.assertTrue(response["ok"])
        self.assertEqual(response["command"], "generate_transcript")
        self.assertEqual(response["transcript_id"], payload["id"])
        self.assertEqual(response["artifact_id"], response["artifacts"][0]["id"])
        self.assertEqual(response["segment_count"], 1)
        self.assertIn("normalized_audio", artifact_types)
        self.assertIn("transcript_text", artifact_types)
        self.assertTrue(normalized_exists)
        self.assertEqual(payload["session_id"], "session-1")
        self.assertEqual(payload["language"], "en")
        self.assertEqual(payload["status"], "succeeded")
        self.assertEqual(payload["source_artifact_id"], normalized_id)
        self.assertLess(payload["segments"][0]["start_ms"], payload["segments"][0]["end_ms"])

    def test_generate_transcript_uses_existing_normalized_audio(self) -> None:
        with tempfile.TemporaryDirectory() as tmp:
            workspace = Path(tmp)
            session_dir = create_audio_session(workspace, [("normalized_audio", "normalized_audio.wav", wav_bytes(b"normalized"))])

            response = run_generate_transcript("session-1", workspace=workspace)

            payload = transcript_payload(response)

        self.assertTrue(response["ok"])
        self.assertEqual(payload["source_artifact_id"], "artifact-normalized_audio")

    def test_generate_transcript_can_use_explicit_fallback_audio_when_mixed_audio_missing(self) -> None:
        with tempfile.TemporaryDirectory() as tmp:
            workspace = Path(tmp)
            session_dir = create_audio_session(workspace, [("system_audio", "system_audio.wav", wav_bytes(b"system"))])

            response = run_generate_transcript("session-1", workspace=workspace, source_artifact_id="artifact-system_audio")

            payload = transcript_payload(response)
            session = load_session(session_dir)
            artifact_types = {artifact["artifact_type"] for artifact in session["artifacts"]}
            normalized_id = next(artifact["id"] for artifact in session["artifacts"] if artifact["artifact_type"] == "normalized_audio")

        self.assertTrue(response["ok"])
        self.assertIn("normalized_audio", artifact_types)
        self.assertEqual(payload["source_artifact_id"], normalized_id)

    def test_generate_transcript_sorts_adapter_segments(self) -> None:
        def unsorted_adapter(audio_path: Path, language: str | None, runtime: str | None) -> list[dict]:
            return [
                {"segment_id": "segment-2", "start_ms": 1000, "end_ms": 2000, "text": "second"},
                {"segment_id": "segment-1", "start_ms": 0, "end_ms": 900, "text": "first"},
            ]

        with tempfile.TemporaryDirectory() as tmp:
            workspace = Path(tmp)
            create_audio_session(workspace, [("mixed_audio", "mixed_audio.wav", wav_bytes(b"mixed"))])

            response = run_generate_transcript("session-1", workspace=workspace, adapter=unsorted_adapter)

            segments = transcript_payload(response)["segments"]

        self.assertTrue(response["ok"])
        self.assertEqual([segment["text"] for segment in segments], ["first", "second"])

    def test_missing_audio_returns_artifact_missing(self) -> None:
        with tempfile.TemporaryDirectory() as tmp:
            workspace = Path(tmp)
            session_dir = create_audio_session(workspace, [])

            response = run_generate_transcript("session-1", workspace=workspace, request_id="local-no-audio")

            transcript_exists = (session_dir / "artifacts" / "transcript.json").exists()
            log_text = (session_dir / "logs" / "processing.log").read_text(encoding="utf-8")

        self.assertFalse(response["ok"])
        self.assertEqual(response["code"], "artifact_missing")
        self.assertFalse(transcript_exists)
        self.assertIn("local-no-audio", log_text)

    def test_invalid_adapter_segments_return_processing_failed_without_artifact(self) -> None:
        def invalid_adapter(audio_path: Path, language: str | None, runtime: str | None) -> list[dict]:
            return [{"segment_id": "bad", "start_ms": 2000, "end_ms": 1000, "text": "bad"}]

        with tempfile.TemporaryDirectory() as tmp:
            workspace = Path(tmp)
            session_dir = create_audio_session(workspace, [("mixed_audio", "mixed_audio.wav", wav_bytes(b"mixed"))])

            response = run_generate_transcript("session-1", workspace=workspace, adapter=invalid_adapter)

            transcript_exists = (session_dir / "artifacts" / "transcript.json").exists()
            artifact_types = {artifact["artifact_type"] for artifact in load_session(session_dir)["artifacts"]}

        self.assertFalse(response["ok"])
        self.assertEqual(response["code"], "processing_failed")
        self.assertFalse(transcript_exists)
        self.assertNotIn("transcript_text", artifact_types)

    def test_adapter_exception_returns_processing_failed_and_preserves_original_audio(self) -> None:
        def failing_adapter(audio_path: Path, language: str | None, runtime: str | None) -> list[dict]:
            raise RuntimeError("fake adapter failed")

        with tempfile.TemporaryDirectory() as tmp:
            workspace = Path(tmp)
            session_dir = create_audio_session(workspace, [("mixed_audio", "mixed_audio.wav", wav_bytes(b"mixed"))])
            original_bytes = (session_dir / "artifacts" / "mixed_audio.wav").read_bytes()

            response = run_generate_transcript("session-1", workspace=workspace, request_id="local-adapter-failure", adapter=failing_adapter)

            final_bytes = (session_dir / "artifacts" / "mixed_audio.wav").read_bytes()
            transcript_exists = (session_dir / "artifacts" / "transcript.json").exists()
            log_text = (session_dir / "logs" / "processing.log").read_text(encoding="utf-8")

        self.assertFalse(response["ok"])
        self.assertEqual(response["code"], "processing_failed")
        self.assertEqual(final_bytes, original_bytes)
        self.assertFalse(transcript_exists)
        self.assertIn("local-adapter-failure", log_text)

    def test_adapter_contract_error_returns_processing_failed_without_transcript_artifact(self) -> None:
        def failing_adapter(audio_path: Path, language: str | None, runtime: str | None) -> list[dict]:
            raise ContractError("processing_failed", "adapter contract failure")

        with tempfile.TemporaryDirectory() as tmp:
            workspace = Path(tmp)
            session_dir = create_audio_session(workspace, [("mixed_audio", "mixed_audio.wav", wav_bytes(b"mixed"))])

            response = run_generate_transcript("session-1", workspace=workspace, adapter=failing_adapter)

            transcript_exists = (session_dir / "artifacts" / "transcript.json").exists()
            artifact_types = {artifact["artifact_type"] for artifact in load_session(session_dir)["artifacts"]}

        self.assertFalse(response["ok"])
        self.assertEqual(response["code"], "processing_failed")
        self.assertFalse(transcript_exists)
        self.assertNotIn("transcript_text", artifact_types)

    def test_transcript_symlink_destination_returns_path_conflict_without_external_write(self) -> None:
        with tempfile.TemporaryDirectory() as tmp:
            root = Path(tmp)
            workspace = root / "workspace"
            session_dir = create_audio_session(workspace, [("mixed_audio", "mixed_audio.wav", wav_bytes(b"mixed"))])
            outside = root / "outside-transcript.json"
            outside.write_text('{"outside": true}\n', encoding="utf-8")
            transcript_path = session_dir / "artifacts" / "transcript.json"
            transcript_path.symlink_to(outside)

            response = run_generate_transcript("session-1", workspace=workspace)

            outside_text = outside.read_text(encoding="utf-8")
            transcript_is_symlink = transcript_path.is_symlink()
            artifact_types = {artifact["artifact_type"] for artifact in load_session(session_dir)["artifacts"]}

        self.assertFalse(response["ok"])
        self.assertEqual(response["code"], "path_conflict")
        self.assertEqual(outside_text, '{"outside": true}\n')
        self.assertTrue(transcript_is_symlink)
        self.assertNotIn("transcript_text", artifact_types)

    def test_transcript_broken_symlink_destination_returns_path_conflict_without_external_write(self) -> None:
        with tempfile.TemporaryDirectory() as tmp:
            root = Path(tmp)
            workspace = root / "workspace"
            session_dir = create_audio_session(workspace, [("mixed_audio", "mixed_audio.wav", wav_bytes(b"mixed"))])
            missing_target = root / "missing" / "transcript.json"
            transcript_path = session_dir / "artifacts" / "transcript.json"
            transcript_path.symlink_to(missing_target)

            response = run_generate_transcript("session-1", workspace=workspace)

            target_exists = missing_target.exists()
            transcript_is_symlink = transcript_path.is_symlink()
            artifact_types = {artifact["artifact_type"] for artifact in load_session(session_dir)["artifacts"]}

        self.assertFalse(response["ok"])
        self.assertEqual(response["code"], "path_conflict")
        self.assertFalse(target_exists)
        self.assertTrue(transcript_is_symlink)
        self.assertNotIn("transcript_text", artifact_types)

    def test_transcript_hardlink_destination_returns_path_conflict_without_external_write(self) -> None:
        with tempfile.TemporaryDirectory() as tmp:
            root = Path(tmp)
            workspace = root / "workspace"
            session_dir = create_audio_session(workspace, [("mixed_audio", "mixed_audio.wav", wav_bytes(b"mixed"))])
            outside = root / "outside-transcript.json"
            outside.write_text('{"outside": true}\n', encoding="utf-8")
            transcript_path = session_dir / "artifacts" / "transcript.json"
            os.link(outside, transcript_path)

            response = run_generate_transcript("session-1", workspace=workspace)

            outside_text = outside.read_text(encoding="utf-8")
            artifact_types = {artifact["artifact_type"] for artifact in load_session(session_dir)["artifacts"]}

        self.assertFalse(response["ok"])
        self.assertEqual(response["code"], "path_conflict")
        self.assertEqual(outside_text, '{"outside": true}\n')
        self.assertNotIn("transcript_text", artifact_types)

    def test_transcript_temp_symlink_returns_path_conflict_without_external_write(self) -> None:
        with tempfile.TemporaryDirectory() as tmp:
            root = Path(tmp)
            workspace = root / "workspace"
            session_dir = create_audio_session(workspace, [("mixed_audio", "mixed_audio.wav", wav_bytes(b"mixed"))])
            outside = root / "outside-temp-transcript.json"
            outside.write_text('{"outside": true}\n', encoding="utf-8")
            temp_path = session_dir / "artifacts" / ".transcript.json.tmp"
            temp_path.symlink_to(outside)

            response = run_generate_transcript("session-1", workspace=workspace)

            outside_text = outside.read_text(encoding="utf-8")
            temp_is_symlink = temp_path.is_symlink()
            transcript_exists = (session_dir / "artifacts" / "transcript.json").exists()
            artifact_types = {artifact["artifact_type"] for artifact in load_session(session_dir)["artifacts"]}

        self.assertFalse(response["ok"])
        self.assertEqual(response["code"], "path_conflict")
        self.assertEqual(outside_text, '{"outside": true}\n')
        self.assertTrue(temp_is_symlink)
        self.assertFalse(transcript_exists)
        self.assertNotIn("transcript_text", artifact_types)

    def test_transcript_temp_hardlink_returns_path_conflict_without_external_write(self) -> None:
        with tempfile.TemporaryDirectory() as tmp:
            root = Path(tmp)
            workspace = root / "workspace"
            session_dir = create_audio_session(workspace, [("mixed_audio", "mixed_audio.wav", wav_bytes(b"mixed"))])
            outside = root / "outside-temp-transcript.json"
            outside.write_text('{"outside": true}\n', encoding="utf-8")
            temp_path = session_dir / "artifacts" / ".transcript.json.tmp"
            os.link(outside, temp_path)

            response = run_generate_transcript("session-1", workspace=workspace)

            outside_text = outside.read_text(encoding="utf-8")
            transcript_exists = (session_dir / "artifacts" / "transcript.json").exists()
            artifact_types = {artifact["artifact_type"] for artifact in load_session(session_dir)["artifacts"]}

        self.assertFalse(response["ok"])
        self.assertEqual(response["code"], "path_conflict")
        self.assertEqual(outside_text, '{"outside": true}\n')
        self.assertFalse(transcript_exists)
        self.assertNotIn("transcript_text", artifact_types)

    def test_unsupported_runtime_is_rejected_before_creating_transcript_or_normalized_audio(self) -> None:
        with tempfile.TemporaryDirectory() as tmp:
            workspace = Path(tmp)
            session_dir = create_audio_session(workspace, [("mixed_audio", "mixed_audio.wav", wav_bytes(b"mixed"))])

            response = run_generate_transcript("session-1", workspace=workspace, runtime="whisper-local")

            artifact_types = {artifact["artifact_type"] for artifact in load_session(session_dir)["artifacts"]}
            transcript_exists = (session_dir / "artifacts" / "transcript.json").exists()
            normalized_exists = (session_dir / "artifacts" / "normalized_audio.wav").exists()

        self.assertFalse(response["ok"])
        self.assertEqual(response["code"], "invalid_input")
        self.assertNotIn("transcript_text", artifact_types)
        self.assertNotIn("normalized_audio", artifact_types)
        self.assertFalse(transcript_exists)
        self.assertFalse(normalized_exists)

    def test_unsupported_runtime_is_rejected_before_missing_session_lookup(self) -> None:
        with tempfile.TemporaryDirectory() as tmp:
            workspace = Path(tmp)

            response = run_generate_transcript("missing-session", workspace=workspace, runtime="not-supported")

        self.assertFalse(response["ok"])
        self.assertEqual(response["code"], "invalid_input")
        self.assertEqual(response["details"]["supported_runtime"], "whisper_cpp")

    def test_whisper_cpp_missing_config_returns_dependency_missing_without_artifacts(self) -> None:
        with tempfile.TemporaryDirectory() as tmp:
            workspace = Path(tmp)
            session_dir = create_audio_session(workspace, [("mixed_audio", "mixed_audio.wav", wav_bytes(b"mixed"))])
            with mock.patch.dict(os.environ, {}, clear=True):
                response = run_generate_transcript("session-1", workspace=workspace, runtime="whisper_cpp")

            artifact_types = {artifact["artifact_type"] for artifact in load_session(session_dir)["artifacts"]}
            transcript_exists = (session_dir / "artifacts" / "transcript.json").exists()
            normalized_exists = (session_dir / "artifacts" / "normalized_audio.wav").exists()

        self.assertFalse(response["ok"])
        self.assertEqual(response["code"], "dependency_missing")
        self.assertEqual(
            response["details"]["missing"],
            ["MEETING_ASSISTANT_TRANSCRIPTION_RUNTIME", "MEETING_ASSISTANT_TRANSCRIPTION_MODEL"],
        )
        self.assertNotIn("transcript_text", artifact_types)
        self.assertNotIn("normalized_audio", artifact_types)
        self.assertFalse(transcript_exists)
        self.assertFalse(normalized_exists)

    def test_whisper_cpp_english_only_model_is_rejected_before_normalization(self) -> None:
        with tempfile.TemporaryDirectory() as tmp:
            root = Path(tmp)
            workspace = root / "workspace"
            runtime_dir = root / "runtime"
            runtime_dir.mkdir()
            session_dir = create_audio_session(workspace, [("mixed_audio", "mixed_audio.wav", wav_bytes(b"mixed"))])
            env = {
                "MEETING_ASSISTANT_TRANSCRIPTION_RUNTIME": fake_whisper_cli(runtime_dir),
                "MEETING_ASSISTANT_TRANSCRIPTION_MODEL": fake_model(runtime_dir, "ggml-base.en-q5_0.bin"),
            }
            with mock.patch.dict(os.environ, env, clear=True):
                response = run_generate_transcript("session-1", workspace=workspace, runtime="whisper_cpp")

            artifact_types = {artifact["artifact_type"] for artifact in load_session(session_dir)["artifacts"]}
            transcript_exists = (session_dir / "artifacts" / "transcript.json").exists()
            normalized_exists = (session_dir / "artifacts" / "normalized_audio.wav").exists()

        self.assertFalse(response["ok"])
        self.assertEqual(response["code"], "dependency_missing")
        self.assertEqual(response["details"]["model_name"], "ggml-base.en-q5_0.bin")
        self.assertNotIn("transcript_text", artifact_types)
        self.assertNotIn("normalized_audio", artifact_types)
        self.assertFalse(transcript_exists)
        self.assertFalse(normalized_exists)

    def test_configured_whisper_cpp_writes_transcript_from_runtime_json(self) -> None:
        with tempfile.TemporaryDirectory() as tmp:
            root = Path(tmp)
            workspace = root / "workspace"
            runtime_dir = root / "runtime"
            runtime_dir.mkdir()
            args_log = root / "whisper-args.json"
            session_dir = create_audio_session(workspace, [("mixed_audio", "mixed_audio.wav", wav_bytes(b"mixed"))])
            env = {
                "MEETING_ASSISTANT_TRANSCRIPTION_RUNTIME": fake_whisper_cli(runtime_dir),
                "MEETING_ASSISTANT_TRANSCRIPTION_MODEL": fake_model(runtime_dir),
                "MEETING_ASSISTANT_FAKE_WHISPER_ARGS_LOG": str(args_log),
            }
            with mock.patch.dict(os.environ, env, clear=True):
                response = run_generate_transcript("session-1", workspace=workspace, language="zh", runtime="whisper_cpp")

            artifact_types = {artifact["artifact_type"] for artifact in load_session(session_dir)["artifacts"]}
            payload = transcript_payload(response)
            args = json.loads(args_log.read_text(encoding="utf-8"))

        self.assertTrue(response["ok"])
        self.assertIn("transcript_text", artifact_types)
        self.assertIn("normalized_audio", artifact_types)
        self.assertEqual(response["segment_count"], 2)
        self.assertEqual([segment["text"] for segment in payload["segments"]], ["中文 HTTP LLM clean architecture", "第二段 EDA"])
        self.assertEqual([segment["start_ms"] for segment in payload["segments"]], [0, 1000])
        self.assertIn("--output-json-full", args)
        self.assertIn("--no-prints", args)
        self.assertIn("-l", args)
        self.assertIn("zh", args)
        self.assertIn("--prompt", args)
        prompt_index = args.index("--prompt") + 1
        self.assertEqual(args[prompt_index], "HTTP LLM clean architecture EDA")

    def test_whisper_cpp_tolerates_invalid_utf8_in_unused_json_details(self) -> None:
        with tempfile.TemporaryDirectory() as tmp:
            root = Path(tmp)
            workspace = root / "workspace"
            runtime_dir = root / "runtime"
            runtime_dir.mkdir()
            create_audio_session(workspace, [("mixed_audio", "mixed_audio.wav", wav_bytes(b"mixed"))])
            env = {
                "MEETING_ASSISTANT_TRANSCRIPTION_RUNTIME": fake_whisper_cli(runtime_dir, "invalid_utf8_token_json"),
                "MEETING_ASSISTANT_TRANSCRIPTION_MODEL": fake_model(runtime_dir),
            }
            with mock.patch.dict(os.environ, env, clear=True):
                response = run_generate_transcript("session-1", workspace=workspace, language="zh", runtime="whisper_cpp")

            payload = transcript_payload(response)

        self.assertTrue(response["ok"])
        self.assertEqual(response["segment_count"], 1)
        self.assertEqual(payload["segments"][0]["text"], "中文 HTTP LLM clean architecture EDA")

    def test_whisper_cpp_invalid_json_returns_processing_failed_without_transcript(self) -> None:
        for mode in ("invalid_json", "empty_segments", "bad_offsets"):
            with self.subTest(mode=mode):
                with tempfile.TemporaryDirectory() as tmp:
                    root = Path(tmp)
                    workspace = root / "workspace"
                    runtime_dir = root / "runtime"
                    runtime_dir.mkdir()
                    session_dir = create_audio_session(workspace, [("mixed_audio", "mixed_audio.wav", wav_bytes(b"mixed"))])
                    env = {
                        "MEETING_ASSISTANT_TRANSCRIPTION_RUNTIME": fake_whisper_cli(runtime_dir, mode),
                        "MEETING_ASSISTANT_TRANSCRIPTION_MODEL": fake_model(runtime_dir),
                    }
                    with mock.patch.dict(os.environ, env, clear=True):
                        response = run_generate_transcript("session-1", workspace=workspace, runtime="whisper_cpp")

                    transcript_exists = (session_dir / "artifacts" / "transcript.json").exists()
                    artifact_types = {artifact["artifact_type"] for artifact in load_session(session_dir)["artifacts"]}

                self.assertFalse(response["ok"])
                self.assertEqual(response["code"], "processing_failed")
                self.assertFalse(transcript_exists)
                self.assertNotIn("transcript_text", artifact_types)

    def test_whisper_cpp_runtime_failure_returns_processing_failed_without_transcript(self) -> None:
        with tempfile.TemporaryDirectory() as tmp:
            root = Path(tmp)
            workspace = root / "workspace"
            runtime_dir = root / "runtime"
            runtime_dir.mkdir()
            session_dir = create_audio_session(workspace, [("mixed_audio", "mixed_audio.wav", wav_bytes(b"mixed"))])
            env = {
                "MEETING_ASSISTANT_TRANSCRIPTION_RUNTIME": fake_whisper_cli(runtime_dir),
                "MEETING_ASSISTANT_TRANSCRIPTION_MODEL": fake_model(runtime_dir),
                "MEETING_ASSISTANT_FAKE_WHISPER_EXIT_CODE": "7",
            }
            with mock.patch.dict(os.environ, env, clear=True):
                response = run_generate_transcript("session-1", workspace=workspace, runtime="whisper_cpp")

            transcript_exists = (session_dir / "artifacts" / "transcript.json").exists()
            artifact_types = {artifact["artifact_type"] for artifact in load_session(session_dir)["artifacts"]}

        self.assertFalse(response["ok"])
        self.assertEqual(response["code"], "processing_failed")
        self.assertEqual(response["details"]["exit_code"], 7)
        self.assertFalse(transcript_exists)
        self.assertNotIn("transcript_text", artifact_types)

    def test_runtime_request_does_not_reuse_existing_transcript_without_runtime_metadata(self) -> None:
        with tempfile.TemporaryDirectory() as tmp:
            root = Path(tmp)
            workspace = root / "workspace"
            runtime_dir = root / "runtime"
            runtime_dir.mkdir()
            session_dir = create_audio_session(workspace, [("mixed_audio", "mixed_audio.wav", wav_bytes(b"mixed"))])
            write_registered_transcript(session_dir, source_artifact_id="artifact-mixed_audio")
            original_payload = (session_dir / "artifacts" / "transcript.json").read_text(encoding="utf-8")
            env = {
                "MEETING_ASSISTANT_TRANSCRIPTION_RUNTIME": fake_whisper_cli(runtime_dir),
                "MEETING_ASSISTANT_TRANSCRIPTION_MODEL": fake_model(runtime_dir),
            }
            with mock.patch.dict(os.environ, env, clear=True):
                response = run_generate_transcript("session-1", workspace=workspace, runtime="whisper_cpp")

            final_payload = (session_dir / "artifacts" / "transcript.json").read_text(encoding="utf-8")
            artifact_types = {artifact["artifact_type"] for artifact in load_session(session_dir)["artifacts"]}

        self.assertFalse(response["ok"])
        self.assertEqual(response["code"], "processing_failed")
        self.assertEqual(final_payload, original_payload)
        self.assertIn("transcript_text", artifact_types)
        self.assertNotIn("normalized_audio", artifact_types)

    def test_existing_transcript_is_reused_without_overwrite(self) -> None:
        with tempfile.TemporaryDirectory() as tmp:
            workspace = Path(tmp)
            session_dir = create_audio_session(workspace, [("mixed_audio", "mixed_audio.wav", wav_bytes(b"mixed"))])

            first = run_generate_transcript("session-1", workspace=workspace)
            transcript_path = Path(str(first["artifacts"][0]["path"]))
            original_payload = transcript_path.read_text(encoding="utf-8")
            second = run_generate_transcript("session-1", workspace=workspace)
            final_payload = transcript_path.read_text(encoding="utf-8")

        self.assertTrue(first["ok"])
        self.assertTrue(second["ok"])
        self.assertTrue(second["reused"])
        self.assertEqual(final_payload, original_payload)

    def test_existing_raw_source_transcript_is_reused_before_normalization(self) -> None:
        with tempfile.TemporaryDirectory() as tmp:
            workspace = Path(tmp)
            session_dir = create_audio_session(workspace, [("mixed_audio", "mixed_audio.wav", wav_bytes(b"mixed"))])
            existing = write_registered_transcript(session_dir, source_artifact_id="artifact-mixed_audio", language="en")

            response = run_generate_transcript("session-1", workspace=workspace, source_artifact_id="artifact-mixed_audio", language="en")

            artifact_types = {artifact["artifact_type"] for artifact in load_session(session_dir)["artifacts"]}
            transcript_payload_text = (session_dir / "artifacts" / "transcript.json").read_text(encoding="utf-8")

        self.assertTrue(response["ok"])
        self.assertTrue(response["reused"])
        self.assertEqual(response["artifacts"][0]["id"], existing["id"])
        self.assertNotIn("normalized_audio", artifact_types)
        self.assertIn("existing transcript", transcript_payload_text)

    def test_existing_default_transcript_is_reused_before_normalization(self) -> None:
        with tempfile.TemporaryDirectory() as tmp:
            workspace = Path(tmp)
            session_dir = create_audio_session(workspace, [("mixed_audio", "mixed_audio.wav", wav_bytes(b"mixed"))])
            existing = write_registered_transcript(session_dir, source_artifact_id="artifact-mixed_audio")

            response = run_generate_transcript("session-1", workspace=workspace)

            artifact_types = {artifact["artifact_type"] for artifact in load_session(session_dir)["artifacts"]}

        self.assertTrue(response["ok"])
        self.assertTrue(response["reused"])
        self.assertEqual(response["artifacts"][0]["id"], existing["id"])
        self.assertNotIn("normalized_audio", artifact_types)

    def test_existing_transcript_language_mismatch_fails_without_overwrite(self) -> None:
        with tempfile.TemporaryDirectory() as tmp:
            workspace = Path(tmp)
            session_dir = create_audio_session(workspace, [("mixed_audio", "mixed_audio.wav", wav_bytes(b"mixed"))])
            write_registered_transcript(session_dir, source_artifact_id="artifact-mixed_audio", language="en")
            original_payload = (session_dir / "artifacts" / "transcript.json").read_text(encoding="utf-8")

            response = run_generate_transcript("session-1", workspace=workspace, language="zh")

            final_payload = (session_dir / "artifacts" / "transcript.json").read_text(encoding="utf-8")
            artifact_types = {artifact["artifact_type"] for artifact in load_session(session_dir)["artifacts"]}

        self.assertFalse(response["ok"])
        self.assertEqual(response["code"], "processing_failed")
        self.assertEqual(final_payload, original_payload)
        self.assertNotIn("normalized_audio", artifact_types)

    def test_existing_transcript_checksum_drift_returns_path_conflict(self) -> None:
        with tempfile.TemporaryDirectory() as tmp:
            workspace = Path(tmp)
            session_dir = create_audio_session(workspace, [("mixed_audio", "mixed_audio.wav", wav_bytes(b"mixed"))])
            write_registered_transcript(session_dir, source_artifact_id="artifact-mixed_audio")
            (session_dir / "artifacts" / "transcript.json").write_text('{"mutated": true}\n', encoding="utf-8")

            response = run_generate_transcript("session-1", workspace=workspace)

            artifact_types = {artifact["artifact_type"] for artifact in load_session(session_dir)["artifacts"]}

        self.assertFalse(response["ok"])
        self.assertEqual(response["code"], "path_conflict")
        self.assertIn("transcript_text", artifact_types)
        self.assertNotIn("normalized_audio", artifact_types)

    def test_existing_transcript_with_unsorted_persisted_segments_is_not_reused(self) -> None:
        with tempfile.TemporaryDirectory() as tmp:
            workspace = Path(tmp)
            session_dir = create_audio_session(workspace, [("mixed_audio", "mixed_audio.wav", wav_bytes(b"mixed"))])
            write_registered_transcript(
                session_dir,
                source_artifact_id="artifact-mixed_audio",
                segments=[
                    {"segment_id": "segment-0002", "start_ms": 1000, "end_ms": 2000, "text": "second"},
                    {"segment_id": "segment-0001", "start_ms": 0, "end_ms": 900, "text": "first"},
                ],
            )

            response = run_generate_transcript("session-1", workspace=workspace)

            artifact_types = {artifact["artifact_type"] for artifact in load_session(session_dir)["artifacts"]}

        self.assertFalse(response["ok"])
        self.assertEqual(response["code"], "processing_failed")
        self.assertIn("transcript_text", artifact_types)
        self.assertNotIn("normalized_audio", artifact_types)

    def test_existing_transcript_with_explicit_runtime_is_not_reused(self) -> None:
        with tempfile.TemporaryDirectory() as tmp:
            workspace = Path(tmp)
            session_dir = create_audio_session(workspace, [("mixed_audio", "mixed_audio.wav", wav_bytes(b"mixed"))])
            write_registered_transcript(session_dir, source_artifact_id="artifact-mixed_audio")

            response = run_generate_transcript("session-1", workspace=workspace, runtime="whisper-local")

            artifact_types = {artifact["artifact_type"] for artifact in load_session(session_dir)["artifacts"]}

        self.assertFalse(response["ok"])
        self.assertEqual(response["code"], "invalid_input")
        self.assertIn("transcript_text", artifact_types)
        self.assertNotIn("normalized_audio", artifact_types)

    def test_registration_failure_rolls_back_transcript_file(self) -> None:
        with tempfile.TemporaryDirectory() as tmp:
            workspace = Path(tmp)
            session_dir = create_audio_session(workspace, [("mixed_audio", "mixed_audio.wav", wav_bytes(b"mixed"))])

            with mock.patch(
                "meeting_assistant_cli.transcript_processing.register_artifact",
                side_effect=ContractError("processing_failed", "registration failed"),
            ):
                response = run_generate_transcript("session-1", workspace=workspace)

            transcript_exists = (session_dir / "artifacts" / "transcript.json").exists()
            temp_exists = (session_dir / "artifacts" / ".transcript.json.tmp").exists()
            artifact_types = {artifact["artifact_type"] for artifact in load_session(session_dir)["artifacts"]}

        self.assertFalse(response["ok"])
        self.assertEqual(response["code"], "processing_failed")
        self.assertFalse(transcript_exists)
        self.assertFalse(temp_exists)
        self.assertNotIn("transcript_text", artifact_types)

    def test_post_registration_verification_failure_rolls_back_transcript_file(self) -> None:
        with tempfile.TemporaryDirectory() as tmp:
            workspace = Path(tmp)
            session_dir = create_audio_session(workspace, [("mixed_audio", "mixed_audio.wav", wav_bytes(b"mixed"))])
            drift_error = ContractError("path_conflict", "Registered artifact checksum changed.", artifact_id="artifact-transcript_text")

            with mock.patch(
                "meeting_assistant_cli.transcript_processing.verify_registered_artifacts",
                side_effect=[True, drift_error],
            ):
                response = run_generate_transcript("session-1", workspace=workspace)

            transcript_exists = (session_dir / "artifacts" / "transcript.json").exists()
            temp_exists = (session_dir / "artifacts" / ".transcript.json.tmp").exists()
            artifact_types = {artifact["artifact_type"] for artifact in load_session(session_dir)["artifacts"]}

        self.assertFalse(response["ok"])
        self.assertEqual(response["code"], "path_conflict")
        self.assertFalse(transcript_exists)
        self.assertFalse(temp_exists)
        self.assertNotIn("transcript_text", artifact_types)

    def test_cli_generate_transcript_emits_json_success_response(self) -> None:
        with tempfile.TemporaryDirectory() as tmp:
            workspace = Path(tmp)
            create_audio_session(workspace, [("mixed_audio", "mixed_audio.wav", wav_bytes(b"mixed"))])
            old_env = os.environ.copy()
            os.environ["MEETING_ASSISTANT_WORKSPACE"] = str(workspace)
            stdout = io.StringIO()
            try:
                with contextlib.redirect_stdout(stdout):
                    exit_code = main(["generate_transcript", "--session-id", "session-1"])
            finally:
                os.environ.clear()
                os.environ.update(old_env)

            payload = json.loads(stdout.getvalue())

        self.assertEqual(exit_code, 0)
        self.assertTrue(payload["ok"])
        self.assertEqual(payload["command"], "generate_transcript")
        self.assertEqual(payload["session_id"], "session-1")
        self.assertEqual(payload["artifact_id"], payload["artifacts"][0]["id"])
        self.assertEqual(payload["segment_count"], 1)

    def test_cli_generate_transcript_missing_session_uses_contract_exit_code(self) -> None:
        with tempfile.TemporaryDirectory() as tmp:
            workspace = Path(tmp)
            old_env = os.environ.copy()
            os.environ["MEETING_ASSISTANT_WORKSPACE"] = str(workspace)
            stdout = io.StringIO()
            try:
                with contextlib.redirect_stdout(stdout):
                    exit_code = main(["generate_transcript", "--session-id", "missing-session"])
            finally:
                os.environ.clear()
                os.environ.update(old_env)

            payload = json.loads(stdout.getvalue())

        self.assertEqual(exit_code, 3)
        self.assertFalse(payload["ok"])
        self.assertEqual(payload["code"], "not_found")

    def test_cli_generate_transcript_runtime_success_uses_zero_exit_code(self) -> None:
        with tempfile.TemporaryDirectory() as tmp:
            root = Path(tmp)
            workspace = root / "workspace"
            runtime_dir = root / "runtime"
            runtime_dir.mkdir()
            create_audio_session(workspace, [("mixed_audio", "mixed_audio.wav", wav_bytes(b"mixed"))])
            old_env = os.environ.copy()
            os.environ.clear()
            os.environ.update(
                {
                    "MEETING_ASSISTANT_WORKSPACE": str(workspace),
                    "MEETING_ASSISTANT_TRANSCRIPTION_RUNTIME": fake_whisper_cli(runtime_dir),
                    "MEETING_ASSISTANT_TRANSCRIPTION_MODEL": fake_model(runtime_dir),
                }
            )
            stdout = io.StringIO()
            try:
                with contextlib.redirect_stdout(stdout):
                    exit_code = main(
                        [
                            "generate_transcript",
                            "--session-id",
                            "session-1",
                            "--runtime",
                            "whisper_cpp",
                        ]
                    )
            finally:
                os.environ.clear()
                os.environ.update(old_env)

            payload = json.loads(stdout.getvalue())

        self.assertEqual(exit_code, 0)
        self.assertTrue(payload["ok"])
        self.assertEqual(payload["segment_count"], 2)

    def test_cli_generate_transcript_runtime_dependency_missing_uses_contract_exit_code(self) -> None:
        with tempfile.TemporaryDirectory() as tmp:
            workspace = Path(tmp)
            create_audio_session(workspace, [("mixed_audio", "mixed_audio.wav", wav_bytes(b"mixed"))])
            old_env = os.environ.copy()
            os.environ.clear()
            os.environ["MEETING_ASSISTANT_WORKSPACE"] = str(workspace)
            stdout = io.StringIO()
            try:
                with contextlib.redirect_stdout(stdout):
                    exit_code = main(
                        [
                            "generate_transcript",
                            "--session-id",
                            "session-1",
                            "--runtime",
                            "whisper_cpp",
                        ]
                    )
            finally:
                os.environ.clear()
                os.environ.update(old_env)

            payload = json.loads(stdout.getvalue())

        self.assertEqual(exit_code, 4)
        self.assertFalse(payload["ok"])
        self.assertEqual(payload["code"], "dependency_missing")


if __name__ == "__main__":
    unittest.main()
