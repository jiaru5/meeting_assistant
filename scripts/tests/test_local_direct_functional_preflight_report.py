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
        "local_direct_functional_preflight_report",
        ROOT / "platform/e2e/local_direct_functional_preflight_report.py",
    )
    assert spec is not None
    module = importlib.util.module_from_spec(spec)
    assert spec.loader is not None
    spec.loader.exec_module(module)
    return module


class LocalDirectFunctionalPreflightReportTests(unittest.TestCase):
    def current_head(self) -> str:
        return subprocess.check_output(["git", "rev-parse", "HEAD"], cwd=ROOT, text=True).strip()

    def digest_file(self, path: Path) -> str:
        return "sha256:" + hashlib.sha256(path.read_bytes()).hexdigest()

    def write_fake_app(self, directory: str, name: str, content: bytes = b"local-direct-app") -> Path:
        app = Path(directory) / f"{name}.app"
        executable = app / "Contents/MacOS/MeetingAssistantNative"
        executable.parent.mkdir(parents=True, exist_ok=True)
        executable.write_bytes(content)
        executable.chmod(0o755)
        return app

    def write_release_bundle_report(self, directory: str) -> Path:
        report_path = Path(directory) / "release-bundle-report.json"
        archive = Path(directory) / "MeetingAssistantNative-Release.zip"
        archive.write_bytes(b"release archive")
        report_path.write_text(
            json.dumps(
                {
                    "report_schema": 1,
                    "release_gate": "release-bundle",
                    "subject_commit": self.current_head(),
                    "builder": "local-direct-functional-preflight",
                    "source_repository": "example/meeting_assistant",
                    "bundle": {
                        "name": archive.name,
                        "path": str(archive),
                        "digest": self.digest_file(archive),
                        "artifact_type": "macos-app-archive",
                        "archive_format": "zip",
                        "app_bundle": "MeetingAssistantNative.app",
                        "build_configuration": "Release",
                        "code_signed": True,
                        "distribution_mode": "local-direct",
                        "install_method": "direct-local-app",
                        "signing_identity": "ad-hoc-local",
                        "notarized": False,
                        "notarization_ticket": "not-applicable",
                        "stapled": False,
                        "packages_runtime_or_model": False,
                        "auto_downloads": False,
                        "contains_meeting_data": False,
                    },
                }
            ),
            encoding="utf-8",
        )
        return report_path

    def write_target_report(
        self,
        directory: str,
        *,
        target_id: str = "macos-arm64-local",
        passed: bool = True,
        installed_app: Path | None = None,
        expected_terms_found: list[str] | None = None,
    ) -> Path:
        installed_app_path = installed_app or Path(directory) / "MeetingAssistantNativeLocal.app"
        report_path = Path(directory) / "target.json"
        report_path.write_text(
            json.dumps(
                {
                    "report_schema": 1,
                    "release_gate": "release-local-direct-target-smoke",
                    "target_scope": "single-target-machine",
                    "subject_commit": self.current_head(),
                    "target_id": target_id,
                    "os": "macos",
                    "architecture": "arm64",
                    "packages_runtime_or_model": False,
                    "auto_downloads": False,
                    "external_network_access": False,
                    "same_chain_report": {
                        "path": f"/tmp/{target_id}/local-direct-same-chain-smoke-report.json",
                        "digest": "sha256:" + ("a" * 64),
                    },
                    "local_direct_app": {
                        "path": str(installed_app_path),
                        "CFBundleIdentifier": "local.meeting-assistant.native.localdirect",
                    },
                    "smoke": {
                        "same_chain_passed": passed,
                        "same_app_identity": True,
                        "launch_modes": ["open"],
                        "stage_passed": {"recording": True, "processing": True, "actions": True},
                        "expected_terms_found": expected_terms_found
                        or ["HTTP", "LLM", "clean architecture"],
                        "actions_markers": ["Copy complete.", "Export complete.", "Delete complete."],
                    },
                    "passed": passed,
                    "not_release_readiness": True,
                }
            ),
            encoding="utf-8",
        )
        return report_path

    def write_repeatability_report(
        self,
        directory: str,
        target_report: Path,
        *,
        target_id: str = "macos-arm64-local",
        expected_targets: list[str] | None = None,
        observed_targets: list[str] | None = None,
    ) -> Path:
        report_path = Path(directory) / "repeatability.json"
        expected = expected_targets or [target_id]
        observed = observed_targets or [target_id]
        report_path.write_text(
            json.dumps(
                {
                    "report_schema": 1,
                    "release_gate": "release-local-direct-repeatability",
                    "target_scope": "all-target-machines",
                    "subject_commit": self.current_head(),
                    "builder": "local-direct-functional-preflight",
                    "source_repository": "example/meeting_assistant",
                    "packages_runtime_or_model": False,
                    "auto_downloads": False,
                    "external_network_access": False,
                    "expected_targets": expected,
                    "observed_targets": observed,
                    "target_machines": [
                        {
                            "target_id": target_id,
                            "os": "macos",
                            "architecture": "arm64",
                            "target_smoke_report": {
                                "path": str(target_report),
                                "digest": self.digest_file(target_report),
                            },
                            "smoke": {"same_chain_passed": True},
                        }
                    ],
                    "passed": True,
                    "not_release_readiness": True,
                    "findings": [],
                }
            ),
            encoding="utf-8",
        )
        return report_path

    def test_build_report_writes_local_machine_only_preflight(self) -> None:
        module = load_report_module()
        with tempfile.TemporaryDirectory() as directory:
            source_app = self.write_fake_app(directory, "MeetingAssistantNative")
            installed_app = self.write_fake_app(directory, "MeetingAssistantNativeLocal")
            release_bundle_report = self.write_release_bundle_report(directory)
            target_report = self.write_target_report(directory, installed_app=installed_app)
            repeatability_report = self.write_repeatability_report(directory, target_report)
            report_path = Path(directory) / "preflight.json"

            report = module.build_report(
                ROOT,
                target_smoke_report_path=target_report,
                repeatability_report_path=repeatability_report,
                source_app_path=source_app,
                release_bundle_report_path=release_bundle_report,
                report_path=report_path,
            )

            self.assertTrue(report["passed"], report["findings"])
            self.assertEqual(report["release_gate"], "local-direct-functional-preflight")
            self.assertEqual(report["target_scope"], "local-machine-only")
            self.assertEqual(report["target_id"], "macos-arm64-local")
            self.assertEqual(report["repeatability_report"]["expected_targets"], ["macos-arm64-local"])
            self.assertTrue(report["not_release_readiness"])
            self.assertIn("HTTP", report["functional_checks"]["expected_terms_found"])
            self.assertTrue(report["local_direct_app_source"]["source_and_installed_executable_match"])
            self.assertTrue(report["local_direct_app_source"]["source_and_installed_unsigned_executable_match"])
            self.assertTrue(
                report["local_direct_app_source"]["source_app"]["unsigned_executable_sha256"].startswith("sha256:")
            )
            self.assertTrue(
                report["local_direct_app_source"]["installed_app"]["unsigned_executable_sha256"].startswith("sha256:")
            )
            self.assertEqual(
                report["local_direct_app_source"]["release_bundle_report"]["subject_commit"],
                self.current_head(),
            )
            self.assertEqual(json.loads(report_path.read_text(encoding="utf-8")), report)

    def test_build_report_fails_when_repeatability_contains_extra_target(self) -> None:
        module = load_report_module()
        with tempfile.TemporaryDirectory() as directory:
            source_app = self.write_fake_app(directory, "MeetingAssistantNative")
            installed_app = self.write_fake_app(directory, "MeetingAssistantNativeLocal")
            release_bundle_report = self.write_release_bundle_report(directory)
            target_report = self.write_target_report(directory, installed_app=installed_app)
            repeatability_report = self.write_repeatability_report(
                directory,
                target_report,
                expected_targets=["macos-arm64-local", "macos-arm64-lab"],
                observed_targets=["macos-arm64-local", "macos-arm64-lab"],
            )

            report = module.build_report(
                ROOT,
                target_smoke_report_path=target_report,
                repeatability_report_path=repeatability_report,
                source_app_path=source_app,
                release_bundle_report_path=release_bundle_report,
            )

            self.assertFalse(report["passed"])
            self.assertTrue(any("expected_targets must be exactly" in item for item in report["findings"]))
            self.assertTrue(any("observed_targets must be exactly" in item for item in report["findings"]))

    def test_build_report_fails_when_target_terms_are_missing(self) -> None:
        module = load_report_module()
        with tempfile.TemporaryDirectory() as directory:
            source_app = self.write_fake_app(directory, "MeetingAssistantNative")
            installed_app = self.write_fake_app(directory, "MeetingAssistantNativeLocal")
            release_bundle_report = self.write_release_bundle_report(directory)
            target_report = self.write_target_report(
                directory,
                installed_app=installed_app,
                expected_terms_found=["HTTP"],
            )
            repeatability_report = self.write_repeatability_report(directory, target_report)

            report = module.build_report(
                ROOT,
                target_smoke_report_path=target_report,
                repeatability_report_path=repeatability_report,
                source_app_path=source_app,
                release_bundle_report_path=release_bundle_report,
            )

            self.assertFalse(report["passed"])
            self.assertTrue(any("missing expected terms" in item for item in report["findings"]))

    def test_build_report_fails_when_installed_app_does_not_match_source(self) -> None:
        module = load_report_module()
        with tempfile.TemporaryDirectory() as directory:
            source_app = self.write_fake_app(directory, "MeetingAssistantNative", b"source")
            installed_app = self.write_fake_app(directory, "MeetingAssistantNativeLocal", b"stale")
            release_bundle_report = self.write_release_bundle_report(directory)
            target_report = self.write_target_report(directory, installed_app=installed_app)
            repeatability_report = self.write_repeatability_report(directory, target_report)

            report = module.build_report(
                ROOT,
                target_smoke_report_path=target_report,
                repeatability_report_path=repeatability_report,
                source_app_path=source_app,
                release_bundle_report_path=release_bundle_report,
            )

            self.assertFalse(report["passed"])
            self.assertTrue(
                any("installed local-direct app unsigned executable content must match" in item for item in report["findings"])
            )

    def test_cli_writes_report_and_marker(self) -> None:
        with tempfile.TemporaryDirectory() as directory:
            source_app = self.write_fake_app(directory, "MeetingAssistantNative")
            installed_app = self.write_fake_app(directory, "MeetingAssistantNativeLocal")
            release_bundle_report = self.write_release_bundle_report(directory)
            target_report = self.write_target_report(directory, installed_app=installed_app)
            repeatability_report = self.write_repeatability_report(directory, target_report)
            report_path = Path(directory) / "preflight.json"

            result = subprocess.run(
                [
                    sys.executable,
                    str(ROOT / "platform/e2e/local_direct_functional_preflight_report.py"),
                    "--root",
                    str(ROOT),
                    "--target-smoke-report",
                    str(target_report),
                    "--repeatability-report",
                    str(repeatability_report),
                    "--source-app",
                    str(source_app),
                    "--release-bundle-report",
                    str(release_bundle_report),
                    "--report",
                    str(report_path),
                ],
                cwd=ROOT,
                capture_output=True,
                text=True,
                check=False,
            )

            self.assertEqual(result.returncode, 0, result.stderr + result.stdout)
            self.assertIn("local-direct-functional-preflight", result.stdout)
            self.assertIn(str(report_path), result.stderr)
            report = json.loads(report_path.read_text(encoding="utf-8"))
            self.assertEqual(report["target_scope"], "local-machine-only")


if __name__ == "__main__":
    unittest.main()
