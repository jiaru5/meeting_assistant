#!/usr/bin/env python3
from __future__ import annotations

import argparse
import re
import sys
from dataclasses import dataclass
from pathlib import Path


ROOT = Path(__file__).resolve().parent.parent
DEVELOPMENT_PLAN = ROOT / "docs/engineering/07-development-plan.md"
RELEASE_PREREQUISITES = [f"VS-MA-{index:02d}" for index in range(14, 23)]
CLOSED_STATUS = "已达退出口径"
VALID_STATUSES = {CLOSED_STATUS, "partial evidence", "未进入 release-scope", "MVP 外"}


@dataclass(frozen=True)
class VerticalSliceRow:
    identifier: str
    status: str
    evidence: str
    next_step: str


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


def normalize_identifier(value: str) -> str:
    return value.strip().strip("` ")


def parse_rows(plan_path: Path) -> dict[str, VerticalSliceRow]:
    rows: dict[str, VerticalSliceRow] = {}
    for line in plan_path.read_text(encoding="utf-8").splitlines():
        cells = split_markdown_row(line)
        if len(cells) < 4:
            continue
        identifier = normalize_identifier(cells[0])
        if not re.fullmatch(r"VS-MA-\d{2}[A-Z]?", identifier):
            continue
        if identifier not in rows:
            rows[identifier] = VerticalSliceRow(
                identifier=identifier,
                status=cells[1].strip("` "),
                evidence=cells[2],
                next_step=cells[3],
            )
    return rows


def format_counts(rows: dict[str, VerticalSliceRow]) -> str:
    counts: dict[str, int] = {}
    for row in rows.values():
        counts[row.status] = counts.get(row.status, 0) + 1
    return ", ".join(f"{status}={count}" for status, count in sorted(counts.items()) if count)


def summarize_text(value: str) -> str:
    text = re.sub(r"`", "", value)
    text = " ".join(text.split())
    return text[:180] + ("..." if len(text) > 180 else "")


def validate_current_phase(rows: dict[str, VerticalSliceRow]) -> list[str]:
    failures: list[str] = []
    missing = [identifier for identifier in RELEASE_PREREQUISITES if identifier not in rows]
    if missing:
        failures.append(f"missing VS-MA release prerequisite rows: {', '.join(missing)}")
    for identifier, row in sorted(rows.items()):
        if row.status not in VALID_STATUSES:
            failures.append(f"{identifier}: unknown VS-MA status {row.status!r}")
        if not row.evidence:
            failures.append(f"{identifier}: status row must include evidence summary")
        if not row.next_step:
            failures.append(f"{identifier}: status row must include next step or residual risk")
    return failures


def validate_release(rows: dict[str, VerticalSliceRow]) -> list[VerticalSliceRow]:
    blockers: list[VerticalSliceRow] = []
    for identifier in RELEASE_PREREQUISITES:
        row = rows.get(identifier)
        if row is None:
            blockers.append(
                VerticalSliceRow(
                    identifier=identifier,
                    status="missing",
                    evidence="",
                    next_step="release prerequisite row is absent",
                )
            )
            continue
        if row.status != CLOSED_STATUS:
            blockers.append(row)
    return blockers


def main() -> int:
    parser = argparse.ArgumentParser(description="Validate VS-MA vertical slice stage readiness.")
    parser.add_argument("scope", choices=("current-phase", "release"))
    args = parser.parse_args()

    rows = parse_rows(DEVELOPMENT_PLAN)
    if not rows:
        print("VS-MA stage check failed: no VS-MA status rows found", file=sys.stderr)
        return 1

    current_failures = validate_current_phase(rows)
    if args.scope == "current-phase":
        if current_failures:
            print(f"VS-MA stage current-phase failed: {format_counts(rows)}", file=sys.stderr)
            for failure in current_failures:
                print(f" - {failure}", file=sys.stderr)
            return 1
        print(f"VS-MA stage current-phase passed: {format_counts(rows)}")
        return 0

    blockers = validate_release(rows)
    if current_failures or blockers:
        print(f"VS-MA stage release failed: {format_counts(rows)}", file=sys.stderr)
        print(
            "Release candidate requires VS-MA-14 through VS-MA-22 to be `已达退出口径` before PV/release gates.",
            file=sys.stderr,
        )
        for failure in current_failures:
            print(f" - {failure}", file=sys.stderr)
        for row in blockers:
            print(
                f" - {row.identifier}: {row.status}; blocker: {summarize_text(row.next_step or row.evidence)}",
                file=sys.stderr,
            )
        return 1

    print(f"VS-MA stage release passed: {format_counts(rows)}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
