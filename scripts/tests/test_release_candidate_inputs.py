from __future__ import annotations

import importlib.util
import json
import sys
import tempfile
import unittest
import zipfile
from pathlib import Path
from unittest import mock


ROOT = Path(__file__).resolve().parents[2]


def load_module():
    spec = importlib.util.spec_from_file_location(
        "release_candidate_inputs",
        ROOT / "scripts/release-candidate-inputs.py",
    )
    assert spec is not None
    module = importlib.util.module_from_spec(spec)
    assert spec.loader is not None
    spec.loader.exec_module(module)
    return module


def write_json(path: Path, payload: dict) -> None:
    path.parent.mkdir(parents=True, exist_ok=True)
    path.write_text(json.dumps(payload, indent=2, sort_keys=True) + "\n", encoding="utf-8")


def write_archive(path: Path) -> None:
    path.parent.mkdir(parents=True, exist_ok=True)
    with zipfile.ZipFile(path, "w") as archive:
        archive.writestr("MeetingAssistantNative.app/Contents/Info.plist", "<plist/>")


def write_bundle_report(path: Path, archive: Path, *, builder: str, source_repository: str) -> None:
    write_json(
        path,
        {
            "report_schema": 1,
            "release_gate": "release-bundle",
            "subject_commit": "a" * 40,
            "builder": builder,
            "source_repository": source_repository,
            "bundle": {
                "name": archive.name,
                "path": str(archive.resolve()),
                "digest": "sha256:" + ("1" * 64),
                "artifact_type": "macos-app-archive",
                "archive_format": "zip",
                "app_bundle": "MeetingAssistantNative.app",
                "build_configuration": "Release",
                "code_signed": True,
                "signing_identity": "Developer ID Application: Meeting Assistant Test (TEAMID1234)",
                "notarized": True,
                "notarization_ticket": "notary-submission-id",
                "stapled": True,
                "packages_runtime_or_model": False,
                "auto_downloads": False,
                "contains_meeting_data": False,
            },
        },
    )


