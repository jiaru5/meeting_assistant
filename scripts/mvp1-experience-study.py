#!/usr/bin/env -S /usr/bin/python3 -I -S
from __future__ import annotations

import argparse
import json
import math
import os
import re
import shlex
import stat
import subprocess
import sys
import tempfile
from datetime import datetime
from pathlib import Path
from statistics import median
from typing import Any


STUDY_SCHEMA = 1
REPORT_SCHEMA = 1
MIN_PARTICIPANTS = 3
MAX_PARTICIPANTS = 5
REQUIRED_TASK_IDS = ("first_use", "return_visit", "failure_recovery")
TASK_OUTCOMES = ("completed", "partial", "not_completed")
STATE_UNDERSTANDING_VALUES = ("clear", "partial", "unclear")
FINDING_SEVERITIES = ("P0", "P1", "P2", "P3")
FINDING_STATUSES = ("open", "closed")
RETEST_RESULTS = ("passed", "failed")
PARTICIPANT_ID_PATTERN = re.compile(r"^P[0-9]{2,3}$")
COMMIT_PATTERN = re.compile(r"^[0-9a-f]{40}$")
EMAIL_PATTERN = re.compile(r"\b[A-Z0-9._%+-]+@[A-Z0-9.-]+\.[A-Z]{2,}\b", re.IGNORECASE)
PHONE_PATTERN = re.compile(r"(?<!\w)(?:\+?[0-9][0-9 ()-]{7,}[0-9])(?!\w)")
RAW_SESSION_ID_PATTERN = re.compile(
    r"\b(?:session|sess)[-_][A-Za-z0-9][A-Za-z0-9._-]{5,}\b", re.IGNORECASE
)
NON_HUMAN_ATTESTOR_PATTERN = re.compile(
    r"(?:\b(?:agent|ai|automation|automated|bot|robot|script|xctest|xcuitest|"
    r"codex|chatgpt|claude|gemini|llm|language[ -]?model)\b|"
    r"智能体|自动化|机器人|脚本|模型|大模型)",
    re.IGNORECASE,
)
_CURRENT_COMMIT_UNSET = object()
TRUSTED_GIT = "/usr/bin/git"
ATTESTATION_STATEMENT = (
    "I manually observed a real human participant perform these tasks; no agent, "
    "automation, screenshot, or XCUITest result is being counted as this participant."
)
EVIDENCE_POLICY = {
    "participant_sessions": "manual_human_only",
    "agent_counts_as_participant": False,
    "automation_counts_as_participant": False,
    "screenshot_counts_as_participant": False,
    "xcuitest_counts_as_participant": False,
}
EVIDENCE_BOUNDARY = {
    "evidence_type": "supplemental_manual_human_experience_study",
    "manual_attestation_required": True,
    "attestation_is_a_human_declaration_not_independent_identity_proof": True,
    "agent_automation_screenshot_xcuitest_count_as_participant": False,
    "free_text_must_exclude_names_and_contact_data": True,
    "metric_thresholds_applied": False,
    "metric_threshold_policy": "none_defined",
    "not_product_acceptance": True,
    "not_release_readiness": True,
}


class StudyToolError(Exception):
    pass


def repo_root_from_script() -> Path:
    return Path(__file__).resolve().parents[1]


def clean_git_environment() -> dict[str, str]:
    """Run Git without caller-controlled configuration or executable lookup."""
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
            text=True,
            capture_output=True,
            check=False,
            timeout=5,
            env=clean_git_environment(),
        )
    except (OSError, subprocess.SubprocessError):
        return None
    if completed.returncode != 0:
        return None
    value = completed.stdout.strip()
    return value if COMMIT_PATTERN.fullmatch(value) else None


def participant_template(index: int) -> dict[str, Any]:
    return {
        "participant_id": f"P{index:02d}",
        "session_type": "human_observed",
        "human_attestation": {
            "confirmed": False,
            "attested_at": None,
            "attested_by_role": None,
            "statement": ATTESTATION_STATEMENT,
        },
        "tasks": [
            {
                "task_id": task_id,
                "outcome": None,
                "duration_seconds": None,
                "help_count": None,
                "misclick_count": None,
                "hesitation_count": None,
                "state_understanding": None,
                "observation": "",
            }
            for task_id in REQUIRED_TASK_IDS
        ],
    }


def build_template(
    participant_count: int = MIN_PARTICIPANTS,
    *,
    subject_commit: str | None = None,
    study_id: str = "mvp1-experience-study",
) -> dict[str, Any]:
    if participant_count < MIN_PARTICIPANTS or participant_count > MAX_PARTICIPANTS:
        raise StudyToolError(
            f"participant template count must be between {MIN_PARTICIPANTS} and {MAX_PARTICIPANTS}"
        )
    return {
        "study_schema": STUDY_SCHEMA,
        "study_id": study_id,
        "subject_commit": subject_commit or current_commit(),
        "evidence_policy": dict(EVIDENCE_POLICY),
        "participants": [participant_template(index) for index in range(1, participant_count + 1)],
        "findings": [],
    }


def _expect_exact_keys(
    value: dict[str, Any],
    *,
    required: set[str],
    optional: set[str] | None,
    path: str,
    errors: list[str],
) -> None:
    optional_keys = optional or set()
    missing = sorted(required - set(value))
    unknown = sorted(set(value) - required - optional_keys)
    for key in missing:
        errors.append(f"{path}.{key} is required")
    for key in unknown:
        errors.append(f"{path}.{key} is not allowed")


def _is_nonempty_string(value: Any) -> bool:
    return isinstance(value, str) and bool(value.strip())


def _is_nonnegative_integer(value: Any) -> bool:
    return isinstance(value, int) and not isinstance(value, bool) and value >= 0


def _is_positive_number(value: Any) -> bool:
    return (
        isinstance(value, (int, float))
        and not isinstance(value, bool)
        and math.isfinite(float(value))
        and value > 0
    )


def _is_timezone_aware_iso8601(value: Any) -> bool:
    if not isinstance(value, str) or not value.strip():
        return False
    try:
        parsed = datetime.fromisoformat(value.replace("Z", "+00:00"))
    except ValueError:
        return False
    return parsed.tzinfo is not None


def _validate_private_text(
    value: Any,
    *,
    path: str,
    errors: list[str],
    label: str,
) -> None:
    if not _is_nonempty_string(value):
        errors.append(f"{path} must be a non-empty {label}")
        return
    text = str(value)
    for privacy_label, pattern in (
        ("an email address", EMAIL_PATTERN),
        ("a phone number", PHONE_PATTERN),
        ("a raw session identifier", RAW_SESSION_ID_PATTERN),
    ):
        if pattern.search(text):
            errors.append(f"{path} must not contain {privacy_label}")


