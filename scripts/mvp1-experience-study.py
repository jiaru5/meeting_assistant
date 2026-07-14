#!/usr/bin/env python3
from __future__ import annotations

import argparse
import json
import math
import re
import subprocess
import sys
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
PARTICIPANT_ID_PATTERN = re.compile(r"^P[0-9]{2,3}$")
COMMIT_PATTERN = re.compile(r"^[0-9a-f]{40}$")
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


def current_commit(root: Path | None = None) -> str | None:
    repository = root if root is not None else repo_root_from_script()
    completed = subprocess.run(
        ["git", "-C", str(repository), "rev-parse", "HEAD"],
        text=True,
        capture_output=True,
        check=False,
    )
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
    if "observation" in value and not isinstance(value["observation"], str):
        errors.append(f"{path}.observation must be a string when present")
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
            optional={"resolution"},
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
        if not _is_nonempty_string(finding.get("summary")):
            errors.append(f"{path}.summary must be a non-empty string")
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
        if severity in ("P0", "P1") and status == "open":
            open_p0_p1.append(
                {
                    "finding_id": str(finding_id),
                    "severity": str(severity),
                    "summary": str(finding.get("summary", "")),
                }
            )
    return open_p0_p1


def validate_study(study: Any) -> dict[str, Any]:
    schema_errors: list[str] = []
    participant_count_errors: list[str] = []
    attestation_errors: list[str] = []
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
    )
    for finding in open_p0_p1:
        blocker_errors.append(
            f"open {finding['severity']} finding {finding['finding_id']}: {finding['summary']}"
        )

    structure_valid = not schema_errors
    participant_count_valid = not participant_count_errors
    human_attestation_valid = (
        participant_count > 0
        and attested_count == participant_count
        and not attestation_errors
    )
    no_open_p0_p1 = not open_p0_p1
    ready_for_review = (
        structure_valid
        and participant_count_valid
        and human_attestation_valid
        and no_open_p0_p1
    )
    errors = schema_errors + participant_count_errors + attestation_errors + blocker_errors
    return {
        "ready_for_review": ready_for_review,
        "checks": {
            "structure_valid": structure_valid,
            "participant_count_valid": participant_count_valid,
            "manual_human_attestation_valid": human_attestation_valid,
            "no_open_p0_p1_findings": no_open_p0_p1,
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


def build_report(study: Any, *, source: str | None = None) -> dict[str, Any]:
    validation = validate_study(study)
    study_object = study if isinstance(study, dict) else {}
    findings = study_object.get("findings", [])
    if not isinstance(findings, list):
        findings = []
    recorded_findings = [finding for finding in findings if isinstance(finding, dict)]
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
        **validation,
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
        "Metric thresholds applied: false (none are defined at this stage)",
        (
            "Evidence boundary: agent, automation, screenshots, and XCUITest do not count "
            "as human participants; attestation is a manual declaration, not independent identity proof."
        ),
        "Privacy boundary: free-text observations must exclude participant names and contact data.",
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
        "- 指标通过阈值：未定义、未应用",
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
                "| ID | Severity | Status | Task | Summary |",
                "|---|---|---|---|---|",
            ]
        )
        for finding in findings:
            lines.append(
                f"| {_markdown_escape(finding.get('finding_id', '-'))} | "
                f"{_markdown_escape(finding.get('severity', '-'))} | "
                f"{_markdown_escape(finding.get('status', '-'))} | "
                f"{_markdown_escape(finding.get('task_id', '-'))} | "
                f"{_markdown_escape(finding.get('summary', '-'))} |"
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
            "参与者只使用 P01 这类匿名编号；自由文本不得记录姓名或联系方式。",
            (
                "当前未定义完成率、时长、求助、误点、犹豫或状态理解的产品通过阈值，"
                "因此这些指标只汇总、不自动判定产品验收或发布就绪。"
            ),
            "",
        ]
    )
    return "\n".join(lines)


def load_study(path: Path) -> Any:
    try:
        return json.loads(path.read_text(encoding="utf-8"))
    except FileNotFoundError as exc:
        raise StudyToolError(f"study file not found: {path}") from exc
    except json.JSONDecodeError as exc:
        raise StudyToolError(
            f"study file is not valid JSON at line {exc.lineno}, column {exc.colno}: {exc.msg}"
        ) from exc


def error_report(message: str, *, source: str | None = None) -> dict[str, Any]:
    report = build_report({}, source=source)
    report["errors"] = [message]
    report["checks"]["structure_valid"] = False
    report["checks"]["participant_count_valid"] = False
    report["checks"]["manual_human_attestation_valid"] = False
    report["ready_for_review"] = False
    report["status"] = "blocked"
    return report


def write_json(path: Path, value: Any) -> None:
    path.parent.mkdir(parents=True, exist_ok=True)
    path.write_text(
        json.dumps(value, ensure_ascii=False, indent=2, sort_keys=True) + "\n",
        encoding="utf-8",
    )


def write_text(path: Path, value: str) -> None:
    path.parent.mkdir(parents=True, exist_ok=True)
    path.write_text(value, encoding="utf-8")


def _resolve_path(value: str) -> Path:
    return Path(value).expanduser().resolve()


def _load_report(path_value: str) -> dict[str, Any]:
    path = _resolve_path(path_value)
    try:
        study = load_study(path)
    except StudyToolError as exc:
        return error_report(str(exc), source=str(path))
    return build_report(study, source=str(path))


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
    init_parser.add_argument("--force", action="store_true")

    validate_parser = subparsers.add_parser("validate", help="Validate study evidence.")
    validate_parser.add_argument("study")
    validate_parser.add_argument("--format", choices=("text", "json"), default="text")
    validate_parser.add_argument("--json-output")

    report_parser = subparsers.add_parser("report", help="Render a concise study report.")
    report_parser.add_argument("study")
    report_parser.add_argument(
        "--format",
        choices=("markdown", "text", "json"),
        default="markdown",
    )
    report_parser.add_argument("--json-output")
    report_parser.add_argument("--markdown-output")
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
        if output_path.exists() and not args.force:
            print(
                f"mvp1 experience study init refused to overwrite existing file: {output_path}",
                file=sys.stderr,
            )
            return 2
        write_json(output_path, template)
        print(f"unattested MVP.1 experience study template: {output_path}")
        print(
            "No human evidence has been recorded yet; complete tasks and manual attestations before validation."
        )
        return 0

    report = _load_report(args.study)
    if args.json_output:
        write_json(_resolve_path(args.json_output), report)
    if args.command == "report" and args.markdown_output:
        write_text(_resolve_path(args.markdown_output), render_markdown(report))
    _print_format(report, args.format)
    return 0 if report["ready_for_review"] else 1


if __name__ == "__main__":
    raise SystemExit(main(sys.argv[1:]))
