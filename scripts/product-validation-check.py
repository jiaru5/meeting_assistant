#!/usr/bin/env python3
from __future__ import annotations

import argparse
import json
import re
import os
import subprocess
import sys
from dataclasses import dataclass
from pathlib import Path


ROOT = Path(__file__).resolve().parent.parent
MATRIX = ROOT / "docs/engineering/06-product-validation-matrix.md"
VALID_STATUSES = {"missing", "planned", "partial", "covered", "manual-evidence"}
LOCAL_FUNCTIONAL_REPORT_GLOB = "platform/e2e/build/local-direct-functional-preflight/reports/local-direct-functional-preflight-*.json"
LOCAL_FUNCTIONAL_EXPECTED_TERMS = ["HTTP", "LLM", "clean architecture"]
LOCAL_FUNCTIONAL_STAGES = ["recording", "processing", "actions"]


@dataclass(frozen=True)
class ValidationRow:
    identifier: str
    scenario: str
    target_entry: str
    evidence: str
    status: str


def split_markdown_row(line: str) -> list[str]:
    if not line.startswith("|") or line.startswith("|---"):
        return []
    cells: list[str] = []
    current: list[str] = []
    in_code = False
    for char in line.strip():
        if char == "`":
            in_code = not in_code
            current.append(char)
            continue
        if char == "|" and not in_code:
            cells.append("".join(current).strip())
            current = []
            continue
        current.append(char)
    cells.append("".join(current).strip())
    if cells and cells[0] == "":
        cells = cells[1:]
    if cells and cells[-1] == "":
        cells = cells[:-1]
    return cells


def parse_rows(matrix_path: Path) -> list[ValidationRow]:
    rows: list[ValidationRow] = []
    for line in matrix_path.read_text(encoding="utf-8").splitlines():
        cells = split_markdown_row(line)
        if len(cells) < 7 or not cells[0].startswith("PV-") or cells[0] == "PV-AREA-001":
            continue
        if cells[0] == "ID":
            continue
        rows.append(
            ValidationRow(
                identifier=cells[0],
                scenario=cells[1],
                target_entry=cells[4],
                evidence=cells[5],
                status=cells[6].strip("` "),
            )
        )
    return rows


def status_counts(rows: list[ValidationRow]) -> dict[str, int]:
    counts = {status: 0 for status in sorted(VALID_STATUSES)}
    for row in rows:
        counts[row.status] = counts.get(row.status, 0) + 1
    return counts


def format_counts(rows: list[ValidationRow]) -> str:
    counts = status_counts(rows)
    return ", ".join(f"{status}={count}" for status, count in sorted(counts.items()) if count)


def extract_blocker(evidence: str) -> str:
    match = re.search(r"阻塞缺口[:：](.*?)(?:。关闭条件|关闭条件[:：]|$)", evidence)
    if match:
        return " ".join(match.group(1).split())
    text = re.sub(r"`", "", evidence)
    text = " ".join(text.split())
    return text[:180] + ("..." if len(text) > 180 else "")


def current_commit(root: Path) -> str | None:
    completed = subprocess.run(
        ["git", "-C", str(root), "rev-parse", "HEAD"],
        capture_output=True,
        text=True,
        check=False,
    )
    if completed.returncode != 0:
        return None
    return completed.stdout.strip()


def validate_current_phase(rows: list[ValidationRow]) -> list[str]:
    failures: list[str] = []
    for row in rows:
        if row.status not in VALID_STATUSES:
            failures.append(f"{row.identifier}: unknown status {row.status!r}")
            continue
        if row.status == "missing":
            failures.append(f"{row.identifier}: current phase cannot leave validation status as missing")
        if row.status in {"planned", "partial", "manual-evidence"}:
            if not row.target_entry:
                failures.append(f"{row.identifier}: non-covered rows must keep a target test entry")
            if "阻塞缺口" not in row.evidence or "关闭条件" not in row.evidence:
                failures.append(f"{row.identifier}: non-covered rows must state blockers and closing conditions")
    return failures


def validate_release(rows: list[ValidationRow]) -> list[ValidationRow]:
    return [row for row in rows if row.status != "covered"]


