from __future__ import annotations

import contextlib
import io
import json
import os
import tempfile
import unittest
from pathlib import Path

from meeting_assistant_cli.cli import main
from meeting_assistant_cli.workspace_contract import create_session, register_artifact, session_directory


def fake_executable(path: Path) -> None:
    path.write_text("#!/usr/bin/env sh\nexit 0\n", encoding="utf-8")
    path.chmod(0o755)


def create_transcript_session(workspace: Path) -> None:
    create_session(workspace, source_type="imported_media", session_id="session-1", status="transcribed")
    session_dir = session_directory(workspace, "session-1")
    transcript = {
        "id": "transcript-1",
        "session_id": "session-1",
        "source_artifact_id": "artifact-mixed_audio",
        "status": "succeeded",
        "segments": [{"segment_id": "segment-0001", "start_ms": 0, "end_ms": 1000, "text": "line"}],
        "created_at": "2026-06-28T00:00:00Z",
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


class CliContractTests(unittest.TestCase):
    def assert_invalid_input_response(
        self,
        argv: list[str],
        *,
        command: str,
        error_contains: str | None = None,
        env: dict[str, str] | None = None,
    ) -> dict:
        stdout = io.StringIO()
        stderr = io.StringIO()
        old_env = os.environ.copy()
        try:
            if env is not None:
                os.environ.update(env)
            with contextlib.redirect_stdout(stdout), contextlib.redirect_stderr(stderr):
                exit_code = main(argv)
        finally:
            os.environ.clear()
            os.environ.update(old_env)

        output = stdout.getvalue().strip()
        self.assertEqual(exit_code, 2)
        self.assertEqual(len(output.splitlines()), 1)
        self.assertEqual(stderr.getvalue(), "")
        self.assertTrue(output.startswith("{"))
        self.assertTrue(output.endswith("}"))

        payload = json.loads(output)
        self.assertIs(payload["ok"], False)
        self.assertTrue(str(payload["request_id"]).startswith("local-"))
        self.assertEqual(payload["command"], command)
        self.assertEqual(payload["code"], "invalid_input")
        self.assertIsInstance(payload["message"], str)
        self.assertTrue(payload["message"])
        self.assertEqual(payload["warnings"], [])
        self.assertIsInstance(payload["details"], dict)
        if error_contains is not None:
            self.assertIn("error", payload["details"])
            self.assertIn(error_contains, payload["details"]["error"])
        return payload

    def test_check_dependencies_rejects_unknown_argument_and_illegal_format_enum(self) -> None:
        cases = [
            (["check_dependencies", "--unknown-field", "value"], "--unknown-field"),
            (["check_dependencies", "--format", "yaml"], "invalid choice"),
        ]

        for argv, error_contains in cases:
            with self.subTest(argv=argv):
                self.assert_invalid_input_response(
                    argv,
                    command="check_dependencies",
                    error_contains=error_contains,
                )

    def test_check_dependencies_success_emits_contract_json(self) -> None:
        with tempfile.TemporaryDirectory() as tmp:
            root = Path(tmp)
            bin_dir = root / "bin"
            bin_dir.mkdir()
            fake_executable(bin_dir / "swift")
            fake_executable(bin_dir / "ffmpeg")
            runtime = bin_dir / "whisper-cli"
            fake_executable(runtime)
            model = root / "ggml-large-v3-turbo-q5_0.bin"
            model.write_text("fake model", encoding="utf-8")
            workspace = root / "workspace"
            env = {
                "PATH": str(bin_dir),
                "MEETING_ASSISTANT_OS_NAME": "Darwin",
                "MEETING_ASSISTANT_MACOS_VERSION": "26.5.1",
                "MEETING_ASSISTANT_CPU_ARCH": "arm64",
                "MEETING_ASSISTANT_MEMORY_BYTES": str(16 * 1024 * 1024 * 1024),
                "MEETING_ASSISTANT_CHIP_NAME": "Apple M-series test fixture",
                "MEETING_ASSISTANT_TRANSCRIPTION_RUNTIME": str(runtime),
                "MEETING_ASSISTANT_TRANSCRIPTION_MODEL": str(model),
            }
            stdout = io.StringIO()
            stderr = io.StringIO()
            old_env = os.environ.copy()
            try:
                os.environ.clear()
                os.environ.update(env)
                with contextlib.redirect_stdout(stdout), contextlib.redirect_stderr(stderr):
                    exit_code = main(["check_dependencies", "--workspace-dir", str(workspace)])
            finally:
                os.environ.clear()
                os.environ.update(old_env)

        payload = json.loads(stdout.getvalue())
        check_ids = {item["id"] for item in payload["checks"]}

        self.assertEqual(exit_code, 0)
        self.assertEqual(stderr.getvalue(), "")
        self.assertTrue(payload["ok"])
        self.assertTrue(str(payload["request_id"]).startswith("local-"))
        self.assertEqual(payload["command"], "check_dependencies")
        self.assertIn("platform.os", check_ids)
        self.assertIn("dependency_downloads.automatic", check_ids)
        self.assertNotIn("code", payload)
        self.assertTrue(any("Speaker labeling runtime is missing" in warning for warning in payload["warnings"]))
        self.assertTrue(any("Screen recording permission status" in warning for warning in payload["warnings"]))
        self.assertTrue(any("Microphone permission status" in warning for warning in payload["warnings"]))

    def test_only_check_dependencies_accepts_format_parameter(self) -> None:
        cases = [
            ("import_media", ["import_media", "--path", "input.wav", "--format", "json"]),
            ("generate_transcript", ["generate_transcript", "--session-id", "session-1", "--format", "json"]),
            (
                "generate_speaker_labels",
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
                ],
            ),
            (
                "export_transcript",
                ["export_transcript", "--session-id", "session-1", "--export-type", "plain_text", "--format", "json"],
            ),
            ("delete_session", ["delete_session", "--session-id", "session-1", "--confirm", "true", "--format", "json"]),
        ]

        for command, argv in cases:
            with self.subTest(command=command):
                self.assert_invalid_input_response(
                    argv,
                    command=command,
                    error_contains="--format",
                )

    def test_export_transcript_rejects_missing_target_parent_before_writing_file(self) -> None:
        with tempfile.TemporaryDirectory() as tmp:
            root = Path(tmp)
            workspace = root / "workspace"
            create_transcript_session(workspace)
            missing_parent = root / "missing" / "transcript.md"

            payload = self.assert_invalid_input_response(
                [
                    "export_transcript",
                    "--session-id",
                    "session-1",
                    "--export-type",
                    "markdown",
                    "--target-path",
                    str(missing_parent),
                ],
                command="export_transcript",
                env={"MEETING_ASSISTANT_WORKSPACE": str(workspace)},
            )

            self.assertEqual(payload["message"], "Export target parent directory does not exist.")
            self.assertEqual(payload["details"]["path"], str(missing_parent))
            self.assertFalse(missing_parent.exists())

    def test_import_media_rejects_missing_path_unknown_argument_and_unsupported_format_parameter(self) -> None:
        cases = [
            (["import_media"], "--path"),
            (["import_media", "--path", "input.wav", "--unknown-field", "value"], "--unknown-field"),
            (["import_media", "--path", "input.wav", "--format", "json"], "--format"),
        ]

        for argv, error_contains in cases:
            with self.subTest(argv=argv):
                self.assert_invalid_input_response(
                    argv,
                    command="import_media",
                    error_contains=error_contains,
                )

    def test_generate_transcript_rejects_missing_session_unknown_argument_and_unsupported_runtime(self) -> None:
        cases = [
            (["generate_transcript"], "--session-id"),
            (["generate_transcript", "--session-id", "session-1", "--unknown-field", "value"], "--unknown-field"),
            (["generate_transcript", "--session-id", "session-1", "--format", "json"], "--format"),
        ]

        for argv, error_contains in cases:
            with self.subTest(argv=argv):
                self.assert_invalid_input_response(
                    argv,
                    command="generate_transcript",
                    error_contains=error_contains,
                )

        payload = self.assert_invalid_input_response(
            ["generate_transcript", "--session-id", "session-does-not-exist", "--runtime", "faster_whisper"],
            command="generate_transcript",
        )
        self.assertEqual(payload["message"], "Unsupported transcription runtime.")
        self.assertEqual(payload["details"]["runtime"], "faster_whisper")
        self.assertEqual(payload["details"]["supported_runtime"], "whisper_cpp")

    def test_generate_speaker_labels_rejects_missing_transcript_invalid_fallback_enum_and_unknown_argument(self) -> None:
        cases = [
            (
                [
                    "generate_speaker_labels",
                    "--session-id",
                    "session-1",
                    "--allow-transcript-only-fallback",
                    "true",
                ],
                "--transcript-id",
            ),
            (
                [
                    "generate_speaker_labels",
                    "--session-id",
                    "session-1",
                    "--transcript-id",
                    "transcript-1",
                    "--allow-transcript-only-fallback",
                    "maybe",
                ],
                "invalid choice",
            ),
            (
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
                ],
                "--unknown-field",
            ),
        ]

        for argv, error_contains in cases:
            with self.subTest(argv=argv):
                self.assert_invalid_input_response(
                    argv,
                    command="generate_speaker_labels",
                    error_contains=error_contains,
                )

    def test_export_transcript_rejects_missing_export_type_invalid_export_enum_and_unknown_argument(self) -> None:
        cases = [
            (["export_transcript", "--export-type", "plain_text"], "--session-id"),
            (["export_transcript", "--session-id", "session-1"], "--export-type"),
            (["export_transcript", "--session-id", "session-1", "--export-type", "html"], "invalid choice"),
            (
                [
                    "export_transcript",
                    "--session-id",
                    "session-1",
                    "--export-type",
                    "plain_text",
                    "--unknown-field",
                    "value",
                ],
                "--unknown-field",
            ),
        ]

        for argv, error_contains in cases:
            with self.subTest(argv=argv):
                self.assert_invalid_input_response(
                    argv,
                    command="export_transcript",
                    error_contains=error_contains,
                )

    def test_delete_session_rejects_missing_confirm_invalid_confirm_enum_and_unknown_argument(self) -> None:
        cases = [
            (["delete_session", "--confirm", "true"], "--session-id"),
            (["delete_session", "--session-id", "session-1"], "--confirm"),
            (["delete_session", "--session-id", "session-1", "--confirm", "yes"], "invalid choice"),
            (
                [
                    "delete_session",
                    "--session-id",
                    "session-1",
                    "--confirm",
                    "true",
                    "--unknown-field",
                    "value",
                ],
                "--unknown-field",
            ),
        ]

        for argv, error_contains in cases:
            with self.subTest(argv=argv):
                self.assert_invalid_input_response(
                    argv,
                    command="delete_session",
                    error_contains=error_contains,
                )

    def test_delete_session_rejects_path_traversal_session_id_without_touching_external_path(self) -> None:
        with tempfile.TemporaryDirectory() as tmp:
            root = Path(tmp)
            workspace = root / "workspace"
            external = root / "outside"
            external.mkdir()
            sentinel = external / "keep.txt"
            sentinel.write_text("keep", encoding="utf-8")

            payload = self.assert_invalid_input_response(
                [
                    "delete_session",
                    "--session-id",
                    "../outside",
                    "--workspace-dir",
                    str(workspace),
                    "--confirm",
                    "true",
                ],
                command="delete_session",
            )

            self.assertEqual(payload["message"], "Session id contains unsupported path characters.")
            self.assertEqual(payload["details"]["session_id"], "../outside")
            self.assertEqual(sentinel.read_text(encoding="utf-8"), "keep")


if __name__ == "__main__":
    unittest.main()
