#!/usr/bin/env -S /usr/bin/python3 -I -S
"""Create and validate MVP.1 manual screenshot visual-review evidence.

This tool deliberately separates a human visual review from the task XCUITest
artifact that supplies its screenshots.  A passing task report is necessary,
but never substitutes for a human observer's attestation.
"""

from __future__ import annotations

import argparse
import hashlib
import importlib.util
import json
import os
import re
import stat
import subprocess
import sys
import tempfile
from datetime import datetime
from pathlib import Path
from typing import Any


REVIEW_SCHEMA = 1
REPORT_SCHEMA = 1
TASK_REPORT_SCHEMA = 2
TASK_REPORT_GATE = "mvp1-task-xcresult-evidence"
REQUIRED_SCREENSHOTS = (
    "00-meetings-recent",
    "01-meetings-empty",
    "02-new-recording-ready",
    "03-recording-live",
    "04-recording-saved",
    "05-processing",
    "06-transcript-ready",
    "07-diagnostics",
)
REQUIRED_TASK_SUMMARY = {
    "result": "Passed",
    "totalTestCount": 17,
    "passedTests": 17,
    "failedTests": 0,
    "skippedTests": 0,
    "expectedFailures": 0,
}
SCREENSHOT_RESULTS = ("pass", "fail")
FINDING_SEVERITIES = ("P0", "P1", "P2", "P3")
FINDING_STATUSES = ("open", "closed")
RETEST_RESULTS = ("passed", "failed")
COMMIT_PATTERN = re.compile(r"^[0-9a-f]{40}$")
SHA256_PATTERN = re.compile(r"^[0-9a-f]{64}$")
EMAIL_PATTERN = re.compile(r"\b[A-Z0-9._%+-]+@[A-Z0-9.-]+\.[A-Z]{2,}\b", re.IGNORECASE)
PHONE_PATTERN = re.compile(r"(?<!\w)(?:\+?[0-9][0-9 ()-]{7,}[0-9])(?!\w)")
RAW_SESSION_ID_PATTERN = re.compile(r"\b(?:session|sess)[-_][A-Za-z0-9][A-Za-z0-9._-]{5,}\b", re.IGNORECASE)
PNG_SIGNATURE = b"\x89PNG\r\n\x1a\n"
TRUSTED_GIT = "/usr/bin/git"
_CURRENT_SUBJECT_UNSET = object()

ATTESTATION_STATEMENT = (
    "I manually reviewed each bound screenshot as a human visual observer. No agent, "
    "automation, screenshot artifact, or XCUITest result is being counted as this visual review."
)
PRIVACY_ATTESTATION_STATEMENT = (
    "I used only synthetic meeting data and excluded names, contact data, real meeting "
    "content, full transcript text, and raw session identifiers from every observation, "
    "finding, resolution, and retest note."
)
EVIDENCE_POLICY = {
    "review_type": "manual_human_screenshot_visual_review",
    "manual_human_attestation_required": True,
    "agent_counts_as_visual_review": False,
    "automation_counts_as_visual_review": False,
    "screenshot_counts_as_visual_review": False,
    "xcuitest_counts_as_visual_review": False,
}
EVIDENCE_BOUNDARY = {
    "evidence_type": "manual_human_screenshot_visual_review",
    "manual_human_attestation_required": True,
    "attestation_is_a_human_declaration_not_independent_identity_proof": True,
    "agent_automation_screenshot_xcuitest_count_as_visual_review": False,
    "structure_validity_is_product_acceptance": False,
    "ready_for_review_is_product_acceptance": False,
    "not_release_readiness": True,
}


class VisualReviewToolError(Exception):
    """Raised when evidence cannot be safely built, read, or validated."""


def repo_root_from_script() -> Path:
    return Path(__file__).resolve().parents[1]


def clean_git_environment() -> dict[str, str]:
    return {
        "GIT_CONFIG_NOSYSTEM": "1",
        "HOME": "/var/empty",
        "LANG": "C",
        "PATH": "/usr/bin:/bin",
    }


def current_commit(root: Path | None = None) -> str | None:
    repository = root if root is not None else repo_root_from_script()
    try:
        completed = subprocess.run(
            [TRUSTED_GIT, "-C", str(repository), "rev-parse", "HEAD"],
            check=False,
            capture_output=True,
            text=True,
            timeout=5,
            env=clean_git_environment(),
        )
    except (OSError, subprocess.SubprocessError):
        return None
    value = completed.stdout.strip()
    return value if completed.returncode == 0 and COMMIT_PATTERN.fullmatch(value) else None


def require_current_subject(subject_commit: str | None = None) -> str:
    current = current_commit()
    if current is None:
        raise VisualReviewToolError("current Git HEAD could not be read; visual review must bind current evidence")
    if subject_commit is not None and subject_commit != current:
        raise VisualReviewToolError(
            "--subject-commit must equal current Git HEAD; historical screenshot review cannot close current PV-MA-014"
        )
    return current


def _is_nonempty_string(value: Any) -> bool:
    return isinstance(value, str) and bool(value.strip())


def _is_timezone_aware_iso8601(value: Any) -> bool:
    if not _is_nonempty_string(value):
        return False
    try:
        parsed = datetime.fromisoformat(str(value).replace("Z", "+00:00"))
    except ValueError:
        return False
    return parsed.tzinfo is not None