def resolve_local_functional_report(root: Path) -> Path | None:
    configured = os.environ.get("MA_LOCAL_DIRECT_FUNCTIONAL_PREFLIGHT_REPORT")
    if configured:
        return Path(configured)
    reports = list(root.glob(LOCAL_FUNCTIONAL_REPORT_GLOB))
    if not reports:
        return None
    return max(reports, key=lambda path: path.stat().st_mtime)


def validate_local_functional_report(root: Path, report_path: Path | None) -> list[str]:
    failures: list[str] = []
    if report_path is None:
        return [
            "local-functional requires a local-direct functional preflight report; "
            "run ./platform/e2e/local-direct-functional-preflight.sh first or set MA_LOCAL_DIRECT_FUNCTIONAL_PREFLIGHT_REPORT"
        ]
    if not report_path.is_file():
        return [f"local-functional report does not exist: {report_path}"]
    try:
        report = json.loads(report_path.read_text(encoding="utf-8"))
    except OSError as exc:
        return [f"local-functional report could not be read: {report_path}: {exc.__class__.__name__}"]
    except json.JSONDecodeError as exc:
        return [f"local-functional report must be valid JSON: {report_path}: {exc.__class__.__name__}"]
    if not isinstance(report, dict):
        return [f"local-functional report must be a JSON object: {report_path}"]

    head = current_commit(root)
    if head is None:
        failures.append("current git commit could not be resolved")
    elif report.get("subject_commit") != head:
        failures.append(f"local-functional report subject_commit must bind current HEAD {head}")

    if report.get("report_schema") != 1:
        failures.append("local-functional report must set report_schema=1")
    if report.get("release_gate") != "local-direct-functional-preflight":
        failures.append("local-functional report must set release_gate='local-direct-functional-preflight'")
    if report.get("target_scope") != "local-machine-only":
        failures.append("local-functional report must set target_scope='local-machine-only'")
    if report.get("passed") is not True:
        failures.append("local-functional report must set passed=True")
    if report.get("not_release_readiness") is not True:
        failures.append("local-functional report must keep not_release_readiness=True")

    release_blockers = report.get("release_blockers")
    if not isinstance(release_blockers, list) or not any(
        isinstance(item, str) and "does not run product-validation release or release-preflight" in item
        for item in release_blockers
    ):
        failures.append("local-functional report must state that it does not run product-validation release or release-preflight")

    app_identity = report.get("local_direct_app")
    if not isinstance(app_identity, dict):
        failures.append("local-functional report must include local_direct_app")
        app_identity = {}
    if app_identity.get("CFBundleIdentifier") != "local.meeting-assistant.native.localdirect":
        failures.append("local-functional report must bind the installed local-direct app bundle identifier")
    if not isinstance(app_identity.get("path"), str) or not app_identity.get("path"):
        failures.append("local-functional report must include the installed app path")

    app_source = report.get("local_direct_app_source")
    if not isinstance(app_source, dict):
        failures.append("local-functional report must include local_direct_app_source")
        app_source = {}
    if app_source.get("source_and_installed_executable_match") is not True:
        failures.append("local-functional report must prove the installed app unsigned executable content matches the current source app")
    if app_source.get("source_and_installed_unsigned_executable_match") is not True:
        failures.append("local-functional report must set source_and_installed_unsigned_executable_match=True")
    release_bundle_report = app_source.get("release_bundle_report")
    if not isinstance(release_bundle_report, dict):
        failures.append("local-functional report must include local_direct_app_source.release_bundle_report")
        release_bundle_report = {}
    if head is not None and release_bundle_report.get("subject_commit") != head:
        failures.append(f"local-functional release bundle report must bind current HEAD {head}")
    if release_bundle_report.get("distribution_mode") != "local-direct":
        failures.append("local-functional release bundle report must use distribution_mode='local-direct'")
    if not isinstance(release_bundle_report.get("digest"), str) or not release_bundle_report.get("digest", "").startswith("sha256:"):
        failures.append("local-functional release bundle report must include a sha256 digest")
    for source_key in ("source_app", "installed_app"):
        source_section = app_source.get(source_key)
        if not isinstance(source_section, dict):
            failures.append(f"local-functional report must include local_direct_app_source.{source_key}")
            source_section = {}
        if not isinstance(source_section.get("path"), str) or not source_section.get("path"):
            failures.append(f"local-functional report must include local_direct_app_source.{source_key}.path")
        if (
            not isinstance(source_section.get("executable_sha256"), str)
            or not source_section.get("executable_sha256", "").startswith("sha256:")
        ):
            failures.append(f"local-functional report must include local_direct_app_source.{source_key}.executable_sha256")
        if (
            not isinstance(source_section.get("unsigned_executable_sha256"), str)
            or not source_section.get("unsigned_executable_sha256", "").startswith("sha256:")
        ):
            failures.append(f"local-functional report must include local_direct_app_source.{source_key}.unsigned_executable_sha256")

    checks = report.get("functional_checks")
    if not isinstance(checks, dict):
        failures.append("local-functional report must include functional_checks")
        checks = {}
    if checks.get("launch_modes") != ["open"]:
        failures.append("local-functional report must use LaunchServices open only")
    if checks.get("same_app_identity") is not True:
        failures.append("local-functional report must set functional_checks.same_app_identity=True")

    stage_passed = checks.get("stage_passed")
    if not isinstance(stage_passed, dict):
        failures.append("local-functional report must include functional_checks.stage_passed")
        stage_passed = {}
    for stage in LOCAL_FUNCTIONAL_STAGES:
        if stage_passed.get(stage) is not True:
            failures.append(f"local-functional report stage {stage} must pass")

    expected_terms = checks.get("expected_terms_found")
    if not isinstance(expected_terms, list):
        failures.append("local-functional report must include functional_checks.expected_terms_found")
        expected_terms = []
    missing_terms = [term for term in LOCAL_FUNCTIONAL_EXPECTED_TERMS if term not in expected_terms]
    if missing_terms:
        failures.append(f"local-functional report missing expected transcript terms: {', '.join(missing_terms)}")

    action_markers = checks.get("actions_markers")
    if not isinstance(action_markers, list):
        failures.append("local-functional report must include functional_checks.actions_markers")
        action_markers = []
    for marker in ("Copy complete.", "Export complete.", "Delete complete."):
        if marker not in action_markers:
            failures.append(f"local-functional report missing action marker: {marker}")

    return failures


