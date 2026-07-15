from __future__ import annotations

import base64
import contextlib
import hashlib
import importlib.util
import io
import json
import os
import stat
import tempfile
import unittest
from unittest import mock
from pathlib import Path


ROOT = Path(__file__).resolve().parents[2]
ONE_PIXEL_PNG = base64.b64decode(
    "iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAYAAAAfFcSJAAAADUlEQVQIHWP4z8DwHwAFgAI/"
    "w78KmwAAAABJRU5ErkJggg=="
)


def load_visual_review_module():
    spec = importlib.util.spec_from_file_location(
        "mvp1_screenshot_visual_review",
        ROOT / "scripts/mvp1-screenshot-visual-review.py",
    )
    assert spec is not None
    module = importlib.util.module_from_spec(spec)
    assert spec.loader is not None
    spec.loader.exec_module(module)
    return module


class MVP1ScreenshotVisualReviewTests(unittest.TestCase):
    def setUp(self) -> None:
        self.module = load_visual_review_module()
        self.subject_commit = "a" * 40
        self.module.current_commit = lambda root=None: self.subject_commit
        self.module._strict_task_evidence_validator = lambda: (
            lambda *, report_path, subject: {}
        )
        self.temporary_directory = tempfile.TemporaryDirectory()
        self.base = Path(self.temporary_directory.name)
        self.screenshot_directory = self.base / "screenshots"
        self.screenshot_directory.mkdir()
        screenshot_items = []
        for name in self.module.REQUIRED_SCREENSHOTS:
            path = self.screenshot_directory / f"{name}.png"
            path.write_bytes(ONE_PIXEL_PNG)
            screenshot_items.append(
                {
                    "name": name,
                    "path": str(path),
                    "sha256": hashlib.sha256(path.read_bytes()).hexdigest(),
                    "width": 1,
                    "height": 1,
                }
            )
        self.task_report = self.base / "mvp1-task-xcresult-report.json"
        self.task_report.write_text(
            json.dumps(
                {
                    "schema_version": 2,
                    "release_gate": "mvp1-task-xcresult-evidence",
                    "passed": True,
                    "upstream_test_status": 0,
                    "subject_commit": self.subject_commit,
                    "subject_commit_before_test": self.subject_commit,
                    "summary": dict(self.module.REQUIRED_TASK_SUMMARY),
                    "screenshot_visual_review": "pending",
                    "fixture_checks_passed": None,
                    "app_identity": {},
                    "attachments": {"exported_screenshots": screenshot_items},
                }
            ),
            encoding="utf-8",
        )

    def tearDown(self) -> None:
        self.temporary_directory.cleanup()

    def template(self) -> dict:
        return self.module.build_template(
            task_evidence_report=str(self.task_report),
            subject_commit=self.subject_commit,
            review_id="mvp1-screenshot-visual-review-test",
        )

    def valid_review(self) -> dict:
        review = self.template()
        review["reviewer_attestation"] = {
            "confirmed": True,
            "attested_at": "2026-07-15T16:00:00+08:00",
            "attested_by_role": "manual-visual-reviewer",
            "statement": self.module.ATTESTATION_STATEMENT,
            "synthetic_data_confirmed": True,
            "privacy_statement": self.module.PRIVACY_ATTESTATION_STATEMENT,
        }
        for screenshot in review["screenshots"]:
            screenshot["result"] = "pass"
            screenshot["observation"] = f"Human visual observation for {screenshot['name']}."
        return review

    def validate(self, review: object) -> dict:
        return self.module.validate_visual_review(
            review,
            expected_subject_commit=self.subject_commit,
        )

    def test_valid_flow_binds_exact_task_evidence_and_renders_report(self) -> None:
        review = self.valid_review()
        report = self.module.build_report(
            review,
            source="review.json",
            expected_subject_commit=self.subject_commit,
        )
        markdown = self.module.render_markdown(report)

        self.assertTrue(report["ready_for_review"])
        self.assertEqual(report["status"], "ready_for_review")
        self.assertEqual(report["recorded_screenshot_count"], 8)
        self.assertEqual(
            [item["name"] for item in review["task_evidence"]["screenshots"]],
            list(self.module.REQUIRED_SCREENSHOTS),
        )
        self.assertTrue(report["checks"]["subject_binding_valid"])
        self.assertIn("截图人工视觉审查报告", markdown)
        self.assertIn("不等于产品验收或发布就绪", markdown)

    def test_template_cli_prints_a_bound_unattested_template(self) -> None:
        stdout = io.StringIO()
        with contextlib.redirect_stdout(stdout):
            result = self.module.main(
                [
                    "template",
                    "--task-evidence-report",
                    str(self.task_report),
                    "--subject-commit",
                    self.subject_commit,
                    "--review-id",
                    "template-cli-test",
                ]
            )
        template = json.loads(stdout.getvalue())

        self.assertEqual(result, 0)
        self.assertEqual(template["review_id"], "template-cli-test")
        self.assertFalse(template["reviewer_attestation"]["confirmed"])
        self.assertEqual(
            [item["name"] for item in template["screenshots"]],
            list(self.module.REQUIRED_SCREENSHOTS),
        )

    def test_subject_mismatch_blocks_even_when_the_review_fields_look_complete(self) -> None:
        review = self.valid_review()
        review["subject_commit"] = "b" * 40

        validation = self.validate(review)

        self.assertFalse(validation["ready_for_review"])
        self.assertFalse(validation["checks"]["subject_binding_valid"])
        self.assertIn("does not match current Git HEAD", "\n".join(validation["errors"]))

    def test_task_report_must_retain_pending_visual_review_state(self) -> None:
        report = json.loads(self.task_report.read_text(encoding="utf-8"))
        report["screenshot_visual_review"] = "complete"
        self.task_report.write_text(json.dumps(report), encoding="utf-8")

        with self.assertRaisesRegex(
            self.module.VisualReviewToolError,
            "screenshot_visual_review='pending'",
        ):
            self.template()

    def test_fixture_task_report_cannot_be_used_as_human_review_evidence(self) -> None:
        report = json.loads(self.task_report.read_text(encoding="utf-8"))
        report["fixture_checks_passed"] = True
        self.task_report.write_text(json.dumps(report), encoding="utf-8")

        with self.assertRaisesRegex(
            self.module.VisualReviewToolError,
            "trusted production evidence",
        ):
            self.template()

    def test_unattested_template_cannot_be_counted_as_human_visual_review(self) -> None:
        review = self.template()
        for screenshot in review["screenshots"]:
            screenshot["result"] = "pass"
            screenshot["observation"] = "A human observation would be required here."

        validation = self.validate(review)

        self.assertFalse(validation["ready_for_review"])
        self.assertFalse(validation["checks"]["manual_human_attestation_valid"])
        self.assertIn("human visual observer", "\n".join(validation["errors"]))

    def test_failed_screenshot_without_matching_finding_blocks(self) -> None:
        review = self.valid_review()
        review["screenshots"][2]["result"] = "fail"
        review["screenshots"][2]["observation"] = "Human reviewer saw a clipped primary action."

        validation = self.validate(review)

        self.assertFalse(validation["ready_for_review"])
        self.assertFalse(validation["checks"]["failed_screenshots_tracked"])
        self.assertIn("failed screenshot", "\n".join(validation["errors"]))

    def test_open_high_severity_finding_blocks(self) -> None:
        review = self.valid_review()
        review["findings"] = [
            {
                "finding_id": "VR-001",
                "severity": "P1",
                "status": "open",
                "summary": "A human reviewer could not identify the destructive action safely.",
                "screenshot_names": ["07-diagnostics"],
            }
        ]

        validation = self.validate(review)

        self.assertFalse(validation["ready_for_review"])
        self.assertFalse(validation["checks"]["no_open_p0_p1_findings"])
        self.assertIn("open P1 finding VR-001", "\n".join(validation["errors"]))

    def test_closed_high_severity_finding_requires_resolution_and_passed_human_retest(self) -> None:
        review = self.valid_review()
        review["findings"] = [
            {
                "finding_id": "VR-002",
                "severity": "P0",
                "status": "closed",
                "summary": "An earlier build exposed the wrong destructive target.",
                "screenshot_names": ["04-recording-saved"],
                "resolution": " ",
            }
        ]

        validation = self.validate(review)

        self.assertFalse(validation["ready_for_review"])
        self.assertFalse(
            validation["checks"]["closed_p0_p1_resolution_and_human_retest_valid"]
        )
        errors = "\n".join(validation["errors"])
        self.assertIn("resolution is required", errors)
        self.assertIn("retest is required", errors)

    def test_screenshot_hash_mismatch_blocks_the_subject_binding(self) -> None:
        review = self.valid_review()
        screenshot_path = self.screenshot_directory / "00-meetings-recent.png"
        screenshot_path.write_bytes(ONE_PIXEL_PNG + b"changed")

        validation = self.validate(review)

        self.assertFalse(validation["ready_for_review"])
        self.assertFalse(validation["checks"]["subject_binding_valid"])
        self.assertIn("SHA-256 does not match", "\n".join(validation["errors"]))

    def test_init_is_atomic_private_and_refuses_existing_or_symlink_target(self) -> None:
        output = self.base / "review.json"
        stdout = io.StringIO()
        with contextlib.redirect_stdout(stdout):
            first = self.module.main(
                [
                    "init",
                    str(output),
                    "--task-evidence-report",
                    str(self.task_report),
                    "--subject-commit",
                    self.subject_commit,
                ]
            )
        original_bytes = output.read_bytes()
        with contextlib.redirect_stderr(io.StringIO()):
            second = self.module.main(
                [
                    "init",
                    str(output),
                    "--task-evidence-report",
                    str(self.task_report),
                    "--subject-commit",
                    self.subject_commit,
                ]
            )
        sentinel = self.base / "sentinel.json"
        sentinel.write_text("do not replace", encoding="utf-8")
        symlink_output = self.base / "unsafe-link.json"
        symlink_output.symlink_to(sentinel)
        with contextlib.redirect_stderr(io.StringIO()):
            unsafe = self.module.main(
                [
                    "init",
                    str(symlink_output),
                    "--task-evidence-report",
                    str(self.task_report),
                    "--subject-commit",
                    self.subject_commit,
                ]
            )

        self.assertEqual(first, 0)
        self.assertEqual(second, 2)
        self.assertEqual(unsafe, 2)
        self.assertEqual(stat.S_IMODE(output.stat().st_mode), 0o600)
        self.assertEqual(output.read_bytes(), original_bytes)
        self.assertEqual(sentinel.read_text(encoding="utf-8"), "do not replace")
        self.assertIn("No human visual evidence", stdout.getvalue())

    def test_cli_validate_and_report_bind_the_current_subject(self) -> None:
        review_path = self.base / "review.json"
        validation_json = self.base / "validation.json"
        report_json = self.base / "report.json"
        report_markdown = self.base / "report.md"
        review_path.write_text(json.dumps(self.valid_review()), encoding="utf-8")
        stdout = io.StringIO()
        with contextlib.redirect_stdout(stdout):
            validate_result = self.module.main(
                [
                    "validate",
                    str(review_path),
                    "--format",
                    "json",
                    "--json-output",
                    str(validation_json),
                ]
            )
            report_result = self.module.main(
                [
                    "report",
                    str(review_path),
                    "--json-output",
                    str(report_json),
                    "--markdown-output",
                    str(report_markdown),
                ]
            )

        self.assertEqual(validate_result, 0)
        self.assertEqual(report_result, 0)
        self.assertIn("ready_for_review", stdout.getvalue())
        self.assertIn("截图人工视觉审查报告", stdout.getvalue())
        self.assertTrue(json.loads(validation_json.read_text(encoding="utf-8"))["ready_for_review"])
        self.assertTrue(json.loads(report_json.read_text(encoding="utf-8"))["ready_for_review"])
        self.assertIn("截图人工视觉审查报告", report_markdown.read_text(encoding="utf-8"))
        for output in (validation_json, report_json, report_markdown):
            self.assertEqual(stat.S_IMODE(output.stat().st_mode), 0o600)
        with contextlib.redirect_stderr(io.StringIO()):
            repeated_output = self.module.main(
                [
                    "validate",
                    str(review_path),
                    "--json-output",
                    str(validation_json),
                ]
            )
        self.assertEqual(repeated_output, 2)


    def test_symlink_task_report_or_screenshot_is_rejected(self) -> None:
        report_link = self.base / "task-report-link.json"
        report_link.symlink_to(self.task_report)
        with self.assertRaisesRegex(
            self.module.VisualReviewToolError,
            "regular non-symlink",
        ):
            self.module.build_template(
                task_evidence_report=str(report_link),
                subject_commit=self.subject_commit,
            )

        screenshot_path = self.screenshot_directory / "00-meetings-recent.png"
        screenshot_path.unlink()
        screenshot_path.symlink_to(self.base / "missing.png")
        with self.assertRaisesRegex(
            self.module.VisualReviewToolError,
            "regular non-symlink",
        ):
            self.template()

    def test_minimal_handwritten_task_report_fails_strict_trusted_provenance(self) -> None:
        strict_module = load_visual_review_module()
        strict_module.current_commit = lambda root=None: self.subject_commit

        with self.assertRaisesRegex(
            strict_module.VisualReviewToolError,
            "strict trusted provenance",
        ):
            strict_module.build_template(
                task_evidence_report=str(self.task_report),
                subject_commit=self.subject_commit,
            )

    def test_historical_subject_is_rejected_by_the_cli(self) -> None:
        stderr = io.StringIO()
        with contextlib.redirect_stderr(stderr):
            result = self.module.main(
                [
                    "template",
                    "--task-evidence-report",
                    str(self.task_report),
                    "--subject-commit",
                    "b" * 40,
                ]
            )

        self.assertEqual(result, 2)
        self.assertIn("must equal current Git HEAD", stderr.getvalue())

    def test_private_text_and_failed_closed_retest_are_rejected(self) -> None:
        review = self.valid_review()
        review["screenshots"][0]["observation"] = "Reviewer email is person@example.com."
        review["findings"] = [
            {
                "finding_id": "VR-003",
                "severity": "P1",
                "status": "closed",
                "summary": "The visual hierarchy was repaired.",
                "screenshot_names": ["00-meetings-recent"],
                "resolution": "The primary action now has a stable label.",
                "retest": {
                    "human_retested": True,
                    "result": "failed",
                    "retested_at": "2026-07-15T16:10:00+08:00",
                    "observation": "The primary action is still unclear.",
                },
            }
        ]

        validation = self.validate(review)

        self.assertFalse(validation["ready_for_review"])
        errors = "\n".join(validation["errors"])
        self.assertIn("email address", errors)
        self.assertIn("must be 'passed'", errors)

    def test_closed_high_severity_finding_with_passed_human_retest_is_allowed(self) -> None:
        review = self.valid_review()
        review["findings"] = [
            {
                "finding_id": "VR-004",
                "severity": "P0",
                "status": "closed",
                "summary": "The destructive-action label was clarified.",
                "screenshot_names": ["07-diagnostics"],
                "resolution": "The action label now names the affected meeting.",
                "retest": {
                    "human_retested": True,
                    "result": "passed",
                    "retested_at": "2026-07-15T16:20:00+08:00",
                    "observation": "The corrected label is clear in the reviewed screenshot.",
                },
            }
        ]

        validation = self.validate(review)

        self.assertTrue(validation["ready_for_review"])

    def test_current_commit_uses_a_clean_git_environment(self) -> None:
        strict_module = load_visual_review_module()
        completed = mock.Mock(returncode=0, stdout=self.subject_commit + "\n")
        with mock.patch.object(strict_module.subprocess, "run", return_value=completed) as run:
            self.assertEqual(strict_module.current_commit(), self.subject_commit)

        self.assertEqual(run.call_args.kwargs["env"], strict_module.clean_git_environment())


if __name__ == "__main__":
    unittest.main()
