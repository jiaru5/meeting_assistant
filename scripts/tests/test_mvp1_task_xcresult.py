from __future__ import annotations

import base64
import hashlib
import importlib.util
import json
import os
import plistlib
import re
import signal
import stat
import struct
import subprocess
import tempfile
import time
import unittest
import zlib
from pathlib import Path


REPO_ROOT = Path(__file__).resolve().parents[2]
VERIFIER = REPO_ROOT / "scripts" / "mvp1-task-xcresult.py"
TASK_SOURCE = (
    REPO_ROOT
    / "platform"
    / "native-app"
    / "UITests"
    / "MeetingAssistantNativeAppUITests"
    / "DesignedNativeShellAppBundleTests.swift"
)
WRAPPER = REPO_ROOT / "platform" / "native-app" / "scripts" / "test-app-bundle.sh"
METHOD_PATTERN = re.compile(r"^\s*func\s+(test[A-Za-z0-9_]+)\s*\(", re.MULTILINE)
SCREENSHOTS = (
    "00-meetings-recent",
    "01-meetings-empty",
    "02-new-recording-ready",
    "03-recording-live",
    "04-recording-saved",
    "05-processing",
    "06-transcript-ready",
    "07-diagnostics",
)
PNG = base64.b64decode(
    "iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAQAAAC1HAwCAAAAC0lEQVR42mNk+A8AAQUBAScY42YAAAAASUVORK5CYII="
)


def png_with_crc_valid_broken_idat(payload: bytes) -> bytes:
    result = bytearray(payload[:8])
    offset = 8
    while offset < len(payload):
        length = struct.unpack(">I", payload[offset : offset + 4])[0]
        chunk_type = payload[offset + 4 : offset + 8]
        data_start = offset + 8
        data_end = data_start + length
        data = payload[data_start:data_end]
        if chunk_type == b"IDAT":
            data = b"not-a-zlib-stream"
        result.extend(struct.pack(">I", len(data)))
        result.extend(chunk_type)
        result.extend(data)
        result.extend(struct.pack(">I", zlib.crc32(data, zlib.crc32(chunk_type)) & 0xFFFFFFFF))
        offset = data_end + 4
    return bytes(result)


