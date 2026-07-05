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