def _validate_private_text(value: Any, *, path: str, errors: list[str]) -> None:
    if not _is_nonempty_string(value):
        errors.append(f"{path} must be a non-empty private note")
        return
    text = str(value)
    for label, pattern in (
        ("an email address", EMAIL_PATTERN),
        ("a phone number", PHONE_PATTERN),
        ("a raw session identifier", RAW_SESSION_ID_PATTERN),
    ):
        if pattern.search(text):
            errors.append(f"{path} must not contain {label}")


def _expect_exact_keys(
    value: dict[str, Any],
    *,
    required: set[str],
    optional: set[str] | None,
    path: str,
    errors: list[str],
) -> None:
    optional_keys = optional or set()
    for key in sorted(required - set(value)):
        errors.append(f"{path}.{key} is required")
    for key in sorted(set(value) - required - optional_keys):
        errors.append(f"{path}.{key} is not allowed")


def _absolute_path(value: str, *, label: str) -> Path:
    if not _is_nonempty_string(value):
        raise VisualReviewToolError(f"{label} must be a non-empty path")
    expanded = os.path.expanduser(value)
    if not os.path.isabs(expanded):
        raise VisualReviewToolError(f"{label} must be an absolute path")
    return Path(os.path.abspath(expanded))


def _resolve_path(value: str, *, label: str) -> Path:
    """Resolve a CLI-supplied path without dereferencing a possible symlink."""
    if not _is_nonempty_string(value):
        raise VisualReviewToolError(f"{label} must be a non-empty path")
    return Path(os.path.abspath(os.path.expanduser(value)))


def _require_regular_non_symlink(path: Path, *, label: str) -> os.stat_result:
    try:
        metadata = path.lstat()
    except FileNotFoundError as exc:
        raise VisualReviewToolError(f"{label} is missing: {path}") from exc
    except OSError as exc:
        raise VisualReviewToolError(f"{label} could not be inspected safely: {path}: {exc}") from exc
    if not stat.S_ISREG(metadata.st_mode):
        raise VisualReviewToolError(
            f"{label} must be a regular non-symlink file: {path}"
        )
    return metadata


def _sha256_file(path: Path) -> str:
    digest = hashlib.sha256()
    try:
        with path.open("rb") as handle:
            for block in iter(lambda: handle.read(1024 * 1024), b""):
                digest.update(block)
    except OSError as exc:
        raise VisualReviewToolError(f"could not hash file safely: {path}: {exc}") from exc
    return digest.hexdigest()


def _read_json_regular(path: Path, *, label: str) -> Any:
    _require_regular_non_symlink(path, label=label)
    try:
        return json.loads(path.read_text(encoding="utf-8"))
    except (OSError, UnicodeError) as exc:
        raise VisualReviewToolError(f"{label} could not be read safely: {path}: {exc}") from exc
    except json.JSONDecodeError as exc:
        raise VisualReviewToolError(
            f"{label} is not valid JSON at line {exc.lineno}, column {exc.colno}: {exc.msg}"
        ) from exc


def _validate_png_path_and_sha256(
    *,
    name: str,
    path_value: Any,
    expected_sha256: Any,
) -> dict[str, str]:
    if not isinstance(path_value, str):
        raise VisualReviewToolError(f"task screenshot {name!r} path must be an absolute PNG path")
    path = _absolute_path(path_value, label=f"task screenshot {name!r} path")
    if path.suffix.lower() != ".png":
        raise VisualReviewToolError(f"task screenshot {name!r} must use a .png path")
    _require_regular_non_symlink(path, label=f"task screenshot {name!r}")
    if not isinstance(expected_sha256, str) or not SHA256_PATTERN.fullmatch(expected_sha256):
        raise VisualReviewToolError(f"task screenshot {name!r} must record a lowercase SHA-256")
    try:
        with path.open("rb") as handle:
            signature = handle.read(len(PNG_SIGNATURE))
    except OSError as exc:
        raise VisualReviewToolError(f"could not read task screenshot {name!r}: {exc}") from exc
    if signature != PNG_SIGNATURE:
        raise VisualReviewToolError(f"task screenshot {name!r} is not a PNG file")
    observed_sha256 = _sha256_file(path)
    if observed_sha256 != expected_sha256:
        raise VisualReviewToolError(
            f"task screenshot {name!r} SHA-256 does not match its task report"
        )
    return {"name": name, "path": str(path), "sha256": observed_sha256}


def _strict_task_evidence_validator() -> Any:
    source_path = repo_root_from_script() / "scripts" / "mvp1-accessibility-walkthrough.py"
    _require_regular_non_symlink(source_path, label="strict task evidence validator")
    try:
        specification = importlib.util.spec_from_file_location(
            "mvp1_accessibility_task_evidence_validator", source_path
        )
        if specification is None or specification.loader is None:
            raise VisualReviewToolError("strict task evidence validator could not be loaded")
        module = importlib.util.module_from_spec(specification)
        specification.loader.exec_module(module)
    except VisualReviewToolError:
        raise
    except Exception as exc:
        raise VisualReviewToolError(
            f"strict task evidence validator could not be loaded safely: {exc}"
        ) from exc
    validator = getattr(module, "_validated_task_evidence", None)
    if not callable(validator):
        raise VisualReviewToolError("strict task evidence validator has no task-evidence entry point")
    return validator


