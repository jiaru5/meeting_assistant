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
        "native_app_bundle_ui_automation_report",
        ROOT / "platform/e2e/native_app_bundle_ui_automation_report.py",
    )
    assert spec is not None
    module = importlib.util.module_from_spec(spec)
    assert spec.loader is not None
    spec.loader.exec_module(module)
    return module


class NativeAppBundleUIAutomationReportTests(unittest.TestCase):
    def test_build_report_classifies_local_authentication_blocker(self) -> None:
        module = load_report_module()
        with tempfile.TemporaryDirectory() as directory:
            log_path = Path(directory) / "xcodebuild.log"
            report_path = Path(directory) / "report.json"
            log_path.write_text(
                "Failed to initialize for UI testing: Error Domain=com.apple.LocalAuthentication "
                'Code=-4 "System authentication is running."\n',
                encoding="utf-8",
            )

            report = module.build_report(
                smoke_name="real runtime",
                log_path=log_path,
                report_path=report_path,
                exit_code=65,
                destination="platform=macOS,arch=arm64",
            )

            self.assertFalse(report["passed"])
            self.assertTrue(report["blocked"])
            self.assertEqual(report["blocker_type"], "local_authentication_in_progress")
            self.assertTrue(report["signals"]["local_authentication_in_progress"])
            self.assertFalse(report["proves_ui_or_provider_behavior"])
            self.assertTrue(report["not_release_readiness"])
            self.assertEqual(json.loads(report_path.read_text(encoding="utf-8")), report)

    def test_build_report_classifies_automation_mode_timeout(self) -> None:
        module = load_report_module()
        with tempfile.TemporaryDirectory() as directory:
            log_path = Path(directory) / "xcodebuild.log"
            report_path = Path(directory) / "report.json"
            log_path.write_text("Timed out while enabling automation mode\n", encoding="utf-8")

            report = module.build_report(
                smoke_name="real runtime",
                log_path=log_path,
                report_path=report_path,
                exit_code=65,
                destination="platform=macOS",
            )

            self.assertEqual(report["blocker_type"], "automation_mode_unavailable")
            self.assertTrue(report["signals"]["automation_mode_unavailable"])
            self.assertTrue(report["blocked_before_test_body"])

    def test_build_report_classifies_real_runtime_processing_timeout(self) -> None:
        module = load_report_module()
        with tempfile.TemporaryDirectory() as directory:
            log_path = Path(directory) / "xcodebuild.log"
            report_path = Path(directory) / "report.json"
            log_path.write_text(
                'Test Case "-[MeetingAssistantNativeAppUITests.AppBundleLocatorSmokeTests '
                'testRealWhisperRuntimeTranscriptReviewFromLaunchedAppBundleWhenExplicitlyEnabled]" started.\n'
                'Click "ma.processing.startButton" Button[0.50, 0.50]\n'
                "Checking `Expect predicate `label CONTAINS "
                '"Processing completed with transcript-only speaker labels." '
                'OR value CONTAINS "Processing completed with transcript-only speaker labels."`\n'
                "failed - Expected real runtime processing to complete from the launched app bundle. "
                "Diagnostics: /tmp/meeting-assistant-real-runtime-diagnostics/real-runtime-timeout-session-app-ui-runtime.json.\n",
                encoding="utf-8",
            )

            report = module.build_report(
                smoke_name="real runtime",
                log_path=log_path,
                report_path=report_path,
                exit_code=65,
                destination="platform=macOS,arch=arm64",
            )

            self.assertFalse(report["passed"])
            self.assertTrue(report["blocked"])
            self.assertEqual(report["blocker_type"], "real_runtime_processing_timeout")
            self.assertTrue(report["signals"]["real_runtime_processing_timeout"])
            self.assertFalse(report["blocked_before_test_body"])
            self.assertTrue(report["test_body_started"])
            self.assertTrue(report["processing_start_clicked"])
            self.assertFalse(report["processing_completed"])
            self.assertEqual(
                report["diagnostic_report"],
                "/tmp/meeting-assistant-real-runtime-diagnostics/real-runtime-timeout-session-app-ui-runtime.json",
            )
            self.assertFalse(report["proves_ui_or_provider_behavior"])
            self.assertIn("does not prove real runtime processing completed", " ".join(report["residual_risks"]))

    def test_cli_writes_report_and_marker(self) -> None:
        with tempfile.TemporaryDirectory() as directory:
            log_path = Path(directory) / "xcodebuild.log"
            report_path = Path(directory) / "report.json"
            log_path.write_text("System authentication is running\n", encoding="utf-8")
            result = subprocess.run(
                [
                    sys.executable,
                    str(ROOT / "platform/e2e/native_app_bundle_ui_automation_report.py"),
                    "--smoke-name",
                    "real runtime",
                    "--log",
                    str(log_path),
                    "--report",
                    str(report_path),
                    "--exit-code",
                    "65",
                    "--destination",
                    "platform=macOS,arch=arm64",
                ],
                cwd=ROOT,
                capture_output=True,
                text=True,
                check=False,
            )

            self.assertEqual(result.returncode, 0, result.stderr + result.stdout)
            self.assertIn("blocker_type=local_authentication_in_progress", result.stdout)
            self.assertIn("native app-bundle UI automation blocker report written", result.stderr)
            self.assertTrue(report_path.is_file())


if __name__ == "__main__":
    unittest.main()
