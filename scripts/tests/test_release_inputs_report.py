from __future__ import annotations

import base64
import hashlib
import importlib.util
import json
import subprocess
import sys
import tempfile
import unittest
import zipfile
from pathlib import Path


ROOT = Path(__file__).resolve().parents[2]


def load_report_module():
    spec = importlib.util.spec_from_file_location(
        "release_inputs_report",
        ROOT / "scripts/release-inputs-report.py",
    )
    assert spec is not None
    module = importlib.util.module_from_spec(spec)
    assert spec.loader is not None
    spec.loader.exec_module(module)
    return module


class ReleaseInputsReportTests(unittest.TestCase):
    def write_release_archive(self, directory: Path, *, app_name: str = "MeetingAssistantNative.app") -> Path:
        archive_path = directory / "MeetingAssistantNative.zip"
        app_root = directory / "fixture-app" / app_name
        contents = app_root / "Contents"
        macos = contents / "MacOS"
        macos.mkdir(parents=True)
        (contents / "Info.plist").write_text(
            "<?xml version=\"1.0\" encoding=\"UTF-8\"?><plist version=\"1.0\"><dict /></plist>\n",
            encoding="utf-8",
        )
        executable = macos / "MeetingAssistantNative"
        executable.write_text("#!/bin/sh\nexit 0\n", encoding="utf-8")
        executable.chmod(0o755)
        with zipfile.ZipFile(archive_path, "w") as archive:
            for path in sorted(app_root.rglob("*")):
                archive.write(path, path.relative_to(app_root.parent))
        return archive_path

    def write_dsse_attestation(self, path: Path, *, bundle_name: str, bundle_digest: str) -> None:
        statement = {
            "_type": "https://in-toto.io/Statement/v1",
            "predicateType": "https://slsa.dev/provenance/v1",
            "subject": [
                {
                    "name": bundle_name,
                    "digest": {"sha256": bundle_digest.split(":", 1)[1]},
                }
            ],
            "predicate": {
                "buildDefinition": {
                    "buildType": "https://github.com/actions/workflow/meeting-assistant-release",
                },
                "runDetails": {
                    "builder": {"id": "github-actions-oidc"},
                },
            },
        }
        envelope = {
            "payloadType": "application/vnd.in-toto+json",
            "payload": base64.b64encode(json.dumps(statement).encode("utf-8")).decode("ascii"),
            "signatures": [{"keyid": "fixture", "sig": "fixture"}],
        }
        path.write_text(json.dumps(envelope), encoding="utf-8")

    def write_sigstore_bundle(self, path: Path) -> None:
        path.write_text(
            json.dumps({"mediaType": "application/vnd.dev.sigstore.bundle+json", "fixture": True}),
            encoding="utf-8",
        )

    def test_cli_materializes_digest_bound_release_input_reports(self) -> None:
        with tempfile.TemporaryDirectory() as directory:
            work = Path(directory)
            archive = self.write_release_archive(work)
            digest = "sha256:" + hashlib.sha256(archive.read_bytes()).hexdigest()
            attestation = work / "release-provenance.dsse.json"
            sigstore_bundle = work / "release-signature.sigstore-bundle.json"
            self.write_dsse_attestation(attestation, bundle_name=archive.name, bundle_digest=digest)
            self.write_sigstore_bundle(sigstore_bundle)
            output_dir = work / "inputs"

            result = subprocess.run(
                [
                    sys.executable,
                    str(ROOT / "scripts/release-inputs-report.py"),
                    "--root",
                    str(ROOT),
                    "--archive",
                    str(archive),
                    "--attestation",
                    str(attestation),
                    "--sigstore-bundle",
                    str(sigstore_bundle),
                    "--builder",
                    "github-actions-oidc",
                    "--source-repository",
                    "example/meeting_assistant",
                    "--signing-identity",
                    "Developer ID Application: Example",
                    "--notarization-ticket",
                    "ticket-id",
                    "--certificate-identity",
                    "https://github.com/example/meeting_assistant/.github/workflows/release.yml@refs/tags/v1",
                    "--certificate-issuer",
                    "https://token.actions.githubusercontent.com",
                    "--transparency-log-id",
                    "rekor-fixture",
                    "--transparency-log-index",
                    "42",
                    "--bundle-report",
                    str(output_dir / "bundle/release-bundle-report.json"),
                    "--provenance-report",
                    str(output_dir / "supply-chain/release-provenance-report.json"),
                    "--signature-report",
                    str(output_dir / "supply-chain/release-signature-report.json"),
                ],
                cwd=ROOT,
                capture_output=True,
                text=True,
                check=False,
            )

            self.assertEqual(result.returncode, 0, result.stderr + result.stdout)
            self.assertIn("release input reports materialized", result.stdout)
            bundle = json.loads((output_dir / "bundle/release-bundle-report.json").read_text(encoding="utf-8"))
            provenance = json.loads(
                (output_dir / "supply-chain/release-provenance-report.json").read_text(encoding="utf-8")
            )
            signature = json.loads(
                (output_dir / "supply-chain/release-signature-report.json").read_text(encoding="utf-8")
            )
            self.assertEqual(bundle["release_gate"], "release-bundle")
            self.assertEqual(bundle["bundle"]["digest"], digest)
            self.assertEqual(bundle["bundle"]["app_bundle"], "MeetingAssistantNative.app")
            self.assertFalse(bundle["bundle"]["packages_runtime_or_model"])
            self.assertEqual(provenance["artifacts"][0]["digest"], digest)
            self.assertEqual(provenance["attestation"]["digest"], "sha256:" + hashlib.sha256(attestation.read_bytes()).hexdigest())
            self.assertEqual(signature["signed_artifacts"][0]["digest"], digest)
            self.assertEqual(signature["signed_artifacts"][0]["signature_bundle"]["format"], "sigstore-bundle-json")

    def test_build_reports_fails_when_dsse_subject_digest_does_not_match_archive(self) -> None:
        module = load_report_module()
        with tempfile.TemporaryDirectory() as directory:
            work = Path(directory)
            archive = self.write_release_archive(work)
            attestation = work / "release-provenance.dsse.json"
            sigstore_bundle = work / "release-signature.sigstore-bundle.json"
            self.write_dsse_attestation(
                attestation,
                bundle_name=archive.name,
                bundle_digest="sha256:" + ("a" * 64),
            )
            self.write_sigstore_bundle(sigstore_bundle)

            args = module.parse_args(
                [
                    "--root",
                    str(ROOT),
                    "--archive",
                    str(archive),
                    "--attestation",
                    str(attestation),
                    "--sigstore-bundle",
                    str(sigstore_bundle),
                    "--builder",
                    "github-actions-oidc",
                    "--source-repository",
                    "example/meeting_assistant",
                    "--signing-identity",
                    "Developer ID Application: Example",
                    "--notarization-ticket",
                    "ticket-id",
                    "--certificate-identity",
                    "identity",
                    "--certificate-issuer",
                    "issuer",
                    "--transparency-log-id",
                    "rekor",
                    "--transparency-log-index",
                    "1",
                ]
            )

            with self.assertRaisesRegex(module.ReportError, "DSSE statement subject must include"):
                module.build_reports(args)

    def test_build_reports_fails_when_archive_does_not_contain_native_app(self) -> None:
        module = load_report_module()
        with tempfile.TemporaryDirectory() as directory:
            work = Path(directory)
            archive = self.write_release_archive(work, app_name="Other.app")
            digest = "sha256:" + hashlib.sha256(archive.read_bytes()).hexdigest()
            attestation = work / "release-provenance.dsse.json"
            sigstore_bundle = work / "release-signature.sigstore-bundle.json"
            self.write_dsse_attestation(attestation, bundle_name=archive.name, bundle_digest=digest)
            self.write_sigstore_bundle(sigstore_bundle)

            args = module.parse_args(
                [
                    "--root",
                    str(ROOT),
                    "--archive",
                    str(archive),
                    "--attestation",
                    str(attestation),
                    "--sigstore-bundle",
                    str(sigstore_bundle),
                    "--builder",
                    "github-actions-oidc",
                    "--source-repository",
                    "example/meeting_assistant",
                    "--signing-identity",
                    "Developer ID Application: Example",
                    "--notarization-ticket",
                    "ticket-id",
                    "--certificate-identity",
                    "identity",
                    "--certificate-issuer",
                    "issuer",
                    "--transparency-log-id",
                    "rekor",
                    "--transparency-log-index",
                    "1",
                ]
            )

            with self.assertRaisesRegex(module.ReportError, "must contain MeetingAssistantNative.app"):
                module.build_reports(args)


if __name__ == "__main__":
    unittest.main()