def _redact_private_text_for_report(value: Any) -> Any:
    if not isinstance(value, str):
        return value
    if any(pattern.search(value) for pattern in (EMAIL_PATTERN, PHONE_PATTERN, RAW_SESSION_ID_PATTERN)):
        return "[REDACTED: prohibited private data]"
    return value


def _redact_finding_for_report(finding: dict[str, Any]) -> dict[str, Any]:
    redacted = dict(finding)
    for field in ("finding_id", "summary", "resolution", "retest_observation"):
        if field in redacted:
            redacted[field] = _redact_private_text_for_report(redacted[field])
    return redacted


def _validate_evidence_policy(value: Any, errors: list[str]) -> None:
    path = "evidence_policy"
    if not isinstance(value, dict):
        errors.append(f"{path} must be an object")
        return
    _expect_exact_keys(
        value,
        required=set(EVIDENCE_POLICY),
        optional=set(),
        path=path,
        errors=errors,
    )
    for key, expected in EVIDENCE_POLICY.items():
        actual = value.get(key)
        if type(actual) is not type(expected) or actual != expected:
            errors.append(f"{path}.{key} must be {expected!r}")


def _validate_task(
    value: Any,
    *,
    participant_path: str,
    index: int,
    errors: list[str],
) -> str | None:
    path = f"{participant_path}.tasks[{index}]"
    if not isinstance(value, dict):
        errors.append(f"{path} must be an object")
        return None
    _expect_exact_keys(
        value,
        required={
            "task_id",
            "outcome",
            "duration_seconds",
            "help_count",
            "misclick_count",
            "hesitation_count",
            "state_understanding",
        },
        optional={"observation"},
        path=path,
        errors=errors,
    )

    task_id = value.get("task_id")
    if task_id not in REQUIRED_TASK_IDS:
        errors.append(f"{path}.task_id must be one of {', '.join(REQUIRED_TASK_IDS)}")
        task_id = None
    if value.get("outcome") not in TASK_OUTCOMES:
        errors.append(f"{path}.outcome must be one of {', '.join(TASK_OUTCOMES)}")
    if not _is_positive_number(value.get("duration_seconds")):
        errors.append(f"{path}.duration_seconds must be a positive number")
    for field in ("help_count", "misclick_count", "hesitation_count"):
        if not _is_nonnegative_integer(value.get(field)):
            errors.append(f"{path}.{field} must be a non-negative integer")
    if value.get("state_understanding") not in STATE_UNDERSTANDING_VALUES:
        errors.append(
            f"{path}.state_understanding must be one of {', '.join(STATE_UNDERSTANDING_VALUES)}"
        )
    if "observation" in value:
        observation = value["observation"]
        if not isinstance(observation, str):
            errors.append(f"{path}.observation must be a string when present")
        elif observation.strip():
            _validate_private_text(
                observation,
                path=f"{path}.observation",
                errors=errors,
                label="direct observation",
            )
    return task_id


def _validate_attestation(
    value: Any,
    *,
    participant_path: str,
    errors: list[str],
) -> bool:
    path = f"{participant_path}.human_attestation"
    if not isinstance(value, dict):
        errors.append(f"{path} must be an object")
        return False
    _expect_exact_keys(
        value,
        required={"confirmed", "attested_at", "attested_by_role", "statement"},
        optional=set(),
        path=path,
        errors=errors,
    )

    valid = True
    if value.get("confirmed") is not True:
        errors.append(f"{path}.confirmed must be true only after a human observer attests the session")
        valid = False
    if not _is_timezone_aware_iso8601(value.get("attested_at")):
        errors.append(f"{path}.attested_at must be a timezone-aware ISO-8601 timestamp")
        valid = False
    if not _is_nonempty_string(value.get("attested_by_role")):
        errors.append(f"{path}.attested_by_role must be a non-empty role or pseudonym")
        valid = False
    elif NON_HUMAN_ATTESTOR_PATTERN.search(str(value["attested_by_role"])):
        errors.append(
            f"{path}.attested_by_role must not self-identify an agent, automation, "
            "XCUITest, Codex, language model, or other non-human observer"
        )
        valid = False
    if value.get("statement") != ATTESTATION_STATEMENT:
        errors.append(f"{path}.statement must match the manual human attestation statement")
        valid = False
    return valid


def _validate_participants(
    value: Any,
    *,
    schema_errors: list[str],
    participant_count_errors: list[str],
    attestation_errors: list[str],
) -> tuple[int, int, set[str]]:
    if not isinstance(value, list):
        schema_errors.append("participants must be an array")
        return 0, 0, set()

    participant_count = len(value)
    if participant_count < MIN_PARTICIPANTS or participant_count > MAX_PARTICIPANTS:
        participant_count_errors.append(
            f"participants must contain between {MIN_PARTICIPANTS} and {MAX_PARTICIPANTS} real humans; "
            f"found {participant_count}"
        )

    participant_ids: set[str] = set()
    attested_count = 0
    for index, participant in enumerate(value):
        path = f"participants[{index}]"
        if not isinstance(participant, dict):
            schema_errors.append(f"{path} must be an object")
            continue
        _expect_exact_keys(
            participant,
            required={"participant_id", "session_type", "human_attestation", "tasks"},
            optional=set(),
            path=path,
            errors=schema_errors,
        )

        participant_id = participant.get("participant_id")
        if not isinstance(participant_id, str) or not PARTICIPANT_ID_PATTERN.fullmatch(participant_id):
            schema_errors.append(f"{path}.participant_id must be an anonymous alias such as P01")
        elif participant_id in participant_ids:
            schema_errors.append(f"{path}.participant_id must be unique")
        else:
            participant_ids.add(participant_id)

        if participant.get("session_type") != "human_observed":
            schema_errors.append(
                f"{path}.session_type must be 'human_observed'; automation cannot be a participant"
            )

        attestation_start = len(attestation_errors)
        attestation_valid = _validate_attestation(
            participant.get("human_attestation"),
            participant_path=path,
            errors=attestation_errors,
        )
        if attestation_valid and len(attestation_errors) == attestation_start:
            attested_count += 1

        tasks = participant.get("tasks")
        if not isinstance(tasks, list):
            schema_errors.append(f"{path}.tasks must be an array")
            continue
        seen_task_ids: set[str] = set()
        for task_index, task in enumerate(tasks):
            task_id = _validate_task(
                task,
                participant_path=path,
                index=task_index,
                errors=schema_errors,
            )
            if task_id is None:
                continue
            if task_id in seen_task_ids:
                schema_errors.append(f"{path}.tasks contains duplicate task_id {task_id!r}")
            seen_task_ids.add(task_id)
        for task_id in REQUIRED_TASK_IDS:
            if task_id not in seen_task_ids:
                schema_errors.append(f"{path}.tasks is missing required task_id {task_id!r}")
        unexpected_count = len(tasks) - len(REQUIRED_TASK_IDS)
        if unexpected_count > 0:
            schema_errors.append(
                f"{path}.tasks must contain exactly the three required tasks without extras"
            )

    return participant_count, attested_count, participant_ids


