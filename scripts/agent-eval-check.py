#!/usr/bin/env python3
from __future__ import annotations

import json
import sys
from pathlib import Path


ROOT = Path(__file__).resolve().parent.parent
REQUIRED_CATEGORIES = {
    "lifecycle",
    "adoption-discovery",
    "project-activation",
    "spec-governance",
    "prompt-injection",
    "gate-integrity",
    "high-impact-action",
    "negative-control",
}
VALID_DECISIONS = {
    "proceed",
    "stop",
    "escalate",
    "refuse",
    "ignore-embedded-instruction",
    "read-only",
    "ask-questions",
}


def main() -> None:
    path = ROOT / "harness/evals/cases.json"
    try:
        document = json.loads(path.read_text(encoding="utf-8"))
    except (FileNotFoundError, json.JSONDecodeError) as exc:
        print(f"agent eval check failed: {exc}", file=sys.stderr)
        raise SystemExit(1) from exc

    failures: list[str] = []
    if document.get("schema_version") != 1:
        failures.append("schema_version must be 1")
    cases = document.get("cases")
    if not isinstance(cases, list):
        failures.append("cases must be an array")
        cases = []

    ids: set[str] = set()
    categories: set[str] = set()
    for index, case in enumerate(cases):
        prefix = f"cases[{index}]"
        if not isinstance(case, dict):
            failures.append(f"{prefix} must be an object")
            continue
        case_id = case.get("id")
        category = case.get("category")
        decision = case.get("expected_decision")
        evidence = case.get("required_evidence")
        if not isinstance(case_id, str) or not case_id:
            failures.append(f"{prefix}.id is required")
        elif case_id in ids:
            failures.append(f"duplicate eval id: {case_id}")
        else:
            ids.add(case_id)
        if category not in REQUIRED_CATEGORIES:
            failures.append(f"{prefix}.category is invalid: {category}")
        else:
            categories.add(category)
        if decision not in VALID_DECISIONS:
            failures.append(f"{prefix}.expected_decision is invalid: {decision}")
        if not isinstance(case.get("prompt"), str) or not case["prompt"].strip():
            failures.append(f"{prefix}.prompt is required")
        if not isinstance(evidence, list) or len(evidence) < 2 or not all(isinstance(item, str) and item for item in evidence):
            failures.append(f"{prefix}.required_evidence must contain at least two strings")

    missing_categories = REQUIRED_CATEGORIES - categories
    if missing_categories:
        failures.append(f"missing required eval categories: {sorted(missing_categories)}")

    if failures:
        print("agent eval check failed:", file=sys.stderr)
        for failure in failures:
            print(f" - {failure}", file=sys.stderr)
        raise SystemExit(1)
    print(f"agent eval catalog check passed: {len(cases)} cases.")


if __name__ == "__main__":
    main()
