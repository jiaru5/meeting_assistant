import json
import os
import subprocess
import tempfile
import time
import unittest
from pathlib import Path


ROOT = Path(__file__).resolve().parents[2]
SCRIPT = ROOT / "platform/native-app/scripts/local-app-permission-diagnostics.sh"


class LocalAppPermissionDiagnosticsTests(unittest.TestCase):
    def write_json(self, path: Path, payload: dict) -> None:
        path.parent.mkdir(parents=True, exist_ok=True)
        path.write_text(json.dumps(payload), encoding="utf-8")

    def test_selects_latest_recording_report_from_search_roots(self) -> None:
        with tempfile.TemporaryDirectory() as tmpdir:
            tmp = Path(tmpdir)
            install_report = tmp / "install.json"
            report_file = tmp / "diagnostics.json"
            native_root = tmp / "native-build"
            e2e_root = tmp / "e2e-build"
            installed_path = "/Users/example/Applications/MeetingAssistantNativeLocal.app"

            self.write_json(
                install_report,
                {
                    "installed_app": {
                        "path": installed_path,
                        "CFBundleIdentifier": "local.meeting-assistant.native.localdirect",
                        "CFBundleName": "MeetingAssistantNativeLocal",
                        "CFBundleDisplayName": "Meeting Assistant Native Local",
                        "codesign": {
                            "CDHash": "new-cdhash",
                            "Signature": "adhoc",
                            "TeamIdentifier": "not set",
                        },
                    },
                    "local_tcc_identity_strategy": "stable-local-direct-bundle-id",
                },
            )

            old_report = native_root / "local-direct-recording-smoke" / "local-direct-recording-smoke-report.json"
            malformed_report = (
                native_root
                / "local-direct-recording-smoke-malformed"
                / "local-direct-recording-smoke-report.json"
            )
            direct_report = (
                native_root
                / "local-direct-recording-smoke-direct"
                / "local-direct-recording-smoke-report.json"
            )
            new_report = (
                e2e_root
                / "release-local-direct-target-smoke"
                / "same-chain"
                / "latest"
                / "recording"
                / "local-direct-recording-smoke-report.json"
            )
            self.write_json(
                old_report,
                {
                    "app_identity": {
                        "path": "/Users/example/Applications/Old.app",
                        "codesign": {"CDHash": "old-cdhash"},
                    },
                    "permission_failure_details": [],
                },
            )
            malformed_report.parent.mkdir(parents=True, exist_ok=True)
            malformed_report.write_text("[", encoding="utf-8")
            self.write_json(
                direct_report,
                {
                    "passed": True,
                    "app_identity": {
                        "path": installed_path,
                        "codesign": {"CDHash": "new-cdhash"},
                    },
                    "runner_configuration": {"launch_mode": "direct"},
                    "permission_failure_details": [],
                },
            )
            self.write_json(
                new_report,
                {
                    "passed": False,
                    "blocker_type": "permission_denied",
                    "app_identity": {
                        "path": installed_path,
                        "codesign": {"CDHash": "new-cdhash"},
                    },
                    "runner_configuration": {"launch_mode": "open"},
                    "permission_failure_details": ["Screen Recording permission is denied."],
                },
            )
            old_time = time.time() - 120
            malformed_time = time.time() - 90
            direct_time = time.time() - 60
            new_time = time.time()
            os.utime(old_report, (old_time, old_time))
            os.utime(malformed_report, (malformed_time, malformed_time))
            os.utime(direct_report, (direct_time, direct_time))
            os.utime(new_report, (new_time, new_time))

            env = os.environ.copy()
            env["MA_NATIVE_LOCAL_APP_RECORDING_REPORT_SEARCH_ROOTS"] = os.pathsep.join(
                [str(native_root), str(e2e_root)]
            )
            result = subprocess.run(
                [
                    str(SCRIPT),
                    "--install-report",
                    str(install_report),
                    "--report-file",
                    str(report_file),
                ],
                cwd=ROOT,
                env=env,
                text=True,
                stdout=subprocess.PIPE,
                stderr=subprocess.PIPE,
                check=False,
            )

            self.assertEqual(result.returncode, 0, result.stderr)
            diagnostics = json.loads(report_file.read_text(encoding="utf-8"))
            self.assertEqual(diagnostics["recording_report"], str(new_report.resolve()))
            self.assertEqual(diagnostics["recording_report_selection"], "latest")
            self.assertTrue(diagnostics["recording_report_found"])
            self.assertTrue(diagnostics["screen_recording_permission_denied"])
            self.assertTrue(diagnostics["same_app_as_recording_smoke"])
            self.assertEqual(
                diagnostics["latest_matching_direct_success_recording_report"],
                str(direct_report.resolve()),
            )
            self.assertEqual(
                diagnostics["latest_matching_open_permission_denied_recording_report"],
                str(new_report.resolve()),
            )
            self.assertTrue(diagnostics["launchservices_tcc_attribution_suspected"])
            self.assertIn("LaunchServices open", diagnostics["launchservices_tcc_attribution_summary"])
            self.assertTrue(diagnostics["user_action_required"])


if __name__ == "__main__":
    unittest.main()
