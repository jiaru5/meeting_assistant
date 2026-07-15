from __future__ import annotations

import contextlib
import importlib.util
import io
import json
import os
import stat
import tempfile
import unittest
from pathlib import Path
from unittest import mock


ROOT = Path(__file__).resolve().parents[2]


def load_study_module():
    spec = importlib.util.spec_from_file_location(
        "mvp1_experience_study",
        ROOT / "scripts/mvp1-experience-study.py",
    )
    assert spec is not None
    module = importlib.util.module_from_spec(spec)
    assert spec.loader is not None
    spec.loader.exec_module(module)
    return module


class MVP1ExperienceStudyTests(unittest.TestCase):
    def setUp(self) -> None:
        self.module = load_study_module()

    def valid_study(self, participant_count: int = 3) -> dict:
        study = self.module.build_template(
            participant_count,
            subject_commit="a" * 40,
            study_id="mvp1-study-test",
        )
        for participant_index, participant in enumerate(study["participants"], start=1):
            participant["human_attestation"] = {
                "confirmed": True,
                "attested_at": f"2026-07-{participant_index:02d}T10:00:00+08:00",
                "attested_by_role": "researcher",
                "statement": self.module.ATTESTATION_STATEMENT,
            }
            for task_index, task in enumerate(participant["tasks"], start=1):
                task.update(
                    {
                        "outcome": "completed",
                        "duration_seconds": participant_index * 10 + task_index,
                        "help_count": 0,
                        "misclick_count": task_index - 1,
                        "hesitation_count": participant_index - 1,
                        "state_understanding": "clear",
                        "observation": "Anonymous task observation without personal data.",
                    }
                )
        return study

    def test_template_is_explicitly_unattested_and_cannot_validate_as_human_evidence(self) -> None:
        template = self.module.build_template(3, subject_commit="a" * 40)

        self.assertEqual(len(template["participants"]), 3)
        self.assertEqual(
            {task["task_id"] for task in template["participants"][0]["tasks"]},
            set(self.module.REQUIRED_TASK_IDS),
        )
        self.assertTrue(
            all(
                participant["human_attestation"]["confirmed"] is False
                for participant in template["participants"]
            )
        )
        self.assertFalse(self.module.validate_study(template)["ready_for_review"])

    def test_valid_three_person_study_is_ready_without_metric_thresholds(self) -> None:
        report = self.module.build_report(self.valid_study(3), source="study.json")

        self.assertTrue(report["ready_for_review"])
        self.assertEqual(report["status"], "ready_for_review")
        self.assertEqual(report["participant_count"], 3)
        self.assertEqual(report["manually_attested_participant_count"], 3)
        self.assertFalse(report["checks"]["metric_thresholds_applied"])
        self.assertFalse(report["evidence_boundary"]["metric_thresholds_applied"])
        self.assertTrue(report["evidence_boundary"]["not_product_acceptance"])
        self.assertTrue(report["evidence_boundary"]["not_release_readiness"])

    def test_five_person_study_is_within_allowed_range(self) -> None:
        validation = self.module.validate_study(self.valid_study(5))

        self.assertTrue(validation["ready_for_review"])
        self.assertEqual(validation["participant_count"], 5)

    def test_two_or_six_participants_fail_the_count_check(self) -> None:
        two_person = self.valid_study(3)
        two_person["participants"] = two_person["participants"][:2]
        six_person = self.valid_study(5)
        sixth = self.module.participant_template(6)
        sixth["human_attestation"] = {
            "confirmed": True,
            "attested_at": "2026-07-06T10:00:00+08:00",
            "attested_by_role": "researcher",
            "statement": self.module.ATTESTATION_STATEMENT,
        }
        for task in sixth["tasks"]:
            task.update(
                {
                    "outcome": "completed",
                    "duration_seconds": 20,
                    "help_count": 0,
                    "misclick_count": 0,
                    "hesitation_count": 0,
                    "state_understanding": "clear",
                }
            )
        six_person["participants"].append(sixth)

        two_validation = self.module.validate_study(two_person)
        six_validation = self.module.validate_study(six_person)

        self.assertFalse(two_validation["checks"]["participant_count_valid"])
        self.assertFalse(six_validation["checks"]["participant_count_valid"])
        self.assertIn("found 2", "\n".join(two_validation["errors"]))
        self.assertIn("found 6", "\n".join(six_validation["errors"]))

    def test_all_three_tasks_and_observation_fields_are_required_structurally(self) -> None:
        study = self.valid_study()
        study["participants"][0]["tasks"] = study["participants"][0]["tasks"][:2]
        del study["participants"][1]["tasks"][0]["help_count"]

        validation = self.module.validate_study(study)
        errors = "\n".join(validation["errors"])

        self.assertFalse(validation["checks"]["structure_valid"])
        self.assertIn("missing required task_id 'failure_recovery'", errors)
        self.assertIn("help_count is required", errors)

    def test_automation_or_xcuitest_cannot_be_declared_as_a_participant(self) -> None:
        study = self.valid_study()
        study["participants"][0]["session_type"] = "xcuitest"
        study["evidence_policy"]["automation_counts_as_participant"] = True
        study["evidence_policy"]["screenshot_counts_as_participant"] = True

        validation = self.module.validate_study(study)
        errors = "\n".join(validation["errors"])

        self.assertFalse(validation["ready_for_review"])
        self.assertIn("automation cannot be a participant", errors)
        self.assertIn("automation_counts_as_participant must be False", errors)
        self.assertIn("screenshot_counts_as_participant must be False", errors)

    def test_manual_attestation_must_be_confirmed_timestamped_and_explicit(self) -> None:
        study = self.valid_study()
        attestation = study["participants"][0]["human_attestation"]
        attestation["confirmed"] = False
        attestation["attested_at"] = "2026-07-01T10:00:00"
        attestation["statement"] = "XCUITest passed."

        validation = self.module.validate_study(study)
        errors = "\n".join(validation["errors"])

        self.assertFalse(validation["checks"]["manual_human_attestation_valid"])
        self.assertIn("only after a human observer attests", errors)
        self.assertIn("timezone-aware ISO-8601", errors)
        self.assertIn("manual human attestation statement", errors)

    def test_participant_alias_is_anonymous_and_name_fields_are_rejected(self) -> None:
        study = self.valid_study()
        study["participants"][0]["participant_id"] = "Alice"
        study["participants"][0]["name"] = "Alice Example"

        validation = self.module.validate_study(study)
        errors = "\n".join(validation["errors"])

        self.assertFalse(validation["checks"]["structure_valid"])
        self.assertIn("anonymous alias such as P01", errors)
        self.assertIn("participants[0].name is not allowed", errors)

    def test_open_p0_or_p1_blocks_but_open_p2_does_not(self) -> None:
        blocked = self.valid_study()
        blocked["findings"] = [
            {
                "finding_id": "F-001",
                "severity": "P1",
                "status": "open",
                "summary": "Participant could not identify the recovery action.",
                "task_id": "failure_recovery",
                "participant_ids": ["P01"],
            }
        ]
        lower_priority = self.valid_study()
        lower_priority["findings"] = [
            {
                "finding_id": "F-002",
                "severity": "P2",
                "status": "open",
                "summary": "A secondary label caused hesitation.",
                "task_id": "first_use",
                "participant_ids": ["P02"],
            }
        ]

        blocked_validation = self.module.validate_study(blocked)
        lower_priority_validation = self.module.validate_study(lower_priority)
        lower_priority_markdown = self.module.render_markdown(
            self.module.build_report(lower_priority)
        )

        self.assertFalse(blocked_validation["ready_for_review"])
        self.assertFalse(blocked_validation["checks"]["no_open_p0_p1_findings"])
        self.assertTrue(lower_priority_validation["ready_for_review"])
        self.assertIn("F-002", lower_priority_markdown)
        self.assertIn("P2", lower_priority_markdown)

    def test_malformed_finding_references_and_non_finite_duration_fail_cleanly(self) -> None:
        study = self.valid_study()
        study["participants"][0]["tasks"][0]["duration_seconds"] = float("inf")
        study["findings"] = [
            {
                "finding_id": "F-INVALID",
                "severity": "P2",
                "status": "open",
                "summary": "Malformed reference fixture.",
                "task_id": "first_use",
                "participant_ids": [{"not": "an alias"}],
            }
        ]

        validation = self.module.validate_study(study)
        errors = "\n".join(validation["errors"])

        self.assertFalse(validation["ready_for_review"])
        self.assertIn("duration_seconds must be a positive number", errors)
        self.assertIn("must contain only participant aliases", errors)

    def test_closed_p0_is_recorded_but_does_not_block(self) -> None:
        study = self.valid_study()
        study["findings"] = [
            {
                "finding_id": "F-003",
                "severity": "P0",
                "status": "closed",
                "summary": "A destructive action targeted the wrong session in an earlier build.",
                "task_id": "cross_task",
                "participant_ids": ["P01"],
                "resolution": "Retested with the corrected build.",
                "retested": True,
                "retest_result": "passed",
            }
        ]

        report = self.module.build_report(study)

        self.assertTrue(report["ready_for_review"])
        self.assertEqual(report["finding_counts"]["P0"]["closed"], 1)
        self.assertTrue(report["checks"]["closed_p0_p1_manual_retest_valid"])

    def test_closed_p0_or_p1_requires_resolution_and_passed_manual_retest(self) -> None:
        study = self.valid_study()
        study["findings"] = [
            {
                "finding_id": "F-004",
                "severity": "P1",
                "status": "closed",
                "summary": "Recovery action was not discoverable.",
                "task_id": "failure_recovery",
                "participant_ids": ["P01"],
                "resolution": " ",
                "retested": False,
                "retest_result": "failed",
            }
        ]

        validation = self.module.validate_study(study)
        errors = "\n".join(validation["errors"])

        self.assertFalse(validation["ready_for_review"])
        self.assertTrue(validation["checks"]["no_open_p0_p1_findings"])
        self.assertFalse(validation["checks"]["closed_p0_p1_manual_retest_valid"])
        self.assertIn("resolution must be non-empty", errors)
        self.assertIn("manual human retest", errors)
        self.assertIn("retest_result must be 'passed'", errors)

    def test_closed_p2_remains_compatible_without_retest_fields(self) -> None:
        study = self.valid_study()
        study["findings"] = [
            {
                "finding_id": "F-005",
                "severity": "P2",
                "status": "closed",
                "summary": "Secondary copy caused hesitation.",
                "task_id": "return_visit",
                "participant_ids": ["P02"],
            }
        ]

        self.assertTrue(self.module.validate_study(study)["ready_for_review"])

    def test_report_aggregates_observations_without_applying_acceptance_thresholds(self) -> None:
        study = self.valid_study()
        study["participants"][0]["tasks"][0].update(
            {
                "outcome": "not_completed",
                "help_count": 3,
                "state_understanding": "unclear",
            }
        )

        report = self.module.build_report(study)
        metrics = report["task_metrics"]["first_use"]
        markdown = self.module.render_markdown(report)

        self.assertTrue(report["ready_for_review"])
        self.assertEqual(metrics["outcomes"]["not_completed"], 1)
        self.assertEqual(metrics["help_count"], 3)
        self.assertIn("指标通过阈值：未定义、未应用", markdown)
        self.assertIn("不能计为真人参与者", markdown)
        self.assertIn("不能独立证明参与者身份", markdown)
        self.assertIn("不得记录姓名或联系方式", markdown)
        self.assertIn("不等于产品验收或发布就绪", markdown)

    def test_init_refuses_overwrite_and_never_marks_attestation_true(self) -> None:
        with tempfile.TemporaryDirectory() as directory:
            output = Path(directory) / "study.json"
            stdout = io.StringIO()
            with contextlib.redirect_stdout(stdout):
                first_result = self.module.main(
                    ["init", str(output), "--subject-commit", "b" * 40]
                )
            with contextlib.redirect_stderr(io.StringIO()):
                second_result = self.module.main(
                    ["init", str(output), "--subject-commit", "b" * 40]
                )

            written = json.loads(output.read_text(encoding="utf-8"))
            self.assertEqual(first_result, 0)
            self.assertEqual(second_result, 2)
            self.assertIn("No human evidence has been recorded yet", stdout.getvalue())
            self.assertEqual(stat.S_IMODE(output.stat().st_mode), 0o600)
            self.assertTrue(
                all(
                    participant["human_attestation"]["confirmed"] is False
                    for participant in written["participants"]
                )
            )
            preserved = output.read_bytes()
            with contextlib.redirect_stderr(io.StringIO()):
                with self.assertRaises(SystemExit) as force_error:
                    self.module.main(
                        ["init", str(output), "--subject-commit", "c" * 40, "--force"]
                    )
            self.assertEqual(force_error.exception.code, 2)
            self.assertEqual(output.read_bytes(), preserved)

    def test_validate_and_report_write_machine_and_markdown_outputs(self) -> None:
        with tempfile.TemporaryDirectory() as directory:
            base = Path(directory)
            study_path = base / "study.json"
            validation_path = base / "validation.json"
            report_path = base / "report.json"
            markdown_path = base / "report.md"
            study_path.write_text(
                json.dumps(self.valid_study(), ensure_ascii=False),
                encoding="utf-8",
            )

            with contextlib.redirect_stdout(io.StringIO()):
                validate_result = self.module.main(
                    [
                        "validate",
                        str(study_path),
                        "--format",
                        "json",
                        "--json-output",
                        str(validation_path),
                        "--allow-historical-subject",
                    ]
                )
                report_result = self.module.main(
                    [
                        "report",
                        str(study_path),
                        "--json-output",
                        str(report_path),
                        "--markdown-output",
                        str(markdown_path),
                        "--allow-historical-subject",
                    ]
                )

            self.assertEqual(validate_result, 0)
            self.assertEqual(report_result, 0)
            self.assertTrue(json.loads(validation_path.read_text(encoding="utf-8"))["ready_for_review"])
            self.assertTrue(json.loads(report_path.read_text(encoding="utf-8"))["ready_for_review"])
            self.assertIn("# MVP.1 真人体验研究报告", markdown_path.read_text(encoding="utf-8"))
            self.assertEqual(stat.S_IMODE(validation_path.stat().st_mode), 0o600)
            self.assertEqual(stat.S_IMODE(report_path.stat().st_mode), 0o600)
            self.assertEqual(stat.S_IMODE(markdown_path.stat().st_mode), 0o600)

    def test_validate_and_report_refuse_input_output_and_cross_output_conflicts(self) -> None:
        with tempfile.TemporaryDirectory() as directory:
            study_path = Path(directory) / "study.json"
            study_path.write_text(json.dumps(self.valid_study()), encoding="utf-8")

            with contextlib.redirect_stderr(io.StringIO()):
                validate_result = self.module.main(
                    ["validate", str(study_path), "--json-output", str(study_path), "--force"]
                )
                report_result = self.module.main(
                    [
                        "report",
                        str(study_path),
                        "--json-output",
                        str(Path(directory) / "same-output"),
                        "--markdown-output",
                        str(Path(directory) / "same-output"),
                        "--force",
                    ]
                )

            self.assertEqual(validate_result, 2)
            self.assertEqual(report_result, 2)
            self.assertEqual(json.loads(study_path.read_text(encoding="utf-8"))["study_id"], "mvp1-study-test")

    def test_output_aliases_are_rejected_even_when_force_is_explicit(self) -> None:
        with tempfile.TemporaryDirectory() as directory:
            base = Path(directory)
            study_path = base / "study.json"
            alias_path = base / "study-alias.json"
            study_path.write_text(json.dumps(self.valid_study()), encoding="utf-8")
            os.link(study_path, alias_path)

            with contextlib.redirect_stderr(io.StringIO()):
                result = self.module.main(
                    ["validate", str(study_path), "--json-output", str(alias_path), "--force"]
                )

            self.assertEqual(result, 2)
            self.assertEqual(json.loads(study_path.read_text(encoding="utf-8"))["study_id"], "mvp1-study-test")

    def test_validate_and_report_refuse_existing_outputs_without_force(self) -> None:
        with tempfile.TemporaryDirectory() as directory:
            base = Path(directory)
            study_path = base / "study.json"
            validation_path = base / "validation.json"
            markdown_path = base / "report.md"
            study_path.write_text(json.dumps(self.valid_study()), encoding="utf-8")
            validation_path.write_text("preserve-validation", encoding="utf-8")
            markdown_path.write_text("preserve-markdown", encoding="utf-8")

            with contextlib.redirect_stderr(io.StringIO()):
                validate_result = self.module.main(
                    ["validate", str(study_path), "--json-output", str(validation_path)]
                )
                report_result = self.module.main(
                    ["report", str(study_path), "--markdown-output", str(markdown_path)]
                )

            self.assertEqual(validate_result, 2)
            self.assertEqual(report_result, 2)
            self.assertEqual(validation_path.read_text(encoding="utf-8"), "preserve-validation")
            self.assertEqual(markdown_path.read_text(encoding="utf-8"), "preserve-markdown")

    def test_force_atomically_replaces_outputs_in_same_directory_with_private_mode(self) -> None:
        with tempfile.TemporaryDirectory() as directory:
            base = Path(directory)
            study_path = base / "study.json"
            report_path = base / "report.json"
            markdown_path = base / "report.md"
            study_path.write_text(json.dumps(self.valid_study()), encoding="utf-8")
            report_path.write_text("old", encoding="utf-8")
            markdown_path.write_text("old", encoding="utf-8")
            with contextlib.redirect_stdout(io.StringIO()):
                result = self.module.main(
                    [
                        "report",
                        str(study_path),
                        "--json-output",
                        str(report_path),
                        "--markdown-output",
                        str(markdown_path),
                        "--force",
                        "--allow-historical-subject",
                    ]
                )

            self.assertEqual(result, 0)
            self.assertEqual(stat.S_IMODE(report_path.stat().st_mode), 0o600)
            self.assertEqual(stat.S_IMODE(markdown_path.stat().st_mode), 0o600)
            self.assertTrue(json.loads(report_path.read_text(encoding="utf-8"))["ready_for_review"])
            self.assertFalse(any(base.glob(".*.tmp")))
            self.assertFalse(any(base.glob(".*.bak")))

    def test_force_batch_publish_failure_restores_every_previous_output(self) -> None:
        with tempfile.TemporaryDirectory() as directory:
            base = Path(directory)
            study_path = base / "study.json"
            report_path = base / "report.json"
            markdown_path = base / "report.md"
            study_path.write_text(json.dumps(self.valid_study()), encoding="utf-8")
            report_path.write_text("old-json", encoding="utf-8")
            markdown_path.write_text("old-markdown", encoding="utf-8")
            report_path.chmod(0o640)
            markdown_path.chmod(0o644)
            real_replace = os.replace

            def fail_markdown_publish(source, destination):
                source_path = Path(source)
                destination_path = Path(destination)
                if source_path.suffix == ".tmp" and destination_path == markdown_path:
                    raise OSError("simulated second publish failure")
                real_replace(source, destination)

            with mock.patch.object(
                self.module.os,
                "replace",
                side_effect=fail_markdown_publish,
            ):
                with contextlib.redirect_stderr(io.StringIO()):
                    result = self.module.main(
                        [
                            "report",
                            str(study_path),
                            "--json-output",
                            str(report_path),
                            "--markdown-output",
                            str(markdown_path),
                            "--force",
                            "--allow-historical-subject",
                        ]
                    )

            self.assertEqual(result, 2)
            self.assertEqual(report_path.read_text(encoding="utf-8"), "old-json")
            self.assertEqual(markdown_path.read_text(encoding="utf-8"), "old-markdown")
            self.assertEqual(stat.S_IMODE(report_path.stat().st_mode), 0o640)
            self.assertEqual(stat.S_IMODE(markdown_path.stat().st_mode), 0o644)
            self.assertFalse(any(base.glob(".*.tmp")))
            self.assertFalse(any(base.glob(".*.bak")))

    def test_force_cli_refuses_existing_directory_output_without_moving_it(self) -> None:
        with tempfile.TemporaryDirectory() as directory:
            base = Path(directory)
            study_path = base / "study.json"
            output_directory = base / "report.json"
            sentinel = output_directory / "sentinel.txt"
            study_path.write_text(json.dumps(self.valid_study()), encoding="utf-8")
            output_directory.mkdir()
            sentinel.write_text("preserve", encoding="utf-8")

            with contextlib.redirect_stderr(io.StringIO()):
                result = self.module.main(
                    [
                        "report",
                        str(study_path),
                        "--json-output",
                        str(output_directory),
                        "--force",
                        "--allow-historical-subject",
                    ]
                )

            self.assertEqual(result, 2)
            self.assertTrue(output_directory.is_dir())
            self.assertEqual(sentinel.read_text(encoding="utf-8"), "preserve")
            self.assertFalse(any(base.glob(".*.tmp")))
            self.assertFalse(any(base.glob(".*.bak")))

    def test_write_outputs_refuses_existing_directory_without_preflight(self) -> None:
        with tempfile.TemporaryDirectory() as directory:
            base = Path(directory)
            output_directory = base / "direct.json"
            sentinel = output_directory / "sentinel.txt"
            output_directory.mkdir()
            sentinel.write_text("preserve", encoding="utf-8")

            with self.assertRaises(self.module.StudyToolError):
                self.module.write_outputs([(output_directory, "replacement")], force=True)

            self.assertTrue(output_directory.is_dir())
            self.assertEqual(sentinel.read_text(encoding="utf-8"), "preserve")
            self.assertFalse(any(base.glob(".*.tmp")))
            self.assertFalse(any(base.glob(".*.bak")))

    def test_force_reserves_backup_name_until_existing_output_is_moved(self) -> None:
        with tempfile.TemporaryDirectory() as directory:
            base = Path(directory)
            output_path = base / "report.json"
            output_path.write_text("old", encoding="utf-8")
            real_replace = os.replace
            backup_reservations: list[bool] = []

            def observe_backup_reservation(source, destination):
                destination_path = Path(destination)
                if destination_path.suffix == ".bak":
                    backup_reservations.append(destination_path.is_file())
                real_replace(source, destination)

            with mock.patch.object(
                self.module.os,
                "replace",
                side_effect=observe_backup_reservation,
            ):
                self.module.write_outputs([(output_path, "new")], force=True)

            self.assertEqual(backup_reservations, [True])
            self.assertEqual(output_path.read_text(encoding="utf-8"), "new")
            self.assertEqual(stat.S_IMODE(output_path.stat().st_mode), 0o600)
            self.assertFalse(any(base.glob(".*.tmp")))
            self.assertFalse(any(base.glob(".*.bak")))

    def test_force_backup_cleanup_failure_is_controlled_and_reports_retained_old_bytes(self) -> None:
        with tempfile.TemporaryDirectory() as directory:
            base = Path(directory)
            study_path = base / "study.json"
            output_path = base / "report.json"
            study_path.write_text(json.dumps(self.valid_study()), encoding="utf-8")
            output_path.write_text("old-report", encoding="utf-8")
            real_unlink = Path.unlink

            def deny_backup_cleanup(path: Path, *args, **kwargs):
                if path.suffix == ".bak":
                    raise PermissionError("simulated backup cleanup denial")
                return real_unlink(path, *args, **kwargs)

            stderr = io.StringIO()
            with mock.patch.object(Path, "unlink", new=deny_backup_cleanup):
                with contextlib.redirect_stderr(stderr):
                    result = self.module.main(
                        [
                            "report",
                            str(study_path),
                            "--json-output",
                            str(output_path),
                            "--force",
                            "--allow-historical-subject",
                        ]
                    )

            retained_backups = list(base.glob(".*.bak"))
            self.assertEqual(result, 2)
            self.assertTrue(json.loads(output_path.read_text(encoding="utf-8"))["ready_for_review"])
            self.assertEqual(1, len(retained_backups))
            self.assertEqual("old-report", retained_backups[0].read_text(encoding="utf-8"))
            self.assertIn("new outputs remain active", stderr.getvalue())
            self.assertIn(str(retained_backups[0]), stderr.getvalue())
            self.assertFalse(any(base.glob(".*.tmp")))

    def test_no_clobber_race_rolls_back_first_output_and_preserves_concurrent_file(self) -> None:
        with tempfile.TemporaryDirectory() as directory:
            base = Path(directory)
            first = base / "first.json"
            second = base / "second.md"
            real_link = os.link
            calls = 0

            def race_on_second_publish(source, destination):
                nonlocal calls
                calls += 1
                if calls == 2:
                    second.write_text("concurrent-writer", encoding="utf-8")
                    raise FileExistsError("simulated no-clobber race")
                real_link(source, destination)

            with mock.patch.object(self.module.os, "link", side_effect=race_on_second_publish):
                with self.assertRaises(self.module.StudyToolError):
                    self.module.write_outputs(
                        [(first, "first"), (second, "second")],
                        force=False,
                    )

            self.assertFalse(first.exists())
            self.assertEqual(second.read_text(encoding="utf-8"), "concurrent-writer")
            self.assertFalse(any(base.glob(".*.tmp")))
            self.assertFalse(any(base.glob(".*.bak")))

    def test_require_current_commit_accepts_only_matching_head(self) -> None:
        matching = self.valid_study()
        matching["subject_commit"] = "c" * 40
        with mock.patch.object(self.module, "current_commit", return_value="c" * 40):
            validation = self.module.validate_study(matching, require_current_commit=True)

        mismatching = self.valid_study()
        with mock.patch.object(self.module, "current_commit", return_value="b" * 40):
            mismatch = self.module.validate_study(mismatching, require_current_commit=True)

        self.assertTrue(validation["ready_for_review"])
        self.assertTrue(validation["checks"]["subject_commit_matches_current_commit"])
        self.assertFalse(mismatch["ready_for_review"])
        self.assertFalse(mismatch["checks"]["subject_commit_matches_current_commit"])
        self.assertIn("does not match current Git HEAD", "\n".join(mismatch["errors"]))

    def test_require_current_commit_fails_closed_when_head_is_unreadable(self) -> None:
        with mock.patch.object(self.module, "current_commit", return_value=None):
            validation = self.module.validate_study(
                self.valid_study(),
                require_current_commit=True,
            )

        self.assertFalse(validation["ready_for_review"])
        self.assertFalse(validation["checks"]["subject_commit_matches_current_commit"])
        self.assertIn("fails closed", "\n".join(validation["errors"]))

    def test_current_commit_returns_none_when_git_cannot_be_executed(self) -> None:
        with mock.patch.object(self.module.subprocess, "run", side_effect=OSError("git unavailable")):
            self.assertIsNone(self.module.current_commit())

    def test_cli_require_current_commit_writes_blocked_report_on_mismatch(self) -> None:
        with tempfile.TemporaryDirectory() as directory:
            base = Path(directory)
            study_path = base / "study.json"
            output_path = base / "validation.json"
            study_path.write_text(json.dumps(self.valid_study()), encoding="utf-8")

            with mock.patch.object(self.module, "current_commit", return_value="b" * 40):
                with contextlib.redirect_stdout(io.StringIO()):
                    result = self.module.main(
                        [
                            "validate",
                            str(study_path),
                            "--json-output",
                            str(output_path),
                            "--require-current-commit",
                        ]
                    )

            report = json.loads(output_path.read_text(encoding="utf-8"))
            self.assertEqual(result, 1)
            self.assertFalse(report["ready_for_review"])
            self.assertTrue(report["checks"]["current_commit_required"])
            self.assertFalse(report["checks"]["subject_commit_matches_current_commit"])

    def test_cli_requires_current_commit_by_default_with_explicit_historical_opt_out(self) -> None:
        with tempfile.TemporaryDirectory() as directory:
            base = Path(directory)
            study_path = base / "study.json"
            default_output = base / "default.json"
            historical_output = base / "historical.json"
            study_path.write_text(json.dumps(self.valid_study()), encoding="utf-8")

            with mock.patch.object(self.module, "current_commit", return_value="b" * 40):
                with contextlib.redirect_stdout(io.StringIO()):
                    default_result = self.module.main(
                        [
                            "validate",
                            str(study_path),
                            "--json-output",
                            str(default_output),
                        ]
                    )
                    historical_result = self.module.main(
                        [
                            "validate",
                            str(study_path),
                            "--json-output",
                            str(historical_output),
                            "--allow-historical-subject",
                        ]
                    )

            default_report = json.loads(default_output.read_text(encoding="utf-8"))
            historical_report = json.loads(historical_output.read_text(encoding="utf-8"))
            self.assertEqual(1, default_result)
            self.assertFalse(default_report["ready_for_review"])
            self.assertTrue(default_report["checks"]["current_commit_required"])
            self.assertEqual(0, historical_result)
            self.assertTrue(historical_report["ready_for_review"])
            self.assertFalse(historical_report["checks"]["current_commit_required"])

    def test_invalid_json_produces_machine_readable_blocked_report(self) -> None:
        with tempfile.TemporaryDirectory() as directory:
            base = Path(directory)
            study_path = base / "invalid.json"
            report_path = base / "report.json"
            study_path.write_text("{not-json", encoding="utf-8")

            with contextlib.redirect_stdout(io.StringIO()):
                result = self.module.main(
                    [
                        "validate",
                        str(study_path),
                        "--json-output",
                        str(report_path),
                    ]
                )

            report = json.loads(report_path.read_text(encoding="utf-8"))
            self.assertEqual(result, 1)
            self.assertEqual(report["status"], "blocked")
            self.assertIn("not valid JSON", report["errors"][0])


if __name__ == "__main__":
    unittest.main()
