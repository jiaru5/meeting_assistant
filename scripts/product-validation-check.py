#!/usr/bin/env python3
from __future__ import annotations

import argparse
import re
import sys
from dataclasses import dataclass
from pathlib import Path


ROOT = Path(__file__).resolve().parent.parent
MATRIX = ROOT / "docs/engineering/06-product-validation-matrix.md"
VALID_STATUSES = {"missing", "planned", "partial", "covered", "manual-evidence"}


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


def main() -> int:
    parser = argparse.ArgumentParser(description="Validate product validation matrix readiness.")
    parser.add_argument("scope", choices=("current-phase", "release"))
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
