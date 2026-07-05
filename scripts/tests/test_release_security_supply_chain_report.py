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
        "release_security_supply_chain_report",
        ROOT / "platform/e2e/release_security_supply_chain_report.py",
    )
    assert spec is not None
    module = importlib.util.module_from_spec(spec)
    assert spec.loader is not None
    spec.loader.exec_module(module)
    return module


class ReleaseSecuritySupplyChainReportTests(unittest.TestCase):
    def write_root(self, directory: str, *, unsafe_supply_chain: bool = False) -> Path:
        root = Path(directory)
        (root / "harness").mkdir()
        components = [
            {"id": "native-app", "path": "platform/native-app", "production": True},
            {"id": "processing-cli", "path": "platform/processing-cli", "production": True},
        ]
        (root / "harness/project-manifest.json").write_text(
            json.dumps({"components": components}),
            encoding="utf-8",
        )
        module = load_report_module()
        for component in components:
            component_root = root / component["path"]
            (component_root / "security").mkdir(parents=True)
            (component_root / "supply-chain").mkdir(parents=True)
            security_report = {"component": component["id"], **module.EXPECTED_SECURITY_VALUES}
            supply_chain_report = {"component": component["id"], "sbom": component["id"], **module.EXPECTED_SUPPLY_CHAIN_VALUES}
            if unsafe_supply_chain and component["id"] == "processing-cli":
                supply_chain_report["auto_downloads"] = True
            (component_root / "security/security-report.json").write_text(
                json.dumps(security_report),
                encoding="utf-8",
            )
            (component_root / "supply-chain/supply-chain-report.json").write_text(
                json.dumps(supply_chain_report),
                encoding="utf-8",
            )
        return root

    def write_outputs(self, directory: str, *, omit_provider_marker: str | None = None) -> tuple[Path, Path, Path, Path]:
        module = load_report_module()
        output_dir = Path(directory)
        security_output = output_dir / "security.log"
        supply_chain_output = output_dir / "supply-chain.log"
        provider_output = output_dir / "provider.log"
        report_path = output_dir / "report.json"
        security_output.write_text("security-check passed.\n", encoding="utf-8")
        supply_chain_output.write_text("supply-chain-check passed: phase=current.\n", encoding="utf-8")
        markers = [
            marker
            for key, marker in module.EXPECTED_PROVIDER_MARKERS.items()
            if key != omit_provider_marker
        ]
        provider_output.write_text("\n".join(markers) + "\n", encoding="utf-8")
        return security_output, supply_chain_output, provider_output, report_path

    def test_build_report_writes_release_scope_security_supply_chain_evidence(self) -> None:
        module = load_report_module()
        with tempfile.TemporaryDirectory() as directory:
            root = self.write_root(directory)
            security_output, supply_chain_output, provider_output, report_path = self.write_outputs(directory)

            report = module.build_report(
                root,
                security_output_path=security_output,
                supply_chain_output_path=supply_chain_output,
                provider_output_path=provider_output,
                report_path=report_path,
                release_scope=True,
            )

            self.assertTrue(report["passed"])
            self.assertEqual(report["release_gate"], "release-scope-security-supply-chain")
            self.assertTrue(report["release_scope_security_supply_chain"])
            self.assertEqual(report["vs_ma"], ["VS-MA-22"])
            self.assertIn("PV-MA-007", report["pv"])
            self.assertTrue(report["not_release_readiness"])
            self.assertFalse(report["missing_provider_markers"])
            self.assertTrue(all(item["passed"] for item in report["security_reports"]))
            self.assertTrue(all(item["passed"] for item in report["supply_chain_reports"]))
            self.assertEqual(json.loads(report_path.read_text(encoding="utf-8")), report)

    def test_build_report_fails_closed_when_provider_marker_is_missing(self) -> None:
        module = load_report_module()
        with tempfile.TemporaryDirectory() as directory:
            root = self.write_root(directory)
            security_output, supply_chain_output, provider_output, report_path = self.write_outputs(
                directory,
                omit_provider_marker="model_provenance",
            )

            report = module.build_report(
                root,
                security_output_path=security_output,
                supply_chain_output_path=supply_chain_output,
                provider_output_path=provider_output,
                report_path=report_path,
                release_scope=True,
            )

            self.assertFalse(report["passed"])
            self.assertEqual(report["missing_provider_markers"], ["model_provenance"])
            self.assertIn("missing release-provider markers", report["findings"][0])

    def test_build_report_fails_closed_when_component_report_is_unsafe(self) -> None:
        module = load_report_module()
        with tempfile.TemporaryDirectory() as directory:
            root = self.write_root(directory, unsafe_supply_chain=True)
            security_output, supply_chain_output, provider_output, report_path = self.write_outputs(directory)

            report = module.build_report(
                root,
                security_output_path=security_output,
                supply_chain_output_path=supply_chain_output,
                provider_output_path=provider_output,
                report_path=report_path,
                release_scope=True,
            )

            self.assertFalse(report["passed"])
            self.assertIn("supply-chain report for processing-cli must set auto_downloads=False", report["findings"])

    def test_cli_writes_release_scope_report_and_marker(self) -> None:
        with tempfile.TemporaryDirectory() as directory:
            root = self.write_root(directory)
            security_output, supply_chain_output, provider_output, report_path = self.write_outputs(directory)
            result = subprocess.run(
                [
                    sys.executable,
                    str(ROOT / "platform/e2e/release_security_supply_chain_report.py"),
                    "--root",
                    str(root),
                    "--security-output",
                    str(security_output),
                    "--supply-chain-output",
                    str(supply_chain_output),
                    "--provider-output",
                    str(provider_output),
                    "--report",
                    str(report_path),
                    "--security-exit-code",
                    "0",
                    "--supply-chain-exit-code",
                    "0",
                    "--provider-exit-code",
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
            self.assertIn("release-scope-security-supply-chain", result.stdout)
            self.assertIn("release-scope security supply-chain gate passed", result.stdout)
            self.assertIn(str(report_path), result.stderr)
            self.assertTrue(report_path.is_file())


if __name__ == "__main__":
    unittest.main()