def _validate_trusted_task_report(
    *, report_path: Path, report: dict[str, Any], subject_commit: str
) -> None:
    if "fixture_checks_passed" not in report or report.get("fixture_checks_passed") is not None:
        raise VisualReviewToolError(
            "task evidence report must be trusted production evidence, not a fixture report"
        )
    if report.get("screenshot_visual_review") != "pending":
        raise VisualReviewToolError(
            "task evidence report must retain screenshot_visual_review='pending' before human review"
        )
    app_identity = report.get("app_identity")
    if not isinstance(app_identity, dict):
        raise VisualReviewToolError("task evidence report is missing bound app identity")
    subject = {
        "subject_commit": subject_commit,
        "tested_app_path": app_identity.get("path"),
        "tested_bundle_id": app_identity.get("bundle_id"),
        "tested_app_cdhash": app_identity.get("cdhash"),
        "tested_app_executable_sha256": app_identity.get("executable_sha256"),
    }
    validator = _strict_task_evidence_validator()
    try:
        validator(report_path=report_path, subject=subject)
    except Exception as exc:
        raise VisualReviewToolError(
            f"task evidence report failed strict trusted provenance verification: {exc}"
        ) from exc


def validated_task_evidence(
    report_path_value: str,
    *,
    subject_commit: str,
) -> dict[str, Any]:
    """Read a task report and retain only the immutable visual-review binding."""
    if not isinstance(subject_commit, str) or not COMMIT_PATTERN.fullmatch(subject_commit):
        raise VisualReviewToolError("subject_commit must be a 40-character lowercase Git commit hash")
    report_path = _resolve_path(report_path_value, label="task evidence report")
    report = _read_json_regular(report_path, label="task evidence report")
    if not isinstance(report, dict):
        raise VisualReviewToolError("task evidence report must be a JSON object")
    if (
        report.get("schema_version") != TASK_REPORT_SCHEMA
        or report.get("release_gate") != TASK_REPORT_GATE
    ):
        raise VisualReviewToolError("task evidence report has the wrong schema or release gate")
    if report.get("passed") is not True or report.get("upstream_test_status") != 0:
        raise VisualReviewToolError("task evidence report must be a successful zero-exit report")
    if report.get("summary") != REQUIRED_TASK_SUMMARY:
        raise VisualReviewToolError(
            "task evidence report must prove exactly 17 passed, 0 failed, 0 skipped, and 0 expected failures"
        )
    if (
        report.get("subject_commit") != subject_commit
        or report.get("subject_commit_before_test") != subject_commit
    ):
        raise VisualReviewToolError(
            "task evidence report subject commits do not match the visual-review subject"
        )
    _validate_trusted_task_report(
        report_path=report_path,
        report=report,
        subject_commit=subject_commit,
    )

    attachments = report.get("attachments")
    screenshots = attachments.get("exported_screenshots") if isinstance(attachments, dict) else None
    if not isinstance(screenshots, list) or len(screenshots) != len(REQUIRED_SCREENSHOTS):
        raise VisualReviewToolError("task evidence report must contain exactly the eight required screenshots")
    names: list[str] = []
    bound_screenshots: list[dict[str, str]] = []
    for index, screenshot in enumerate(screenshots):
        path = f"attachments.exported_screenshots[{index}]"
        if not isinstance(screenshot, dict):
            raise VisualReviewToolError(f"{path} must be an object")
        name = screenshot.get("name")
        if not isinstance(name, str):
            raise VisualReviewToolError(f"{path}.name must be a screenshot identifier")
        names.append(name)
        bound_screenshots.append(
            _validate_png_path_and_sha256(
                name=name,
                path_value=screenshot.get("path"),
                expected_sha256=screenshot.get("sha256"),
            )
        )
    if tuple(names) != REQUIRED_SCREENSHOTS:
        raise VisualReviewToolError(
            "task evidence report screenshot names must be the fixed ordered MVP.1 screenshot set"
        )
    return {
        "report_path": str(report_path),
        "report_sha256": _sha256_file(report_path),
        "subject_commit": subject_commit,
        "screenshots": bound_screenshots,
    }


def screenshot_template(name: str) -> dict[str, Any]:
    return {"name": name, "result": None, "observation": ""}


def build_template(
    *,
    task_evidence_report: str,
    subject_commit: str | None = None,
    review_id: str = "mvp1-screenshot-visual-review",
) -> dict[str, Any]:
    subject = require_current_subject(subject_commit)
    if not _is_nonempty_string(review_id):
        raise VisualReviewToolError("review_id must be a non-empty string")
    return {
        "visual_review_schema": REVIEW_SCHEMA,
        "review_id": review_id,
        "subject_commit": subject,
        "evidence_policy": dict(EVIDENCE_POLICY),
        "task_evidence": validated_task_evidence(
            task_evidence_report,
            subject_commit=subject,
        ),
        "reviewer_attestation": {
            "confirmed": False,
            "attested_at": None,
            "attested_by_role": None,
            "statement": ATTESTATION_STATEMENT,
            "synthetic_data_confirmed": False,
            "privacy_statement": PRIVACY_ATTESTATION_STATEMENT,
        },
        "screenshots": [screenshot_template(name) for name in REQUIRED_SCREENSHOTS],
        "findings": [],
    }


def _validate_evidence_policy(value: Any, errors: list[str]) -> None:
    if not isinstance(value, dict):
        errors.append("evidence_policy must be an object")
        return
    _expect_exact_keys(
        value,
        required=set(EVIDENCE_POLICY),
        optional=set(),
        path="evidence_policy",
        errors=errors,
    )
    for key, expected in EVIDENCE_POLICY.items():
        actual = value.get(key)
        if type(actual) is not type(expected) or actual != expected:
            errors.append(f"evidence_policy.{key} must be {expected!r}")


