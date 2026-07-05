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
        "release_sidecar_target_smoke_report",
        ROOT / "platform/e2e/release_sidecar_target_smoke_report.py",
    )
    assert spec is not None
    module = importlib.util.module_from_spec(spec)
    assert spec.loader is not None
    spec.loader.exec_module(module)
    return module


class ReleaseSidecarTargetSmokeReportTests(unittest.TestCase):
    def write_sidecar_files(self, directory: str) -> dict[str, Path]:
        root = Path(directory)
        asset_root = root / "home" / ".local"
        runtime = asset_root / "bin" / "whisper-cli"
        model = asset_root / "share" / "ai-models" / "whisper.cpp" / "large-v3-turbo" / "ggml-large-v3-turbo-q5_0.bin"
        audio = asset_root / "share" / "ai-fixtures" / "asr" / "zh-en-tech" / "mixed-zh-en-tech.wav"
        license_file = Path(str(model) + ".license.txt")
        provenance_file = Path(str(model) + ".provenance.json")
        for path, content in (
            (runtime, "#!/bin/sh\nexit 0\n"),
            (model, "model bytes"),
            (audio, "RIFFfixture"),
            (license_file, "Apache-2.0 fixture license\n"),
            (provenance_file, '{"source":"fixture","model":"large-v3-turbo","license":"Apache-2.0"}\n'),
        ):
            path.parent.mkdir(parents=True, exist_ok=True)
            path.write_text(content, encoding="utf-8")
        runtime.chmod(0o755)
        return {
            "runtime": runtime,
            "model": model,
            "audio": audio,
            "license": license_file,
            "provenance": provenance_file,
        }

    def write_provider_output(self, directory: str, *, omit_marker: str | None = None) -> Path:
        module = load_report_module()
        output = Path(directory) / "provider.log"
        markers = [
            marker
            for key, marker in module.EXPECTED_PROVIDER_MARKERS.items()
            if key != omit_marker
        ]
        output.write_text("\n".join(markers) + "\n", encoding="utf-8")
        return output

    def test_build_report_writes_digest_bound_target_smoke(self) -> None:
        module = load_report_module()
        with tempfile.TemporaryDirectory() as directory:
            files = self.write_sidecar_files(directory)
            provider_output = self.write_provider_output(directory)
            report_path = Path(directory) / "report.json"

            report = module.build_report(
                ROOT,
                provider_output_path=provider_output,
                report_path=report_path,
                target_id="macos-arm64-local",
                target_os="macos",
                architecture="arm64",
                runtime_path=str(files["runtime"]),
                model_path=str(files["model"]),
                smoke_audio_path=str(files["audio"]),
                model_license_file=str(files["license"]),
                model_provenance_file=str(files["provenance"]),
            )

            self.assertTrue(report["passed"], report["findings"])
            self.assertEqual(report["release_gate"], "release-sidecar-target-smoke")
            self.assertEqual(report["target_id"], "macos-arm64-local")
            self.assertFalse(report["packages_runtime_or_model"])
            self.assertFalse(report["auto_downloads"])
            self.assertFalse(report["external_network_access"])
            self.assertTrue(report["smoke"]["check_dependencies_ok"])
            self.assertTrue(report["smoke"]["whisper_cpp_smoke_passed"])
            self.assertTrue(report["smoke"]["no_auto_downloads_observed"])
            self.assertEqual(report["artifacts"]["runtime"]["name"], "whisper-cli")
            self.assertTrue(report["artifacts"]["model"]["digest"].startswith("sha256:"))
            self.assertIn("license_ref", report["artifacts"]["model"])
            self.assertTrue(report["not_release_readiness"])
            self.assertEqual(json.loads(report_path.read_text(encoding="utf-8")), report)

    def test_build_report_fails_closed_when_provider_marker_is_missing(self) -> None:
        module = load_report_module()
        with tempfile.TemporaryDirectory() as directory:
            files = self.write_sidecar_files(directory)
            provider_output = self.write_provider_output(directory, omit_marker="model_provenance")

            report = module.build_report(
                ROOT,
                provider_output_path=provider_output,
                provider_exit_code=0,
                runtime_path=str(files["runtime"]),
                model_path=str(files["model"]),
                smoke_audio_path=str(files["audio"]),
                model_license_file=str(files["license"]),
                model_provenance_file=str(files["provenance"]),
            )

            self.assertFalse(report["passed"])
            self.assertEqual(report["missing_provider_markers"], ["model_provenance"])
            self.assertIn("missing release-provider markers", report["findings"][0])

    def test_build_report_fails_closed_for_non_local_asset_path(self) -> None:
        module = load_report_module()
        with tempfile.TemporaryDirectory() as directory:
            files = self.write_sidecar_files(directory)
            outside_runtime = Path(directory) / "runtime" / "whisper-cli"
            outside_runtime.parent.mkdir()
            outside_runtime.write_text("#!/bin/sh\n", encoding="utf-8")
            provider_output = self.write_provider_output(directory)

            report = module.build_report(
                ROOT,
                provider_output_path=provider_output,
                provider_exit_code=0,
                runtime_path=str(outside_runtime),
                model_path=str(files["model"]),
                smoke_audio_path=str(files["audio"]),
                model_license_file=str(files["license"]),
                model_provenance_file=str(files["provenance"]),
            )

            self.assertFalse(report["passed"])
            self.assertTrue(any("runtime must be under a user .local root" in item for item in report["findings"]))

    def test_cli_writes_report_and_marker(self) -> None:
        with tempfile.TemporaryDirectory() as directory:
            files = self.write_sidecar_files(directory)
            provider_output = self.write_provider_output(directory)
            report_path = Path(directory) / "report.json"
            result = subprocess.run(
                [
                    sys.executable,
                    str(ROOT / "platform/e2e/release_sidecar_target_smoke_report.py"),
                    "--root",
                    str(ROOT),
                    "--provider-output",
                    str(provider_output),
                    "--report",
                    str(report_path),
                    "--provider-exit-code",
                    "0",
                    "--target-id",
                    "macos arm64 local",
                    "--target-os",
                    "macos",
                    "--architecture",
                    "arm64",
                    "--runtime",
                    str(files["runtime"]),
                    "--model",
                    str(files["model"]),
                    "--smoke-audio",
                    str(files["audio"]),
                    "--model-license-file",
                    str(files["license"]),
                    "--model-provenance-file",
                    str(files["provenance"]),
                ],
                cwd=ROOT,
                env=os.environ.copy(),
                capture_output=True,
                text=True,
                check=False,
            )

            self.assertEqual(result.returncode, 0, result.stderr + result.stdout)
            self.assertIn("release-sidecar-target-smoke", result.stdout)
            self.assertIn(str(report_path), result.stderr)
            report = json.loads(report_path.read_text(encoding="utf-8"))
            self.assertEqual(report["target_id"], "macos-arm64-local")


if __name__ == "__main__":
    unittest.main()
