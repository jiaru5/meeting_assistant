#!/usr/bin/env python3
from __future__ import annotations

import re
import sys
from pathlib import Path


ROOT = Path(__file__).resolve().parent.parent
USES_PATTERN = re.compile(r"^\s*(?:-\s*)?uses:\s*([^#\s]+)")
SHA_PATTERN = re.compile(r"^[0-9a-f]{40}$")


def main() -> None:
    failures: list[str] = []
    workflow_dir = ROOT / ".github/workflows"
    for workflow in sorted(workflow_dir.glob("*.y*ml")):
        for line_number, line in enumerate(workflow.read_text(encoding="utf-8").splitlines(), start=1):
            match = USES_PATTERN.match(line)
            if not match:
                continue
            action = match.group(1)
            if action.startswith("./"):
                continue
            if "@" not in action:
                failures.append(f"{workflow.relative_to(ROOT)}:{line_number}: action has no ref: {action}")
                continue
            _, ref = action.rsplit("@", 1)
            if not SHA_PATTERN.fullmatch(ref):
                failures.append(
                    f"{workflow.relative_to(ROOT)}:{line_number}: action must be pinned to a full commit SHA: {action}"
                )
    if failures:
        print("action pin check failed:", file=sys.stderr)
        for failure in failures:
            print(f" - {failure}", file=sys.stderr)
        raise SystemExit(1)
    print("action pin check passed.")


if __name__ == "__main__":
    main()