def _validate_task_evidence(
    value: Any,
    *,
    subject_commit: Any,
    errors: list[str],
) -> None:
    if not isinstance(value, dict):
        errors.append("task_evidence must be an object")
        return
    _expect_exact_keys(
        value,
        required={"report_path", "report_sha256", "subject_commit", "screenshots"},
        optional=set(),
        path="task_evidence",
        errors=errors,
    )
    report_path = value.get("report_path")
    if not isinstance(report_path, str):
        errors.append("task_evidence.report_path must be an absolute path")
        return
    if not isinstance(subject_commit, str) or not COMMIT_PATTERN.fullmatch(subject_commit):
        return
    try:
        observed = validated_task_evidence(report_path, subject_commit=subject_commit)
    except VisualReviewToolError as exc:
        errors.append(str(exc))
        return
    if value != observed:
        errors.append("task_evidence fields do not match the retained task evidence report")


def _validate_attestation(value: Any, errors: list[str]) -> None:
    if not isinstance(value, dict):
        errors.append("reviewer_attestation must be an object")
        return
    _expect_exact_keys(
        value,
        required={
            "confirmed",
            "attested_at",
            "attested_by_role",
            "statement",
            "synthetic_data_confirmed",
            "privacy_statement",
        },
        optional=set(),
        path="reviewer_attestation",
        errors=errors,
    )
    if value.get("confirmed") is not True:
        errors.append(
            "reviewer_attestation.confirmed must be true only after a human visual observer completes the review"
        )
    if not _is_timezone_aware_iso8601(value.get("attested_at")):
        errors.append(
            "reviewer_attestation.attested_at must be a timezone-aware ISO-8601 timestamp"
        )
    if not _is_nonempty_string(value.get("attested_by_role")):
        errors.append("reviewer_attestation.attested_by_role must be a non-empty role or pseudonym")
    if value.get("statement") != ATTESTATION_STATEMENT:
        errors.append("reviewer_attestation.statement must match the manual human visual attestation")
    if value.get("synthetic_data_confirmed") is not True:
        errors.append(
            "reviewer_attestation.synthetic_data_confirmed must be true after checking every note"
        )
    if value.get("privacy_statement") != PRIVACY_ATTESTATION_STATEMENT:
        errors.append("reviewer_attestation.privacy_statement must match the privacy attestation")


def _validate_screenshot_reviews(
    value: Any,
    *,
    schema_errors: list[str],
    recording_errors: list[str],
) -> tuple[dict[str, str], set[str]]:
    if not isinstance(value, list):
        schema_errors.append("screenshots must be an array")
        return {}, set()
    names: list[str] = []
    results: dict[str, str] = {}
    failed: set[str] = set()
    for index, screenshot in enumerate(value):
        path = f"screenshots[{index}]"
        if not isinstance(screenshot, dict):
            schema_errors.append(f"{path} must be an object")
            continue
        _expect_exact_keys(
            screenshot,
            required={"name", "result", "observation"},
            optional=set(),
            path=path,
            errors=schema_errors,
        )
        name = screenshot.get("name")
        if not isinstance(name, str) or name not in REQUIRED_SCREENSHOTS:
            schema_errors.append(f"{path}.name must be one of the fixed screenshot names")
            continue
        names.append(name)
        if name in results:
            schema_errors.append(f"screenshots contains duplicate name {name!r}")
            continue
        result = screenshot.get("result")
        if result not in SCREENSHOT_RESULTS:
            recording_errors.append(
                f"{path}.result must be 'pass' or 'fail' after direct human visual observation"
            )
        else:
            results[name] = result
            if result == "fail":
                failed.add(name)
        _validate_private_text(
            screenshot.get("observation"),
            path=f"{path}.observation",
            errors=recording_errors,
        )
    if tuple(names) != REQUIRED_SCREENSHOTS:
        schema_errors.append("screenshots must contain the fixed ordered MVP.1 screenshot set exactly once")
    return results, failed


def _validate_retest(value: Any, *, path: str, errors: list[str]) -> bool:
    if not isinstance(value, dict):
        errors.append(f"{path} must be an object")
        return False
    _expect_exact_keys(
        value,
        required={"human_retested", "result", "retested_at", "observation"},
        optional=set(),
        path=path,
        errors=errors,
    )
    valid = True
    if value.get("human_retested") is not True:
        errors.append(f"{path}.human_retested must be true only after a manual human retest")
        valid = False
    if value.get("result") not in RETEST_RESULTS:
        errors.append(f"{path}.result must be one of {', '.join(RETEST_RESULTS)}")
        valid = False
    if not _is_timezone_aware_iso8601(value.get("retested_at")):
        errors.append(f"{path}.retested_at must be a timezone-aware ISO-8601 timestamp")
        valid = False
    observation_error_count = len(errors)
    _validate_private_text(value.get("observation"), path=f"{path}.observation", errors=errors)
    if len(errors) != observation_error_count:
        valid = False
    return valid


