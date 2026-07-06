from __future__ import annotations

import importlib.util
import json
import os
import sys
import tempfile
import unittest
import zipfile
from pathlib import Path
from unittest import mock


ROOT = Path(__file__).resolve().parents[2]


def load_module():
    spec = importlib.util.spec_from_file_location(
        "release_bundle_create",
        ROOT / "scripts/release-bundle-create.py",
    )
    assert spec is not None
    module = importlib.util.module_from_spec(spec)
    assert spec.loader is not None
    spec.loader.exec_module(module)
    return module


class ReleaseBundleCreateTests(unittest.TestCase):
    def test_create_release_bundle_defaults_to_local_direct_and_writes_report(self) -> None:
        module = load_module()
        commands: list[list[str]] = []

        with tempfile.TemporaryDirectory() as directory:
            work = Path(directory)
            output = work / "MeetingAssistantNative-Release.zip"
            report_path = work / "release-bundle-report.json"
            derived_data = work / "DerivedData"

            def write_app_archive(path: Path) -> None:
                path.parent.mkdir(parents=True, exist_ok=True)
                with zipfile.ZipFile(path, "w") as archive:
                    archive.writestr("MeetingAssistantNative.app/Contents/Info.plist", "<plist/>")
                    archive.writestr("MeetingAssistantNative.app/Contents/MacOS/MeetingAssistantNative", "binary")

            def fake_run_command(command, label, *, cwd=None, env=None):
                commands.append(command)
                if command[:3] == ["git", "-C", str(ROOT)] and command[3:] == ["rev-parse", "HEAD"]:
                    return "c" * 40 + "\n"
                if command and command[0] == "xcodebuild":
                    self.assertIn("CODE_SIGN_STYLE=Manual", command)
                    self.assertIn("CODE_SIGN_IDENTITY=-", command)
                    self.assertNotIn("OTHER_CODE_SIGN_FLAGS=--timestamp", command)
                    app = derived_data / "Build/Products/Release/MeetingAssistantNative.app"
                    (app / "Contents/MacOS").mkdir(parents=True)
                    (app / "Contents/Info.plist").write_text("<plist/>", encoding="utf-8")
                    (app / "Contents/MacOS/MeetingAssistantNative").write_text("binary", encoding="utf-8")
                    return "built\n"
                if command[:2] == ["/usr/bin/codesign", "--verify"]:
                    return ""
                if command[:3] == ["/usr/bin/codesign", "-dv", "--verbose=4"]:
                    return "CodeDirectory flags=0x2(adhoc)\n"
                if command[:2] == ["/usr/bin/ditto", "-c"]:
                    write_app_archive(Path(command[-1]))
                    return ""
                if command == [str(ROOT / "scripts/release-bundle-check.sh")]:
                    self.assertEqual(env["MEETING_ASSISTANT_RELEASE_BUNDLE_REPORT"], str(report_path.resolve()))
                    return "release-bundle-check passed.\n"
                raise AssertionError(f"unexpected command for {label}: {command}")

            args = module.parse_args(
                [
                    "--root",
                    str(ROOT),
                    "--source-repository",
                    "example/meeting_assistant",
                    "--builder",
                    "local-release-rehearsal",
                    "--derived-data-path",
                    str(derived_data),
                    "--output",
                    str(output),
                    "--report",
                    str(report_path),
                ]
            )
            with mock.patch.object(module, "run_command", side_effect=fake_run_command):
                report = module.create_release_bundle(args)

            written = json.loads(report_path.read_text(encoding="utf-8"))
            self.assertEqual(report, written)
            self.assertEqual(written["release_gate"], "release-bundle")
            self.assertEqual(written["subject_commit"], "c" * 40)
            bundle = written["bundle"]
            self.assertEqual(bundle["distribution_mode"], "local-direct")
            self.assertEqual(bundle["install_method"], "direct-local-app")
            self.assertEqual(bundle["signing_identity"], "ad-hoc-local")
            self.assertFalse(bundle["notarized"])
            self.assertEqual(bundle["notarization_ticket"], "not-applicable")
            self.assertFalse(bundle["stapled"])
            self.assertFalse(bundle["packages_runtime_or_model"])
            self.assertFalse(bundle["auto_downloads"])
            self.assertFalse(bundle["contains_meeting_data"])
            self.assertFalse(
                any(str(ROOT / "scripts/release-credential-check.py") in " ".join(command) for command in commands)
            )
            self.assertFalse(any(command[:3] == ["/usr/bin/xcrun", "notarytool", "submit"] for command in commands))

    def test_create_developer_id_release_bundle_runs_notary_staple_and_writes_report(self) -> None:
        module = load_module()
        identity = "Developer ID Application: Meeting Assistant Test (TEAMID1234)"
        commands: list[list[str]] = []

        with tempfile.TemporaryDirectory() as directory:
            work = Path(directory)
            output = work / "MeetingAssistantNative-Release.zip"
            report_path = work / "release-bundle-report.json"
            derived_data = work / "DerivedData"
            notary_archive = work / "MeetingAssistantNative-for-notary.zip"

            def write_app_archive(path: Path) -> None:
                path.parent.mkdir(parents=True, exist_ok=True)
                with zipfile.ZipFile(path, "w") as archive:
                    archive.writestr("MeetingAssistantNative.app/Contents/Info.plist", "<plist/>")
                    archive.writestr("MeetingAssistantNative.app/Contents/MacOS/MeetingAssistantNative", "binary")

            def fake_run_command(command, label, *, cwd=None, env=None):
                commands.append(command)
                if command[:3] == ["git", "-C", str(ROOT)] and command[3:] == ["rev-parse", "HEAD"]:
                    return "a" * 40 + "\n"
                if (
                    command[:2] == [sys.executable, str(ROOT / "scripts/release-credential-check.py")]
                    and "--identity-pattern" in command
                ):
                    self.assertIn(identity, command)
                    return "release credential prerequisite check passed.\n"
                if command and command[0] == "xcodebuild":
                    self.assertIn("CODE_SIGN_STYLE=Manual", command)
                    self.assertIn(f"CODE_SIGN_IDENTITY={identity}", command)
                    self.assertIn("OTHER_CODE_SIGN_FLAGS=--timestamp", command)
                    app = derived_data / "Build/Products/Release/MeetingAssistantNative.app"
                    (app / "Contents/MacOS").mkdir(parents=True)
                    (app / "Contents/Info.plist").write_text("<plist/>", encoding="utf-8")
                    (app / "Contents/MacOS/MeetingAssistantNative").write_text("binary", encoding="utf-8")
                    return "built\n"
                if command[:2] == ["/usr/bin/codesign", "--verify"]:
                    return ""
                if command[:3] == ["/usr/bin/codesign", "-dv", "--verbose=4"]:
                    return f"Authority={identity}\nSignature=Developer ID\n"
                if command[:2] == ["/usr/bin/ditto", "-c"]:
                    write_app_archive(Path(command[-1]))
                    return ""
                if command[:3] == ["/usr/bin/xcrun", "notarytool", "submit"]:
                    self.assertIn(str(notary_archive.resolve()), command)
                    self.assertIn("--keychain-profile", command)
                    self.assertIn("meeting-assistant-notary", command)
                    return "id: 01234567-89AB-CDEF-0123-456789ABCDEF\nstatus: Accepted\n"
                if command[:3] == ["/usr/bin/xcrun", "stapler", "staple"]:
                    return "stapled\n"
                if command[:3] == ["/usr/bin/xcrun", "stapler", "validate"]:
                    return "accepted\n"
                if command[:4] == ["/usr/sbin/spctl", "-a", "-t", "exec"]:
                    return "accepted\n"
                if command == [str(ROOT / "scripts/release-bundle-check.sh")]:
                    self.assertEqual(env["MEETING_ASSISTANT_RELEASE_BUNDLE_REPORT"], str(report_path.resolve()))
                    return "release-bundle-check passed.\n"
                raise AssertionError(f"unexpected command for {label}: {command}")

            args = module.parse_args(
                [
                    "--root",
                    str(ROOT),
                    "--source-repository",
                    "example/meeting_assistant",
                    "--distribution-mode",
                    "developer-id",
                    "--signing-identity",
                    identity,
                    "--notary-profile",
                    "meeting-assistant-notary",
                    "--builder",
                    "github-actions-oidc",
                    "--derived-data-path",
                    str(derived_data),
                    "--notary-archive",
                    str(notary_archive),
                    "--output",
                    str(output),
                    "--report",
                    str(report_path),
                ]
            )
            with mock.patch.object(module, "run_command", side_effect=fake_run_command):
                report = module.create_release_bundle(args)

            self.assertTrue(output.is_file())
            self.assertTrue(report_path.is_file())
            written = json.loads(report_path.read_text(encoding="utf-8"))
            self.assertEqual(report, written)
            self.assertEqual(written["release_gate"], "release-bundle")
            self.assertEqual(written["subject_commit"], "a" * 40)
            self.assertEqual(written["builder"], "github-actions-oidc")
            self.assertEqual(written["source_repository"], "example/meeting_assistant")
            bundle = written["bundle"]
            self.assertEqual(bundle["name"], "MeetingAssistantNative-Release.zip")
            self.assertEqual(bundle["path"], str(output.resolve()))
            self.assertRegex(bundle["digest"], r"^sha256:[a-f0-9]{64}$")
            self.assertEqual(bundle["archive_format"], "zip")
            self.assertEqual(bundle["build_configuration"], "Release")
            self.assertTrue(bundle["code_signed"])
            self.assertEqual(bundle["distribution_mode"], "developer-id")
            self.assertEqual(bundle["install_method"], "developer-id-zip")
            self.assertEqual(bundle["signing_identity"], identity)
            self.assertTrue(bundle["notarized"])
            self.assertEqual(bundle["notarization_ticket"], "01234567-89AB-CDEF-0123-456789ABCDEF")
            self.assertTrue(bundle["stapled"])
            self.assertFalse(bundle["packages_runtime_or_model"])
            self.assertFalse(bundle["auto_downloads"])
            self.assertFalse(bundle["contains_meeting_data"])

            command_names = [" ".join(command[:3]) for command in commands]
            self.assertIn("xcodebuild build -configuration", command_names)
            self.assertIn("/usr/bin/xcrun notarytool submit", command_names)
            self.assertIn("/usr/bin/xcrun stapler staple", command_names)
            self.assertIn("/usr/bin/xcrun stapler validate", command_names)

    def test_create_release_bundle_requires_identity_and_notary_profile(self) -> None:
        module = load_module()
        with mock.patch.dict(os.environ, {}, clear=True):
            args = module.parse_args(
                [
                    "--root",
                    str(ROOT),
                    "--source-repository",
                    "example/repo",
                    "--distribution-mode",
                    "developer-id",
                ]
            )

        with self.assertRaisesRegex(module.ReleaseBundleError, "release signing identity is required"):
            module.create_release_bundle(args)

        args = module.parse_args(
            [
                "--root",
                str(ROOT),
                "--source-repository",
                "example/repo",
                "--distribution-mode",
                "developer-id",
                "--signing-identity",
                "Developer ID Application: Meeting Assistant Test (TEAMID1234)",
            ]
        )
        with self.assertRaisesRegex(module.ReleaseBundleError, "notarytool keychain profile is required"):
            module.create_release_bundle(args)

    def test_create_release_bundle_rejects_failed_notarization(self) -> None:
        module = load_module()
        identity = "Developer ID Application: Meeting Assistant Test (TEAMID1234)"

        with tempfile.TemporaryDirectory() as directory:
            work = Path(directory)
            derived_data = work / "DerivedData"
            output = work / "MeetingAssistantNative-Release.zip"
            report_path = work / "release-bundle-report.json"
            notary_archive = work / "MeetingAssistantNative-for-notary.zip"

            def write_app_archive(path: Path) -> None:
                path.parent.mkdir(parents=True, exist_ok=True)
                with zipfile.ZipFile(path, "w") as archive:
                    archive.writestr("MeetingAssistantNative.app/Contents/Info.plist", "<plist/>")

            def fake_run_command(command, label, *, cwd=None, env=None):
                if command[:3] == ["git", "-C", str(ROOT)] and command[3:] == ["rev-parse", "HEAD"]:
                    return "b" * 40 + "\n"
                if command[:2] == [sys.executable, str(ROOT / "scripts/release-credential-check.py")]:
                    return "release credential prerequisite check passed.\n"
                if command and command[0] == "xcodebuild":
                    app = derived_data / "Build/Products/Release/MeetingAssistantNative.app"
                    (app / "Contents").mkdir(parents=True)
                    (app / "Contents/Info.plist").write_text("<plist/>", encoding="utf-8")
                    return "built\n"
                if command[:2] == ["/usr/bin/codesign", "--verify"]:
                    return ""
                if command[:3] == ["/usr/bin/codesign", "-dv", "--verbose=4"]:
                    return f"Authority={identity}\nSignature=Developer ID\n"
                if command[:2] == ["/usr/bin/ditto", "-c"]:
                    write_app_archive(Path(command[-1]))
                    return ""
                if command[:3] == ["/usr/bin/xcrun", "notarytool", "submit"]:
                    return "id: 11111111-1111-1111-1111-111111111111\nstatus: Invalid\n"
                raise AssertionError(f"unexpected command for {label}: {command}")

            args = module.parse_args(
                [
                    "--root",
                    str(ROOT),
                    "--source-repository",
                    "example/meeting_assistant",
                    "--distribution-mode",
                    "developer-id",
                    "--signing-identity",
                    identity,
                    "--notary-profile",
                    "meeting-assistant-notary",
                    "--derived-data-path",
                    str(derived_data),
                    "--notary-archive",
                    str(notary_archive),
                    "--output",
                    str(output),
                    "--report",
                    str(report_path),
                ]
            )
            with mock.patch.object(module, "run_command", side_effect=fake_run_command):
                with self.assertRaisesRegex(
                    module.ReleaseBundleError,
                    "notarytool submission must be Accepted",
                ):
                    module.create_release_bundle(args)

            self.assertFalse(report_path.exists())


if __name__ == "__main__":
    unittest.main()