class ReleaseCandidateInputsTests(unittest.TestCase):
    def test_release_candidate_inputs_runs_bundle_create_reports_and_gates(self) -> None:
        module = load_module()
        commands: list[list[str]] = []
        envs: list[dict[str, str] | None] = []

        with tempfile.TemporaryDirectory() as directory:
            work = Path(directory)
            archive = work / "MeetingAssistantNative-Release.zip"
            bundle_report = work / "bundle/release-bundle-report.json"
            provenance_report = work / "supply-chain/release-provenance-report.json"
            signature_report = work / "supply-chain/release-signature-report.json"
            sidecar_report = work / "supply-chain/release-sidecar-report.json"
            attestation = work / "release-provenance.dsse.json"
            sigstore_bundle = work / "release-signature.sigstore-bundle.json"
            attestation.write_text('{"payloadType":"application/vnd.in-toto+json"}\n', encoding="utf-8")
            sigstore_bundle.write_text('{"mediaType":"application/vnd.dev.sigstore.bundle+json"}\n', encoding="utf-8")
            write_json(sidecar_report, {"release_gate": "release-sidecar-portability"})

            def fake_run_command(command, label, *, cwd=None, env=None):
                commands.append(command)
                envs.append(env)
                if command[:2] == [sys.executable, str(ROOT / "scripts/release-bundle-create.py")]:
                    self.assertIn("--signing-identity", command)
                    self.assertIn("--notary-profile", command)
                    write_archive(archive)
                    write_bundle_report(
                        bundle_report,
                        archive,
                        builder="github-actions-oidc",
                        source_repository="example/meeting_assistant",
                    )
                    return "release bundle created\n"
                if command[:2] == [sys.executable, str(ROOT / "scripts/release-inputs-report.py")]:
                    self.assertIn("--verify-release-bundle", command)
                    self.assertIn("--archive", command)
                    self.assertIn(str(archive.resolve()), command)
                    self.assertIn("--attestation", command)
                    self.assertIn(str(attestation.resolve()), command)
                    self.assertIn("--sigstore-bundle", command)
                    self.assertIn(str(sigstore_bundle.resolve()), command)
                    self.assertIn("--notarization-ticket", command)
                    self.assertIn("notary-submission-id", command)
                    write_json(provenance_report, {"release_provenance_attestation": "produced"})
                    write_json(signature_report, {"signing_status": "signed"})
                    return "release input reports materialized\n"
                if command == [str(ROOT / "scripts/release-bundle-check.sh")]:
                    self.assertEqual(env["MEETING_ASSISTANT_RELEASE_BUNDLE_REPORT"], str(bundle_report.resolve()))
                    return "release-bundle-check passed\n"
                if command == [str(ROOT / "scripts/supply-chain-check.sh"), "release"]:
                    self.assertEqual(env["MEETING_ASSISTANT_RELEASE_PROVENANCE_REPORT"], str(provenance_report.resolve()))
                    self.assertEqual(env["MEETING_ASSISTANT_RELEASE_SIGNATURE_REPORT"], str(signature_report.resolve()))
                    self.assertEqual(env["MEETING_ASSISTANT_RELEASE_SIDECAR_REPORT"], str(sidecar_report.resolve()))
                    return "supply-chain-check passed\n"
                if command == ["git", "-C", str(ROOT), "rev-parse", "HEAD"]:
                    return "a" * 40 + "\n"
                raise AssertionError(f"unexpected command for {label}: {command}")

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
                    "--bundle-report",
                    str(bundle_report),
                    "--provenance-report",
                    str(provenance_report),
                    "--signature-report",
                    str(signature_report),
                    "--sidecar-report",
                    str(sidecar_report),
                    "--signing-identity",
                    "Developer ID Application: Meeting Assistant Test (TEAMID1234)",
                    "--notary-profile",
                    "meeting-assistant-notary",
                    "--builder",
                    "github-actions-oidc",
                    "--source-repository",
                    "example/meeting_assistant",
                    "--certificate-identity",
                    "https://github.com/example/meeting_assistant/.github/workflows/release.yml@refs/tags/v1",
                    "--certificate-issuer",
                    "https://token.actions.githubusercontent.com",
                    "--transparency-log-id",
                    "rekor-id",
                    "--transparency-log-index",
                    "42",
                ]
            )
            with mock.patch.object(module, "run_command", side_effect=fake_run_command):
                module.run_release_candidate_inputs(args)

            command_names = [" ".join(command[:2]) for command in commands]
            self.assertEqual(
                command_names[:4],
                [
                    f"{sys.executable} {ROOT / 'scripts/release-bundle-create.py'}",
                    f"{sys.executable} {ROOT / 'scripts/release-inputs-report.py'}",
                    str(ROOT / "scripts/release-bundle-check.sh"),
                    f"{ROOT / 'scripts/supply-chain-check.sh'} release",
                ],
            )

    def test_release_candidate_inputs_requires_attestation_before_bundle_create(self) -> None:
        module = load_module()
        with tempfile.TemporaryDirectory() as directory:
            work = Path(directory)
            sigstore_bundle = work / "release-signature.sigstore-bundle.json"
            sigstore_bundle.write_text("{}\n", encoding="utf-8")
            args = module.parse_args(
                [
                    "--root",
                    str(ROOT),
                    "--sigstore-bundle",
                    str(sigstore_bundle),
                    "--source-repository",
                    "example/meeting_assistant",
                ]
            )
            with mock.patch.object(module, "run_command") as run_command:
                with self.assertRaisesRegex(module.ReleaseCandidateInputsError, "DSSE/SLSA attestation is required"):
                    module.run_release_candidate_inputs(args)
                run_command.assert_not_called()

    def test_skip_bundle_create_uses_existing_bundle_report_defaults(self) -> None:
        module = load_module()
        commands: list[list[str]] = []
        with tempfile.TemporaryDirectory() as directory:
            work = Path(directory)
            archive = work / "MeetingAssistantNative-Release.zip"
            bundle_report = work / "bundle/release-bundle-report.json"
            provenance_report = work / "supply-chain/release-provenance-report.json"
            signature_report = work / "supply-chain/release-signature-report.json"
            sidecar_report = work / "supply-chain/release-sidecar-report.json"
            attestation = work / "release-provenance.dsse.json"
            sigstore_bundle = work / "release-signature.sigstore-bundle.json"
            write_archive(archive)
            write_bundle_report(
                bundle_report,
                archive,
                builder="bundle-report-builder",
                source_repository="bundle/report/repo",
            )
            attestation.write_text('{"payloadType":"application/vnd.in-toto+json"}\n', encoding="utf-8")
            sigstore_bundle.write_text('{"mediaType":"application/vnd.dev.sigstore.bundle+json"}\n', encoding="utf-8")
            write_json(sidecar_report, {"release_gate": "release-sidecar-portability"})

            def fake_run_command(command, label, *, cwd=None, env=None):
                commands.append(command)
                if command[:2] == [sys.executable, str(ROOT / "scripts/release-inputs-report.py")]:
                    self.assertNotIn(str(ROOT / "scripts/release-bundle-create.py"), " ".join(command))
                    self.assertIn("bundle-report-builder", command)
                    self.assertIn("bundle/report/repo", command)
                    self.assertIn("Developer ID Application: Meeting Assistant Test (TEAMID1234)", command)
                    self.assertIn("notary-submission-id", command)
                    write_json(provenance_report, {"release_provenance_attestation": "produced"})
                    write_json(signature_report, {"signing_status": "signed"})
                    return "release input reports materialized\n"
                if command == [str(ROOT / "scripts/release-bundle-check.sh")]:
                    return "release-bundle-check passed\n"
                if command == [str(ROOT / "scripts/supply-chain-check.sh"), "release"]:
                    return "supply-chain-check passed\n"
                if command == ["git", "-C", str(ROOT), "rev-parse", "HEAD"]:
                    return "a" * 40 + "\n"
                raise AssertionError(f"unexpected command for {label}: {command}")

            args = module.parse_args(
                [
                    "--root",
                    str(ROOT),
                    "--skip-bundle-create",
                    "--archive",
                    str(archive),
                    "--attestation",
                    str(attestation),
                    "--sigstore-bundle",
                    str(sigstore_bundle),
                    "--bundle-report",
                    str(bundle_report),
                    "--provenance-report",
                    str(provenance_report),
                    "--signature-report",
                    str(signature_report),
                    "--sidecar-report",
                    str(sidecar_report),
                    "--certificate-identity",
                    "https://github.com/example/meeting_assistant/.github/workflows/release.yml@refs/tags/v1",
                    "--certificate-issuer",
                    "https://token.actions.githubusercontent.com",
                    "--transparency-log-id",
                    "rekor-id",
                    "--transparency-log-index",
                    "42",
                ]
            )
            with mock.patch.object(module, "run_command", side_effect=fake_run_command):
                module.run_release_candidate_inputs(args)

            self.assertFalse(
                any(str(ROOT / "scripts/release-bundle-create.py") in " ".join(command) for command in commands)
            )


if __name__ == "__main__":
    unittest.main()
