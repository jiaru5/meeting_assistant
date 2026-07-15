from __future__ import annotations

import contextlib
import hashlib
import importlib.util
import io
import json
import os
import plistlib
import stat
import tempfile
import unittest
from pathlib import Path
from unittest import mock


ROOT = Path(__file__).resolve().parents[2]


def load_walkthrough_module():
    spec = importlib.util.spec_from_file_location(
        "mvp1_accessibility_walkthrough",
        ROOT / "scripts/mvp1-accessibility-walkthrough.py",
    )
    assert spec is not None
    module = importlib.util.module_from_spec(spec)
    assert spec.loader is not None
    spec.loader.exec_module(module)
    return module


class MVP1AccessibilityWalkthroughTests(unittest.TestCase):
    def setUp(self) -> None:
        self.module = load_walkthrough_module()
        self.temporary_directory = tempfile.TemporaryDirectory()
        self.base = Path(self.temporary_directory.name)
        self.app_path = self.base / "MeetingAssistantNative.app"
        self.bundle_id = "local.meeting-assistant.native"
        self.cdhash = "b" * 40
        self.subject_commit = self.module.current_commit()
        self.macos_version = self.module.current_macos_version()
        self.assertIsNotNone(self.subject_commit)
        self.assertIsNotNone(self.macos_version)
        contents = self.app_path / "Contents"
        contents.mkdir(parents=True)
        executable_name = "MeetingAssistantNative"
        with (contents / "Info.plist").open("wb") as handle:
            plistlib.dump(
                {
                    "CFBundleIdentifier": self.bundle_id,
                    "CFBundleExecutable": executable_name,
                },
                handle,
            )
        self.app_executable = contents / "MacOS" / executable_name
        self.app_executable.parent.mkdir()
        self.app_executable.write_bytes(b"fixture app executable\n")
        self.app_executable.chmod(0o755)
        self.app_executable_sha256 = hashlib.sha256(self.app_executable.read_bytes()).hexdigest()
        self.fake_codesign = self.base / "fake-codesign"
        self.fake_codesign.write_text(
            f"#!/bin/sh\nprintf 'CDHash={self.cdhash}\\n' >&2\n",
            encoding="utf-8",
        )
        self.fake_codesign.chmod(0o755)
        self.xctestrun = self.base / "fixture.xctestrun"
        self.xctestrun.write_bytes(b"fixture xctestrun")
        verifier_source = ROOT / "scripts" / "mvp1-task-xcresult.py"
        self.verifier_snapshot = self.base / "frozen" / "mvp1-task-xcresult.py"
        self.verifier_snapshot.parent.mkdir()
        self.verifier_snapshot.write_bytes(verifier_source.read_bytes())
        self.verifier_snapshot.chmod(0o400)
        self.verifier_sha256 = hashlib.sha256(self.verifier_snapshot.read_bytes()).hexdigest()
        self.trusted_toolchain = self.module.current_trusted_task_toolchain()
        self.artifact_binding = self.base / "task-artifacts-before-test.json"
        self.artifact_binding_payload = {
            "schema_version": 1,
            "binding_type": "mvp1-task-artifacts-before-test",
            "captured_by_verifier_sha256": self.verifier_sha256,
            "toolchain": self.trusted_toolchain,
        }
        self.artifact_binding.write_text(
            json.dumps(self.artifact_binding_payload),
            encoding="utf-8",
        )
        self.artifact_binding.chmod(0o400)
        self.xcresult = self.base / "fixture.xcresult"
        self.xcresult.mkdir()
        (self.xcresult / "result.txt").write_text("retained xcresult fixture\n", encoding="utf-8")
        self.screenshots_dir = self.base / "screenshots"
        self.screenshots_dir.mkdir()
        screenshot_items = []
        for name in (
            "00-meetings-recent",
            "01-meetings-empty",
            "02-new-recording-ready",
            "03-recording-live",
            "04-recording-saved",
            "05-processing",
            "06-transcript-ready",
            "07-diagnostics",
        ):
            screenshot_path = self.screenshots_dir / f"{name}.png"
            screenshot_path.write_bytes(f"fixture screenshot {name}\n".encode("utf-8"))
            screenshot_items.append(
                {
                    "name": name,
                    "path": str(screenshot_path),
                    "sha256": hashlib.sha256(screenshot_path.read_bytes()).hexdigest(),
                    "width": 1440,
                    "height": 900,
                }
            )
        self.task_evidence_report = self.base / "mvp1-task-xcresult-report.json"
        fingerprint = "f" * 64
        xcresult_manifest = self.module._directory_manifest(self.xcresult)
        self.task_evidence_report.write_text(
            json.dumps(
                {
                    "schema_version": 2,
                    "release_gate": "mvp1-task-xcresult-evidence",
                    "passed": True,
                    "upstream_test_status": 0,
                    "toolchain": self.trusted_toolchain,
                    "task_subject_paths_clean": True,
                    "subject_commit": self.subject_commit,
                    "subject_commit_before_test": self.subject_commit,
                    "prepared_input_fingerprint": fingerprint,
                    "current_input_fingerprint_after_test": fingerprint,
                    "app_identity": {
                        "path": str(self.app_path.resolve()),
                        "bundle_id": self.bundle_id,
                        "cdhash": self.cdhash,
                        "executable_sha256": self.app_executable_sha256,
                    },
                    "summary": {
                        "result": "Passed",
                        "totalTestCount": 17,
                        "passedTests": 17,
                        "failedTests": 0,
                        "skippedTests": 0,
                        "expectedFailures": 0,
                    },
                    "verifier_snapshot": {
                        "path": str(self.verifier_snapshot),
                        "source_path": str(verifier_source),
                        "expected_sha256": self.verifier_sha256,
                        "executed_sha256": self.verifier_sha256,
                        "matched": True,
                    },
                    "attachments": {
                        "exported_screenshots": screenshot_items
                    },
                    "xctestrun": {
                        "path": str(self.xctestrun),
                        "sha256": hashlib.sha256(self.xctestrun.read_bytes()).hexdigest(),
                    },
                    "artifact_binding_file": {
                        "path": str(self.artifact_binding),
                        "sha256": hashlib.sha256(self.artifact_binding.read_bytes()).hexdigest(),
                        "expected_sha256": hashlib.sha256(
                            self.artifact_binding.read_bytes()
                        ).hexdigest(),
                        "observed_sha256": hashlib.sha256(
                            self.artifact_binding.read_bytes()
                        ).hexdigest(),
                        "matched": True,
                    },
                    "artifact_binding_before_test": self.artifact_binding_payload,
                    "xcresult": {"path": str(self.xcresult), **xcresult_manifest},
                }
            ),
            encoding="utf-8",
        )

    def tearDown(self) -> None:
        self.temporary_directory.cleanup()

    def template(self) -> dict:
        return self.module.build_template(
            subject_commit=self.subject_commit,
            tested_app_path=str(self.app_path),
            tested_bundle_id=self.bundle_id,
            tested_app_cdhash=self.cdhash,
            macos_version=self.macos_version,
            walkthrough_id="mvp1-accessibility-test",
            codesign_tool=str(self.fake_codesign),
            task_evidence_report=str(self.task_evidence_report),
        )

    def validate(self, walkthrough: object) -> dict:
        return self.module.validate_walkthrough(
            walkthrough,
            codesign_tool=str(self.fake_codesign),
        )

    def report(self, walkthrough: object, *, source: str | None = None) -> dict:
        return self.module.build_report(
            walkthrough,
            source=source,
            codesign_tool=str(self.fake_codesign),
        )

    def valid_walkthrough(self) -> dict:
        walkthrough = self.template()
        walkthrough["observer_attestation"] = {
            "confirmed": True,
            "attested_at": "2026-07-14T16:00:00+08:00",
            "attested_by_role": "manual-observer",
            "statement": self.module.ATTESTATION_STATEMENT,
            "synthetic_data_confirmed": True,
            "privacy_statement": self.module.PRIVACY_ATTESTATION_STATEMENT,
        }
        for check in walkthrough["checks"]:
            check["result"] = "pass"
            check["observation"] = (
                f"Direct manual VoiceOver and keyboard observation for {check['check_id']}."
            )
        return walkthrough

    def test_template_is_bound_unattested_and_never_counts_automation_as_walkthrough(self) -> None:
        template = self.template()
        validation = self.validate(template)

        self.assertEqual(
            str(self.app_path.resolve()),
            template["subject"]["tested_app_path"],
        )
        self.assertEqual(list(self.module.CHECK_IDS), [item["check_id"] for item in template["checks"]])
        self.assertTrue(all(item["result"] is None for item in template["checks"]))
        self.assertFalse(template["observer_attestation"]["confirmed"])
        self.assertFalse(template["observer_attestation"]["synthetic_data_confirmed"])
        self.assertEqual(self.module.ATTESTATION_STATEMENT, template["observer_attestation"]["statement"])
        self.assertEqual(
            self.module.PRIVACY_ATTESTATION_STATEMENT,
            template["observer_attestation"]["privacy_statement"],
        )
        for key in (
            "agent_counts_as_walkthrough",
            "source_contract_counts_as_walkthrough",
            "automation_counts_as_walkthrough",
            "screenshot_counts_as_walkthrough",
            "xcuitest_counts_as_walkthrough",
        ):
            self.assertFalse(template["evidence_policy"][key])
        self.assertFalse(validation["ready_for_review"])
        self.assertFalse(validation["checks"]["manual_observer_attestation_valid"])
        self.assertFalse(validation["checks"]["all_fixed_checks_recorded"])
        self.assertEqual(
            str(self.task_evidence_report.resolve()),
            template["task_evidence"]["report_path"],
        )

    def test_explicit_task_report_bytes_bind_strict_validation_to_the_caller_snapshot(self) -> None:
        walkthrough = self.valid_walkthrough()
        original_report_bytes = self.task_evidence_report.read_bytes()
        changed_report = json.loads(original_report_bytes)
        changed_report["subject_commit"] = "0" * 40
        self.task_evidence_report.write_text(json.dumps(changed_report), encoding="utf-8")

        observed = self.module._validated_task_evidence(
            report_path=self.task_evidence_report,
            report_bytes=original_report_bytes,
            subject=walkthrough["subject"],
        )

        self.assertEqual(
            hashlib.sha256(original_report_bytes).hexdigest(),
            observed["report_sha256"],
        )
        with self.assertRaisesRegex(self.module.WalkthroughToolError, "does not bind the walkthrough"):
            self.module._validated_task_evidence(
                report_path=self.task_evidence_report,
                subject=walkthrough["subject"],
            )

    def test_human_attestation_requires_confirmation_timezone_role_and_exact_statement(self) -> None:
        walkthrough = self.valid_walkthrough()
        walkthrough["observer_attestation"] = {
            "confirmed": False,
            "attested_at": "2026-07-14T16:00:00",
            "attested_by_role": " ",
            "statement": "XCUITest and screenshots passed, so this is a manual walkthrough.",
        }

        validation = self.validate(walkthrough)
        errors = "\n".join(validation["errors"])

        self.assertFalse(validation["ready_for_review"])
        self.assertFalse(validation["checks"]["manual_observer_attestation_valid"])
        self.assertIn("only after a human observer completes the real-app walkthrough", errors)
        self.assertIn("timezone-aware ISO-8601", errors)
        self.assertIn("non-empty role or pseudonym", errors)
        self.assertIn("must match the manual observer statement", errors)
        self.assertIn("synthetic_data_confirmed must be true", errors)
        self.assertIn("privacy_statement", errors)

    def test_policy_tampering_cannot_turn_agent_or_automated_artifacts_into_manual_evidence(self) -> None:
        walkthrough = self.valid_walkthrough()
        walkthrough["evidence_policy"]["agent_counts_as_walkthrough"] = True
        walkthrough["evidence_policy"]["automation_counts_as_walkthrough"] = True
        walkthrough["evidence_policy"]["screenshot_counts_as_walkthrough"] = True
        walkthrough["evidence_policy"]["xcuitest_counts_as_walkthrough"] = True

        report = self.report(walkthrough)
        errors = "\n".join(report["errors"])

        self.assertFalse(report["ready_for_review"])
        self.assertFalse(report["checks"]["structure_valid"])
        self.assertIn("evidence_policy.agent_counts_as_walkthrough must be False", errors)
        self.assertIn("evidence_policy.automation_counts_as_walkthrough must be False", errors)
        self.assertIn("evidence_policy.screenshot_counts_as_walkthrough must be False", errors)
        self.assertIn("evidence_policy.xcuitest_counts_as_walkthrough must be False", errors)
        self.assertTrue(
            report["evidence_boundary"][
                "attestation_is_a_human_declaration_not_independent_identity_proof"
            ]
        )
        self.assertFalse(report["evidence_boundary"]["ready_for_review_is_product_acceptance"])
        self.assertTrue(report["evidence_boundary"]["not_release_readiness"])

    def test_valid_walkthrough_is_ready_for_review_without_claiming_product_acceptance(self) -> None:
        report = self.report(self.valid_walkthrough(), source="walkthrough.json")

        self.assertTrue(report["ready_for_review"])
        self.assertEqual("ready_for_review", report["status"])
        self.assertEqual(len(self.module.CHECK_IDS), report["recorded_check_count"])
        self.assertEqual(list(sorted(self.module.CHECK_IDS)), report["passed_check_ids"])
        self.assertFalse(report["checks"]["usability_thresholds_applied"])
        self.assertFalse(report["checks"]["structure_validity_is_product_acceptance"])
        self.assertFalse(report["evidence_boundary"]["ready_for_review_is_product_acceptance"])

    def test_subject_commit_app_and_environment_identity_must_match_strict_formats(self) -> None:
        walkthrough = self.valid_walkthrough()
        walkthrough["subject"].update(
            {
                "subject_commit": "A" * 40,
                "tested_app_path": "relative/MeetingAssistantNative.app",
                "tested_bundle_id": "not-a-reverse-dns-id",
                "tested_app_cdhash": "B" * 40,
            }
        )
        walkthrough["environment"]["operating_system"] = "Linux"
        walkthrough["environment"]["macos_version"] = "26"

        validation = self.validate(walkthrough)
        errors = "\n".join(validation["errors"])

        self.assertFalse(validation["ready_for_review"])
        self.assertFalse(validation["checks"]["subject_binding_valid"])
        self.assertIn("40-character lowercase Git commit hash", errors)
        self.assertIn("absolute .app path", errors)
        self.assertIn("reverse-DNS-style bundle identifier", errors)
        self.assertIn("40-character lowercase CDHash", errors)
        self.assertIn("environment.operating_system must be 'macOS'", errors)
        self.assertIn("dotted macOS version", errors)

    def test_nonexistent_bound_app_cannot_be_ready_for_review(self) -> None:
        walkthrough = self.valid_walkthrough()
        missing_app = self.base / "MissingMeetingAssistantNative.app"
        walkthrough["subject"]["tested_app_path"] = str(missing_app)

        validation = self.validate(walkthrough)
        errors = "\n".join(validation["errors"])

        self.assertFalse(validation["ready_for_review"])
        self.assertFalse(validation["checks"]["subject_binding_valid"])
        self.assertIn("does not exist", errors)

    def test_stale_commit_and_fabricated_app_identity_cannot_be_ready_for_review(self) -> None:
        walkthrough = self.valid_walkthrough()
        walkthrough["subject"]["subject_commit"] = "c" * 40
        walkthrough["subject"]["tested_bundle_id"] = "local.meeting-assistant.fabricated"
        walkthrough["subject"]["tested_app_cdhash"] = "d" * 40

        validation = self.validate(walkthrough)
        errors = "\n".join(validation["errors"])

        self.assertFalse(validation["ready_for_review"])
        self.assertFalse(validation["checks"]["subject_binding_valid"])
        self.assertIn("must match current Git HEAD", errors)
        self.assertIn("does not match bound app identity", errors)
        self.assertIn("does not match bound app CDHash", errors)

    def test_task_evidence_must_be_retained_successful_and_provenance_stable(self) -> None:
        original = self.task_evidence_report.read_bytes()
        cases = (
            (("passed",), False, "must be a successful zero-exit report"),
            (("schema_version",), 1, "wrong schema or gate"),
            (
                ("toolchain", "mode"),
                "fixture",
                "trusted Apple toolchain provenance",
            ),
            (
                ("toolchain", "tools", "git", "sha256"),
                "e" * 64,
                "trusted Apple toolchain provenance",
            ),
            (("verifier_snapshot", "matched"), False, "verifier provenance is incomplete"),
            (
                ("verifier_snapshot", "executed_sha256"),
                "e" * 64,
                "verifier provenance is incomplete",
            ),
            (
                ("verifier_snapshot", "path"),
                str(self.base / "missing-frozen-verifier.py"),
                "frozen verifier snapshot is missing or changed",
            ),
            (
                ("verifier_snapshot", "source_path"),
                str(self.base / "not-canonical-verifier.py"),
                "does not name the canonical verifier source",
            ),
            (
                ("artifact_binding_file", "matched"),
                False,
                "missing its pre-test artifact binding",
            ),
            (
                ("artifact_binding_file", "expected_sha256"),
                "e" * 64,
                "missing its pre-test artifact binding",
            ),
            (
                ("artifact_binding_file", "observed_sha256"),
                "e" * 64,
                "missing its pre-test artifact binding",
            ),
            (
                ("artifact_binding_before_test", "captured_by_verifier_sha256"),
                "e" * 64,
                "was not captured by the frozen verifier",
            ),
            (
                ("artifact_binding_before_test", "toolchain", "mode"),
                "fixture",
                "was not captured by the frozen verifier",
            ),
        )

        for path, replacement, expected_error in cases:
            with self.subTest(path=".".join(path)):
                self.task_evidence_report.write_bytes(original)
                walkthrough = self.valid_walkthrough()
                task_report = json.loads(original)
                target = task_report
                for key in path[:-1]:
                    target = target[key]
                target[path[-1]] = replacement
                self.task_evidence_report.write_text(json.dumps(task_report), encoding="utf-8")

                validation = self.validate(walkthrough)

                self.assertFalse(validation["ready_for_review"])
                self.assertFalse(validation["checks"]["subject_binding_valid"])
                self.assertIn(expected_error, "\n".join(validation["errors"]))

        self.task_evidence_report.write_bytes(original)

    def test_retained_screenshot_and_xcresult_contents_must_not_change(self) -> None:
        screenshot_walkthrough = self.valid_walkthrough()
        first_screenshot = next(self.screenshots_dir.glob("*.png"))
        first_screenshot.write_bytes(b"changed screenshot\n")
        screenshot_validation = self.validate(screenshot_walkthrough)

        self.assertFalse(screenshot_validation["ready_for_review"])
        self.assertIn("screenshot is missing or changed", "\n".join(screenshot_validation["errors"]))

        first_screenshot.write_bytes(
            f"fixture screenshot {first_screenshot.stem}\n".encode("utf-8")
        )
        xcresult_walkthrough = self.valid_walkthrough()
        (self.xcresult / "result.txt").write_text("changed xcresult\n", encoding="utf-8")
        xcresult_validation = self.validate(xcresult_walkthrough)

        self.assertFalse(xcresult_validation["ready_for_review"])
        self.assertIn("bundle contents are missing or changed", "\n".join(xcresult_validation["errors"]))

    def test_retained_screenshot_disappearing_during_hashing_is_blocked(self) -> None:
        walkthrough = self.valid_walkthrough()
        real_open = Path.open

        def disappear_while_opening(path: Path, *args, **kwargs):
            if path.suffix == ".png":
                raise FileNotFoundError("simulated screenshot removal")
            return real_open(path, *args, **kwargs)

        with mock.patch.object(
            Path,
            "open",
            new=disappear_while_opening,
        ):
            validation = self.validate(walkthrough)

        self.assertFalse(validation["ready_for_review"])
        self.assertIn("simulated screenshot removal", "\n".join(validation["errors"]))

    def test_bound_app_executable_and_strict_signature_must_remain_valid(self) -> None:
        walkthrough = self.valid_walkthrough()
        self.app_executable.write_bytes(b"changed app executable\n")

        changed = self.validate(walkthrough)

        self.assertFalse(changed["ready_for_review"])
        self.assertIn("does not match the bound app executable", "\n".join(changed["errors"]))

        self.app_executable.write_bytes(b"fixture app executable\n")
        failing_codesign = self.base / "failing-codesign"
        failing_codesign.write_text(
            "#!/bin/sh\n"
            "if [ \"${1:-}\" = \"--verify\" ]; then echo 'invalid signature' >&2; exit 1; fi\n"
            f"echo 'CDHash={self.cdhash}' >&2\n",
            encoding="utf-8",
        )
        failing_codesign.chmod(0o755)
        invalid_signature = self.module.validate_walkthrough(
            walkthrough,
            codesign_tool=str(failing_codesign),
        )

        self.assertFalse(invalid_signature["ready_for_review"])
        self.assertIn(
            "strict code-signature verification failed",
            "\n".join(invalid_signature["errors"]),
        )

    def test_privacy_attestation_and_conservative_text_checks_fail_closed(self) -> None:
        walkthrough = self.valid_walkthrough()
        walkthrough["observer_attestation"]["synthetic_data_confirmed"] = False
        walkthrough["checks"][0]["observation"] = (
            "Contact alex@example.com about session-customer-123456."
        )

        validation = self.validate(walkthrough)
        errors = "\n".join(validation["errors"])

        self.assertFalse(validation["ready_for_review"])
        self.assertIn("synthetic_data_confirmed must be true", errors)
        self.assertIn("must not contain an email address", errors)
        self.assertIn("must not contain a raw session identifier", errors)

    def test_template_normalizes_cdhash_case_but_rejects_invalid_binding_values(self) -> None:
        template = self.module.build_template(
            subject_commit=self.subject_commit,
            tested_app_path=str(self.app_path),
            tested_bundle_id=self.bundle_id,
            tested_app_cdhash="B" * 40,
            macos_version=self.macos_version,
            codesign_tool=str(self.fake_codesign),
            task_evidence_report=str(self.task_evidence_report),
        )
        self.assertEqual("b" * 40, template["subject"]["tested_app_cdhash"])

        with self.assertRaisesRegex(self.module.WalkthroughToolError, "subject.subject_commit"):
            self.module.build_template(
                subject_commit="short",
                tested_app_path=str(self.app_path),
                tested_bundle_id=self.bundle_id,
                tested_app_cdhash=self.cdhash,
                macos_version=self.macos_version,
                codesign_tool=str(self.fake_codesign),
                task_evidence_report=str(self.task_evidence_report),
            )

    def test_fixed_checks_reject_missing_duplicate_extra_and_requirement_tampering(self) -> None:
        walkthrough = self.valid_walkthrough()
        missing_id = walkthrough["checks"][-1]["check_id"]
        walkthrough["checks"] = walkthrough["checks"][:-1]
        walkthrough["checks"].append(dict(walkthrough["checks"][0]))
        walkthrough["checks"][0]["requirement"] = "A mutable replacement requirement."
        walkthrough["checks"].append(
            {
                "check_id": "invented_check",
                "requirement": "Not part of the frozen walkthrough.",
                "result": "pass",
                "observation": "Synthetic observation.",
            }
        )

        validation = self.validate(walkthrough)
        errors = "\n".join(validation["errors"])

        self.assertFalse(validation["ready_for_review"])
        self.assertFalse(validation["checks"]["structure_valid"])
        self.assertIn("must match the fixed walkthrough requirement", errors)
        self.assertIn("duplicate check_id", errors)
        self.assertIn(f"missing required check_id '{missing_id}'", errors)
        self.assertIn("checks[9].check_id must be one of", errors)
        self.assertIn("exactly the fixed walkthrough checks without extras", errors)

    def test_failed_check_must_be_tracked_by_a_finding(self) -> None:
        walkthrough = self.valid_walkthrough()
        walkthrough["checks"][0]["result"] = "fail"

        untracked = self.validate(walkthrough)
        self.assertFalse(untracked["checks"]["failed_checks_tracked"])
        self.assertIn("must be referenced by a finding", "\n".join(untracked["errors"]))

        walkthrough["findings"] = [
            {
                "finding_id": "A11Y-001",
                "severity": "P2",
                "status": "open",
                "summary": "The heading announcement was unclear.",
                "check_ids": [walkthrough["checks"][0]["check_id"]],
            }
        ]
        tracked = self.validate(walkthrough)
        self.assertTrue(tracked["checks"]["failed_checks_tracked"])
        self.assertTrue(tracked["checks"]["no_open_p0_p1_findings"])
        self.assertTrue(tracked["ready_for_review"])

    def test_open_p0_or_p1_blocks_while_open_p2_does_not(self) -> None:
        blocked = self.valid_walkthrough()
        blocked["findings"] = [
            {
                "finding_id": "A11Y-P1",
                "severity": "P1",
                "status": "open",
                "summary": "Keyboard focus cannot reach the recovery action.",
                "check_ids": ["route_and_session_focus"],
            }
        ]
        lower_priority = self.valid_walkthrough()
        lower_priority["findings"] = [
            {
                "finding_id": "A11Y-P2",
                "severity": "P2",
                "status": "open",
                "summary": "A secondary announcement could be shorter.",
                "check_ids": ["processing_status_announcements"],
            }
        ]

        blocked_validation = self.validate(blocked)
        lower_priority_validation = self.validate(lower_priority)

        self.assertFalse(blocked_validation["ready_for_review"])
        self.assertFalse(blocked_validation["checks"]["no_open_p0_p1_findings"])
        self.assertIn("open P1 finding A11Y-P1", "\n".join(blocked_validation["errors"]))
        self.assertTrue(lower_priority_validation["ready_for_review"])

    def test_closed_p0_or_p1_requires_resolution_manual_passed_retest_and_passing_check(self) -> None:
        walkthrough = self.valid_walkthrough()
        walkthrough["checks"][0]["result"] = "fail"
        walkthrough["findings"] = [
            {
                "finding_id": "A11Y-CLOSED-P1",
                "severity": "P1",
                "status": "closed",
                "summary": "The primary heading was not announced.",
                "check_ids": [walkthrough["checks"][0]["check_id"]],
                "resolution": " ",
                "retest": {
                    "result": "fail",
                    "retested_at": "2026-07-14T17:00:00",
                    "observation": " ",
                },
            }
        ]

        validation = self.validate(walkthrough)
        errors = "\n".join(validation["errors"])

        self.assertFalse(validation["ready_for_review"])
        self.assertTrue(validation["checks"]["no_open_p0_p1_findings"])
        self.assertFalse(validation["checks"]["closed_p0_p1_resolution_and_retest_valid"])
        self.assertIn("resolution is required for a closed P1 finding", errors)
        self.assertIn("result must be 'pass'", errors)
        self.assertIn("timezone-aware ISO-8601", errors)
        self.assertIn("must be a non-empty direct observation", errors)
        self.assertIn("cannot close P1 while referenced check", errors)

    def test_closed_p0_with_resolution_and_passed_manual_retest_is_ready(self) -> None:
        walkthrough = self.valid_walkthrough()
        walkthrough["findings"] = [
            {
                "finding_id": "A11Y-CLOSED-P0",
                "severity": "P0",
                "status": "closed",
                "summary": "An earlier build confirmed the wrong destructive action.",
                "check_ids": ["delete_prompt_focus_and_return_cancel"],
                "resolution": "The confirmation flow now requires the explicit destructive button.",
                "retest": {
                    "result": "pass",
                    "retested_at": "2026-07-14T17:30:00+08:00",
                    "observation": "A human observer directly repeated the keyboard-only flow.",
                },
            }
        ]

        report = self.report(walkthrough)

        self.assertTrue(report["ready_for_review"])
        self.assertTrue(report["checks"]["closed_p0_p1_resolution_and_retest_valid"])
        self.assertEqual(1, report["finding_counts"]["P0"]["closed"])

    def test_init_refuses_overwrite_and_writes_private_unattested_template(self) -> None:
        output = self.base / "walkthrough.json"
        arguments = [
            "init",
            str(output),
            "--subject-commit",
            self.subject_commit,
            "--tested-app-path",
            str(self.app_path),
            "--bundle-id",
            self.bundle_id,
            "--cdhash",
            self.cdhash,
            "--macos-version",
            self.macos_version,
            "--codesign-tool",
            str(self.fake_codesign),
            "--task-evidence-report",
            str(self.task_evidence_report),
        ]
        stdout = io.StringIO()
        with contextlib.redirect_stdout(stdout):
            first_result = self.module.main(arguments)
        original = output.read_bytes()
        with contextlib.redirect_stderr(io.StringIO()):
            second_result = self.module.main(arguments)

        written = json.loads(output.read_text(encoding="utf-8"))
        self.assertEqual(0, first_result)
        self.assertEqual(2, second_result)
        self.assertEqual(original, output.read_bytes())
        self.assertEqual(0o600, stat.S_IMODE(output.stat().st_mode))
        self.assertFalse(written["observer_attestation"]["confirmed"])
        self.assertIn("No real-app walkthrough evidence has been recorded", stdout.getvalue())

    def test_validate_and_report_outputs_are_atomic_private_and_do_not_overwrite(self) -> None:
        walkthrough_path = self.base / "walkthrough.json"
        json_output = self.base / "report.json"
        markdown_output = self.base / "report.md"
        walkthrough_path.write_text(json.dumps(self.valid_walkthrough()), encoding="utf-8")
        links: list[tuple[Path, Path]] = []
        real_link = os.link

        def recording_link(source, destination):
            links.append((Path(source), Path(destination)))
            real_link(source, destination)

        with mock.patch.object(self.module.os, "link", side_effect=recording_link):
            with contextlib.redirect_stdout(io.StringIO()):
                result = self.module.main(
                    [
                        "report",
                        str(walkthrough_path),
                        "--json-output",
                        str(json_output),
                        "--markdown-output",
                        str(markdown_output),
                        "--codesign-tool",
                        str(self.fake_codesign),
                    ]
                )

        self.assertEqual(0, result)
        self.assertEqual(2, len(links))
        self.assertTrue(all(source.parent == destination.parent for source, destination in links))
        self.assertTrue(all(not source.exists() for source, _ in links))
        self.assertEqual(0o600, stat.S_IMODE(json_output.stat().st_mode))
        self.assertEqual(0o600, stat.S_IMODE(markdown_output.stat().st_mode))
        self.assertTrue(json.loads(json_output.read_text(encoding="utf-8"))["ready_for_review"])
        self.assertIn("# MVP.1 VoiceOver / 键盘实机走查报告", markdown_output.read_text(encoding="utf-8"))

        original_json = json_output.read_bytes()
        original_markdown = markdown_output.read_bytes()
        with contextlib.redirect_stderr(io.StringIO()):
            second_result = self.module.main(
                [
                    "report",
                    str(walkthrough_path),
                    "--json-output",
                    str(json_output),
                    "--markdown-output",
                    str(markdown_output),
                    "--codesign-tool",
                    str(self.fake_codesign),
                ]
            )
        self.assertEqual(2, second_result)
        self.assertEqual(original_json, json_output.read_bytes())
        self.assertEqual(original_markdown, markdown_output.read_bytes())

    def test_duplicate_output_path_and_input_output_alias_are_rejected(self) -> None:
        walkthrough_path = self.base / "walkthrough.json"
        walkthrough_path.write_text(json.dumps(self.valid_walkthrough()), encoding="utf-8")
        shared_output = self.base / "same-output"
        dangling_target = self.base / "dangling-target.json"
        symlink_output = self.base / "symlink-output.json"
        symlink_output.symlink_to(dangling_target)
        fifo_output = self.base / "fifo-output"
        os.mkfifo(fifo_output)

        with contextlib.redirect_stderr(io.StringIO()):
            duplicate_result = self.module.main(
                [
                    "report",
                    str(walkthrough_path),
                    "--json-output",
                    str(shared_output),
                    "--markdown-output",
                    str(shared_output),
                    "--codesign-tool",
                    str(self.fake_codesign),
                ]
            )
            alias_result = self.module.main(
                [
                    "validate",
                    str(walkthrough_path),
                    "--json-output",
                    str(walkthrough_path),
                    "--codesign-tool",
                    str(self.fake_codesign),
                ]
            )
            symlink_result = self.module.main(
                [
                    "validate",
                    str(walkthrough_path),
                    "--json-output",
                    str(symlink_output),
                    "--codesign-tool",
                    str(self.fake_codesign),
                ]
            )
            fifo_result = self.module.main(
                [
                    "validate",
                    str(walkthrough_path),
                    "--json-output",
                    str(fifo_output),
                    "--codesign-tool",
                    str(self.fake_codesign),
                ]
            )

        self.assertEqual(2, duplicate_result)
        self.assertFalse(shared_output.exists())
        self.assertEqual(2, alias_result)
        self.assertEqual(2, symlink_result)
        self.assertTrue(symlink_output.is_symlink())
        self.assertFalse(dangling_target.exists())
        self.assertEqual(2, fifo_result)
        self.assertTrue(stat.S_ISFIFO(fifo_output.lstat().st_mode))
        self.assertEqual(
            "mvp1-accessibility-test",
            json.loads(walkthrough_path.read_text(encoding="utf-8"))["walkthrough_id"],
        )

    def test_multi_output_publish_failure_rolls_back_already_published_output(self) -> None:
        first = self.base / "first.json"
        second = self.base / "second.md"
        real_link = os.link
        call_count = 0

        def fail_second_link(source, destination):
            nonlocal call_count
            call_count += 1
            if call_count == 2:
                raise OSError("simulated second publish failure")
            real_link(source, destination)

        with mock.patch.object(self.module.os, "link", side_effect=fail_second_link):
            with self.assertRaisesRegex(self.module.WalkthroughToolError, "failed to atomically publish"):
                self.module.atomic_write_outputs([(first, "{}\n"), (second, "report\n")])

        self.assertFalse(first.exists())
        self.assertFalse(second.exists())
        self.assertEqual([], list(self.base.glob(".*.tmp")))

    def test_force_flag_is_rejected_and_cannot_bypass_no_overwrite_policy(self) -> None:
        walkthrough_path = self.base / "walkthrough.json"
        output_path = self.base / "report.json"
        walkthrough_path.write_text(json.dumps(self.valid_walkthrough()), encoding="utf-8")
        output_path.write_text("preserve-existing-output", encoding="utf-8")

        with contextlib.redirect_stderr(io.StringIO()):
            with self.assertRaises(SystemExit) as raised:
                self.module.main(
                    [
                        "validate",
                        str(walkthrough_path),
                        "--json-output",
                        str(output_path),
                        "--codesign-tool",
                        str(self.fake_codesign),
                        "--force",
                    ]
                )

        self.assertEqual(2, raised.exception.code)
        self.assertEqual("preserve-existing-output", output_path.read_text(encoding="utf-8"))

    def test_invalid_json_writes_a_private_machine_readable_blocked_report(self) -> None:
        walkthrough_path = self.base / "invalid.json"
        output_path = self.base / "validation.json"
        walkthrough_path.write_text("{not-json", encoding="utf-8")

        with contextlib.redirect_stdout(io.StringIO()):
            result = self.module.main(
                [
                    "validate",
                    str(walkthrough_path),
                    "--format",
                    "json",
                    "--json-output",
                    str(output_path),
                    "--codesign-tool",
                    str(self.fake_codesign),
                ]
            )

        report = json.loads(output_path.read_text(encoding="utf-8"))
        self.assertEqual(1, result)
        self.assertFalse(report["ready_for_review"])
        self.assertEqual("blocked", report["status"])
        self.assertIn("not valid JSON", report["errors"][0])
        self.assertEqual(0o600, stat.S_IMODE(output_path.stat().st_mode))

    def test_unreadable_walkthrough_writes_a_blocked_report_without_traceback(self) -> None:
        walkthrough_path = self.base / "unreadable.json"
        output_path = self.base / "unreadable-report.json"
        walkthrough_path.write_text("{}\n", encoding="utf-8")
        resolved_walkthrough_path = walkthrough_path.resolve()
        real_read_text = Path.read_text

        def deny_walkthrough_read(path: Path, *args, **kwargs):
            if path.resolve() == resolved_walkthrough_path:
                raise PermissionError("simulated unreadable walkthrough")
            return real_read_text(path, *args, **kwargs)

        with mock.patch.object(Path, "read_text", new=deny_walkthrough_read):
            with contextlib.redirect_stdout(io.StringIO()):
                result = self.module.main(
                    [
                        "validate",
                        str(walkthrough_path),
                        "--json-output",
                        str(output_path),
                        "--codesign-tool",
                        str(self.fake_codesign),
                    ]
                )

        report = json.loads(output_path.read_text(encoding="utf-8"))
        self.assertEqual(1, result)
        self.assertFalse(report["ready_for_review"])
        self.assertIn("simulated unreadable walkthrough", report["errors"][0])
        self.assertEqual(0o600, stat.S_IMODE(output_path.stat().st_mode))


if __name__ == "__main__":
    unittest.main()