def _validate_findings(
    value: Any,
    *,
    screenshot_results: dict[str, str],
    schema_errors: list[str],
    closure_errors: list[str],
) -> tuple[list[dict[str, str]], set[str]]:
    if not isinstance(value, list):
        schema_errors.append("findings must be an array")
        return [], set()
    seen_ids: set[str] = set()
    referenced_screenshots: set[str] = set()
    open_p0_p1: list[dict[str, str]] = []
    for index, finding in enumerate(value):
        path = f"findings[{index}]"
        if not isinstance(finding, dict):
            schema_errors.append(f"{path} must be an object")
            continue
        _expect_exact_keys(
            finding,
            required={"finding_id", "severity", "status", "summary", "screenshot_names"},
            optional={"resolution", "retest"},
            path=path,
            errors=schema_errors,
        )
        finding_id = finding.get("finding_id")
        if not _is_nonempty_string(finding_id):
            schema_errors.append(f"{path}.finding_id must be a non-empty string")
        elif finding_id in seen_ids:
            schema_errors.append(f"{path}.finding_id must be unique")
        else:
            seen_ids.add(finding_id)
        severity = finding.get("severity")
        status = finding.get("status")
        if severity not in FINDING_SEVERITIES:
            schema_errors.append(f"{path}.severity must be one of {', '.join(FINDING_SEVERITIES)}")
        if status not in FINDING_STATUSES:
            schema_errors.append(f"{path}.status must be one of {', '.join(FINDING_STATUSES)}")
        _validate_private_text(finding.get("summary"), path=f"{path}.summary", errors=schema_errors)

        screenshot_names = finding.get("screenshot_names")
        valid_screenshot_names: list[str] = []
        if not isinstance(screenshot_names, list) or not screenshot_names:
            schema_errors.append(f"{path}.screenshot_names must be a non-empty array")
        elif not all(isinstance(name, str) for name in screenshot_names):
            schema_errors.append(f"{path}.screenshot_names must contain only screenshot names")
        else:
            if len(screenshot_names) != len(set(screenshot_names)):
                schema_errors.append(f"{path}.screenshot_names must not contain duplicates")
            for name in screenshot_names:
                if name not in REQUIRED_SCREENSHOTS:
                    schema_errors.append(f"{path}.screenshot_names references unknown screenshot {name!r}")
                else:
                    valid_screenshot_names.append(name)
                    referenced_screenshots.add(name)

        if "resolution" in finding and not isinstance(finding["resolution"], str):
            schema_errors.append(f"{path}.resolution must be a string when present")
        elif "resolution" in finding and finding["resolution"].strip():
            _validate_private_text(
                finding["resolution"],
                path=f"{path}.resolution",
                errors=schema_errors,
            )
        if "retest" in finding:
            _validate_retest(finding["retest"], path=f"{path}.retest", errors=schema_errors)

        if severity in ("P0", "P1") and status == "open":
            open_p0_p1.append(
                {
                    "finding_id": str(finding_id),
                    "severity": str(severity),
                    "summary": str(finding.get("summary", "")),
                }
            )
        if severity in ("P0", "P1") and status == "closed":
            if not _is_nonempty_string(finding.get("resolution")):
                closure_errors.append(f"{path}.resolution is required for a closed {severity} finding")
            retest = finding.get("retest")
            if "retest" not in finding:
                closure_errors.append(f"{path}.retest is required for a closed {severity} finding")
            else:
                retest_errors: list[str] = []
                retest_valid = _validate_retest(retest, path=f"{path}.retest", errors=retest_errors)
                closure_errors.extend(retest_errors)
                if retest_valid and isinstance(retest, dict) and retest.get("result") != "passed":
                    closure_errors.append(
                        f"{path}.retest.result must be 'passed' for a closed {severity} finding"
                    )
            for name in valid_screenshot_names:
                if screenshot_results.get(name) != "pass":
                    closure_errors.append(
                        f"{path} cannot close {severity} while referenced screenshot {name!r} is not pass"
                    )
    return open_p0_p1, referenced_screenshots


