from __future__ import annotations

import hashlib
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
        "release_sidecar_portability_report",
        ROOT / "platform/e2e/release_sidecar_portability_report.py",
    )
    assert spec is not None
    module = importlib.util.module_from_spec(spec)
    assert spec.loader is not None
    spec.loader.exec_module(module)
    return module


class ReleaseSidecarPortabilityReportTests(unittest.TestCase):
    def current_head(self) -> str:
        return subprocess.check_output(["git", "rev-parse", "HEAD"], cwd=ROOT, text=True).strip()

    def digest(self, value: str) -> str:
        return "sha256:" + hashlib.sha256(value.encode("utf-8")).hexdigest()

    def write_target_smoke_report(
        self,
        directory: str,
        *,
        target_id: str = "macos-arm64-ci",
        head: str | None = None,
        passed: bool = True,
        no_auto_downloads_observed: bool = True,
    ) -> Path:
        report_path = Path(directory) / f"{target_id}.json"
        digest = self.digest(target_id)
        report_path.write_text(
            json.dumps(
                {
                    "report_schema": 1,
                    "release_gate": "release-sidecar-target-smoke",
                    "subject_commit": head or self.current_head(),
                    "target_id": target_id,
                    "os": "macos",
                    "architecture": "arm64",
                    "packages_runtime_or_model": False,
                    "auto_downloads": False,
                    "external_network_access": False,
                    "passed": passed,
                    "artifacts": {
                        "runtime": {
                            "name": "whisper-cli",
                            "path": f"/Users/runner/.local/opt/whisper.cpp/{target_id}/whisper-cli",
                            "digest": digest,
                            "source": "user-prepared-local-runtime",
                        },
                        "model": {
                            "name": "ggml-large-v3-turbo-q5_0.bin",
                            "path": (
                                "/Users/runner/.local/share/ai-models/whisper.cpp/"
                                f"{target_id}/ggml-large-v3-turbo-q5_0.bin"
                            ),
                            "digest": digest,
                            "source": "user-prepared-local-model",
                            "license": "Apache-2.0",
                            "provenance_ref": (
                                "/Users/runner/.local/share/ai-models/whisper.cpp/"
                                f"{target_id}/provenance.json"
                            ),
                        },
                        "smoke_audio_fixture": {
                            "name": "mixed-zh-en-tech.wav",
                            "path": (
                                "/Users/runner/.local/share/ai-fixtures/asr/zh-en-tech/"
                                f"{target_id}/mixed-zh-en-tech.wav"
                            ),
                            "digest": digest,
                            "source": "user-prepared-local-fixture",
                        },
                    },
                    "smoke": {
                        "check_dependencies_ok": True,
                        "whisper_cpp_smoke_passed": True,
                        "no_auto_downloads_observed": no_auto_downloads_observed,
                    },
                }
            ),
            encoding="utf-8",
        )
        return report_path

    def test_build_report_writes_all_target_sidecar_portability_report(self) -> None:
        module = load_report_module()
        with tempfile.TemporaryDirectory() as directory:
            target_report = self.write_target_smoke_report(directory)
            report_path = Path(directory) / "release-sidecar-report.json"

            report = module.build_report(
                ROOT,
                target_smoke_report_paths=[target_report],
                expected_targets=["macos arm64 ci"],
                report_path=report_path,
                builder="github-actions-oidc",
                source_repository_value="example/meeting_assistant",
            )

            self.assertTrue(report["passed"], report["findings"])
            self.assertEqual(report["release_gate"], "release-sidecar-portability")
            self.assertEqual(report["target_scope"], "all-target-machines")
            self.assertFalse(report["packages_runtime_or_model"])
            self.assertFalse(report["auto_downloads"])
            self.assertFalse(report["external_network_access"])
            self.assertEqual(report["expected_targets"], ["macos-arm64-ci"])
            self.assertEqual(report["observed_targets"], ["macos-arm64-ci"])
            target = report["target_machines"][0]
            self.assertEqual(target["target_id"], "macos-arm64-ci")
            self.assertEqual(
                target["smoke_report"]["digest"],
                "sha256:" + hashlib.sha256(target_report.read_bytes()).hexdigest(),
            )
            self.assertTrue(target["smoke"]["whisper_cpp_smoke_passed"])
            self.assertEqual(json.loads(report_path.read_text(encoding="utf-8")), report)

    def test_build_report_fails_closed_when_expected_target_is_missing(self) -> None:
        module = load_report_module()
        with tempfile.TemporaryDirectory() as directory:
            target_report = self.write_target_smoke_report(directory)

            report = module.build_report(
                ROOT,
                target_smoke_report_paths=[target_report],
                expected_targets=["macos-arm64-ci", "macos-arm64-release-lab"],
                builder="github-actions-oidc",
                source_repository_value="example/meeting_assistant",
            )

            self.assertFalse(report["passed"])
            self.assertEqual(report["target_scope"], "incomplete-target-set")
            self.assertIn("missing expected target smoke reports: macos-arm64-release-lab", report["findings"])

    def test_build_report_fails_closed_when_target_smoke_failed(self) -> None:
        module = load_report_module()
        with tempfile.TemporaryDirectory() as directory:
            target_report = self.write_target_smoke_report(
                directory,
                passed=False,
                no_auto_downloads_observed=False,
            )

            report = module.build_report(
                ROOT,
                target_smoke_report_paths=[target_report],
                expected_targets=["macos-arm64-ci"],
                builder="github-actions-oidc",
                source_repository_value="example/meeting_assistant",
            )

            self.assertFalse(report["passed"])
            self.assertTrue(any("must set passed=True" in item for item in report["findings"]))
            self.assertTrue(any("smoke must set no_auto_downloads_observed=True" in item for item in report["findings"]))

    def test_cli_writes_report_and_marker(self) -> None:
        with tempfile.TemporaryDirectory() as directory:
            target_report = self.write_target_smoke_report(directory)
            report_path = Path(directory) / "release-sidecar-report.json"

            result = subprocess.run(
                [
                    sys.executable,
                    str(ROOT / "platform/e2e/release_sidecar_portability_report.py"),
                    "--root",
                    str(ROOT),
                    "--target-smoke-report",
                    str(target_report),
                    "--expected-target",
                    "macos-arm64-ci",
                    "--report",
                    str(report_path),
                    "--builder",
                    "github-actions-oidc",
                    "--source-repository",
                    "example/meeting_assistant",
                ],
                cwd=ROOT,
                env=os.environ.copy(),
                capture_output=True,
                text=True,
                check=False,
            )

            self.assertEqual(result.returncode, 0, result.stderr + result.stdout)
            self.assertIn("release-sidecar-portability", result.stdout)
            self.assertIn(str(report_path), result.stderr)
            report = json.loads(report_path.read_text(encoding="utf-8"))
            self.assertEqual(report["target_scope"], "all-target-machines")


if __name__ == "__main__":
    unittest.main()
