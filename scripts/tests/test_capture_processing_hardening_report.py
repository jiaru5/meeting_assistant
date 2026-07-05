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
        "capture_processing_hardening_report",
        ROOT / "platform/e2e/capture_processing_hardening_report.py",
    )
    assert spec is not None
    module = importlib.util.module_from_spec(spec)
    assert spec.loader is not None
    spec.loader.exec_module(module)
    return module


class CaptureProcessingHardeningReportTests(unittest.TestCase):
    def write_output(self, directory: str, *, omit_marker: str | None = None) -> tuple[Path, Path]:
        module = load_report_module()
        output_path = Path(directory) / "capture-processing-output.log"
        report_path = Path(directory) / "capture-processing-report.json"
        markers = [
            marker
            for key, marker in module.EXPECTED_MARKERS.items()
            if key != omit_marker
        ]
        output_path.write_text("\n".join(markers) + "\n", encoding="utf-8")
        return output_path, report_path

    def test_build_report_writes_release_scope_provider_hardening_evidence(self) -> None:
        module = load_report_module()
        with tempfile.TemporaryDirectory() as directory:
            output_path, report_path = self.write_output(directory)

            report = module.build_report(output_path, report_path=report_path, exit_code=0, release_scope=True)

            self.assertTrue(report_path.is_file())
            self.assertEqual(json.loads(report_path.read_text(encoding="utf-8")), report)
            self.assertTrue(report["passed"])
            self.assertEqual(report["release_gate"], "release-scope-provider-hardening")
            self.assertTrue(report["release_scope_provider_hardening"])
            self.assertEqual(report["vs_ma"], ["VS-MA-21"])
            self.assertEqual(report["pv"], ["PV-MA-009"])
            self.assertTrue(report["not_release_readiness"])
            self.assertFalse(report["missing_markers"])
            self.assertTrue(report["marker_results"]["concurrency_retry"])
            self.assertIn("PV-MA-006", report["related_pv"])
            self.assertIn("does not prove real ScreenCaptureKit native capture artifacts", report["release_blockers"])

    def test_build_report_fails_closed_when_marker_is_missing(self) -> None:
        module = load_report_module()
        with tempfile.TemporaryDirectory() as directory:
            output_path, report_path = self.write_output(directory, omit_marker="concurrency_retry")

            report = module.build_report(output_path, report_path=report_path, exit_code=0, release_scope=True)

            self.assertFalse(report["passed"])
            self.assertEqual(report["missing_markers"], ["concurrency_retry"])
            self.assertIn("missing expected markers", report["findings"][0])

    def test_build_report_fails_closed_when_smoke_exits_nonzero(self) -> None:
        module = load_report_module()
        with tempfile.TemporaryDirectory() as directory:
            output_path, report_path = self.write_output(directory)

            report = module.build_report(output_path, report_path=report_path, exit_code=5, release_scope=True)

            self.assertFalse(report["passed"])
            self.assertEqual(report["smoke_exit_code"], 5)
            self.assertIn("capture-processing-smoke exited 5", report["findings"])

    def test_cli_writes_release_scope_report_and_marker(self) -> None:
        with tempfile.TemporaryDirectory() as directory:
            output_path, report_path = self.write_output(directory)
            result = subprocess.run(
                [
                    sys.executable,
                    str(ROOT / "platform/e2e/capture_processing_hardening_report.py"),
                    "--output",
                    str(output_path),
                    "--report",
                    str(report_path),
                    "--exit-code",
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
            self.assertIn("release-scope-provider-hardening", result.stdout)
            self.assertIn("release-scope provider hardening gate passed", result.stdout)
            self.assertIn(str(report_path), result.stderr)
            self.assertTrue(report_path.is_file())


if __name__ == "__main__":
    unittest.main()
