from __future__ import annotations

import hashlib
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
        "release_local_direct_repeatability_report",
        ROOT / "platform/e2e/release_local_direct_repeatability_report.py",
    )
    assert spec is not None
    module = importlib.util.module_from_spec(spec)
    assert spec.loader is not None
    spec.loader.exec_module(module)
    return module


class ReleaseLocalDirectRepeatabilityReportTests(unittest.TestCase):
    def current_head(self) -> str:
        return subprocess.check_output(["git", "rev-parse", "HEAD"], cwd=ROOT, text=True).strip()

    def digest(self, value: str) -> str:
        return "sha256:" + hashlib.sha256(value.encode("utf-8")).hexdigest()

    def write_target_report(
        self,
        directory: str,
        *,
        target_id: str = "macos-arm64-local",
        head: str | None = None,
        passed: bool = True,
        launch_modes: list[str] | None = None,
    ) -> Path:
        report_path = Path(directory) / f"{target_id}.json"
        report_path.write_text(
            json.dumps(
                {
                    "report_schema": 1,
                    "release_gate": "release-local-direct-target-smoke",
                    "target_scope": "single-target-machine",
                    "subject_commit": head or self.current_head(),
                    "target_id": target_id,
                    "os": "macos",
                    "architecture": "arm64",
                    "packages_runtime_or_model": False,
                    "auto_downloads": False,
                    "external_network_access": False,
                    "same_chain_report": {
                        "path": f"/tmp/{target_id}/local-direct-same-chain-smoke-report.json",
                        "digest": self.digest(target_id),
                    },
                    "local_direct_app": {
                        "path": "/Users/runner/Applications/MeetingAssistantNativeLocal.app",
                        "CFBundleIdentifier": "local.meeting-assistant.native.localdirect",
                    },
                    "smoke": {
                        "same_chain_passed": passed,
                        "same_app_identity": True,
                        "launch_modes": launch_modes or ["open"],
                        "stage_passed": {"recording": True, "processing": True, "actions": True},
                    },
                    "passed": passed,
                    "not_release_readiness": True,
                }
            ),
            encoding="utf-8",
        )
        return report_path

    def test_build_report_writes_all_target_local_direct_repeatability_report(self) -> None:
        module = load_report_module()
        with tempfile.TemporaryDirectory() as directory:
            target_report = self.write_target_report(directory)
            report_path = Path(directory) / "repeatability.json"

            report = module.build_report(
                ROOT,
                target_smoke_report_paths=[target_report],
                expected_targets=["macos arm64 local"],
                report_path=report_path,
                builder="local-direct-rehearsal",
                source_repository_value="example/meeting_assistant",
            )

            self.assertTrue(report["passed"], report["findings"])
            self.assertEqual(report["release_gate"], "release-local-direct-repeatability")
            self.assertEqual(report["target_scope"], "all-target-machines")
            self.assertEqual(report["expected_targets"], ["macos-arm64-local"])
            self.assertEqual(report["observed_targets"], ["macos-arm64-local"])
            target = report["target_machines"][0]
            self.assertEqual(target["target_id"], "macos-arm64-local")
            self.assertEqual(
                target["target_smoke_report"]["digest"],
                "sha256:" + hashlib.sha256(target_report.read_bytes()).hexdigest(),
            )
            self.assertTrue(target["smoke"]["same_chain_passed"])
            self.assertEqual(json.loads(report_path.read_text(encoding="utf-8")), report)

    def test_build_report_fails_closed_when_expected_target_is_missing(self) -> None:
        module = load_report_module()
        with tempfile.TemporaryDirectory() as directory:
            target_report = self.write_target_report(directory)

            report = module.build_report(
                ROOT,
                target_smoke_report_paths=[target_report],
                expected_targets=["macos-arm64-local", "macos-arm64-lab"],
                builder="local-direct-rehearsal",
                source_repository_value="example/meeting_assistant",
            )

            self.assertFalse(report["passed"])
            self.assertEqual(report["target_scope"], "incomplete-target-set")
            self.assertIn("missing expected target smoke reports: macos-arm64-lab", report["findings"])

    def test_build_report_fails_closed_when_target_smoke_failed(self) -> None:
        module = load_report_module()
        with tempfile.TemporaryDirectory() as directory:
            target_report = self.write_target_report(directory, passed=False)

            report = module.build_report(
                ROOT,
                target_smoke_report_paths=[target_report],
                expected_targets=["macos-arm64-local"],
                builder="local-direct-rehearsal",
                source_repository_value="example/meeting_assistant",
            )

            self.assertFalse(report["passed"])
            self.assertTrue(any("must set passed=True" in item for item in report["findings"]))
            self.assertTrue(any("same_chain_passed=True" in item for item in report["findings"]))

    def test_cli_writes_report_and_marker(self) -> None:
        with tempfile.TemporaryDirectory() as directory:
            target_report = self.write_target_report(directory)
            report_path = Path(directory) / "repeatability.json"
            result = subprocess.run(
                [
                    sys.executable,
                    str(ROOT / "platform/e2e/release_local_direct_repeatability_report.py"),
                    "--root",
                    str(ROOT),
                    "--target-smoke-report",
                    str(target_report),
                    "--expected-target",
                    "macos-arm64-local",
                    "--report",
                    str(report_path),
                    "--builder",
                    "local-direct-rehearsal",
                    "--source-repository",
                    "example/meeting_assistant",
                ],
                cwd=ROOT,
                capture_output=True,
                text=True,
                check=False,
            )

            self.assertEqual(result.returncode, 0, result.stderr + result.stdout)
            self.assertIn("release-local-direct-repeatability", result.stdout)
            self.assertIn(str(report_path), result.stderr)
            report = json.loads(report_path.read_text(encoding="utf-8"))
            self.assertEqual(report["target_scope"], "all-target-machines")


if __name__ == "__main__":
    unittest.main()
