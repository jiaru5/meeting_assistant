from __future__ import annotations

import importlib.util
import json
import subprocess
import sys
import tempfile
import unittest
from pathlib import Path


ROOT = Path(__file__).resolve().parents[2]


def load_report_module():
    spec = importlib.util.spec_from_file_location(
        "release_local_direct_target_smoke_report",
        ROOT / "platform/e2e/release_local_direct_target_smoke_report.py",
    )
    assert spec is not None
    module = importlib.util.module_from_spec(spec)
    assert spec.loader is not None
    spec.loader.exec_module(module)
    return module


class ReleaseLocalDirectTargetSmokeReportTests(unittest.TestCase):
    def write_same_chain_report(
        self,
        directory: str,
        *,
        passed: bool = True,
        stage_exit_codes: dict[str, int] | None = None,
        stage_passed: dict[str, bool] | None = None,
        stage_reports: dict[str, str] | None = None,
        blocker_type: str | None = None,
        blocker_detail: str | None = None,
        launch_modes: list[str] | None = None,
        expected_terms_found: list[str] | None = None,
    ) -> Path:
        report_path = Path(directory) / "local-direct-same-chain-smoke-report.json"
        stage_exit_codes = stage_exit_codes or {"recording": 0, "processing": 0, "actions": 0}
        stage_passed = stage_passed or {"recording": True, "processing": True, "actions": True}
        report_path.write_text(
            json.dumps(
                {
                    "report_schema": 1,
                    "release_gate": "local-direct-same-chain-smoke",
                    "passed": passed,
                    "blocker_type": blocker_type or "",
                    "blocker_detail": blocker_detail or "",
                    "stage_exit_codes": stage_exit_codes,
                    "stage_passed": stage_passed,
                    "stage_reports": stage_reports or {},
                    "same_app_identity": True,
                    "requires_clean_app_processes": True,
                    "launch_modes": launch_modes or ["open"],
                    "app_identity": {
                        "path": "/Users/runner/Applications/MeetingAssistantNativeLocal.app",
                        "CFBundleIdentifier": "local.meeting-assistant.native.localdirect",
                        "CFBundleName": "MeetingAssistantNativeLocal",
                        "codesign": {"CDHash": "abcdef123456"},
                    },
                    "recording_markers": [
                        "Recording readiness is ready.",
                        "Recording in progress.",
                        "Recording saved.",
                        "screen_video: available",
                        "mixed_audio: available",
                    ],
                    "processing_artifacts": {
                        "normalized_audio": {"status": "available", "path": "normalized_audio.wav"},
                        "transcript_text": {
                            "status": "available",
                            "path": "transcript.json",
                            "expected_terms_found": expected_terms_found
                            or ["HTTP", "LLM", "clean architecture"],
                        },
                        "speaker_labels": {"status": "degraded", "path": "speaker_labels.json"},
                    },
                    "actions_markers": [
                        "Transcript actions are ready or action controls enabled.",
                        "Copy complete.",
                        "Export complete.",
                        "Delete complete.",
                    ],
                    "export_exists": True,
                    "export_path": "/tmp/session.md",
                    "delete_event_path": "events/meeting_session.deleted.v1.jsonl",
                    "session_root_exists_after_delete": False,
                    "starts_recording": True,
                    "starts_processing": True,
                    "uses_system_pasteboard": True,
                    "uses_save_panel": True,
                    "opens_system_settings": False,
                    "modifies_tcc_or_system_settings": False,
                    "requires_developer_id_or_notarization": False,
                    "not_release_readiness": True,
                }
            ),
            encoding="utf-8",
        )
        return report_path

    def test_build_report_writes_digest_bound_target_smoke(self) -> None:
        module = load_report_module()
        with tempfile.TemporaryDirectory() as directory:
            same_chain_report = self.write_same_chain_report(directory)
            report_path = Path(directory) / "target.json"

            report = module.build_report(
                ROOT,
                same_chain_report_path=same_chain_report,
                report_path=report_path,
                target_id="macos arm64 local",
                target_os="macos",
                architecture="arm64",
            )

            self.assertTrue(report["passed"], report["findings"])
            self.assertEqual(report["release_gate"], "release-local-direct-target-smoke")
            self.assertEqual(report["target_scope"], "single-target-machine")
            self.assertEqual(report["target_id"], "macos-arm64-local")
            self.assertEqual(report["smoke"]["launch_modes"], ["open"])
            self.assertTrue(report["smoke"]["same_app_identity"])
            self.assertEqual(report["local_direct_app"]["CFBundleIdentifier"], "local.meeting-assistant.native.localdirect")
            self.assertTrue(report["same_chain_report"]["digest"].startswith("sha256:"))
            self.assertTrue(report["not_release_readiness"])
            self.assertEqual(json.loads(report_path.read_text(encoding="utf-8")), report)

    def test_build_report_fails_closed_when_expected_terms_are_missing(self) -> None:
        module = load_report_module()
        with tempfile.TemporaryDirectory() as directory:
            same_chain_report = self.write_same_chain_report(
                directory,
                expected_terms_found=["HTTP", "LLM"],
            )

            report = module.build_report(ROOT, same_chain_report_path=same_chain_report)

            self.assertFalse(report["passed"])
            self.assertTrue(any("missing expected terms" in item for item in report["findings"]))

    def test_build_report_fails_closed_when_launch_mode_is_not_open(self) -> None:
        module = load_report_module()
        with tempfile.TemporaryDirectory() as directory:
            same_chain_report = self.write_same_chain_report(directory, launch_modes=["direct"])

            report = module.build_report(ROOT, same_chain_report_path=same_chain_report)

            self.assertFalse(report["passed"])
            self.assertTrue(any("LaunchServices open only" in item for item in report["findings"]))

    def test_build_report_propagates_stage_blocker_context(self) -> None:
        module = load_report_module()
        with tempfile.TemporaryDirectory() as directory:
            recording_report = Path(directory) / "recording.json"
            recording_report.write_text(
                json.dumps(
                    {
                        "passed": False,
                        "blocker_type": "permission_denied",
                        "blocker_detail_summary": (
                            "Screen Recording permission is denied.; authorize exact app "
                            "/Users/runner/Applications/MeetingAssistantNativeLocal.app "
                            "(designated_requirement=identifier \"local.meeting-assistant.native.localdirect\" "
                            "and certificate root = H\"abc\")"
                        ),
                    }
                ),
                encoding="utf-8",
            )
            same_chain_report = self.write_same_chain_report(
                directory,
                passed=False,
                blocker_type="same_chain_stage_failed",
                blocker_detail="One or more local-direct same-chain stages failed.",
                stage_exit_codes={"recording": 1, "processing": 1, "actions": 1},
                stage_passed={"recording": False, "processing": False, "actions": False},
                stage_reports={"recording": str(recording_report)},
            )

            report = module.build_report(ROOT, same_chain_report_path=same_chain_report)

            self.assertFalse(report["passed"])
            self.assertTrue(any("recording blocker: permission_denied" in item for item in report["failure_context"]))
            self.assertTrue(any("Screen Recording permission is denied" in item for item in report["findings"]))
            self.assertTrue(any("designated_requirement" in item for item in report["findings"]))

    def test_cli_writes_report_and_marker(self) -> None:
        with tempfile.TemporaryDirectory() as directory:
            same_chain_report = self.write_same_chain_report(directory)
            report_path = Path(directory) / "target.json"
            result = subprocess.run(
                [
                    sys.executable,
                    str(ROOT / "platform/e2e/release_local_direct_target_smoke_report.py"),
                    "--root",
                    str(ROOT),
                    "--same-chain-report",
                    str(same_chain_report),
                    "--report",
                    str(report_path),
                    "--target-id",
                    "macos arm64 local",
                    "--target-os",
                    "macos",
                    "--architecture",
                    "arm64",
                ],
                cwd=ROOT,
                capture_output=True,
                text=True,
                check=False,
            )

            self.assertEqual(result.returncode, 0, result.stderr + result.stdout)
            self.assertIn("release-local-direct-target-smoke", result.stdout)
            self.assertIn(str(report_path), result.stderr)
            report = json.loads(report_path.read_text(encoding="utf-8"))
            self.assertEqual(report["target_id"], "macos-arm64-local")


if __name__ == "__main__":
    unittest.main()