def validate_visual_review(
    review: Any,
    *,
    expected_subject_commit: str | None | object = _CURRENT_SUBJECT_UNSET,
) -> dict[str, Any]:
    schema_errors: list[str] = []
    binding_errors: list[str] = []
    attestation_errors: list[str] = []
    recording_errors: list[str] = []
    finding_tracking_errors: list[str] = []
    closure_errors: list[str] = []
    blocker_errors: list[str] = []

    if not isinstance(review, dict):
        schema_errors.append("visual review document must be a JSON object")
        review = {}
    _expect_exact_keys(
        review,
        required={
            "visual_review_schema",
            "review_id",
            "subject_commit",
            "evidence_policy",
            "task_evidence",
            "reviewer_attestation",
            "screenshots",
            "findings",
        },
        optional=set(),
        path="visual_review",
        errors=schema_errors,
    )
    if review.get("visual_review_schema") != REVIEW_SCHEMA:
        schema_errors.append(f"visual_review_schema must be {REVIEW_SCHEMA}")
    if not _is_nonempty_string(review.get("review_id")):
        schema_errors.append("review_id must be a non-empty string")
    subject_commit = review.get("subject_commit")
    if not isinstance(subject_commit, str) or not COMMIT_PATTERN.fullmatch(subject_commit):
        binding_errors.append("subject_commit must be a 40-character lowercase Git commit hash")

    current = current_commit()
    if not isinstance(current, str) or not COMMIT_PATTERN.fullmatch(current):
        binding_errors.append(
            "current Git HEAD could not be read; visual review subject binding fails closed"
        )
    else:
        if expected_subject_commit is not _CURRENT_SUBJECT_UNSET:
            if not isinstance(expected_subject_commit, str) or not COMMIT_PATTERN.fullmatch(
                expected_subject_commit
            ):
                binding_errors.append("expected subject must be a 40-character lowercase Git commit hash")
            elif expected_subject_commit != current:
                binding_errors.append(
                    "expected subject cannot differ from current Git HEAD for current PV-MA-014 evidence"
                )
        if subject_commit != current:
            binding_errors.append(
                f"subject_commit {subject_commit!r} does not match current Git HEAD {current!r}"
            )

    _validate_evidence_policy(review.get("evidence_policy"), schema_errors)
    _validate_task_evidence(
        review.get("task_evidence"),
        subject_commit=subject_commit,
        errors=binding_errors,
    )
    _validate_attestation(review.get("reviewer_attestation"), attestation_errors)
    screenshot_results, failed_screenshots = _validate_screenshot_reviews(
        review.get("screenshots"),
        schema_errors=schema_errors,
        recording_errors=recording_errors,
    )
    open_p0_p1, referenced_screenshots = _validate_findings(
        review.get("findings"),
        screenshot_results=screenshot_results,
        schema_errors=schema_errors,
        closure_errors=closure_errors,
    )
    for name in sorted(failed_screenshots - referenced_screenshots):
        finding_tracking_errors.append(
            f"failed screenshot {name!r} must be referenced by a finding"
        )
    for finding in open_p0_p1:
        blocker_errors.append(
            f"open {finding['severity']} finding {finding['finding_id']}: {finding['summary']}"
        )

    structure_valid = not schema_errors
    subject_binding_valid = not binding_errors
    manual_human_attestation_valid = not attestation_errors
    all_screenshot_reviews_recorded = (
        not recording_errors and len(screenshot_results) == len(REQUIRED_SCREENSHOTS)
    )
    failed_screenshots_tracked = not finding_tracking_errors
    closed_p0_p1_resolution_and_human_retest_valid = not closure_errors
    no_open_p0_p1_findings = not open_p0_p1
    ready_for_review = all(
        (
            structure_valid,
            subject_binding_valid,
            manual_human_attestation_valid,
            all_screenshot_reviews_recorded,
            failed_screenshots_tracked,
            closed_p0_p1_resolution_and_human_retest_valid,
            no_open_p0_p1_findings,
        )
    )
    return {
        "ready_for_review": ready_for_review,
        "checks": {
            "structure_valid": structure_valid,
            "subject_binding_valid": subject_binding_valid,
            "manual_human_attestation_valid": manual_human_attestation_valid,
            "all_screenshot_reviews_recorded": all_screenshot_reviews_recorded,
            "failed_screenshots_tracked": failed_screenshots_tracked,
            "closed_p0_p1_resolution_and_human_retest_valid": closed_p0_p1_resolution_and_human_retest_valid,
            "no_open_p0_p1_findings": no_open_p0_p1_findings,
            "structure_validity_is_product_acceptance": False,
        },
        "required_screenshot_names": list(REQUIRED_SCREENSHOTS),
        "recorded_screenshot_count": len(screenshot_results),
        "passed_screenshot_names": sorted(
            name for name, result in screenshot_results.items() if result == "pass"
        ),
        "failed_screenshot_names": sorted(failed_screenshots),
        "open_p0_p1_findings": open_p0_p1,
        "errors": (
            schema_errors
            + binding_errors
            + attestation_errors
            + recording_errors
            + finding_tracking_errors
            + closure_errors
            + blocker_errors
        ),
    }


def _finding_counts(value: Any) -> dict[str, dict[str, int]]:
    findings = value if isinstance(value, list) else []
    return {
        severity: {
            status: sum(
                1
                for finding in findings
                if isinstance(finding, dict)
                and finding.get("severity") == severity
                and finding.get("status") == status
            )
            for status in FINDING_STATUSES
        }
        for severity in FINDING_SEVERITIES
    }


def build_report(
    review: Any,
    *,
    source: str | None = None,
    expected_subject_commit: str | None | object = _CURRENT_SUBJECT_UNSET,
) -> dict[str, Any]:
    validation = validate_visual_review(
        review,
        expected_subject_commit=expected_subject_commit,
    )
    document = review if isinstance(review, dict) else {}
    screenshots = document.get("screenshots")
    findings = document.get("findings")
    return {
        "report_schema": REPORT_SCHEMA,
        "report_type": "mvp1-manual-screenshot-visual-review",
        "source": source,
        "review_id": document.get("review_id"),
        "subject_commit": document.get("subject_commit"),
        "task_evidence": document.get("task_evidence") if isinstance(document.get("task_evidence"), dict) else {},
        "status": "ready_for_review" if validation["ready_for_review"] else "blocked",
        **validation,
        "screenshot_reviews": [item for item in screenshots if isinstance(item, dict)]
        if isinstance(screenshots, list)
        else [],
        "findings": [item for item in findings if isinstance(item, dict)]
        if isinstance(findings, list)
        else [],
        "finding_counts": _finding_counts(findings),
        "evidence_boundary": dict(EVIDENCE_BOUNDARY),
    }


def render_text(report: dict[str, Any]) -> str:
    status = "READY FOR REVIEW" if report["ready_for_review"] else "BLOCKED"
    checks = report["checks"]
    lines = [
        f"MVP.1 manual screenshot visual review: {status}",
        f"Subject commit: {report.get('subject_commit', '-')}",
        (
            "Screenshots: "
            f"{report['recorded_screenshot_count']}/{len(REQUIRED_SCREENSHOTS)} "
            f"(passed {len(report['passed_screenshot_names'])}, failed {len(report['failed_screenshot_names'])})"
        ),
        f"Manual human attestation valid: {str(checks['manual_human_attestation_valid']).lower()}",
        f"Failed screenshots tracked: {str(checks['failed_screenshots_tracked']).lower()}",
        f"Open P0/P1 findings: {len(report['open_p0_p1_findings'])}",
        "READY FOR REVIEW is not product acceptance or release readiness.",
        "Agents, automation, screenshot artifacts, and XCUITest do not count as the human visual review.",
    ]
    if report["errors"]:
        lines.append("Errors:")
        lines.extend(f" - {error}" for error in report["errors"])
    return "\n".join(lines) + "\n"