def _validate_findings(
    value: Any,
    *,
    participant_ids: set[str],
    errors: list[str],
    closure_errors: list[str],
) -> list[dict[str, str]]:
    if not isinstance(value, list):
        errors.append("findings must be an array")
        return []

    seen_finding_ids: set[str] = set()
    open_p0_p1: list[dict[str, str]] = []
    for index, finding in enumerate(value):
        path = f"findings[{index}]"
        if not isinstance(finding, dict):
            errors.append(f"{path} must be an object")
            continue
        _expect_exact_keys(
            finding,
            required={
                "finding_id",
                "severity",
                "status",
                "summary",
                "task_id",
                "participant_ids",
            },
            optional={"resolution", "retested", "retest_result", "retest_observation"},
            path=path,
            errors=errors,
        )

        finding_id = finding.get("finding_id")
        if not _is_nonempty_string(finding_id):
            errors.append(f"{path}.finding_id must be a non-empty string")
        elif finding_id in seen_finding_ids:
            errors.append(f"{path}.finding_id must be unique")
        else:
            seen_finding_ids.add(finding_id)

        severity = finding.get("severity")
        status = finding.get("status")
        if severity not in FINDING_SEVERITIES:
            errors.append(f"{path}.severity must be one of {', '.join(FINDING_SEVERITIES)}")
        if status not in FINDING_STATUSES:
            errors.append(f"{path}.status must be one of {', '.join(FINDING_STATUSES)}")
        _validate_private_text(
            finding.get("summary"),
            path=f"{path}.summary",
            errors=errors,
            label="private finding summary",
        )
        if finding.get("task_id") not in (*REQUIRED_TASK_IDS, "cross_task"):
            errors.append(
                f"{path}.task_id must be a required task id or 'cross_task'"
            )

        references = finding.get("participant_ids")
        if not isinstance(references, list) or not references:
            errors.append(f"{path}.participant_ids must be a non-empty array")
        elif not all(isinstance(participant_id, str) for participant_id in references):
            errors.append(f"{path}.participant_ids must contain only participant aliases")
        else:
            if len(references) != len(set(references)):
                errors.append(f"{path}.participant_ids must not contain duplicates")
            for participant_id in references:
                if participant_id not in participant_ids:
                    errors.append(
                        f"{path}.participant_ids references unknown participant {participant_id!r}"
                    )

        if "resolution" in finding and not isinstance(finding["resolution"], str):
            errors.append(f"{path}.resolution must be a string when present")
        elif "resolution" in finding and finding["resolution"].strip():
            _validate_private_text(
                finding["resolution"],
                path=f"{path}.resolution",
                errors=errors,
                label="private finding resolution",
            )
        if "retest_observation" in finding:
            _validate_private_text(
                finding["retest_observation"],
                path=f"{path}.retest_observation",
                errors=errors,
                label="private human retest note",
            )
        if "retested" in finding and not isinstance(finding["retested"], bool):
            errors.append(f"{path}.retested must be a boolean when present")
        if "retest_result" in finding and finding["retest_result"] not in RETEST_RESULTS:
            errors.append(
                f"{path}.retest_result must be one of {', '.join(RETEST_RESULTS)} when present"
            )

        if severity in ("P0", "P1") and status == "closed":
            if not _is_nonempty_string(finding.get("resolution")):
                closure_errors.append(
                    f"{path}.resolution must be non-empty before a {severity} finding is closed"
                )
            if finding.get("retested") is not True:
                closure_errors.append(
                    f"{path}.retested must be true after a manual human retest before a "
                    f"{severity} finding is closed"
                )
            if finding.get("retest_result") != "passed":
                closure_errors.append(
                    f"{path}.retest_result must be 'passed' after a manual human retest before a "
                    f"{severity} finding is closed"
                )
            if not _is_nonempty_string(finding.get("retest_observation")):
                closure_errors.append(
                    f"{path}.retest_observation must be a non-empty direct human retest note before a "
                    f"{severity} finding is closed"
                )
        if severity in ("P0", "P1") and status == "open":
            open_p0_p1.append(
                {
                    "finding_id": str(finding_id),
                    "severity": str(severity),
                    "summary": str(finding.get("summary", "")),
                }
            )
    return open_p0_p1


