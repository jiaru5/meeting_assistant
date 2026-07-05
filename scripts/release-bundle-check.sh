#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT_DIR"

report_path="${MEETING_ASSISTANT_RELEASE_BUNDLE_REPORT:-.harness/evidence/release/bundle/release-bundle-report.json}"

python3 - "$ROOT_DIR" "$report_path" <<'PY'
from __future__ import annotations

import hashlib
import json
import re
import subprocess
import sys
from pathlib import Path
from typing import Any


root = Path(sys.argv[1])
configured_report_path = Path(sys.argv[2])
if not configured_report_path.is_absolute():
    configured_report_path = root / configured_report_path

failures: list[str] = []


def current_commit() -> str | None:
    completed = subprocess.run(
        ["git", "-C", str(root), "rev-parse", "HEAD"],
        text=True,
        capture_output=True,
        check=False,
    )
    if completed.returncode != 0:
        return None
    return completed.stdout.strip()


def load_report(path: Path) -> dict[str, Any] | None:
    if not path.is_file():
        failures.append(f"release bundle report is required: {path}")
        return None
    try:
        payload = json.loads(path.read_text(encoding="utf-8"))
    except json.JSONDecodeError as exc:
        failures.append(f"release bundle report must be valid JSON: {path}: {exc}")
        return None
    if not isinstance(payload, dict):
        failures.append(f"release bundle report must be a JSON object: {path}")
        return None
    return payload


def resolve_path(value: Any, label: str) -> Path | None:
    if not isinstance(value, str) or not value:
        failures.append(f"{label} must be a non-empty path")
        return None
    path = Path(value)
    if not path.is_absolute():
        path = root / path
    return path


def require_equal(report: dict[str, Any], key: str, expected: Any, label: str) -> None:
    if report.get(key) != expected:
        failures.append(f"{label} must set {key}={expected!r}")


def require_non_empty_string(report: dict[str, Any], key: str, label: str) -> None:
    if not isinstance(report.get(key), str) or not report.get(key):
        failures.append(f"{label} must set non-empty {key}")


def require_sha256_digest(value: Any, label: str) -> str | None:
    if not isinstance(value, str) or re.fullmatch(r"sha256:[a-fA-F0-9]{64}", value) is None:
        failures.append(f"{label} must be a sha256:<64 hex> digest")
        return None
    return value.lower()


def sha256_file(path: Path) -> str:
    digest = hashlib.sha256()
    with path.open("rb") as handle:
        for chunk in iter(lambda: handle.read(1024 * 1024), b""):
            digest.update(chunk)
    return "sha256:" + digest.hexdigest()


head = current_commit()
report = load_report(configured_report_path)

if report is not None:
    require_equal(report, "report_schema", 1, "release bundle report")
    require_equal(report, "release_gate", "release-bundle", "release bundle report")
    if head is not None:
        require_equal(report, "subject_commit", head, "release bundle report")
    require_non_empty_string(report, "builder", "release bundle report")
    require_non_empty_string(report, "source_repository", "release bundle report")

    bundle = report.get("bundle")
    if not isinstance(bundle, dict):
        failures.append("release bundle report must include a bundle object")
    else:
        require_non_empty_string(bundle, "name", "release bundle")
        artifact_path = resolve_path(bundle.get("path"), "release bundle path")
        expected_digest = require_sha256_digest(bundle.get("digest"), "release bundle digest")
        require_equal(bundle, "artifact_type", "macos-app-archive", "release bundle")
        require_equal(bundle, "app_bundle", "MeetingAssistantNative.app", "release bundle")
        require_equal(bundle, "build_configuration", "Release", "release bundle")
        require_equal(bundle, "code_signed", True, "release bundle")
        require_equal(bundle, "notarized", True, "release bundle")
        require_equal(bundle, "stapled", True, "release bundle")
        require_equal(bundle, "packages_runtime_or_model", False, "release bundle")
        require_equal(bundle, "auto_downloads", False, "release bundle")
        require_equal(bundle, "contains_meeting_data", False, "release bundle")
        require_non_empty_string(bundle, "signing_identity", "release bundle")
        require_non_empty_string(bundle, "notarization_ticket", "release bundle")
        if artifact_path is not None:
            if not artifact_path.is_file():
                failures.append(f"release bundle artifact must exist as a file: {artifact_path}")
            elif expected_digest is not None and sha256_file(artifact_path) != expected_digest:
                failures.append(f"release bundle artifact digest mismatch: {artifact_path}")

if failures:
    print("release bundle evidence failed:", file=sys.stderr)
    for failure in failures:
        print(f" - {failure}", file=sys.stderr)
    raise SystemExit(1)

print("release bundle evidence passed.")
PY

echo "release-bundle-check passed."
