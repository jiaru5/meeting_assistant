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


def load_report_module():
    spec = importlib.util.spec_from_file_location(
        "release_native_ui_hardening_report",
        ROOT / "platform/e2e/release_native_ui_hardening_report.py",
    )
    assert spec is not None
    module = importlib.util.module_from_spec(spec)
    assert spec.loader is not None
    spec.loader.exec_module(module)
    return module


class ReleaseNativeUIHardeningReportTests(unittest.TestCase):
    def write_outputs(self, directory: str, *, omit_marker: str | None = None) -> tuple[Path, Path, Path]:
        module = load_report_module()
        real_capture_output = Path(directory) / "real-capture.log"
        hardening_output = Path(directory) / "hardening.log"
        report_path = Path(directory) / "report.json"
        real_capture_markers = [
            marker
            for key, marker in module.EXPECTED_MARKERS.items()
            if key.startswith("real_capture") and key != omit_marker
        ]
        hardening_markers = [
            marker
            for key, marker in module.EXPECTED_MARKERS.items()
            if key.startswith("hardening") and key != omit_marker
        ]
        real_capture_output.write_text("\n".join(real_capture_markers) + "\n", encoding="utf-8")
        hardening_output.write_text("\n".join(hardening_markers) + "\n", encoding="utf-8")
        return real_capture_output, hardening_output, report_path

    def test_build_report_writes_release_scope_native_ui_hardening_evidence(self) -> None:
        module = load_report_module()
        with tempfile.TemporaryDirectory() as directory:
            real_capture_output, hardening_output, report_path = self.write_outputs(directory)

            report = module.build_report(
                real_capture_output,
                hardening_output,
                report_path=report_path,
                real_capture_exit_code=0,
                hardening_exit_code=0,
                release_scope=True,
            )

            self.assertTrue(report_path.is_file())
            self.assertEqual(json.loads(report_path.read_text(encoding="utf-8")), report)
            self.assertTrue(report["passed"])
            self.assertFalse(report["blocked"])
            self.assertEqual(report["blocker_type"], "none")
            self.assertEqual(report["release_gate"], "release-scope-native-ui-hardening")
            self.assertTrue(report["release_scope_native_ui_hardening"])
            self.assertEqual(report["vs_ma"], ["VS-MA-21"])
            self.assertEqual(report["pv"], ["PV-MA-009"])
            self.assertIn("PV-MA-002", report["related_pv"])
            self.assertTrue(report["marker_results"]["real_capture_pass_marker"])
            self.assertTrue(report["marker_results"]["hardening_completed_state"])
            self.assertTrue(report["not_release_readiness"])
            self.assertTrue(report["real_capture_adapter_capability"]["source_contract_ok"])
            self.assertTrue(report["real_capture_combined_recording_file_supported"])
            self.assertFalse(report["real_capture_separate_audio_artifacts_supported"])
            self.assertFalse(report["real_capture_independent_audio_artifacts_proven"])
            self.assertFalse(report["real_capture_mixed_audio_artifact_proven"])
            self.assertFalse(report["real_capture_to_processing_same_chain_proven"])
            self.assertIn("does not prove full real capture -> transcript/export/delete same-chain success", report["release_blockers"])
            self.assertIn("does not prove a separate mixed_audio artifact from ScreenCaptureKit", report["release_blockers"])

    def test_build_report_fails_closed_when_marker_is_missing(self) -> None:
        module = load_report_module()
        with tempfile.TemporaryDirectory() as directory:
            real_capture_output, hardening_output, report_path = self.write_outputs(
                directory,
                omit_marker="hardening_path_conflict",
            )

            report = module.build_report(
                real_capture_output,
                hardening_output,
                report_path=report_path,
                real_capture_exit_code=0,
                hardening_exit_code=0,
                release_scope=True,
            )

            self.assertFalse(report["passed"])
            self.assertTrue(report["blocked"])
            self.assertEqual(report["blocker_type"], "marker_validation_failed")
            self.assertEqual(report["missing_markers"], ["hardening_path_conflict"])
            self.assertIn("missing expected markers", report["findings"][0])

    def test_build_report_fails_closed_when_real_capture_permission_is_denied(self) -> None:
        module = load_report_module()
        with tempfile.TemporaryDirectory() as directory:
            real_capture_output, hardening_output, report_path = self.write_outputs(directory)
            real_capture_output.write_text(
                real_capture_output.read_text(encoding="utf-8")
                + "Native capture permissions are denied or unknown. Error code: permission_denied\n"
                + f"DerivedData path: {directory}/DerivedData/AppBundleUITests\n"
                + f"App bundle under test: {directory}/DerivedData/AppBundleUITests/Build/Products/Debug/MeetingAssistantNative.app\n"
                + f"Captured xcodebuild log: {directory}/DerivedData/AppBundleUITests/real-capture-app-bundle-smoke.log\n"
                + "Test session results, code coverage, and logs:\n"
                + f"\t{directory}/DerivedData/Xcode/Logs/Test/Test-MeetingAssistantNative.xcresult\n",
                encoding="utf-8",
            )

            report = module.build_report(
                real_capture_output,
                hardening_output,
                report_path=report_path,
                real_capture_exit_code=65,
                hardening_exit_code=0,
                release_scope=True,
            )

            self.assertFalse(report["passed"])
            self.assertTrue(report["blocked"])
            self.assertEqual(report["blocker_type"], "real_capture_permission_denied")
            self.assertTrue(report["real_capture_permission_denied"])
            self.assertEqual(report["real_capture_exit_code"], 65)
            self.assertEqual(report["real_capture_derived_data_path"], f"{directory}/DerivedData/AppBundleUITests")
            self.assertEqual(
                report["real_capture_app_bundle_under_test"],
                f"{directory}/DerivedData/AppBundleUITests/Build/Products/Debug/MeetingAssistantNative.app",
            )
            self.assertEqual(
                report["real_capture_xcodebuild_log_path"],
                f"{directory}/DerivedData/AppBundleUITests/real-capture-app-bundle-smoke.log",
            )
            self.assertEqual(
                report["real_capture_xcresult_path"],
                f"{directory}/DerivedData/Xcode/Logs/Test/Test-MeetingAssistantNative.xcresult",
            )
            self.assertTrue(report["real_capture_tcc_remediation"])
            self.assertIn("Screen Recording", report["real_capture_tcc_remediation"][0])
            self.assertIn("real capture app-bundle smoke exited 65", report["findings"])

    def test_build_report_fails_closed_when_adapter_capability_contract_changes(self) -> None:
        module = load_report_module()
        with tempfile.TemporaryDirectory() as directory:
            real_capture_output, hardening_output, report_path = self.write_outputs(directory)
            source_root = Path(directory) / "source-root"
            adapter_source = source_root / module.ADAPTER_SOURCE_RELATIVE_PATH
            adapter_source.parent.mkdir(parents=True)
            adapter_source.write_text(
                """
public actor AppleScreenCaptureKitNativeCaptureAdapter {
    public static let identity = "apple_screencapturekit"
    public static let capabilitySummary = AppleScreenCaptureKitNativeCaptureCapabilitySummary(
        adapterID: identity,
        framework: "ScreenCaptureKit",
        supportedCaptureTargets: [.screen],
        producedArtifactTypes: NativeCaptureArtifactType.allCases,
        producesCombinedRecordingFile: true,
        producesSeparateAudioArtifacts: true
    )
}
""",
                encoding="utf-8",
            )

            report = module.build_report(
                real_capture_output,
                hardening_output,
                report_path=report_path,
                real_capture_exit_code=0,
                hardening_exit_code=0,
                release_scope=True,
                source_root=source_root,
            )

            self.assertFalse(report["passed"])
            self.assertTrue(report["blocked"])
            self.assertEqual(report["blocker_type"], "adapter_capability_contract_changed")
            self.assertFalse(report["real_capture_adapter_capability"]["source_contract_ok"])
            self.assertTrue(report["real_capture_separate_audio_artifacts_supported"])
            self.assertIn("adapter capability source contract changed", report["findings"][0])

    def test_cli_writes_release_scope_report_and_marker(self) -> None:
        with tempfile.TemporaryDirectory() as directory:
            real_capture_output, hardening_output, report_path = self.write_outputs(directory)
            result = subprocess.run(
                [
                    sys.executable,
                    str(ROOT / "platform/e2e/release_native_ui_hardening_report.py"),
                    "--real-capture-output",
                    str(real_capture_output),
                    "--hardening-output",
                    str(hardening_output),
                    "--report",
                    str(report_path),
                    "--real-capture-exit-code",
                    "0",
                    "--hardening-exit-code",
                    "0",
                    "--release-scope",
                ],
                cwd=ROOT,
                env=os.environ.copy(),
                capture_output=True,
                text=True,
                check=False,
            )

            self.assertEqual(result.returncode, 0, result.stderr + result.stdout)
            self.assertIn("release-scope-native-ui-hardening", result.stdout)
            self.assertIn("release-scope native UI hardening gate passed", result.stdout)
            self.assertIn(str(report_path), result.stderr)
            self.assertTrue(report_path.is_file())


if __name__ == "__main__":
    unittest.main()