def _markdown_escape(value: Any) -> str:
    return str(value).replace("|", "\\|").replace("\n", " ")


def render_markdown(report: dict[str, Any]) -> str:
    status = "可进入评审" if report["ready_for_review"] else "阻断"
    lines = [
        "# MVP.1 截图人工视觉审查报告",
        "",
        f"- 状态：**{status}**",
        f"- Subject commit：`{_markdown_escape(report.get('subject_commit', '-'))}`",
        (
            f"- 截图：{report['recorded_screenshot_count']}/{len(REQUIRED_SCREENSHOTS)}；"
            f"pass {len(report['passed_screenshot_names'])}，fail {len(report['failed_screenshot_names'])}"
        ),
        "- `ready_for_review` 只表示人工截图审查记录结构完整，不等于产品验收或发布就绪。",
        "",
        "## 截图观察",
        "",
        "| 截图 | 结果 | 人工观察 |",
        "|---|---|---|",
    ]
    for screenshot in report["screenshot_reviews"]:
        lines.append(
            f"| {_markdown_escape(screenshot.get('name', '-'))} | "
            f"{_markdown_escape(screenshot.get('result', '-'))} | "
            f"{_markdown_escape(screenshot.get('observation', '-'))} |"
        )
    lines.extend(["", "## Findings", ""])
    if report["findings"]:
        lines.extend(
            [
                "| ID | Severity | Status | Screenshots | Summary | Resolution | Retest |",
                "|---|---|---|---|---|---|---|",
            ]
        )
        for finding in report["findings"]:
            lines.append(
                f"| {_markdown_escape(finding.get('finding_id', '-'))} | "
                f"{_markdown_escape(finding.get('severity', '-'))} | "
                f"{_markdown_escape(finding.get('status', '-'))} | "
                f"{_markdown_escape(', '.join(finding.get('screenshot_names', [])))} | "
                f"{_markdown_escape(finding.get('summary', '-'))} | "
                f"{_markdown_escape(finding.get('resolution', '-'))} | "
                f"{_markdown_escape(finding.get('retest', '-'))} |"
            )
    else:
        lines.append("没有记录 finding。")
    if report["errors"]:
        lines.extend(["", "## 校验错误", ""])
        lines.extend(f"- {_markdown_escape(error)}" for error in report["errors"])
    lines.extend(
        [
            "",
            "## 证据边界",
            "",
            "本工具绑定已通过的 17/17 task XCUITest 截图，但截图、XCUITest、自动化和 Agent 都不能冒充人工视觉审查。",
            "人工观察、finding、resolution 和 retest 只可使用合成数据，且不得含姓名、联系方式、真实会议内容、完整 transcript 或原始 session identifier。",
            "",
        ]
    )
    return "\n".join(lines)


def _load_review(path: Path) -> Any:
    return _read_json_regular(path, label="visual review")


def error_report(
    message: str,
    *,
    source: str | None,
    expected_subject_commit: str | None | object = _CURRENT_SUBJECT_UNSET,
) -> dict[str, Any]:
    report = build_report(
        {},
        source=source,
        expected_subject_commit=expected_subject_commit,
    )
    report["ready_for_review"] = False
    report["status"] = "blocked"
    report["errors"] = [message, *report["errors"]]
    for key, value in report["checks"].items():
        if isinstance(value, bool):
            report["checks"][key] = False
    return report


def _validate_output_paths(
    *, input_path: Path | None, outputs: list[tuple[str, Path]]
) -> None:
    targets = [path for _, path in outputs]
    if len({str(path) for path in targets}) != len(targets):
        raise VisualReviewToolError("output paths must be unique")
    for label, target in outputs:
        if input_path is not None and target == input_path:
            raise VisualReviewToolError(f"{label} output must not overwrite the review input: {target}")
        if os.path.lexists(target):
            raise VisualReviewToolError(f"refused to overwrite existing {label} output: {target}")


def _prepare_atomic_output(path: Path, content: str) -> tuple[Path, int, int]:
    path.parent.mkdir(parents=True, exist_ok=True)
    descriptor, temporary_name = tempfile.mkstemp(
        prefix=f".{path.name}.", suffix=".tmp", dir=path.parent
    )
    temporary = Path(temporary_name)
    try:
        os.fchmod(descriptor, 0o600)
        with os.fdopen(descriptor, "w", encoding="utf-8", newline="") as handle:
            descriptor = -1
            handle.write(content)
            handle.flush()
            os.fsync(handle.fileno())
        metadata = temporary.stat()
        if stat.S_IMODE(metadata.st_mode) != 0o600:
            raise VisualReviewToolError(
                f"temporary output permissions must be 0600: {temporary}"
            )
        return temporary, metadata.st_dev, metadata.st_ino
    except Exception:
        if descriptor >= 0:
            os.close(descriptor)
        temporary.unlink(missing_ok=True)
        raise


