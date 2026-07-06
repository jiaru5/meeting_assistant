from __future__ import annotations

import importlib.util
import json
import os
import subprocess
import sys
import tempfile
import unittest
from pathlib import Path


ROOT = Path(__file__).resolve().parents[2]
PROCESSING_SRC = ROOT / "platform/processing-cli/src"
sys.path.insert(0, str(PROCESSING_SRC))

from meeting_assistant_cli.workspace_contract import sha256_file  # noqa: E402


def load_report_module():
    spec = importlib.util.spec_from_file_location(
        "native_capture_artifact_report",
        ROOT / "platform/e2e/native_capture_artifact_report.py",
    )
    assert spec is not None
    module = importlib.util.module_from_spec(spec)
    assert spec.loader is not None
    spec.loader.exec_module(module)
    return module


class NativeCaptureArtifactReportTests(unittest.TestCase):
    def test_smoke_script_invokes_structured_report_generator(self) -> None:
        script = (ROOT / "platform/e2e/native-capture-artifact-smoke.sh").read_text(encoding="utf-8")

        self.assertIn("MA_NATIVE_CAPTURE_ARTIFACT_SMOKE_REPORT", script)
        self.assertIn("MA_NATIVE_CAPTURE_ARTIFACT_REPORT", script)
        self.assertIn("platform/e2e/native_capture_artifact_report.py", script)
        self.assertIn("--summary", script)
        self.assertIn("--report", script)
        self.assertIn("--failure-report", script)
        self.assertIn("preserving native exit code", script)

    def write_fixture(
        self,
        directory: str,
        *,
        include_audio_degradation_reason: bool = True,
        capture_system_audio: bool = False,
        capture_microphone_audio: bool = False,
        system_audio_available: bool = False,
        microphone_audio_available: bool = False,
        mixed_audio_available: bool = False,
    ) -> tuple[Path, Path, Path]:
        base = Path(directory)
        workspace = base / "workspace"
        session_id = "session-native-capture-report"
        session_dir = workspace / "sessions" / session_id
        artifacts_dir = session_dir / "artifacts"
        artifacts_dir.mkdir(parents=True)
        screen_video = artifacts_dir / "screen.mov"
        screen_video.write_bytes(b"synthetic screen capture bytes\n")
        checksum = sha256_file(screen_video)
        now = "2026-07-05T00:00:00Z"

        artifacts: list[dict[str, object]] = [
            {
                "id": "artifact-screen",
                "session_id": session_id,
                "artifact_type": "screen_video",
                "path": "artifacts/screen.mov",
                "format": "mov",
                "capture_status": "available",
                "checksum": checksum,
                "created_at": now,
            }
        ]
        for artifact_type, requested, available in (
            ("system_audio", capture_system_audio, system_audio_available),
            ("microphone_audio", capture_microphone_audio, microphone_audio_available),
        ):
            if available:
                audio_path = artifacts_dir / f"{artifact_type}.m4a"
                audio_path.write_bytes(f"synthetic {artifact_type} bytes\n".encode("utf-8"))
                artifact = {
                    "id": f"artifact-{artifact_type}",
                    "session_id": session_id,
                    "artifact_type": artifact_type,
                    "path": f"artifacts/{artifact_type}.m4a",
                    "format": "m4a",
                    "capture_status": "available",
                    "checksum": sha256_file(audio_path),
                    "created_at": now,
                }
            else:
                artifact = {
                    "id": f"artifact-{artifact_type}",
                    "session_id": session_id,
                    "artifact_type": artifact_type,
                    "path": f"artifacts/{artifact_type}.wav",
                    "format": "wav",
                    "capture_status": "degraded" if requested else "missing",
                    "created_at": now,
                }
                if include_audio_degradation_reason:
                    artifact["degradation_reason"] = f"{artifact_type} unavailable in screen-only capture smoke"
            artifacts.append(artifact)
        if mixed_audio_available:
            mixed_audio = artifacts_dir / "mixed_audio.m4a"
            mixed_audio.write_bytes(b"synthetic mixed audio bytes\n")
            artifacts.append(
                {
                    "id": "artifact-mixed_audio",
                    "session_id": session_id,
                    "artifact_type": "mixed_audio",
                    "path": "artifacts/mixed_audio.m4a",
                    "format": "m4a",
                    "capture_status": "available",
                    "checksum": sha256_file(mixed_audio),
                    "created_at": now,
                }
            )
        else:
            mixed_requested = capture_system_audio or capture_microphone_audio
            mixed_artifact: dict[str, object] = {
                "id": "artifact-mixed_audio",
                "session_id": session_id,
                "artifact_type": "mixed_audio",
                "path": "artifacts/mixed_audio.wav",
                "format": "wav",
                "capture_status": "degraded" if mixed_requested else "missing",
                "created_at": now,
            }
            if include_audio_degradation_reason:
                mixed_artifact["degradation_reason"] = "mixed_audio unavailable in native capture smoke"
            artifacts.append(mixed_artifact)

        session = {
            "id": session_id,
            "source_type": "native_recording",
            "status": "recorded",
            "started_at": now,
            "ended_at": now,
            "workspace_dir": str(session_dir),
            "created_at": now,
            "updated_at": now,
            "artifacts": artifacts,
        }
        (session_dir / "session.json").write_text(
            json.dumps(session, ensure_ascii=False, indent=2, sort_keys=True) + "\n",
            encoding="utf-8",
        )

        summary = {
            "ok": True,
            "script": "native-capture-smoke",
            "adapter": "AppleScreenCaptureKitNativeCaptureAdapter",
            "workspace": str(workspace),
            "session_id": session_id,
            "capture_system_audio": capture_system_audio,
            "capture_microphone_audio": capture_microphone_audio,
            "screen_video_path": str(screen_video),
            "screen_video_bytes": screen_video.stat().st_size,
            "screen_video_checksum": checksum,
        }
        summary_path = base / "summary.json"
        report_path = base / "report.json"
        summary_path.write_text(json.dumps(summary, ensure_ascii=False), encoding="utf-8")
        return summary_path, report_path, session_dir

    def write_failure_summary(self, directory: str) -> tuple[Path, Path]:
        base = Path(directory)
        summary = {
            "ok": False,
            "script": "native-capture-smoke",
            "adapter": "AppleScreenCaptureKitNativeCaptureAdapter",
            "workspace": str(base / "workspace"),
            "session_id": "session-native-capture-report",
            "duration_seconds": 2,
            "capture_system_audio": False,
            "capture_microphone_audio": False,
            "failure_stage": "start",
            "message": "Screen Recording permission is denied.",
            "start_response": {
                "ok": False,
                "request_id": "native-capture-smoke-start_native_recording",
                "command": "start_native_recording",
                "session_id": None,
                "status": None,
                "capture_target": None,
                "code": "permission_denied",
                "message": "Screen Recording permission is denied.",
                "details": ["Screen Recording permission is denied."],
                "artifacts": [],
            },
            "validation_errors": [],
            "notes": ["This script is an opt-in local smoke and is not part of the default native-app gate."],
        }
        summary_path = base / "failure-summary.json"
        report_path = base / "failure-report.json"
        summary_path.write_text(json.dumps(summary, ensure_ascii=False), encoding="utf-8")
        return summary_path, report_path

    def test_build_report_writes_partial_evidence_and_fail_closed_processing_result(self) -> None:
        module = load_report_module()
        with tempfile.TemporaryDirectory() as directory:
            summary_path, report_path, session_dir = self.write_fixture(directory)

            report = module.build_report(summary_path, report_path=report_path, root=ROOT, python=sys.executable)

            self.assertTrue(report_path.is_file())
            written = json.loads(report_path.read_text(encoding="utf-8"))
            self.assertEqual(report, written)
            self.assertEqual(report["release_gate"], "partial-evidence-only")
            self.assertFalse(report["release_scope_native_capture"])
            self.assertEqual(report["vs_ma"], ["VS-MA-14", "VS-MA-15"])
            self.assertEqual(report["pv"], ["PV-MA-002", "PV-MA-003"])
            self.assertTrue(report["not_release_readiness"])
            self.assertEqual(report["artifacts"]["screen_video"]["capture_status"], "available")
            self.assertTrue(report["artifacts"]["screen_video"]["checksum_verified"])
            self.assertEqual(report["artifacts"]["system_audio"]["capture_status"], "missing")
            self.assertTrue(report["artifacts"]["system_audio"]["has_degradation_reason"])
            self.assertEqual(report["processing_contract"]["exit_code"], 3)
            self.assertEqual(report["processing_contract"]["code"], "artifact_missing")
            self.assertFalse(report["processing_contract"]["derived_artifact_pollution"])
            session = json.loads((session_dir / "session.json").read_text(encoding="utf-8"))
            artifact_types = {artifact["artifact_type"] for artifact in session["artifacts"]}
            self.assertFalse({"normalized_audio", "transcript_text", "speaker_labels"} & artifact_types)

    def test_build_report_accepts_available_mixed_audio_without_no_audio_processing_path(self) -> None:
        module = load_report_module()
        with tempfile.TemporaryDirectory() as directory:
            summary_path, report_path, _ = self.write_fixture(
                directory,
                capture_system_audio=True,
                system_audio_available=True,
                mixed_audio_available=True,
            )

            report = module.build_report(summary_path, report_path=report_path, root=ROOT, python=sys.executable)

            self.assertEqual(report["artifacts"]["system_audio"]["capture_status"], "available")
            self.assertTrue(report["artifacts"]["system_audio"]["checksum_verified"])
            self.assertEqual(report["artifacts"]["mixed_audio"]["capture_status"], "available")
            self.assertTrue(report["artifacts"]["mixed_audio"]["checksum_verified"])
            self.assertTrue(report["processing_contract"]["skipped"])
            self.assertIn("an audio artifact was available", report["processing_contract"]["reason"])
            self.assertFalse(report["processing_contract"]["derived_artifact_pollution"])

    def test_build_report_writes_release_scope_gate_without_release_readiness(self) -> None:
        module = load_report_module()
        with tempfile.TemporaryDirectory() as directory:
            summary_path, report_path, _ = self.write_fixture(directory)

            report = module.build_report(
                summary_path,
                report_path=report_path,
                root=ROOT,
                python=sys.executable,
                release_scope=True,
            )

            self.assertTrue(report_path.is_file())
            self.assertEqual(report["release_gate"], "release-scope-native-capture")
            self.assertTrue(report["release_scope_native_capture"])
            self.assertTrue(report["not_release_readiness"])
            self.assertNotIn("not a release-scope ScreenCaptureKit gate", report["release_blockers"])
            self.assertIn(
                "does not prove independent system_audio and microphone_audio capture artifacts",
                report["release_blockers"],
            )
            self.assertIn(
                "does not prove real native-to-processing successful transcript chain",
                report["release_blockers"],
            )
            self.assertEqual(report["processing_contract"]["code"], "artifact_missing")

    def test_build_report_marks_independent_audio_proven_when_both_tracks_are_available(self) -> None:
        module = load_report_module()
        with tempfile.TemporaryDirectory() as directory:
            summary_path, report_path, _ = self.write_fixture(
                directory,
                capture_system_audio=True,
                capture_microphone_audio=True,
                system_audio_available=True,
                microphone_audio_available=True,
            )

            report = module.build_report(
                summary_path,
                report_path=report_path,
                root=ROOT,
                python=sys.executable,
                release_scope=True,
            )

            self.assertTrue(report["independent_audio_artifacts_proven"])
            self.assertEqual(report["artifacts"]["system_audio"]["capture_status"], "available")
            self.assertEqual(report["artifacts"]["microphone_audio"]["capture_status"], "available")
            self.assertNotIn(
                "does not prove independent system_audio and microphone_audio capture artifacts",
                report["release_blockers"],
            )
            self.assertTrue(report["processing_contract"]["skipped"])

    def test_build_report_rejects_missing_audio_degradation_reason(self) -> None:
        module = load_report_module()
        with tempfile.TemporaryDirectory() as directory:
            summary_path, report_path, _ = self.write_fixture(directory, include_audio_degradation_reason=False)

            with self.assertRaises(module.NativeCaptureArtifactReportError):
                module.build_report(summary_path, report_path=report_path, root=ROOT, python=sys.executable)

            self.assertFalse(report_path.exists())

    def test_build_failure_report_writes_tcc_diagnostics_without_promoting_release(self) -> None:
        module = load_report_module()
        with tempfile.TemporaryDirectory() as directory:
            summary_path, report_path = self.write_failure_summary(directory)

            report = module.build_failure_report(
                summary_path,
                report_path=report_path,
                native_exit_code=1,
                attempts=2,
                display_wake_seconds=120,
                display_wake_settle_seconds=3,
            )

            self.assertTrue(report_path.is_file())
            self.assertEqual(report["release_gate"], "partial-evidence-only")
            self.assertFalse(report["release_scope_native_capture"])
            self.assertTrue(report["not_release_readiness"])
            self.assertEqual(report["failure_stage"], "start")
            self.assertEqual(report["native_exit_code"], 1)
            self.assertEqual(report["native_attempts"], 2)
            self.assertTrue(report["diagnostics"]["permission_or_tcc_likely"])
            self.assertFalse(report["diagnostics"]["timeout_likely"])
            self.assertEqual(report["start_response"]["code"], "permission_denied")
            self.assertIn("Screen Recording", " ".join(report["remediation_hints"]))
            self.assertIn("native capture smoke did not pass", report["findings"][0])

    def test_build_failure_report_can_mark_release_scope_gate_unavailable(self) -> None:
        module = load_report_module()
        with tempfile.TemporaryDirectory() as directory:
            summary_path, report_path = self.write_failure_summary(directory)

            report = module.build_failure_report(
                summary_path,
                report_path=report_path,
                native_exit_code=1,
                release_scope=True,
            )

            self.assertEqual(report["release_gate"], "release-scope-native-capture")
            self.assertTrue(report["release_scope_native_capture"])
            self.assertTrue(report["not_release_readiness"])
            self.assertIn("release-scope evidence remains unavailable", report["findings"][0])

    def test_cli_writes_report_and_emits_non_contract_markers(self) -> None:
        with tempfile.TemporaryDirectory() as directory:
            summary_path, report_path, _ = self.write_fixture(directory)
            env = os.environ.copy()
            pythonpath = [str(PROCESSING_SRC)]
            if env.get("PYTHONPATH"):
                pythonpath.append(env["PYTHONPATH"])
            env["PYTHONPATH"] = os.pathsep.join(pythonpath)

            result = subprocess.run(
                [
                    sys.executable,
                    str(ROOT / "platform/e2e/native_capture_artifact_report.py"),
                    "--summary",
                    str(summary_path),
                    "--report",
                    str(report_path),
                ],
                cwd=ROOT,
                env=env,
                capture_output=True,
                text=True,
                check=False,
            )

            self.assertEqual(result.returncode, 0, result.stderr + result.stdout)
            self.assertIn("real native capture artifact e2e marker", result.stdout)
            self.assertIn("real native capture artifact report marker", result.stdout)
            self.assertIn("partial-evidence-only", result.stdout)
            self.assertIn(str(report_path), result.stderr)
            self.assertTrue(report_path.is_file())

    def test_cli_writes_release_scope_report_and_marker(self) -> None:
        with tempfile.TemporaryDirectory() as directory:
            summary_path, report_path, _ = self.write_fixture(directory)
            env = os.environ.copy()
            pythonpath = [str(PROCESSING_SRC)]
            if env.get("PYTHONPATH"):
                pythonpath.append(env["PYTHONPATH"])
            env["PYTHONPATH"] = os.pathsep.join(pythonpath)

            result = subprocess.run(
                [
                    sys.executable,
                    str(ROOT / "platform/e2e/native_capture_artifact_report.py"),
                    "--summary",
                    str(summary_path),
                    "--report",
                    str(report_path),
                    "--release-scope",
                ],
                cwd=ROOT,
                env=env,
                capture_output=True,
                text=True,
                check=False,
            )

            self.assertEqual(result.returncode, 0, result.stderr + result.stdout)
            self.assertIn("release-scope-native-capture", result.stdout)
            self.assertIn("release-scope native capture artifact gate passed", result.stdout)
            written = json.loads(report_path.read_text(encoding="utf-8"))
            self.assertTrue(written["release_scope_native_capture"])

    def test_cli_writes_failure_report_and_emits_failure_marker(self) -> None:
        with tempfile.TemporaryDirectory() as directory:
            summary_path, report_path = self.write_failure_summary(directory)
            env = os.environ.copy()
            pythonpath = [str(PROCESSING_SRC)]
            if env.get("PYTHONPATH"):
                pythonpath.append(env["PYTHONPATH"])
            env["PYTHONPATH"] = os.pathsep.join(pythonpath)

            result = subprocess.run(
                [
                    sys.executable,
                    str(ROOT / "platform/e2e/native_capture_artifact_report.py"),
                    "--failure-report",
                    "--summary",
                    str(summary_path),
                    "--report",
                    str(report_path),
                    "--native-exit-code",
                    "1",
                    "--attempts",
                    "2",
                    "--display-wake-seconds",
                    "120",
                    "--display-wake-settle-seconds",
                    "3",
                ],
                cwd=ROOT,
                env=env,
                capture_output=True,
                text=True,
                check=False,
            )

            self.assertEqual(result.returncode, 0, result.stderr + result.stdout)
            self.assertIn("failure report marker", result.stdout)
            self.assertIn("failure_stage=start", result.stdout)
            self.assertIn(str(report_path), result.stderr)
            self.assertTrue(report_path.is_file())


if __name__ == "__main__":
    unittest.main()