class MVP1TaskXCResultTests(unittest.TestCase):
    def setUp(self) -> None:
        self.temporary_directory = tempfile.TemporaryDirectory()
        self.root = Path(self.temporary_directory.name)
        self.derived_data = self.root / "DerivedData" / "AppBundleUITests"
        self.derived_data.mkdir(parents=True)
        self.xcresult = self.derived_data / "reports" / "xcresult" / "task-workflow" / "run" / "attempt-1.xcresult"
        self.xcresult.mkdir(parents=True)
        self.app = self._make_bundle("MeetingAssistantNative.app", "local.meeting-assistant.native")
        self.runner = self._make_bundle(
            "MeetingAssistantNativeAppUITests-Runner.app",
            "local.meeting-assistant.native.ui-runner",
        )
        test_bundle = self.runner / "Contents" / "PlugIns" / "MeetingAssistantNativeAppUITests.xctest"
        self._populate_bundle(
            test_bundle,
            "local.meeting-assistant.native.ui-tests",
            "MeetingAssistantNativeAppUITests",
        )
        self.xctestrun = self.derived_data / "Build" / "Products" / "fixture.xctestrun"
        with self.xctestrun.open("wb") as handle:
            plistlib.dump(
                {
                    "__xctestrun_metadata__": {"FormatVersion": 1},
                    "MeetingAssistantNativeAppUITests": {
                        "BlueprintName": "MeetingAssistantNativeAppUITests",
                        "IsUITestBundle": True,
                        "TestHostPath": "__TESTROOT__/Debug/MeetingAssistantNativeAppUITests-Runner.app",
                        "TestHostBundleIdentifier": "local.meeting-assistant.native.ui-runner",
                        "TestBundlePath": (
                            "__TESTHOST__/Contents/PlugIns/MeetingAssistantNativeAppUITests.xctest"
                        ),
                        "UITargetAppPath": "__TESTROOT__/Debug/MeetingAssistantNative.app",
                        "BundleIdentifiersForCrashReportEmphasis": [
                            "local.meeting-assistant.native",
                            "local.meeting-assistant.native.ui-runner",
                        ],
                    },
                },
                handle,
            )
        spec = importlib.util.spec_from_file_location("mvp1_task_xcresult", VERIFIER)
        assert spec is not None and spec.loader is not None
        self.verifier_module = importlib.util.module_from_spec(spec)
        spec.loader.exec_module(self.verifier_module)
        self.frozen_verifier = self.derived_data / "reports" / "frozen" / "mvp1-task-xcresult.py"
        self.frozen_verifier.parent.mkdir(parents=True)
        self.frozen_verifier.write_bytes(VERIFIER.read_bytes())
        self.frozen_verifier.chmod(0o400)
        self.verifier_sha256 = hashlib.sha256(self.frozen_verifier.read_bytes()).hexdigest()
        self.fake_xcodebuild = self.root / "fake-xcodebuild"
        self.fake_xcodebuild.write_text(
            "#!/bin/sh\nprintf 'Xcode Test\\nBuild version TEST\\n'\n",
            encoding="utf-8",
        )
        self.fake_xcodebuild.chmod(0o755)
        self.destination = "platform=macOS"
        self.subject_commit = subprocess.run(
            ["/usr/bin/git", "-C", str(REPO_ROOT), "rev-parse", "HEAD"],
            check=True,
            capture_output=True,
            text=True,
        ).stdout.strip()
        self.fingerprint = self.verifier_module.compute_current_input_fingerprint(
            repo_root=REPO_ROOT,
            destination=self.destination,
            git_tool="/usr/bin/git",
            xcodebuild_tool=str(self.fake_xcodebuild),
        )
        self.fingerprint_path = self.derived_data / ".meeting-assistant-xctestrun-inputs.sha256"
        self.fingerprint_path.write_text(self.fingerprint + "\n", encoding="utf-8")
        self.fake_codesign = self.root / "fake-codesign"
        self.fake_codesign.write_text(
            "#!/bin/sh\necho 'CDHash=0123456789abcdef0123456789abcdef01234567' >&2\n",
            encoding="utf-8",
        )
        self.fake_codesign.chmod(0o755)
        self.artifact_binding_path = self.derived_data / "task-artifacts-before-test.json"
        self.artifact_binding_path.write_text(
            json.dumps(
                self.verifier_module.capture_artifact_binding(
                    xctestrun_path=self.xctestrun,
                    app_path=self.app,
                    runner_path=self.runner,
                    codesign_tool=str(self.fake_codesign),
                    captured_by_verifier_sha256=self.verifier_sha256,
                )
            ),
            encoding="utf-8",
        )
        self.artifact_binding_sha256 = hashlib.sha256(
            self.artifact_binding_path.read_bytes()
        ).hexdigest()
        self.fake_xcresulttool = self.root / "fake-xcresulttool"
        self.fake_xcresulttool.write_text(
            """#!/usr/bin/env python3
import json
import shutil
import sys
from pathlib import Path

args = sys.argv[1:]
if args[:1] == ["xcresulttool"]:
    args = args[1:]
if args[:3] == ["get", "test-results", "summary"]:
    bundle = Path(args[args.index("--path") + 1])
    print((bundle / "summary.json").read_text(encoding="utf-8"))
    if (bundle / "emit-xcresult-cache-on-read").exists():
        (bundle / "database.sqlite3").write_bytes(b"xcresulttool cache bytes\\n")
elif args[:3] == ["get", "test-results", "tests"]:
    bundle = Path(args[args.index("--path") + 1])
    print((bundle / "tests.json").read_text(encoding="utf-8"))
elif args[:2] == ["export", "attachments"]:
    bundle = Path(args[args.index("--path") + 1])
    output = Path(args[args.index("--output-path") + 1])
    output.mkdir(parents=True)
    shutil.copyfile(bundle / "attachments-manifest.json", output / "manifest.json")
    source = bundle / "attachment-files"
    if source.is_dir():
        for path in source.iterdir():
            shutil.copyfile(path, output / path.name)
    if (bundle / "emit-symlink-attachment").exists():
        (output / "unexpected-link").symlink_to(bundle / "summary.json")
else:
    print(f"unexpected fake xcresulttool arguments: {args}", file=sys.stderr)
    sys.exit(64)
""",
            encoding="utf-8",
        )
        self.fake_xcresulttool.chmod(0o755)
        self.source_methods = sorted(METHOD_PATTERN.findall(TASK_SOURCE.read_text(encoding="utf-8")))
        self.assertEqual(17, len(self.source_methods), "fixture must track the exact current task suite")

    def tearDown(self) -> None:
        self.temporary_directory.cleanup()

    def _make_bundle(self, name: str, bundle_id: str) -> Path:
        bundle = self.derived_data / "Build" / "Products" / "Debug" / name
        self._populate_bundle(bundle, bundle_id, Path(name).stem)
        return bundle

    def _populate_bundle(self, bundle: Path, bundle_id: str, executable_name: str) -> None:
        contents = bundle / "Contents"
        contents.mkdir(parents=True)
        with (contents / "Info.plist").open("wb") as handle:
            plistlib.dump(
                {
                    "CFBundleIdentifier": bundle_id,
                    "CFBundleExecutable": executable_name,
                },
                handle,
            )
        executable = contents / "MacOS" / executable_name
        executable.parent.mkdir()
        executable.write_bytes(f"fixture executable for {bundle_id}\n".encode("utf-8"))
        executable.chmod(0o755)

    def _write_fixture(
        self,
        *,
        methods: list[str] | None = None,
        summary: dict[str, object] | None = None,
        screenshots: tuple[str, ...] = SCREENSHOTS,
        png_bytes: bytes = PNG,
    ) -> None:
        observed_methods = methods if methods is not None else self.source_methods
        summary_payload: dict[str, object] = {
            "result": "Passed",
            "totalTestCount": 17,
            "passedTests": 17,
            "failedTests": 0,
            "skippedTests": 0,
            "expectedFailures": 0,
        }
        if summary is not None:
            summary_payload.update(summary)
        (self.xcresult / "summary.json").write_text(json.dumps(summary_payload), encoding="utf-8")
        cases = [
            {
                "nodeType": "Test Case",
                "name": f"{method}()",
                "nodeIdentifier": f"MeetingAssistantNativeAppUITests.{method}",
                "result": "Passed",
            }
            for method in observed_methods
        ]
        tests_payload = {
            "testNodes": [
                {
                    "nodeType": "UI test bundle",
                    "name": "MeetingAssistantNativeAppUITests",
                    "children": [
                        {
                            "nodeType": "Test Suite",
                            "name": "DesignedNativeShellAppBundleTests",
                            "nodeIdentifier": "MeetingAssistantNativeAppUITests.DesignedNativeShellAppBundleTests",
                            "children": cases,
                        }
                    ],
                }
            ]
        }
        (self.xcresult / "tests.json").write_text(json.dumps(tests_payload), encoding="utf-8")
        files = self.xcresult / "attachment-files"
        files.mkdir(exist_ok=True)
        attachments = []
        for index, name in enumerate(screenshots):
            exported_name = f"attachment-{index}.png"
            (files / exported_name).write_bytes(png_bytes)
            attachments.append(
                {
                    "exportedFileName": exported_name,
                    "suggestedHumanReadableName": name,
                    "isAssociatedWithFailure": False,
                    "configurationName": "Test Scheme Action",
                    "deviceName": "Test Mac",
                    "deviceId": "test-mac",
                }
            )
        manifest = [
            {
                "testIdentifier": (
                    "MeetingAssistantNativeAppUITests.DesignedNativeShellAppBundleTests/"
                    f"{self.source_methods[0]}()"
                ),
                "attachments": attachments,
            }
        ]
        (self.xcresult / "attachments-manifest.json").write_text(json.dumps(manifest), encoding="utf-8")

    def _run(
        self,
        *,
        output_name: str,
        source: Path = TASK_SOURCE,
        xcresult: Path | None = None,
        upstream_test_status: int = 0,
        xctestrun: Path | None = None,
        git_tool: str = "/usr/bin/git",
        expected_subject_commit: str | None = None,
        expected_fingerprint: str | None = None,
        artifact_binding: Path | None = None,
        expected_artifact_binding_sha256: str | None = None,
        expected_verifier_sha256: str | None = None,
        codesign_tool: Path | None = None,
        fixture_mode: bool = True,
        environment_overrides: dict[str, str] | None = None,
    ) -> subprocess.CompletedProcess[str]:
        output = self.derived_data / "reports" / "evidence" / output_name
        command = [
            "python3",
            str(self.frozen_verifier),
            "--xcresult",
            str(xcresult or self.xcresult),
            "--derived-data-root",
            str(self.derived_data),
            "--xctestrun",
            str(xctestrun or self.xctestrun),
            "--input-fingerprint-file",
            str(self.fingerprint_path),
            "--expected-input-fingerprint",
            expected_fingerprint or self.fingerprint,
            "--expected-subject-commit",
            expected_subject_commit or self.subject_commit,
            "--destination",
            self.destination,
            "--test-source",
            str(source),
            "--output-dir",
            str(output),
            "--app",
            str(self.app),
            "--runner",
            str(self.runner),
            "--artifact-binding-file",
            str(artifact_binding or self.artifact_binding_path),
            "--expected-artifact-binding-sha256",
            expected_artifact_binding_sha256 or self.artifact_binding_sha256,
            "--verifier-source",
            str(VERIFIER),
            "--expected-verifier-sha256",
            expected_verifier_sha256 or self.verifier_sha256,
            "--repo-root",
            str(REPO_ROOT),
            "--upstream-test-status",
            str(upstream_test_status),
            "--xcresulttool",
            str(self.fake_xcresulttool),
            "--codesign-tool",
            str(codesign_tool or self.fake_codesign),
            "--git-tool",
            git_tool,
            "--xcodebuild-tool",
            str(self.fake_xcodebuild),
        ]
        if fixture_mode:
            command.append("--fixture-mode")
        return subprocess.run(
            command,
            check=False,
            capture_output=True,
            text=True,
            env={
                **os.environ,
                "MA_MVP1_EXECUTED_VERIFIER_SHA256": self.verifier_sha256,
                **(environment_overrides or {}),
            },
        )

    def _report(self, output_name: str) -> dict[str, object]:
        path = (
            self.derived_data
            / "reports"
            / "evidence"
            / output_name
            / "mvp1-task-xcresult-report.json"
        )
        return json.loads(path.read_text(encoding="utf-8"))

    def test_complete_success_exports_eight_screenshots_and_pending_review_report(self) -> None:
        self._write_fixture()

        completed = self._run(output_name="success")

        self.assertEqual(1, completed.returncode, completed.stderr)
        report = self._report("success")
        self.assertFalse(report["passed"])
        self.assertTrue(report["fixture_checks_passed"])
        self.assertEqual("fixture", report["toolchain"]["mode"])
        self.assertEqual(2, report["schema_version"])
        self.assertEqual("pending", report["screenshot_visual_review"])
        self.assertEqual(17, report["summary"]["passedTests"])
        self.assertEqual(self.source_methods, [case["method"] for case in report["tests"]])
        exported = report["attachments"]["exported_screenshots"]
        self.assertEqual(list(SCREENSHOTS), [item["name"] for item in exported])
        for item in exported:
            self.assertTrue(Path(item["path"]).is_file())
            self.assertRegex(item["sha256"], r"^[0-9a-f]{64}$")
            self.assertEqual(0o600, stat.S_IMODE(Path(item["path"]).stat().st_mode))
        for identity_key in ("app_identity", "runner_identity"):
            self.assertRegex(report[identity_key]["cdhash"], r"^[0-9a-f]{40}$")
            self.assertRegex(report[identity_key]["executable_sha256"], r"^[0-9a-f]{64}$")
        self.assertRegex(report["subject_commit"], r"^[0-9a-f]{40}$")
        self.assertTrue(report["task_subject_paths_clean"])
        self.assertGreater(report["xcresult"]["file_count"], 0)
        self.assertRegex(report["xcresult"]["manifest_sha256"], r"^[0-9a-f]{64}$")
        self.assertEqual(
            report["artifact_binding_before_test"]["xctestrun"]["sha256"],
            report["xctestrun"]["sha256"],
        )
        self.assertTrue(report["verifier_snapshot"]["matched"])
        self.assertEqual(
            self.verifier_sha256,
            report["verifier_snapshot"]["executed_sha256"],
        )
        self.assertTrue(report["artifact_binding_file"]["matched"])
        self.assertEqual(
            self.artifact_binding_sha256,
            report["artifact_binding_file"]["observed_sha256"],
        )
        report_path = (
            self.derived_data
            / "reports"
            / "evidence"
            / "success"
            / "mvp1-task-xcresult-report.json"
        )
        self.assertEqual(0o600, stat.S_IMODE(report_path.stat().st_mode))
        self.assertEqual(0o700, stat.S_IMODE(report_path.parent.stat().st_mode))

        untrusted = self._run(output_name="untrusted-tools", fixture_mode=False)
        self.assertEqual(2, untrusted.returncode)
        self.assertIn("trusted task evidence requires", untrusted.stderr)
        self.assertFalse(
            (
                self.derived_data
                / "reports"
                / "evidence"
                / "untrusted-tools"
                / "mvp1-task-xcresult-report.json"
            ).exists()
        )

        redirected_git = self._run(
            output_name="git-environment-scrubbed",
            environment_overrides={
                "GIT_DIR": str(self.root / "attacker.git"),
                "GIT_WORK_TREE": str(self.root / "attacker-worktree"),
                "GIT_INDEX_FILE": str(self.root / "attacker-index"),
                "GIT_OBJECT_DIRECTORY": str(self.root / "attacker-objects"),
            },
        )
        self.assertEqual(1, redirected_git.returncode)
        self.assertTrue(self._report("git-environment-scrubbed")["fixture_checks_passed"])

    def test_retained_xcresult_manifest_is_captured_after_xcresulttool_cache_materializes(self) -> None:
        self._write_fixture()
        (self.xcresult / "emit-xcresult-cache-on-read").write_text("1\n", encoding="utf-8")

        completed = self._run(output_name="xcresult-cache-materialized")

        self.assertEqual(1, completed.returncode, completed.stderr)
        report = self._report("xcresult-cache-materialized")
        self.assertTrue((self.xcresult / "database.sqlite3").is_file())
        self.assertEqual(
            {
                "path": str(self.xcresult.resolve()),
                **self.verifier_module.directory_manifest(self.xcresult),
            },
            report["xcresult"],
        )

    def test_xcode_attachment_suffixes_are_normalized_without_accepting_arbitrary_names(self) -> None:
        self._write_fixture()
        manifest_path = self.xcresult / "attachments-manifest.json"
        manifest = json.loads(manifest_path.read_text(encoding="utf-8"))
        for index, attachment in enumerate(manifest[0]["attachments"]):
            attachment["suggestedHumanReadableName"] = (
                f"{SCREENSHOTS[index]}_{index}_01234567-89AB-CDEF-0123-456789ABCDEF.png"
            )
        manifest_path.write_text(json.dumps(manifest), encoding="utf-8")

        normalized = self._run(output_name="xcode-suffixed-names")

        self.assertEqual(1, normalized.returncode, normalized.stderr)
        normalized_report = self._report("xcode-suffixed-names")
        self.assertTrue(normalized_report["fixture_checks_passed"])
        self.assertEqual(
            list(SCREENSHOTS),
            [item["name"] for item in normalized_report["attachments"]["exported_screenshots"]],
        )

        self._write_fixture()
        invalid_manifest_path = self.xcresult / "attachments-manifest.json"
        invalid_manifest = json.loads(invalid_manifest_path.read_text(encoding="utf-8"))
        invalid_manifest[0]["attachments"][0]["suggestedHumanReadableName"] = (
            f"{SCREENSHOTS[0]}_0_not-a-uuid.png"
        )
        invalid_manifest_path.write_text(json.dumps(invalid_manifest), encoding="utf-8")

        invalid = self._run(output_name="invalid-xcode-suffix")

        self.assertEqual(1, invalid.returncode)
        invalid_report = self._report("invalid-xcode-suffix")
        self.assertFalse(invalid_report["fixture_checks_passed"])
        self.assertTrue(
            any(SCREENSHOTS[0] in finding for finding in invalid_report["findings"]),
            invalid_report["findings"],
        )

    def test_capture_cli_writes_private_no_clobber_pretest_binding(self) -> None:
        output = self.derived_data / "reports" / "capture-cli" / "binding.json"
        command = [
            "python3",
            str(VERIFIER),
            "capture",
            "--derived-data-root",
            str(self.derived_data),
            "--xctestrun",
            str(self.xctestrun),
            "--app",
            str(self.app),
            "--runner",
            str(self.runner),
            "--output",
            str(output),
            "--codesign-tool",
            str(self.fake_codesign),
            "--fixture-mode",
        ]

        environment = {
            **os.environ,
            "MA_MVP1_EXECUTED_VERIFIER_SHA256": self.verifier_sha256,
        }
        first = subprocess.run(
            command,
            check=False,
            capture_output=True,
            text=True,
            env=environment,
        )
        original = output.read_bytes()
        second = subprocess.run(
            command,
            check=False,
            capture_output=True,
            text=True,
            env=environment,
        )

        self.assertEqual(0, first.returncode, first.stderr)
        self.assertEqual(2, second.returncode)
        self.assertIn("refusing to overwrite", second.stderr)
        self.assertEqual(original, output.read_bytes())
        self.assertEqual(
            [f"MVP1_ARTIFACT_BINDING_SHA256={hashlib.sha256(original).hexdigest()}"],
            [
                line
                for line in first.stdout.splitlines()
                if line.startswith("MVP1_ARTIFACT_BINDING_SHA256=")
            ],
        )
        self.assertEqual(0o400, stat.S_IMODE(output.stat().st_mode))

        dangling_target = output.parent / "dangling-target.json"
        symlink_output = output.parent / "symlink-binding.json"
        symlink_output.symlink_to(dangling_target)
        symlink_command = list(command)
        symlink_command[symlink_command.index("--output") + 1] = str(symlink_output)
        symlink_result = subprocess.run(
            symlink_command,
            check=False,
            capture_output=True,
            text=True,
            env=environment,
        )

        self.assertEqual(2, symlink_result.returncode)
        self.assertIn("refusing to overwrite", symlink_result.stderr)
        self.assertTrue(symlink_output.is_symlink())
        self.assertFalse(dangling_target.exists())

    def test_runner_before_body_failure_is_a_negative_report(self) -> None:
        self._write_fixture(
            methods=[],
            summary={
                "result": "Failed",
                "totalTestCount": 0,
                "passedTests": 0,
                "failedTests": 0,
            },
            screenshots=(),
        )

        completed = self._run(output_name="runner-failure")

        self.assertEqual(1, completed.returncode)
        report = self._report("runner-failure")
        self.assertFalse(report["passed"])
        self.assertTrue(any("totalTestCount" in finding for finding in report["findings"]))
        self.assertTrue(any("missing source task tests" in finding for finding in report["findings"]))

    def test_symlink_attachment_is_a_negative_report_without_traceback(self) -> None:
        self._write_fixture()
        (self.xcresult / "emit-symlink-attachment").write_text("1\n", encoding="utf-8")

        completed = self._run(output_name="symlink-attachment")

        self.assertEqual(1, completed.returncode)
        self.assertNotIn("Traceback", completed.stderr)
        report = self._report("symlink-attachment")
        self.assertFalse(report["passed"])
        self.assertTrue(
            any("symlink" in finding for finding in report["findings"]),
            report["findings"],
        )

    def test_nonzero_upstream_status_can_never_write_passed_evidence(self) -> None:
        self._write_fixture()

        completed = self._run(output_name="upstream-failure", upstream_test_status=70)

        self.assertEqual(1, completed.returncode)
        report = self._report("upstream-failure")
        self.assertFalse(report["passed"])
        self.assertEqual(70, report["upstream_test_status"])
        self.assertTrue(any("exited with status 70" in finding for finding in report["findings"]))

    def test_semantically_unchanged_binding_bytes_cannot_rebaseline_after_capture(self) -> None:
        self._write_fixture()
        self.artifact_binding_path.write_text(
            self.artifact_binding_path.read_text(encoding="utf-8") + "\n",
            encoding="utf-8",
        )

        completed = self._run(output_name="binding-bytes-changed")

        self.assertEqual(1, completed.returncode)
        report = self._report("binding-bytes-changed")
        self.assertFalse(report["passed"])
        self.assertFalse(report["artifact_binding_file"]["matched"])
        self.assertTrue(
            any("binding SHA-256 changed" in finding for finding in report["findings"])
        )

    def test_executed_verifier_must_match_pretest_snapshot_hash(self) -> None:
        self._write_fixture()

        completed = self._run(
            output_name="verifier-hash-changed",
            expected_verifier_sha256="e" * 64,
        )

        self.assertEqual(1, completed.returncode)
        report = self._report("verifier-hash-changed")
        self.assertFalse(report["passed"])
        self.assertFalse(report["verifier_snapshot"]["matched"])
        self.assertTrue(
            any("verifier snapshot SHA-256" in finding for finding in report["findings"])
        )

    def test_head_change_during_task_run_cannot_bind_old_result_to_new_commit(self) -> None:
        self._write_fixture()

        completed = self._run(
            output_name="head-changed",
            expected_subject_commit="b" * 40,
        )

        self.assertEqual(1, completed.returncode)
        report = self._report("head-changed")
        self.assertFalse(report["passed"])
        self.assertTrue(any("HEAD changed during" in item for item in report["findings"]))

    def test_input_fingerprint_is_recomputed_after_the_test_run(self) -> None:
        self._write_fixture()
        stale_fingerprint = "e" * 64
        self.fingerprint_path.write_text(stale_fingerprint + "\n", encoding="utf-8")

        completed = self._run(
            output_name="fingerprint-changed",
            expected_fingerprint=stale_fingerprint,
        )

        self.assertEqual(1, completed.returncode)
        report = self._report("fingerprint-changed")
        self.assertFalse(report["passed"])
        self.assertTrue(any("fingerprint changed during" in item for item in report["findings"]))

    def test_uncommitted_task_subject_paths_cannot_be_commit_bound_evidence(self) -> None:
        self._write_fixture()
        dirty_git = self.root / "dirty-git"
        dirty_git.write_text(
            """#!/usr/bin/env python3
import sys
if "rev-parse" in sys.argv:
    print("a" * 40)
    raise SystemExit(0)
if "status" in sys.argv:
    print(" M platform/native-app/UITests/MeetingAssistantNativeAppUITests/DesignedNativeShellAppBundleTests.swift")
    raise SystemExit(0)
raise SystemExit(64)
""",
            encoding="utf-8",
        )
        dirty_git.chmod(0o755)

        completed = self._run(output_name="dirty-subject", git_tool=str(dirty_git))

        self.assertEqual(1, completed.returncode)
        report = self._report("dirty-subject")
        self.assertFalse(report["passed"])
        self.assertFalse(report["task_subject_paths_clean"])
        self.assertTrue(any("uncommitted or untracked" in item for item in report["findings"]))

    def test_incomplete_seventeen_test_result_fails_closed(self) -> None:
        self._write_fixture(
            methods=self.source_methods[:-1],
            summary={"totalTestCount": 16, "passedTests": 16},
        )

        completed = self._run(output_name="incomplete")

        self.assertEqual(1, completed.returncode)
        report = self._report("incomplete")
        self.assertTrue(any(self.source_methods[-1] in finding for finding in report["findings"]))

    def test_missing_named_screenshot_fails_closed(self) -> None:
        self._write_fixture(screenshots=SCREENSHOTS[:-1])

        completed = self._run(output_name="missing-screenshot")

        self.assertEqual(1, completed.returncode)
        report = self._report("missing-screenshot")
        self.assertTrue(any("07-diagnostics" in finding for finding in report["findings"]))
        self.assertEqual("pending", report["screenshot_visual_review"])

    def test_truncated_png_signature_only_attachment_fails_closed(self) -> None:
        self._write_fixture(png_bytes=b"\x89PNG\r\n\x1a\nfixture")

        completed = self._run(output_name="broken-png")

        self.assertEqual(1, completed.returncode)
        report = self._report("broken-png")
        self.assertFalse(report["passed"])
        self.assertTrue(any("decodable PNG" in finding for finding in report["findings"]))

    @unittest.skipUnless(Path("/usr/bin/sips").is_file(), "requires macOS sips")
    def test_crc_valid_but_undecodable_png_fails_closed(self) -> None:
        self._write_fixture(png_bytes=png_with_crc_valid_broken_idat(PNG))

        completed = self._run(output_name="undecodable-png")

        self.assertEqual(1, completed.returncode)
        report = self._report("undecodable-png")
        self.assertFalse(report["passed"])
        self.assertTrue(any("full image decode" in finding for finding in report["findings"]))

    def test_prepared_app_executable_change_is_detected_after_test(self) -> None:
        self._write_fixture()
        executable = Path(
            json.loads(self.artifact_binding_path.read_text(encoding="utf-8"))["app_identity"][
                "executable_path"
            ]
        )
        executable.write_bytes(b"changed after task test started\n")

        completed = self._run(output_name="app-artifact-changed")

        self.assertEqual(1, completed.returncode)
        report = self._report("app-artifact-changed")
        self.assertFalse(report["passed"])
        self.assertTrue(any("app_identity changed" in finding for finding in report["findings"]))

    def test_strict_codesign_verification_failure_cannot_bind_artifacts(self) -> None:
        self._write_fixture()
        failing_codesign = self.root / "failing-codesign"
        failing_codesign.write_text(
            "#!/bin/sh\n"
            "if [ \"${1:-}\" = \"--verify\" ]; then echo 'invalid signature' >&2; exit 1; fi\n"
            "echo 'CDHash=0123456789abcdef0123456789abcdef01234567' >&2\n",
            encoding="utf-8",
        )
        failing_codesign.chmod(0o755)

        completed = self._run(
            output_name="invalid-signature",
            codesign_tool=failing_codesign,
        )

        self.assertEqual(1, completed.returncode)
        report = self._report("invalid-signature")
        self.assertFalse(report["passed"])
        self.assertTrue(any("strict code-signature verification failed" in item for item in report["findings"]))

    def test_task_source_path_must_be_the_current_repository_suite(self) -> None:
        self._write_fixture()
        mismatched_source = self.root / "DesignedNativeShellAppBundleTests.swift"
        source_text = TASK_SOURCE.read_text(encoding="utf-8").replace(
            f"func {self.source_methods[0]}(",
            "func testSourceOnlyReplacement(",
            1,
        )
        mismatched_source.write_text(source_text, encoding="utf-8")

        completed = self._run(output_name="source-mismatch", source=mismatched_source)

        self.assertEqual(2, completed.returncode)
        self.assertIn("current repository suite", completed.stderr)
        self.assertFalse(
            (self.derived_data / "reports" / "evidence" / "source-mismatch").exists()
        )

    def test_xctestrun_must_bind_the_verified_app_and_runner(self) -> None:
        self._write_fixture()
        mismatched_xctestrun = self.derived_data / "Build" / "Products" / "mismatch.xctestrun"
        with self.xctestrun.open("rb") as handle:
            payload = plistlib.load(handle)
        payload["MeetingAssistantNativeAppUITests"]["UITargetAppPath"] = (
            "__TESTROOT__/Debug/Other.app"
        )
        with mismatched_xctestrun.open("wb") as handle:
            plistlib.dump(payload, handle)

        completed = self._run(
            output_name="xctestrun-mismatch", xctestrun=mismatched_xctestrun
        )

        self.assertEqual(1, completed.returncode)
        report = self._report("xctestrun-mismatch")
        self.assertFalse(report["passed"])
        self.assertTrue(any("target app path" in finding for finding in report["findings"]))

    def test_paths_are_confined_and_existing_output_is_never_overwritten(self) -> None:
        self._write_fixture()
        first = self._run(output_name="no-overwrite")
        self.assertEqual(1, first.returncode, first.stderr)
        report_path = (
            self.derived_data
            / "reports"
            / "evidence"
            / "no-overwrite"
            / "mvp1-task-xcresult-report.json"
        )
        original = report_path.read_bytes()

        second = self._run(output_name="no-overwrite")

        self.assertEqual(2, second.returncode)
        self.assertIn("refusing to overwrite", second.stderr)
        self.assertEqual(original, report_path.read_bytes())

        external_xcresult = self.root / "outside.xcresult"
        external_xcresult.mkdir()
        escaped = self._run(output_name="escaped-xcresult", xcresult=external_xcresult)
        self.assertEqual(2, escaped.returncode)
        self.assertIn("xcresult must be inside", escaped.stderr)
        self.assertFalse((self.derived_data / "reports" / "evidence" / "escaped-xcresult").exists())

        dangling_target = self.derived_data / "reports" / "evidence" / "dangling-target"
        symlink_output = self.derived_data / "reports" / "evidence" / "symlink-output"
        symlink_output.symlink_to(dangling_target)
        symlink_result = self._run(output_name="symlink-output")
        self.assertEqual(2, symlink_result.returncode)
        self.assertIn("refusing to overwrite", symlink_result.stderr)
        self.assertTrue(symlink_output.is_symlink())
        self.assertFalse(dangling_target.exists())

    def test_wrapper_contract_uses_attempt_scoped_result_paths_without_deleting_results(self) -> None:
        script = WRAPPER.read_text(encoding="utf-8")
        self.assertIn('result_run_dir="$derived_data_path/reports/xcresult/', script)
        self.assertIn('result_bundle_path="$result_run_dir/attempt-$attempt.xcresult"', script)
        self.assertIn('-resultBundlePath "$result_bundle_path"', script)
        self.assertIn('final-attempt-path.txt', script)
        self.assertIn('require_current_xctestrun_fingerprint_for_task_evidence', script)
        self.assertIn('--upstream-test-status "$upstream_test_status"', script)
        self.assertIn('--expected-subject-commit "$validated_task_subject_commit"', script)
        self.assertIn('task-artifacts-before-test.json', script)
        self.assertIn('--artifact-binding-file "$last_task_artifact_binding_path"', script)
        self.assertIn('app_bundle_lock_path=', script)
        self.assertIn('os.link(candidate, lock_path, follow_symlinks=False)', script)
        self.assertIn('run_frozen_task_xcresult_verifier', script)
        self.assertIn('require_trusted_mvp1_toolchain', script)
        self.assertIn("--test-requirement '=anchor apple'", script)
        self.assertIn('python_tool="/usr/bin/python3"', script)
        self.assertIn('"$python_tool" -I -S - "$snapshot_path"', script)
        python_invocation_lines = [
            line
            for line in script.splitlines()
            if '"$python_tool"' in line and "[[" not in line
        ]
        self.assertGreaterEqual(len(python_invocation_lines), 8)
        self.assertTrue(
            all("-I -S" in line for line in python_invocation_lines),
            python_invocation_lines,
        )
        self.assertIn("run_clean_git", script)
        self.assertIn("/usr/bin/env -i", script)
        self.assertIn("GIT_CONFIG_NOSYSTEM=1", script)
        self.assertNotIn("command -v git", script)
        self.assertNotIn("shasum", script)
        self.assertIn('--expected-verifier-sha256 "$last_task_frozen_verifier_sha256"', script)
        self.assertIn(
            '--expected-artifact-binding-sha256 "$last_task_artifact_binding_sha256"',
            script,
        )
        self.assertIn("MVP1_ARTIFACT_BINDING_SHA256=", script)
        self.assertNotIn(
            'shasum -a 256 "$last_task_artifact_binding_path"',
            script,
        )
        self.assertNotIn('python3 "$task_xcresult_verifier"', script)
        self.assertNotIn(
            '--xcresulttool "${MA_NATIVE_APP_XCRESULTTOOL:-/usr/bin/xcrun}"',
            script,
        )
        self.assertIn('--xcodebuild-tool "$xcodebuild_tool"', script)
        self.assertNotRegex(script, r"rm\s+-[^\n]*r[^\n]*xcresult")

        loader_match = re.search(
            r"(run_frozen_task_xcresult_verifier\(\) \{.*?^\})\n\nset_xctestrun_env",
            script,
            flags=re.MULTILINE | re.DOTALL,
        )
        self.assertIsNotNone(loader_match)
        snapshot = self.root / "loader-probe.py"
        marker = self.root / "loader-marker.txt"
        snapshot_payload = (
            "import os\n"
            "import sys\n"
            "from pathlib import Path\n"
            "Path(sys.argv[1]).write_text("
            "os.environ['MA_MVP1_EXECUTED_VERIFIER_SHA256'], encoding='utf-8')\n"
        )
        snapshot.write_text(snapshot_payload, encoding="utf-8")
        snapshot.chmod(0o400)
        snapshot_sha256 = hashlib.sha256(snapshot.read_bytes()).hexdigest()
        driver = self.root / "loader-driver.sh"
        driver.write_text(
            "#!/bin/bash\nset -euo pipefail\npython_tool=/usr/bin/python3\n"
            + loader_match.group(1)
            + '\nrun_frozen_task_xcresult_verifier "$1" "$2" "$3"\n',
            encoding="utf-8",
        )
        driver.chmod(0o700)

        injected_python_dir = self.root / "loader-python-injection"
        injected_python_dir.mkdir()
        injected_python_marker = self.root / "loader-sitecustomize-invoked"
        (injected_python_dir / "sitecustomize.py").write_text(
            "from pathlib import Path\n"
            f"Path({str(injected_python_marker)!r}).write_text('invoked\\n', encoding='utf-8')\n",
            encoding="utf-8",
        )
        isolated_environment = {
            **os.environ,
            "PYTHONHOME": str(self.root / "invalid-python-home"),
            "PYTHONPATH": str(injected_python_dir),
            "PYTHONUSERBASE": str(injected_python_dir),
        }

        first = subprocess.run(
            [str(driver), str(snapshot), snapshot_sha256, str(marker)],
            env=isolated_environment,
            check=False,
            capture_output=True,
            text=True,
        )
        self.assertEqual(0, first.returncode, first.stderr)
        self.assertEqual(snapshot_sha256, marker.read_text(encoding="utf-8"))
        self.assertFalse(injected_python_marker.exists())

        snapshot.chmod(0o600)
        snapshot.write_text(snapshot_payload + "# changed\n", encoding="utf-8")
        snapshot.chmod(0o400)
        marker.unlink()
        tampered = subprocess.run(
            [str(driver), str(snapshot), snapshot_sha256, str(marker)],
            check=False,
            capture_output=True,
            text=True,
        )
        self.assertEqual(2, tampered.returncode)
        self.assertFalse(marker.exists())
        self.assertIn("changed before execution", tampered.stderr)

    def test_wrapper_releases_hardlink_lock_on_early_exit(self) -> None:
        derived_data = self.root / "lock-cleanup-derived-data"
        environment = {
            **os.environ,
            "MA_NATIVE_APP_DERIVED_DATA_PATH": str(derived_data),
            "MA_NATIVE_APP_XCODEBUILD_TOOL": str(self.fake_xcodebuild),
            "MA_NATIVE_APP_PREPARE_ONLY": "invalid",
        }

        completed = subprocess.run(
            ["/bin/bash", str(WRAPPER)],
            cwd=REPO_ROOT,
            env=environment,
            check=False,
            capture_output=True,
            text=True,
        )

        self.assertEqual(2, completed.returncode)
        self.assertFalse((derived_data / ".meeting-assistant-app-bundle.lock").exists())
        self.assertEqual([], list(derived_data.glob(".meeting-assistant-app-bundle.owner.*")))

        untrusted_derived_data = self.root / "untrusted-tool-derived-data"
        untrusted_environment = {
            **os.environ,
            "MA_NATIVE_APP_DERIVED_DATA_PATH": str(untrusted_derived_data),
            "MA_NATIVE_APP_XCODEBUILD_TOOL": str(self.fake_xcodebuild),
            "MA_NATIVE_APP_TASK_XCUITEST": "1",
            "MA_NATIVE_APP_PREPARE_ONLY": "0",
        }
        untrusted = subprocess.run(
            ["/bin/bash", str(WRAPPER)],
            cwd=REPO_ROOT,
            env=untrusted_environment,
            check=False,
            capture_output=True,
            text=True,
        )
        self.assertEqual(2, untrusted.returncode)
        self.assertIn("rejects MA_NATIVE_APP_XCODEBUILD_TOOL override", untrusted.stderr)
        self.assertFalse(
            (untrusted_derived_data / ".meeting-assistant-app-bundle.lock").exists()
        )
        self.assertEqual(
            [],
            list(untrusted_derived_data.glob(".meeting-assistant-app-bundle.owner.*")),
        )

        fake_path = self.root / "fake-path"
        fake_path.mkdir()
        marker_paths = []
        for tool_name in ("python3", "git", "shasum"):
            marker = self.root / f"path-{tool_name}-invoked"
            marker_paths.append(marker)
            fake_tool = fake_path / tool_name
            fake_tool.write_text(
                "#!/bin/sh\n"
                f"printf 'invoked\\n' > {str(marker)!r}\n"
                "exit 99\n",
                encoding="utf-8",
            )
            fake_tool.chmod(0o755)
        path_probe_environment = {
            **os.environ,
            "GIT_DIR": str(self.root / "redirected.git"),
            "GIT_WORK_TREE": str(self.root / "redirected-worktree"),
            "GIT_INDEX_FILE": str(self.root / "redirected-index"),
            "MA_NATIVE_APP_DERIVED_DATA_PATH": str(self.derived_data),
            "MA_NATIVE_APP_PREPARE_ONLY": "1",
            "MA_NATIVE_APP_REUSE_XCTESTRUN": "1",
            "MA_NATIVE_APP_TASK_XCUITEST": "1",
            "MA_NATIVE_APP_XCODEBUILD_TOOL": str(self.fake_xcodebuild),
            "PATH": f"{fake_path}:/usr/bin:/bin",
        }
        python_injection = self.root / "wrapper-python-injection"
        python_injection.mkdir()
        python_injection_marker = self.root / "wrapper-sitecustomize-invoked"
        (python_injection / "sitecustomize.py").write_text(
            "from pathlib import Path\n"
            f"Path({str(python_injection_marker)!r}).write_text('invoked\\n', encoding='utf-8')\n",
            encoding="utf-8",
        )
        path_probe_environment.update(
            {
                "PYTHONHOME": str(self.root / "invalid-python-home"),
                "PYTHONPATH": str(python_injection),
                "PYTHONUSERBASE": str(python_injection),
            }
        )
        path_probe = subprocess.run(
            ["/bin/bash", str(WRAPPER)],
            cwd=REPO_ROOT,
            env=path_probe_environment,
            check=False,
            capture_output=True,
            text=True,
        )
        self.assertEqual(0, path_probe.returncode, path_probe.stdout + path_probe.stderr)
        self.assertIn("prepared without starting UI automation", path_probe.stdout)
        self.assertNotIn("could not compute the current app/test input fingerprint", path_probe.stderr)
        self.assertNotIn("could not bind the prepared subject", path_probe.stderr)
        self.assertTrue(all(not marker.exists() for marker in marker_paths))
        self.assertFalse(python_injection_marker.exists())
        for evidence_tool in (
            VERIFIER,
            REPO_ROOT / "scripts" / "mvp1-accessibility-walkthrough.py",
            REPO_ROOT / "scripts" / "mvp1-experience-study.py",
        ):
            direct_entrypoint = subprocess.run(
                [str(evidence_tool), "--help"],
                cwd=REPO_ROOT,
                env=path_probe_environment,
                check=False,
                capture_output=True,
                text=True,
            )
            self.assertEqual(
                0,
                direct_entrypoint.returncode,
                direct_entrypoint.stdout + direct_entrypoint.stderr,
            )
            self.assertFalse(python_injection_marker.exists())

        signal_derived_data = self.root / "signal-lock-cleanup-derived-data"
        child_pid_path = self.root / "blocking-xcodebuild.pid"
        blocking_xcodebuild = self.root / "blocking-xcodebuild"
        blocking_xcodebuild.write_text(
            "#!/usr/bin/env python3\n"
            "import os\n"
            "import signal\n"
            "import sys\n"
            "from pathlib import Path\n"
            "if sys.argv[1:] == ['-version']:\n"
            "    print('Xcode Test\\nBuild version TEST')\n"
            "    raise SystemExit(0)\n"
            "def stop(_signum, _frame):\n"
            "    raise SystemExit(143)\n"
            "for handled in (signal.SIGHUP, signal.SIGINT, signal.SIGTERM):\n"
            "    signal.signal(handled, stop)\n"
            "Path(os.environ['MA_TEST_CHILD_PID_PATH']).write_text(\n"
            "    f'{os.getpid()}\\n', encoding='utf-8'\n"
            ")\n"
            "while True:\n"
            "    signal.pause()\n",
            encoding="utf-8",
        )
        blocking_xcodebuild.chmod(0o755)
        signal_environment = {
            **os.environ,
            "MA_NATIVE_APP_DERIVED_DATA_PATH": str(signal_derived_data),
            "MA_NATIVE_APP_XCODEBUILD_TOOL": str(blocking_xcodebuild),
            "MA_NATIVE_APP_TASK_XCUITEST": "1",
            "MA_NATIVE_APP_PREPARE_ONLY": "1",
            "MA_NATIVE_APP_REUSE_XCTESTRUN": "0",
            "MA_TEST_CHILD_PID_PATH": str(child_pid_path),
        }
        process = subprocess.Popen(
            ["/bin/bash", str(WRAPPER)],
            cwd=REPO_ROOT,
            env=signal_environment,
            stdout=subprocess.PIPE,
            stderr=subprocess.PIPE,
            text=True,
            start_new_session=True,
        )
        try:
            deadline = time.monotonic() + 10
            lock_path = signal_derived_data / ".meeting-assistant-app-bundle.lock"
            while time.monotonic() < deadline:
                if child_pid_path.is_file() and lock_path.exists():
                    break
                if process.poll() is not None:
                    break
                time.sleep(0.02)
            self.assertIsNone(process.poll(), "wrapper exited before the signal-cleanup probe")
            self.assertTrue(child_pid_path.is_file(), "blocking xcodebuild did not start")
            self.assertTrue(lock_path.exists(), "wrapper lock was not acquired")
            child_pid = int(child_pid_path.read_text(encoding="utf-8").strip())

            os.killpg(process.pid, signal.SIGTERM)
            stdout, stderr = process.communicate(timeout=10)

            self.assertEqual(143, process.returncode, stdout + stderr)
            self.assertFalse(lock_path.exists())
            self.assertEqual(
                [],
                list(signal_derived_data.glob(".meeting-assistant-app-bundle.owner.*")),
            )
            child_alive = True
            child_deadline = time.monotonic() + 2
            while time.monotonic() < child_deadline:
                try:
                    os.kill(child_pid, 0)
                except ProcessLookupError:
                    child_alive = False
                    break
                time.sleep(0.02)
            self.assertFalse(child_alive, "blocking xcodebuild child was left behind")
        finally:
            if process.poll() is None:
                os.killpg(process.pid, signal.SIGKILL)
                process.communicate(timeout=5)

    def test_wrapper_refuses_existing_lock_without_removing_its_owner(self) -> None:
        derived_data = self.root / "existing-lock-derived-data"
        derived_data.mkdir()
        lock_path = derived_data / ".meeting-assistant-app-bundle.lock"
        lock_path.write_text("other-owner\n", encoding="utf-8")
        environment = {
            **os.environ,
            "MA_NATIVE_APP_DERIVED_DATA_PATH": str(derived_data),
            "MA_NATIVE_APP_XCODEBUILD_TOOL": str(self.fake_xcodebuild),
            "MA_NATIVE_APP_PREPARE_ONLY": "invalid",
        }

        completed = subprocess.run(
            ["/bin/bash", str(WRAPPER)],
            cwd=REPO_ROOT,
            env=environment,
            check=False,
            capture_output=True,
            text=True,
        )

        self.assertEqual(2, completed.returncode)
        self.assertIn("another app-bundle workflow owns DerivedData lock", completed.stderr)
        self.assertEqual("other-owner\n", lock_path.read_text(encoding="utf-8"))
        self.assertEqual([], list(derived_data.glob(".meeting-assistant-app-bundle.owner.*")))


if __name__ == "__main__":
    unittest.main()