def main() -> int:
    parser = argparse.ArgumentParser(description="Validate product validation matrix readiness.")
    parser.add_argument("scope", choices=("current-phase", "local-functional", "release"))
    args = parser.parse_args()

    rows = parse_rows(MATRIX)
    if not rows:
        print("product validation check failed: no PV-* rows found", file=sys.stderr)
        return 1

    if args.scope == "current-phase":
        failures = validate_current_phase(rows)
        if failures:
            print(f"product validation current-phase failed: {format_counts(rows)}", file=sys.stderr)
            for failure in failures:
                print(f" - {failure}", file=sys.stderr)
            return 1
        print(f"product validation current-phase passed: {format_counts(rows)}")
        return 0

    if args.scope == "local-functional":
        failures = validate_current_phase(rows)
        report_path = resolve_local_functional_report(ROOT)
        failures.extend(validate_local_functional_report(ROOT, report_path))
        if failures:
            print(f"product validation local-functional failed: {format_counts(rows)}", file=sys.stderr)
            for failure in failures:
                print(f" - {failure}", file=sys.stderr)
            return 1
        print(f"product validation local-functional passed: {format_counts(rows)}; report={report_path}")
        print("Local functional scope is not release readiness; release still requires every PV-* row to be `covered`.")
        return 0

    blockers = validate_release(rows)
    if blockers:
        print(f"product validation release failed: {format_counts(rows)}", file=sys.stderr)
        print("Release candidate requires every PV-* row to be `covered`.", file=sys.stderr)
        for row in blockers:
            print(f" - {row.identifier}: {row.status}; blocker: {extract_blocker(row.evidence)}", file=sys.stderr)
        return 1

    print(f"product validation release passed: {format_counts(rows)}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
