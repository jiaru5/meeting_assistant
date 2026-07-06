from __future__ import annotations

import importlib.util
import subprocess
import tempfile
import unittest
from pathlib import Path
from unittest import mock


ROOT = Path(__file__).resolve().parents[2]


def load_credential_module():
    spec = importlib.util.spec_from_file_location(
        "release_credential_check",
        ROOT / "scripts/release-credential-check.py",
    )
    assert spec is not None
    module = importlib.util.module_from_spec(spec)
    assert spec.loader is not None
    spec.loader.exec_module(module)
    return module


class ReleaseCredentialCheckTests(unittest.TestCase):
    def test_parse_codesigning_identities_finds_valid_count_and_identity_names(self) -> None:
        module = load_credential_module()
        valid_count, identities = module.parse_codesigning_identities(
            """
  1) ABCDEF0123456789 "Apple Development: Example (ABCDE12345)"
  2) 0123456789ABCDEF "Developer ID Application: Example Org (ABCDE12345)"
     2 valid identities found
"""
        )

        self.assertEqual(valid_count, 2)
        self.assertIn("Developer ID Application: Example Org (ABCDE12345)", identities)

    def test_build_report_passes_when_release_tools_and_developer_id_identity_exist(self) -> None:
        module = load_credential_module()
        args = module.parse_args(["--root", str(ROOT)])

        def fake_run(command, **kwargs):
            if command[:3] == ["git", "-C", str(ROOT)]:
                return subprocess.CompletedProcess(command, 0, "a" * 40 + "\n", "")
            if command == ["/usr/bin/xcrun", "--find", "notarytool"]:
                return subprocess.CompletedProcess(command, 0, "/usr/bin/notarytool\n", "")
            if command == ["/usr/bin/xcrun", "--find", "stapler"]:
                return subprocess.CompletedProcess(command, 0, "/usr/bin/stapler\n", "")
            if command == ["security", "find-identity", "-v", "-p", "codesigning"]:
                return subprocess.CompletedProcess(
                    command,
                    0,
                    '  1) ABC "Developer ID Application: Example Org (ABCDE12345)"\n'
                    "     1 valid identities found\n",
                    "",
                )
            self.fail(f"unexpected command: {command}")

        with (
            mock.patch.object(module.subprocess, "run", side_effect=fake_run),
            mock.patch.object(module.os.path, "isfile", return_value=True),
            mock.patch.object(module.os, "access", return_value=True),
        ):
            report = module.build_report(args)

        self.assertTrue(report["passed"])
        self.assertEqual(report["release_gate"], "release-credential-prereq")
        self.assertTrue(report["not_release_readiness"])
        self.assertEqual(
            report["checks"]["codesigning_identity"]["matched_identities"],
            ["Developer ID Application: Example Org (ABCDE12345)"],
        )

    def test_build_report_fails_without_developer_id_identity(self) -> None:
        module = load_credential_module()
        args = module.parse_args(["--root", str(ROOT)])

        def fake_run(command, **kwargs):
            if command[:3] == ["git", "-C", str(ROOT)]:
                return subprocess.CompletedProcess(command, 0, "a" * 40 + "\n", "")
            if command in (
                ["/usr/bin/xcrun", "--find", "notarytool"],
                ["/usr/bin/xcrun", "--find", "stapler"],
            ):
                return subprocess.CompletedProcess(command, 0, "ok\n", "")
            if command == ["security", "find-identity", "-v", "-p", "codesigning"]:
                return subprocess.CompletedProcess(command, 0, "     0 valid identities found\n", "")
            self.fail(f"unexpected command: {command}")

        with (
            mock.patch.object(module.subprocess, "run", side_effect=fake_run),
            mock.patch.object(module.os.path, "isfile", return_value=True),
            mock.patch.object(module.os, "access", return_value=True),
        ):
            report = module.build_report(args)

        self.assertFalse(report["passed"])
        self.assertIn("valid identities found: 0", "\n".join(report["failures"]))

    def test_main_writes_failure_report(self) -> None:
        module = load_credential_module()
        with tempfile.TemporaryDirectory() as directory:
            report_path = Path(directory) / "release-credential-report.json"

            def fake_build_report(args):
                return {
                    "report_schema": 1,
                    "release_gate": "release-credential-prereq",
                    "subject_commit": "a" * 40,
                    "root": str(ROOT),
                    "passed": False,
                    "not_release_readiness": True,
                    "checks": {},
                    "failures": ["missing identity"],
                }

            with mock.patch.object(module, "build_report", side_effect=fake_build_report):
                result = module.main(["--root", str(ROOT), "--report", str(report_path)])

            self.assertEqual(result, 1)
            self.assertIn("missing identity", report_path.read_text(encoding="utf-8"))


if __name__ == "__main__":
    unittest.main()