def _atomic_write_outputs(outputs: list[tuple[Path, str]]) -> None:
    if not outputs:
        return
    targets = [path for path, _ in outputs]
    if len({str(path) for path in targets}) != len(targets):
        raise VisualReviewToolError("output paths must be unique")
    for target in targets:
        if os.path.lexists(target):
            raise VisualReviewToolError(f"refused to overwrite existing output: {target}")

    prepared: list[tuple[Path, Path, int, int]] = []
    published: list[tuple[Path, int, int]] = []
    try:
        for target, content in outputs:
            temporary, device, inode = _prepare_atomic_output(target, content)
            prepared.append((target, temporary, device, inode))
        for target, temporary, device, inode in prepared:
            try:
                os.link(temporary, target)
            except FileExistsError as exc:
                raise VisualReviewToolError(f"refused to overwrite existing output: {target}") from exc
            except OSError as exc:
                raise VisualReviewToolError(f"failed to atomically publish output {target}: {exc}") from exc
            published.append((target, device, inode))
            mode = stat.S_IMODE(target.stat().st_mode)
            if mode != 0o600:
                raise VisualReviewToolError(f"output permissions must be 0600: {target} is {mode:04o}")
    except Exception:
        for target, device, inode in reversed(published):
            try:
                metadata = target.stat()
                if metadata.st_dev == device and metadata.st_ino == inode:
                    target.unlink()
            except FileNotFoundError:
                pass
        raise
    finally:
        for _, temporary, _, _ in prepared:
            temporary.unlink(missing_ok=True)


def _json_text(value: Any) -> str:
    return json.dumps(value, ensure_ascii=False, indent=2, sort_keys=True) + "\n"


def _print_format(report: dict[str, Any], output_format: str) -> None:
    if output_format == "json":
        print(_json_text(report), end="")
    elif output_format == "markdown":
        print(render_markdown(report), end="")
    else:
        print(render_text(report), end="")


def _add_template_binding_arguments(parser: argparse.ArgumentParser) -> None:
    parser.add_argument("--task-evidence-report", required=True)
    parser.add_argument("--subject-commit")
    parser.add_argument("--review-id", default="mvp1-screenshot-visual-review")


def parse_args(argv: list[str]) -> argparse.Namespace:
    parser = argparse.ArgumentParser(
        description=(
            "Create and validate strict MVP.1 manual screenshot visual-review evidence. "
            "Agents, automation, screenshot artifacts, and XCUITest never count as the human review."
        )
    )
    subparsers = parser.add_subparsers(dest="command", required=True)

    template_parser = subparsers.add_parser("template", help="Print a bound, unattested JSON template.")
    _add_template_binding_arguments(template_parser)

    init_parser = subparsers.add_parser(
        "init", help="Atomically write a bound, unattested template without overwriting."
    )
    init_parser.add_argument("output")
    _add_template_binding_arguments(init_parser)

    validate_parser = subparsers.add_parser("validate", help="Validate visual-review evidence.")
    validate_parser.add_argument("review")
    validate_parser.add_argument("--format", choices=("text", "json"), default="text")
    validate_parser.add_argument("--json-output")

    report_parser = subparsers.add_parser("report", help="Render a concise visual-review report.")
    report_parser.add_argument("review")
    report_parser.add_argument("--format", choices=("markdown", "text", "json"), default="markdown")
    report_parser.add_argument("--json-output")
    report_parser.add_argument("--markdown-output")
    return parser.parse_args(argv)


def main(argv: list[str]) -> int:
    args = parse_args(argv)
    if args.command in ("template", "init"):
        try:
            template = build_template(
                task_evidence_report=args.task_evidence_report,
                subject_commit=args.subject_commit,
                review_id=args.review_id,
            )
        except VisualReviewToolError as exc:
            print(f"MVP.1 screenshot visual review template failed: {exc}", file=sys.stderr)
            return 2
        if args.command == "template":
            print(_json_text(template), end="")
            return 0
        output = _resolve_path(args.output, label="init output")
        try:
            _atomic_write_outputs([(output, _json_text(template))])
        except VisualReviewToolError as exc:
            print(f"MVP.1 screenshot visual review init failed: {exc}", file=sys.stderr)
            return 2
        print(f"unattested MVP.1 screenshot visual-review template: {output}")
        print("No human visual evidence has been recorded; a human observer must review and attest every screenshot.")
        return 0

    review_path = _resolve_path(args.review, label="visual review")
    outputs: list[tuple[str, Path]] = []
    if args.json_output:
        outputs.append(("JSON", _resolve_path(args.json_output, label="JSON output")))
    if args.command == "report" and args.markdown_output:
        outputs.append(
            ("Markdown", _resolve_path(args.markdown_output, label="Markdown output"))
        )
    try:
        _validate_output_paths(input_path=review_path, outputs=outputs)
    except VisualReviewToolError as exc:
        print(f"MVP.1 screenshot visual review {args.command} output failed: {exc}", file=sys.stderr)
        return 2
    try:
        review = _load_review(review_path)
        report = build_report(
            review,
            source=str(review_path),
        )
    except VisualReviewToolError as exc:
        report = error_report(
            str(exc),
            source=str(review_path),
        )
    rendered_outputs: list[tuple[Path, str]] = []
    if args.json_output:
        json_output = next(path for label, path in outputs if label == "JSON")
        rendered_outputs.append((json_output, _json_text(report)))
    if args.command == "report" and args.markdown_output:
        markdown_output = next(path for label, path in outputs if label == "Markdown")
        rendered_outputs.append((markdown_output, render_markdown(report)))
    try:
        _atomic_write_outputs(rendered_outputs)
    except VisualReviewToolError as exc:
        print(f"MVP.1 screenshot visual review {args.command} output failed: {exc}", file=sys.stderr)
        return 2
    _print_format(report, args.format)
    return 0 if report["ready_for_review"] else 1


if __name__ == "__main__":
    raise SystemExit(main(sys.argv[1:]))
