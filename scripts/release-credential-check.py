#!/usr/bin/env python3
from __future__ import annotations

import argparse
import json
import os
import re
import subprocess
import sys
from pathlib import Path
from typing import Any


DEFAULT_IDENTITY_PATTERN = "Developer ID Application:"


class CredentialCheckError(Exception):
    pass


def repo_root_from_script() -> Path:
    return Path(__file__).resolve().parents[1]


def resolve_path(root: Path, value: str) -> Path:
    path = Path(value).expanduser()
    if not path.is_absolute():
        path = root / path
    return path.resolve()


def current_commit(root: Path) -> str | None:
    completed = subprocess.run(
        ["git", "-C", str(root), "rev-parse", "HEAD"],
        text=True,
        capture_output=True,
        check=False,
    )
    if completed.returncode != 0:
        return None
    return completed.stdout.strip() or None


def run_command(command: list[str]) -> subprocess.CompletedProcess[str]:
    try:
        return subprocess.run(
            command,
            text=True,
            capture_output=True,
            check=False,
        )
    except FileNotFoundError as exc:
        return subprocess.CompletedProcess(command, 127, "", f"{exc.filename}: not found")


def check_command_available(command: list[str], label: str) -> tuple[bool, str]:
    completed = run_command(command)
    output = (completed.stdout + completed.stderr).strip()
    if completed.returncode != 0:
        detail = output.splitlines()[0] if output else f"exit {completed.returncode}"
        return False, f"{label} is required for release material production: {detail}"
    return True, output


def check_executable(path: str, label: str) -> tuple[bool, str]:
    if not os.path.isfile(path) or not os.access(path, os.X_OK):
        return False, f"{label} is required for release material production: {path} is not executable"
    return True, path


def parse_codesigning_identities(output: str) -> tuple[int | None, list[str]]:
    valid_count: int | None = None
    identities: list[str] = []
    for line in output.splitlines():
        count_match = re.search(r"\b(\d+)\s+valid identities found\b", line)
        if count_match:
            valid_count = int(count_match.group(1))
            continue
        identity_match = re.search(r'"([^"]+)"', line)
        if identity_match:
            identities.append(identity_match.group(1))
    return valid_count, identities


def check_codesigning_identity(identity_pattern: str) -> tuple[bool, dict[str, Any], str | None]:
    completed = run_command(["security", "find-identity", "-v", "-p", "codesigning"])
    output = (completed.stdout + completed.stderr).strip()
    if completed.returncode != 0:
        detail = output.splitlines()[0] if output else f"exit {completed.returncode}"
        return False, {"valid_identity_count": None, "matched_identities": []}, (
            f"codesigning identity lookup failed: {detail}"
        )

    valid_count, identities = parse_codesigning_identities(output)
    matched = [identity for identity in identities if identity_pattern in identity]
    detail = {
        "valid_identity_count": valid_count,
        "required_identity_pattern": identity_pattern,
        "matched_identities": matched,
    }
    if not matched:
        count_text = "unknown" if valid_count is None else str(valid_count)
        return False, detail, (
            f"release signing requires a codesigning identity matching {identity_pattern!r}; "
            f"valid identities found: {count_text}"
        )
    return True, detail, None


def build_report(args: argparse.Namespace) -> dict[str, Any]:
    root = resolve_path(repo_root_from_script(), args.root)
    checks: dict[str, Any] = {}
    failures: list[str] = []

    executable_checks = {
        "codesign": "/usr/bin/codesign",
        "spctl": "/usr/sbin/spctl",
    }
    for label, path in executable_checks.items():
        ok, detail = check_executable(path, label)
        checks[label] = {
            "passed": ok,
            "path": path,
            "detail": detail,
        }
        if not ok:
            failures.append(detail)

    xcrun_checks = {
        "notarytool": ["/usr/bin/xcrun", "--find", "notarytool"],
        "stapler": ["/usr/bin/xcrun", "--find", "stapler"],
    }
    for label, command in xcrun_checks.items():
        ok, detail = check_command_available(command, label)
        checks[label] = {
            "passed": ok,
            "command": command,
            "detail": detail,
        }
        if not ok:
            failures.append(detail)

    identity_ok, identity_detail, identity_failure = check_codesigning_identity(args.identity_pattern)
    checks["codesigning_identity"] = {
        "passed": identity_ok,
        **identity_detail,
    }
    if identity_failure is not None:
        failures.append(identity_failure)

    return {
        "report_schema": 1,
        "release_gate": "release-credential-prereq",
        "subject_commit": current_commit(root),
        "root": str(root),
        "passed": not failures,
        "not_release_readiness": True,
        "checks": checks,
        "failures": failures,
    }


def write_report(path: Path, report: dict[str, Any]) -> None:
    path.parent.mkdir(parents=True, exist_ok=True)
    path.write_text(json.dumps(report, indent=2, sort_keys=True) + "\n", encoding="utf-8")


def parse_args(argv: list[str]) -> argparse.Namespace:
    parser = argparse.ArgumentParser(
        description=(
            "Check local prerequisites for producing signed/notarized Meeting Assistant "
            "release materials. This does not build, sign, notarize, or verify a release."
        )
    )
    parser.add_argument("--root", default=str(repo_root_from_script()))
    parser.add_argument(
        "--identity-pattern",
        default=DEFAULT_IDENTITY_PATTERN,
        help="Substring that the release codesigning identity must contain.",
    )
    parser.add_argument("--report", help="Optional JSON report path.")
    return parser.parse_args(argv)


def main(argv: list[str]) -> int:
    args = parse_args(argv)
    root = resolve_path(repo_root_from_script(), args.root)
    report = build_report(args)
    if args.report:
        report_path = resolve_path(root, args.report)
        write_report(report_path, report)
        print(f"release credential prerequisite report: {report_path}", file=sys.stderr)

    if not report["passed"]:
        print("release credential prerequisite check failed:", file=sys.stderr)
        for failure in report["failures"]:
            print(f" - {failure}", file=sys.stderr)
        return 1

    print("release credential prerequisite check passed.")
    return 0


if __name__ == "__main__":
    raise SystemExit(main(sys.argv[1:]))