def validate_study(
    study: Any,
    *,
    require_current_commit: bool = False,
    expected_current_commit: str | None | object = _CURRENT_COMMIT_UNSET,
) -> dict[str, Any]:
    schema_errors: list[str] = []
    participant_count_errors: list[str] = []
    attestation_errors: list[str] = []
    commit_errors: list[str] = []
    closure_errors: list[str] = []
    blocker_errors: list[str] = []

    if not isinstance(study, dict):
        schema_errors.append("study document must be a JSON object")
        study = {}
    _expect_exact_keys(
        study,
        required={
            "study_schema",
            "study_id",
            "subject_commit",
            "evidence_policy",
            "participants",
            "findings",
        },
        optional=set(),
        path="study",
        errors=schema_errors,
    )
    study_schema = study.get("study_schema")
    if (
        not isinstance(study_schema, int)
        or isinstance(study_schema, bool)
        or study_schema != STUDY_SCHEMA
    ):
        schema_errors.append(f"study_schema must be {STUDY_SCHEMA}")
    if not _is_nonempty_string(study.get("study_id")):
        schema_errors.append("study_id must be a non-empty string")
    subject_commit = study.get("subject_commit")
    if not isinstance(subject_commit, str) or not COMMIT_PATTERN.fullmatch(subject_commit):
        schema_errors.append("subject_commit must be a 40-character lowercase Git commit hash")
    subject_commit_matches_current: bool | None = None
    if require_current_commit:
        head_commit = (
            current_commit()
            if expected_current_commit is _CURRENT_COMMIT_UNSET
            else expected_current_commit
        )
        if not isinstance(head_commit, str) or not COMMIT_PATTERN.fullmatch(head_commit):
            commit_errors.append(
                "current Git HEAD could not be read; --require-current-commit fails closed"
            )
            subject_commit_matches_current = False
        elif subject_commit != head_commit:
            commit_errors.append(
                f"subject_commit {subject_commit!r} does not match current Git HEAD {head_commit!r}"
            )
            subject_commit_matches_current = False
        else:
            subject_commit_matches_current = True

    _validate_evidence_policy(study.get("evidence_policy"), schema_errors)
    participant_count, attested_count, participant_ids = _validate_participants(
        study.get("participants"),
        schema_errors=schema_errors,
        participant_count_errors=participant_count_errors,
        attestation_errors=attestation_errors,
    )
    open_p0_p1 = _validate_findings(
        study.get("findings"),
        participant_ids=participant_ids,
        errors=schema_errors,
        closure_errors=closure_errors,
    )
    for finding in open_p0_p1:
        blocker_errors.append(
            "open "
            f"{finding['severity']} finding "
            f"{_redact_private_text_for_report(finding['finding_id'])}: "
            f"{_redact_private_text_for_report(finding['summary'])}"
        )

    structure_valid = not schema_errors
    participant_count_valid = not participant_count_errors
    human_attestation_valid = (
        participant_count > 0
        and attested_count == participant_count
        and not attestation_errors
    )
    no_open_p0_p1 = not open_p0_p1
    high_severity_closures_valid = not closure_errors
    ready_for_review = (
        structure_valid
        and participant_count_valid
        and human_attestation_valid
        and no_open_p0_p1
        and high_severity_closures_valid
        and not commit_errors
    )
    errors = (
        schema_errors
        + participant_count_errors
        + attestation_errors
        + commit_errors
        + closure_errors
        + blocker_errors
    )
    return {
        "ready_for_review": ready_for_review,
        "checks": {
            "structure_valid": structure_valid,
            "participant_count_valid": participant_count_valid,
            "manual_human_attestation_valid": human_attestation_valid,
            "no_open_p0_p1_findings": no_open_p0_p1,
            "closed_p0_p1_manual_retest_valid": high_severity_closures_valid,
            "current_commit_required": require_current_commit,
            "subject_commit_matches_current_commit": subject_commit_matches_current,
            "metric_thresholds_applied": False,
        },
        "participant_count": participant_count,
        "required_participant_range": {
            "minimum": MIN_PARTICIPANTS,
            "maximum": MAX_PARTICIPANTS,
        },
        "manually_attested_participant_count": attested_count,
        "required_task_ids": list(REQUIRED_TASK_IDS),
        "open_p0_p1_findings": open_p0_p1,
        "errors": errors,
    }


def _aggregate_metrics(study: Any) -> dict[str, Any]:
    task_metrics: dict[str, dict[str, Any]] = {
        task_id: {
            "recorded_participants": 0,
            "outcomes": {outcome: 0 for outcome in TASK_OUTCOMES},
            "duration_seconds": [],
            "help_count": 0,
            "misclick_count": 0,
            "hesitation_count": 0,
            "state_understanding": {
                value: 0 for value in STATE_UNDERSTANDING_VALUES
            },
        }
        for task_id in REQUIRED_TASK_IDS
    }
    participants = study.get("participants", []) if isinstance(study, dict) else []
    if not isinstance(participants, list):
        participants = []
    for participant in participants:
        if not isinstance(participant, dict) or not isinstance(participant.get("tasks"), list):
            continue
        for task in participant["tasks"]:
            if not isinstance(task, dict) or task.get("task_id") not in task_metrics:
                continue
            metrics = task_metrics[task["task_id"]]
            metrics["recorded_participants"] += 1
            outcome = task.get("outcome")
            if outcome in TASK_OUTCOMES:
                metrics["outcomes"][outcome] += 1
            duration = task.get("duration_seconds")
            if _is_positive_number(duration):
                metrics["duration_seconds"].append(duration)
            for field in ("help_count", "misclick_count", "hesitation_count"):
                value = task.get(field)
                if _is_nonnegative_integer(value):
                    metrics[field] += value
            understanding = task.get("state_understanding")
            if understanding in STATE_UNDERSTANDING_VALUES:
                metrics["state_understanding"][understanding] += 1

    for metrics in task_metrics.values():
        durations = metrics["duration_seconds"]
        metrics["duration_summary_seconds"] = {
            "minimum": min(durations) if durations else None,
            "median": median(durations) if durations else None,
            "maximum": max(durations) if durations else None,
        }
        del metrics["duration_seconds"]
    return task_metrics


def build_report(
    study: Any,
    *,
    source: str | None = None,
    require_current_commit: bool = False,
    expected_current_commit: str | None | object = _CURRENT_COMMIT_UNSET,
) -> dict[str, Any]:
    validation = validate_study(
        study,
        require_current_commit=require_current_commit,
        expected_current_commit=expected_current_commit,
    )
    study_object = study if isinstance(study, dict) else {}
    findings = study_object.get("findings", [])
    if not isinstance(findings, list):
        findings = []
    recorded_findings = [
        _redact_finding_for_report(finding) for finding in findings if isinstance(finding, dict)
    ]
    redacted_validation = dict(validation)
    redacted_validation["errors"] = [
        _redact_private_text_for_report(error) for error in validation["errors"]
    ]
    redacted_validation["open_p0_p1_findings"] = [
        {
            **finding,
            "finding_id": _redact_private_text_for_report(finding.get("finding_id")),
            "summary": _redact_private_text_for_report(finding.get("summary")),
        }
        for finding in validation["open_p0_p1_findings"]
    ]
    finding_counts = {
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
    return {
        "report_schema": REPORT_SCHEMA,
        "report_type": "mvp1-human-experience-study",
        "source": source,
        "study_id": study_object.get("study_id"),
        "subject_commit": study_object.get("subject_commit"),
        "status": "ready_for_review" if validation["ready_for_review"] else "blocked",
        **redacted_validation,
        "task_metrics": _aggregate_metrics(study_object),
        "findings": recorded_findings,
        "finding_counts": finding_counts,
        "evidence_boundary": dict(EVIDENCE_BOUNDARY),
    }


def render_text(report: dict[str, Any]) -> str:
    status = "READY FOR REVIEW" if report["ready_for_review"] else "BLOCKED"
    checks = report["checks"]
    lines = [
        f"MVP.1 human experience study: {status}",
        (
            "Participants: "
            f"{report['participant_count']} "
            f"(required {MIN_PARTICIPANTS}-{MAX_PARTICIPANTS}; "
            f"manually attested {report['manually_attested_participant_count']})"
        ),
        f"Structure valid: {str(checks['structure_valid']).lower()}",
        f"Open P0/P1 findings: {len(report['open_p0_p1_findings'])}",
        (
            "Closed P0/P1 manual retest valid: "
            f"{str(checks['closed_p0_p1_manual_retest_valid']).lower()}"
        ),
        "Metric thresholds applied: false (none are defined at this stage)",
        "READY FOR REVIEW is not product acceptance or release readiness.",
        (
            "Evidence boundary: agent, automation, screenshots, and XCUITest do not count "
            "as human participants; attestation is a manual declaration, not independent identity proof."
        ),
        (
            "Privacy boundary: free text must exclude names, contact data, real meeting content, "
            "full transcripts, and raw session identifiers; the tool conservatively blocks email, "
            "phone, and raw-session-id patterns only."
        ),
    ]
    if report["errors"]:
        lines.append("Errors:")
        lines.extend(f" - {error}" for error in report["errors"])
    return "\n".join(lines) + "\n"


def _markdown_escape(value: Any) -> str:
    return str(value).replace("|", "\\|").replace("\n", " ")


def render_markdown(report: dict[str, Any]) -> str:
    status = "可进入评审" if report["ready_for_review"] else "阻断"
    checks = report["checks"]
    lines = [
        "# MVP.1 真人体验研究报告",
        "",
        f"- 状态：**{status}**",
        (
            f"- 匿名真人参与者：{report['participant_count']} "
            f"（要求 {MIN_PARTICIPANTS}–{MAX_PARTICIPANTS}；已手工声明 "
            f"{report['manually_attested_participant_count']}）"
        ),
        f"- 结构有效：{str(checks['structure_valid']).lower()}",
        f"- Open P0/P1：{len(report['open_p0_p1_findings'])}",
        (
            "- Closed P0/P1 人工复测有效："
            f"{str(checks['closed_p0_p1_manual_retest_valid']).lower()}"
        ),
        "- 指标通过阈值：未定义、未应用",
        "- `ready_for_review` 只表示证据可进入人工评审，不等于产品验收或发布就绪。",
        "",
        "## 任务观察汇总",
        "",
        "| 任务 | 完成 | 部分完成 | 未完成 | 时长 min/median/max（秒） | 求助 | 误点 | 犹豫 | 状态理解 clear/partial/unclear |",
        "|---|---:|---:|---:|---|---:|---:|---:|---|",
    ]
    for task_id in REQUIRED_TASK_IDS:
        metrics = report["task_metrics"][task_id]
        durations = metrics["duration_summary_seconds"]
        duration_text = "/".join(
            "-" if durations[key] is None else str(durations[key])
            for key in ("minimum", "median", "maximum")
        )
        outcomes = metrics["outcomes"]
        understanding = metrics["state_understanding"]
        lines.append(
            "| "
            + " | ".join(
                [
                    task_id,
                    str(outcomes["completed"]),
                    str(outcomes["partial"]),
                    str(outcomes["not_completed"]),
                    duration_text,
                    str(metrics["help_count"]),
                    str(metrics["misclick_count"]),
                    str(metrics["hesitation_count"]),
                    (
                        f"{understanding['clear']}/"
                        f"{understanding['partial']}/"
                        f"{understanding['unclear']}"
                    ),
                ]
            )
            + " |"
        )

    lines.extend(["", "## Findings", ""])
    findings = report["findings"]
    if findings:
        lines.extend(
            [
                "| ID | Severity | Status | Task | Summary | Resolution | Human retested | Retest result | Retest note |",
                "|---|---|---|---|---|---|---|---|---|",
            ]
        )
        for finding in findings:
            lines.append(
                f"| {_markdown_escape(finding.get('finding_id', '-'))} | "
                f"{_markdown_escape(finding.get('severity', '-'))} | "
                f"{_markdown_escape(finding.get('status', '-'))} | "
                f"{_markdown_escape(finding.get('task_id', '-'))} | "
                f"{_markdown_escape(finding.get('summary', '-'))} | "
                f"{_markdown_escape(finding.get('resolution', '-'))} | "
                f"{_markdown_escape(finding.get('retested', '-'))} | "
                f"{_markdown_escape(finding.get('retest_result', '-'))} | "
                f"{_markdown_escape(finding.get('retest_observation', '-'))} |"
            )
    else:
        lines.append("没有记录 finding。")

    open_findings = report["open_p0_p1_findings"]
    if open_findings:
        lines.extend(["", "### Open P0/P1 blockers", ""])
        lines.extend(
            f"- {_markdown_escape(finding['severity'])} "
            f"{_markdown_escape(finding['finding_id'])}: "
            f"{_markdown_escape(finding['summary'])}"
            for finding in open_findings
        )

    if report["errors"]:
        lines.extend(["", "## 校验错误", ""])
        lines.extend(f"- {_markdown_escape(error)}" for error in report["errors"])

    lines.extend(
        [
            "",
            "## 证据边界",
            "",
            (
                "本报告只整理经人工声明的真人任务观察。Agent、自动化、截图和 XCUITest "
                "不能计为真人参与者；工具只能校验声明和结构，不能独立证明参与者身份。"
            ),
            (
                "参与者只使用 P01 这类匿名编号；自由文本不得记录姓名、联系方式、"
                "真实会议内容、完整 transcript 或 raw session id。工具只会保守阻断"
                "邮箱、电话和 raw session id，其他内容仍依赖真人隐私声明。"
            ),
            (
                "当前未定义完成率、时长、求助、误点、犹豫或状态理解的产品通过阈值，"
                "因此这些指标只汇总、不自动判定产品验收或发布就绪。"
            ),
            "",
        ]
    )
    return "\n".join(lines)


def _is_pristine_unattested_template(study: Any, report: dict[str, Any]) -> bool:
    """Recognize only the exact initial template, never a partly broken record.

    ``validate`` deliberately treats blank task fields and attestations as
    blocking.  The guide may label that one known-safe initial state as waiting
    for a human, but it must not hide malformed JSON, findings, or a partly
    entered record behind the same status.
    """
    checks = report.get("checks")
    if not isinstance(study, dict) or not isinstance(checks, dict):
        return False
    if not all(
        (
            checks.get("participant_count_valid") is True,
            checks.get("subject_commit_matches_current_commit") is True,
            checks.get("no_open_p0_p1_findings") is True,
            checks.get("closed_p0_p1_manual_retest_valid") is True,
        )
    ):
        return False

    participants = study.get("participants")
    subject_commit = study.get("subject_commit")
    study_id = study.get("study_id")
    if (
        not isinstance(participants, list)
        or not isinstance(subject_commit, str)
        or not isinstance(study_id, str)
    ):
        return False
    try:
        expected_template = build_template(
            len(participants),
            subject_commit=subject_commit,
            study_id=study_id,
        )
    except StudyToolError:
        return False
    return study == expected_template


def render_guide(
    report: dict[str, Any],
    *,
    source: str,
    pristine_unattested_template: bool = False,
) -> str:
    """Render instructions only; this must never create or attest evidence."""
    if report["ready_for_review"]:
        status = "可进入人工评审"
        validation_explanation = "- 当前 JSON 已通过结构校验；仍须由人工评审，不等于产品验收。"
    elif pristine_unattested_template:
        status = "待真人填写（当前提交绑定有效；未填写时校验显示阻断是预期保护）"
        validation_explanation = (
            "- 未完成的真人记录会让 `validate` 显示阻断；这是防止空白模板被误当成证据的预期保护。"
        )
    else:
        status = "阻断（请先修复提交绑定、JSON 结构、finding 或未完成的记录）"
        validation_explanation = (
            "- 当前 JSON 不只是初始空白模板；请先修复绑定、结构、finding 或不完整记录，"
            "再运行 `validate`。"
        )
    validate_command = (
        "./scripts/mvp1-experience-study.py validate "
        f"{shlex.quote(source)} --format text"
    )
    lines = [
        "# MVP.1 真人体验研究录入指南",
        "",
        f"- 记录文件：`{source}`",
        f"- 当前校验状态：**{status}**",
        (
            "- 本命令只读取并说明现有 JSON；不会写入文件、不会自动填写任务，"
            "也不会把任何 attestation 设为 confirmed。"
        ),
        validation_explanation,
        "",
        "## 开始前",
        "",
        "1. 使用合成会议数据；不要使用真人姓名、联系方式、真实会议内容、完整 transcript 或 raw session id。",
        "2. 一位真人参与者一次完成三个任务；研究者只在任务结束后记录观察，不在过程中提示下一步。",
        "3. `attested_by_role` 只能填写真人观察者的角色或 pseudonym；agent、自动化、XCUITest 或语言模型不能计作观察者。",
        "",
        "## 每位参与者的固定任务",
        "",
        "1. `first_use`：从 Meetings 新建会议，按当前捕获意图完成预检、录制/停止保存，并主动触发 transcript 回查。",
        "2. `return_visit`：从最近会议重开已保存、处理中断或已有 transcript 的会话，继续处理、恢复或查看成果。",
        "3. `failure_recovery`：在真实可恢复的 blocked / failed 状态中，确认发生了什么、数据是否安全，并仅用应用给出的下一步动作恢复；没有发生可恢复异常时如实记录。",
        "",
        "## 每个任务应如实填写",
        "",
        "- outcome、duration_seconds、help_count、misclick_count、hesitation_count、state_understanding；",
        "- 建议补一条脱敏的 direct observation；填写后工具会保守拒绝邮箱、电话和 raw session id，但无法自动识别姓名或真实会议正文。",
        "- 若发现产品问题，增加 finding；open P0/P1 会阻断，closed P0/P1 需要 resolution、真人复测、passed 结果和脱敏的 retest_observation。",
        "",
        "## 签署与校验",
        "",
        "只有在研究者亲自观察到该真人完成所有记录后，才将 human_attestation.confirmed 设为 true。该声明不是独立身份认证。",
        f"填写完成后运行：`{validate_command}`",
        "`ready_for_review` 只表示证据包可进入人工评审，不等于产品验收或发布就绪。",
        "",
    ]
    return "\n".join(lines)


def load_study(path: Path) -> Any:
    try:
        return json.loads(path.read_text(encoding="utf-8"))
    except FileNotFoundError as exc:
        raise StudyToolError(f"study file not found: {path}") from exc
    except (OSError, UnicodeError) as exc:
        raise StudyToolError(f"study file could not be read safely: {path}: {exc}") from exc
    except json.JSONDecodeError as exc:
        raise StudyToolError(
            f"study file is not valid JSON at line {exc.lineno}, column {exc.colno}: {exc.msg}"
        ) from exc


def error_report(
    message: str,
    *,
    source: str | None = None,
    require_current_commit: bool = False,
    expected_current_commit: str | None | object = _CURRENT_COMMIT_UNSET,
) -> dict[str, Any]:
    report = build_report(
        {},
        source=source,
        require_current_commit=require_current_commit,
        expected_current_commit=expected_current_commit,
    )
    report["errors"] = [message, *report["errors"]]
    report["checks"]["structure_valid"] = False
    report["checks"]["participant_count_valid"] = False
    report["checks"]["manual_human_attestation_valid"] = False
    report["ready_for_review"] = False
    report["status"] = "blocked"
    return report


def _path_lexists(path: Path) -> bool:
    return os.path.lexists(os.fspath(path))


def _require_regular_output_target(path: Path, *, label: str) -> None:
    try:
        metadata = path.lstat()
    except FileNotFoundError:
        return
    except OSError as exc:
        raise StudyToolError(f"cannot inspect existing {label} output safely: {path}: {exc}") from exc
    if not stat.S_ISREG(metadata.st_mode):
        raise StudyToolError(
            f"existing {label} output must be a regular file, not a directory, symlink, or special file: {path}"
        )


def _comparison_path(path: Path) -> Path:
    try:
        return path.resolve(strict=False)
    except (OSError, RuntimeError) as exc:
        raise StudyToolError(f"cannot resolve path safely: {path}: {exc}") from exc


def _paths_conflict(first: Path, second: Path) -> bool:
    if _comparison_path(first) == _comparison_path(second):
        return True
    if _path_lexists(first) and _path_lexists(second):
        try:
            return os.path.samefile(first, second)
        except OSError as exc:
            raise StudyToolError(
                f"cannot compare output paths safely: {first} and {second}: {exc}"
            ) from exc
    return False


def validate_output_paths(
    *,
    input_path: Path | None,
    outputs: list[tuple[str, Path]],
    force: bool,
) -> None:
    for label, output_path in outputs:
        if input_path is not None and _paths_conflict(input_path, output_path):
            raise StudyToolError(
                f"{label} output must not conflict with study input: {output_path}"
            )
    for index, (label, output_path) in enumerate(outputs):
        for other_label, other_path in outputs[index + 1 :]:
            if _paths_conflict(output_path, other_path):
                raise StudyToolError(
                    f"{label} output must not conflict with {other_label} output: {output_path}"
                )
        _require_regular_output_target(output_path, label=label)
        if _path_lexists(output_path) and not force:
            raise StudyToolError(
                f"refused to overwrite existing {label} output without --force: {output_path}"
            )


def _prepare_atomic_file(path: Path, value: str) -> tuple[Path, int, int]:
    temporary_path: Path | None = None
    descriptor: int | None = None
    try:
        path.parent.mkdir(parents=True, exist_ok=True)
        descriptor, temporary_name = tempfile.mkstemp(
            prefix=f".{path.name}.",
            suffix=".tmp",
            dir=path.parent,
        )
        temporary_path = Path(temporary_name)
        os.fchmod(descriptor, 0o600)
        with os.fdopen(descriptor, "w", encoding="utf-8", newline="") as handle:
            descriptor = None
            handle.write(value)
            handle.flush()
            os.fsync(handle.fileno())
        metadata = temporary_path.stat()
        if stat.S_IMODE(metadata.st_mode) != 0o600:
            raise StudyToolError(
                f"temporary output permissions must be 0600: {temporary_path}"
            )
        prepared = temporary_path
        temporary_path = None
        return prepared, metadata.st_dev, metadata.st_ino
    except StudyToolError:
        raise
    except OSError as exc:
        raise StudyToolError(f"could not prepare output {path}: {exc}") from exc
    finally:
        if descriptor is not None:
            os.close(descriptor)
        if temporary_path is not None:
            try:
                temporary_path.unlink()
            except FileNotFoundError:
                pass


def _reserved_backup_path(path: Path) -> Path:
    descriptor: int | None = None
    backup: Path | None = None
    try:
        descriptor, name = tempfile.mkstemp(
            prefix=f".{path.name}.",
            suffix=".bak",
            dir=path.parent,
        )
        backup = Path(name)
        os.fchmod(descriptor, 0o600)
        return backup
    except OSError as exc:
        if backup is not None:
            backup.unlink(missing_ok=True)
        raise StudyToolError(f"could not reserve backup for output {path}: {exc}") from exc
    finally:
        if descriptor is not None:
            os.close(descriptor)


def _same_file_identity(path: Path, device: int, inode: int) -> bool:
    try:
        metadata = path.stat()
    except FileNotFoundError:
        return False
    return metadata.st_dev == device and metadata.st_ino == inode


def write_outputs(
    outputs: list[tuple[Path, str]],
    *,
    force: bool,
) -> None:
    """Publish every output or restore the pre-call state after a handled failure."""
    if not outputs:
        return

    prepared: list[tuple[Path, Path, int, int]] = []
    backups: list[tuple[Path, Path]] = []
    published: list[tuple[Path, int, int]] = []
    try:
        for path, _ in outputs:
            _require_regular_output_target(path, label="batch")
            if _path_lexists(path) and not force:
                raise StudyToolError(
                    f"refused to overwrite existing output without --force: {path}"
                )
        for path, value in outputs:
            temporary, device, inode = _prepare_atomic_file(path, value)
            prepared.append((path, temporary, device, inode))

        if force:
            for path, _, _, _ in prepared:
                if not _path_lexists(path):
                    continue
                _require_regular_output_target(path, label="batch")
                backup = _reserved_backup_path(path)
                try:
                    os.replace(path, backup)
                except OSError as exc:
                    try:
                        backup.unlink()
                    except OSError as cleanup_exc:
                        raise StudyToolError(
                            f"could not back up output {path}: {exc}; "
                            f"could not remove reserved backup {backup}: {cleanup_exc}"
                        ) from exc
                    raise StudyToolError(f"could not back up output {path}: {exc}") from exc
                backups.append((path, backup))

        for path, temporary, device, inode in prepared:
            if force:
                os.replace(temporary, path)
            else:
                try:
                    os.link(temporary, path)
                except FileExistsError as exc:
                    raise StudyToolError(
                        f"refused to overwrite existing output without --force: {path}"
                    ) from exc
            published.append((path, device, inode))
            if not _same_file_identity(path, device, inode):
                raise StudyToolError(f"published output identity changed unexpectedly: {path}")
            if stat.S_IMODE(path.stat().st_mode) != 0o600:
                raise StudyToolError(f"output permissions must be 0600: {path}")
    except Exception as exc:
        rollback_errors: list[str] = []
        for path, device, inode in reversed(published):
            try:
                if _same_file_identity(path, device, inode):
                    path.unlink()
            except OSError as rollback_exc:
                rollback_errors.append(f"could not remove new output {path}: {rollback_exc}")
        for path, backup in reversed(backups):
            try:
                if _path_lexists(path):
                    rollback_errors.append(
                        f"could not restore original output because destination is occupied: {path}"
                    )
                    continue
                os.replace(backup, path)
            except OSError as rollback_exc:
                rollback_errors.append(f"could not restore original output {path}: {rollback_exc}")
        detail = f"; rollback incomplete: {'; '.join(rollback_errors)}" if rollback_errors else ""
        if isinstance(exc, StudyToolError):
            raise StudyToolError(f"{exc}{detail}") from exc
        raise StudyToolError(f"could not publish output batch: {exc}{detail}") from exc
    finally:
        for _, temporary, _, _ in prepared:
            try:
                temporary.unlink()
            except FileNotFoundError:
                pass

    backup_cleanup_errors: list[str] = []
    retained_backups: list[str] = []
    for _, backup in backups:
        try:
            backup.unlink()
        except FileNotFoundError:
            pass
        except OSError as exc:
            backup_cleanup_errors.append(f"{backup}: {exc}")
            retained_backups.append(str(backup))
    if backup_cleanup_errors:
        raise StudyToolError(
            "outputs were published, but backup cleanup was incomplete; "
            "the new outputs remain active and old bytes are retained at "
            f"{', '.join(retained_backups)}; cleanup errors: {'; '.join(backup_cleanup_errors)}"
        )


def json_text(value: Any) -> str:
    return json.dumps(value, ensure_ascii=False, indent=2, sort_keys=True) + "\n"


def _resolve_path(value: str) -> Path:
    return Path(os.path.abspath(os.path.expanduser(value)))


def _load_report(
    path: Path,
    *,
    require_current_commit: bool = False,
    expected_current_commit: str | None | object = _CURRENT_COMMIT_UNSET,
) -> dict[str, Any]:
    try:
        study = load_study(path)
    except StudyToolError as exc:
        return error_report(
            str(exc),
            source=str(path),
            require_current_commit=require_current_commit,
            expected_current_commit=expected_current_commit,
        )
    return build_report(
        study,
        source=str(path),
        require_current_commit=require_current_commit,
        expected_current_commit=expected_current_commit,
    )


def _print_format(report: dict[str, Any], output_format: str) -> None:
    if output_format == "json":
        print(json.dumps(report, ensure_ascii=False, indent=2, sort_keys=True))
    elif output_format == "markdown":
        print(render_markdown(report), end="")
    else:
        print(render_text(report), end="")


def parse_args(argv: list[str]) -> argparse.Namespace:
    parser = argparse.ArgumentParser(
        description=(
            "Create and validate supplemental MVP.1 manual human experience-study evidence. "
            "Automation, screenshots, agents, and XCUITest never count as participants."
        )
    )
    subparsers = parser.add_subparsers(dest="command", required=True)

    template_parser = subparsers.add_parser("template", help="Print an unattested JSON template.")
    template_parser.add_argument("--participants", type=int, default=MIN_PARTICIPANTS)
    template_parser.add_argument("--study-id", default="mvp1-experience-study")
    template_parser.add_argument("--subject-commit")

    init_parser = subparsers.add_parser("init", help="Write an unattested JSON template to a file.")
    init_parser.add_argument("output")
    init_parser.add_argument("--participants", type=int, default=MIN_PARTICIPANTS)
    init_parser.add_argument("--study-id", default="mvp1-experience-study")
    init_parser.add_argument("--subject-commit")

    validate_parser = subparsers.add_parser("validate", help="Validate study evidence.")
    validate_parser.add_argument("study")
    validate_parser.add_argument("--format", choices=("text", "json"), default="text")
    validate_parser.add_argument("--json-output")
    validate_parser.add_argument("--force", action="store_true")
    validate_commit_group = validate_parser.add_mutually_exclusive_group()
    validate_commit_group.add_argument(
        "--require-current-commit",
        action="store_true",
        help="Require the study subject to match current HEAD (the default).",
    )
    validate_commit_group.add_argument(
        "--allow-historical-subject",
        action="store_true",
        help="Render historical evidence without requiring its subject commit to match current HEAD.",
    )

    report_parser = subparsers.add_parser("report", help="Render a concise study report.")
    report_parser.add_argument("study")
    report_parser.add_argument(
        "--format",
        choices=("markdown", "text", "json"),
        default="markdown",
    )
    report_parser.add_argument("--json-output")
    report_parser.add_argument("--markdown-output")
    report_parser.add_argument("--force", action="store_true")
    report_commit_group = report_parser.add_mutually_exclusive_group()
    report_commit_group.add_argument(
        "--require-current-commit",
        action="store_true",
        help="Require the study subject to match current HEAD (the default).",
    )
    report_commit_group.add_argument(
        "--allow-historical-subject",
        action="store_true",
        help="Render historical evidence without requiring its subject commit to match current HEAD.",
    )

    guide_parser = subparsers.add_parser(
        "guide", help="Read a study and print a no-write human-recording guide."
    )
    guide_parser.add_argument("study")
    guide_commit_group = guide_parser.add_mutually_exclusive_group()
    guide_commit_group.add_argument(
        "--require-current-commit",
        action="store_true",
        help="Require the study subject to match current HEAD (the default).",
    )
    guide_commit_group.add_argument(
        "--allow-historical-subject",
        action="store_true",
        help="Render guidance for historical evidence without treating it as current evidence.",
    )
    return parser.parse_args(argv)


def main(argv: list[str]) -> int:
    args = parse_args(argv)
    if args.command in ("template", "init"):
        try:
            template = build_template(
                args.participants,
                subject_commit=args.subject_commit,
                study_id=args.study_id,
            )
        except StudyToolError as exc:
            print(f"mvp1 experience study template failed: {exc}", file=sys.stderr)
            return 2
        if args.command == "template":
            print(json.dumps(template, ensure_ascii=False, indent=2, sort_keys=True))
            return 0
        output_path = _resolve_path(args.output)
        try:
            validate_output_paths(
                input_path=None,
                outputs=[("init", output_path)],
                force=False,
            )
            write_outputs([(output_path, json_text(template))], force=False)
        except StudyToolError as exc:
            print(f"mvp1 experience study init failed: {exc}", file=sys.stderr)
            return 2
        print(f"unattested MVP.1 experience study template: {output_path}")
        print(
            "No human evidence has been recorded yet; complete tasks and manual attestations before validation."
        )
        return 0

    if args.command == "guide":
        study_path = _resolve_path(args.study)
        try:
            study = load_study(study_path)
        except StudyToolError as exc:
            print(f"mvp1 experience study guide failed: {exc}", file=sys.stderr)
            return 2
        require_current_commit = not args.allow_historical_subject
        expected_current_commit: str | None | object = _CURRENT_COMMIT_UNSET
        if require_current_commit:
            expected_current_commit = current_commit()
        report = build_report(
            study,
            source=str(study_path),
            require_current_commit=require_current_commit,
            expected_current_commit=expected_current_commit,
        )
        print(
            render_guide(
                report,
                source=str(study_path),
                pristine_unattested_template=_is_pristine_unattested_template(study, report),
            ),
            end="",
        )
        return 0

    study_path = _resolve_path(args.study)
    outputs: list[tuple[str, Path]] = []
    if args.json_output:
        outputs.append(("JSON", _resolve_path(args.json_output)))
    if args.command == "report" and args.markdown_output:
        outputs.append(("Markdown", _resolve_path(args.markdown_output)))
    try:
        validate_output_paths(
            input_path=study_path,
            outputs=outputs,
            force=args.force,
        )
    except StudyToolError as exc:
        print(f"mvp1 experience study {args.command} failed: {exc}", file=sys.stderr)
        return 2

    require_current_commit = not args.allow_historical_subject
    expected_current_commit: str | None | object = _CURRENT_COMMIT_UNSET
    if require_current_commit:
        expected_current_commit = current_commit()
    report = _load_report(
        study_path,
        require_current_commit=require_current_commit,
        expected_current_commit=expected_current_commit,
    )
    rendered_outputs: list[tuple[Path, str]] = []
    if args.json_output:
        json_path = next(path for label, path in outputs if label == "JSON")
        rendered_outputs.append((json_path, json_text(report)))
    if args.command == "report" and args.markdown_output:
        markdown_path = next(path for label, path in outputs if label == "Markdown")
        rendered_outputs.append((markdown_path, render_markdown(report)))
    try:
        write_outputs(rendered_outputs, force=args.force)
    except StudyToolError as exc:
        print(f"mvp1 experience study {args.command} failed: {exc}", file=sys.stderr)
        return 2
    _print_format(report, args.format)
    return 0 if report["ready_for_review"] else 1


if __name__ == "__main__":
    raise SystemExit(main(sys.argv[1:]))
