#!/usr/bin/env -S /usr/bin/python3 -I -S
from __future__ import annotations

import argparse
import functools
import hashlib
import json
import os
import platform
import plistlib
import re
import stat
import subprocess
import sys
import tempfile
from datetime import datetime
from pathlib import Path
from typing import Any


WALKTHROUGH_SCHEMA = 1
REPORT_SCHEMA = 1
CHECK_RESULTS = ("pass", "fail")
FINDING_SEVERITIES = ("P0", "P1", "P2", "P3")
FINDING_STATUSES = ("open", "closed")
COMMIT_PATTERN = re.compile(r"^[0-9a-f]{40}$")
CDHASH_PATTERN = re.compile(r"^[0-9a-f]{40}$")
SHA256_PATTERN = re.compile(r"^[0-9a-f]{64}$")
CODESIGN_CDHASH_PATTERN = re.compile(r"^CDHash=([0-9a-fA-F]{40})$", re.MULTILINE)
BUNDLE_ID_PATTERN = re.compile(r"^[A-Za-z0-9][A-Za-z0-9.-]*[A-Za-z0-9]$")
MACOS_VERSION_PATTERN = re.compile(r"^[0-9]+(?:\.[0-9]+){1,2}$")
EMAIL_PATTERN = re.compile(r"\b[A-Z0-9._%+-]+@[A-Z0-9.-]+\.[A-Z]{2,}\b", re.IGNORECASE)
PHONE_PATTERN = re.compile(r"(?<!\w)(?:\+?[0-9][0-9 ()-]{7,}[0-9])(?!\w)")
RAW_SESSION_ID_PATTERN = re.compile(r"\b(?:session|sess)[-_][A-Za-z0-9][A-Za-z0-9._-]{5,}\b", re.IGNORECASE)
MAX_FREE_TEXT_LENGTH = 1000
TRUSTED_XCRUN = Path("/usr/bin/xcrun")
TRUSTED_ENV = Path("/usr/bin/env")
TRUSTED_PYTHON_LAUNCHER = Path("/usr/bin/python3")
TRUSTED_CODESIGN = Path("/usr/bin/codesign")
TRUSTED_GIT = Path("/usr/bin/git")
TRUSTED_IMAGE_DECODER = Path("/usr/bin/sips")

ATTESTATION_STATEMENT = (
    "I manually observed the bound app in a real macOS window with VoiceOver enabled "
    "and keyboard-only interaction; every recorded check and retest reflects direct "
    "observation. No agent, source-contract test, automation, screenshot, or XCUITest "
    "result is being counted as this walkthrough."
)
PRIVACY_ATTESTATION_STATEMENT = (
    "I used only synthetic meeting data and excluded participant names, contact data, "
    "real meeting content, full transcript text, and raw session identifiers from every "
    "observation, finding, resolution, and retest note."
)

EVIDENCE_POLICY = {
    "walkthrough_type": "manual_real_app_voiceover_and_keyboard",
    "human_observer_attestation_required": True,
    "agent_counts_as_walkthrough": False,
    "source_contract_counts_as_walkthrough": False,
    "automation_counts_as_walkthrough": False,
    "screenshot_counts_as_walkthrough": False,
    "xcuitest_counts_as_walkthrough": False,
}

EVIDENCE_BOUNDARY = {
    "evidence_type": "manual_real_app_voiceover_and_keyboard_walkthrough",
    "manual_observer_attestation_required": True,
    "attestation_is_a_human_declaration_not_independent_identity_proof": True,
    "agent_source_contract_automation_screenshot_xcuitest_count_as_walkthrough": False,
    "usability_thresholds_applied": False,
    "usability_threshold_policy": "none_defined",
    "structure_validity_is_product_acceptance": False,
    "ready_for_review_is_product_acceptance": False,
    "current_commit_macos_and_app_identity_verified_at_report_generation": True,
    "passed_task_xcresult_provenance_required": True,
    "not_release_readiness": True,
}

CHECK_DEFINITIONS: tuple[tuple[str, str], ...] = (
    (
        "page_heading",
        "Each primary page or task view exposes one unique, understandable VoiceOver heading.",
    ),
    (
        "route_and_session_focus",
        "Route and current-session changes move VoiceOver and keyboard focus to the intended page or task control without an intermediate state stealing focus.",
    ),
    (
        "recording_status_announcements",
        "Recording start, active, stopping, saved, degraded, and failed state changes are announced in user language and expose the next available action.",
    ),
    (
        "processing_status_announcements",
        "Processing start, progress, failure, retry, and completion changes are announced without stealing task focus or exposing a raw session identifier as the success message.",
    ),
    (
        "transcript_status_announcements",
        "Transcript loading, ready, and load-failure changes are announced after strict loading resolves, using the user-facing meeting title and a recoverable next action.",
    ),
    (
        "core_keyboard_shortcuts",
        "Keyboard-only use can trigger the contextual core actions, including Command-Option-R/S/P/C/E when available, and unavailable actions do not run.",
    ),
    (
        "selected_state_not_color_only",
        "The selected navigation or meeting item has a visible non-color indicator and is announced as selected by VoiceOver.",
    ),
    (
        "technical_details_hide_raw_id_by_default",
        "The default task interface hides the raw session identifier; it appears only after the user explicitly expands Technical details or opens diagnostics.",
    ),
    (
        "delete_prompt_focus_and_return_cancel",
        "Delete confirmation receives focus and announces the meeting title and scope; Return and Keypad Enter only cancel, explicit Delete meeting is the only confirmation, and cancellation restores focus.",
    ),
)
CHECK_IDS = tuple(check_id for check_id, _ in CHECK_DEFINITIONS)
CHECK_REQUIREMENTS = dict(CHECK_DEFINITIONS)


class WalkthroughToolError(Exception):
    pass


def repo_root_from_script() -> Path:
    return Path(__file__).resolve().parents[1]


def current_commit(root: Path | None = None) -> str | None:
    repository = root if root is not None else repo_root_from_script()
    try:
        completed = subprocess.run(
            ["git", "-C", str(repository), "rev-parse", "HEAD"],
            text=True,
            capture_output=True,
            check=False,
        )
    except OSError:
        return None
    if completed.returncode != 0:
        return None
    value = completed.stdout.strip()
    return value if COMMIT_PATTERN.fullmatch(value) else None


def current_macos_version() -> str | None:
    version = platform.mac_ver()[0].strip()
    return version if MACOS_VERSION_PATTERN.fullmatch(version) else None


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
        errors.append(f"{path} must be a non-empty direct observation")
        return
    text = str(value)
    if len(text) > MAX_FREE_TEXT_LENGTH:
        errors.append(f"{path} exceeds the {MAX_FREE_TEXT_LENGTH}-character privacy limit")
    for label, pattern in (
        ("an email address", EMAIL_PATTERN),
        ("a phone number", PHONE_PATTERN),
        ("a raw session identifier", RAW_SESSION_ID_PATTERN),
    ):
        if pattern.search(text):
            errors.append(f"{path} must not contain {label}")


def _normalize_app_path(value: str) -> str:
    return str(Path(value).expanduser().resolve())


def _binding_errors(
    *,
    subject_commit: Any,
    tested_app_path: Any,
    tested_bundle_id: Any,
    tested_app_cdhash: Any,
    tested_app_executable_sha256: Any,
    macos_version: Any,
) -> list[str]:
    errors: list[str] = []
    if not isinstance(subject_commit, str) or not COMMIT_PATTERN.fullmatch(subject_commit):
        errors.append("subject.subject_commit must be a 40-character lowercase Git commit hash")
    if (
        not isinstance(tested_app_path, str)
        or not tested_app_path.strip()
        or "\n" in tested_app_path
        or "\r" in tested_app_path
        or not Path(tested_app_path).is_absolute()
        or Path(tested_app_path).suffix != ".app"
    ):
        errors.append("subject.tested_app_path must be an absolute .app path")
    if (
        not isinstance(tested_bundle_id, str)
        or len(tested_bundle_id) > 255
        or "." not in tested_bundle_id
        or ".." in tested_bundle_id
        or not BUNDLE_ID_PATTERN.fullmatch(tested_bundle_id)
    ):
        errors.append("subject.tested_bundle_id must be a reverse-DNS-style bundle identifier")
    if not isinstance(tested_app_cdhash, str) or not CDHASH_PATTERN.fullmatch(
        tested_app_cdhash
    ):
        errors.append("subject.tested_app_cdhash must be a 40-character lowercase CDHash")
    if not isinstance(tested_app_executable_sha256, str) or not SHA256_PATTERN.fullmatch(
        tested_app_executable_sha256
    ):
        errors.append(
            "subject.tested_app_executable_sha256 must be a 64-character lowercase SHA-256"
        )
    if not isinstance(macos_version, str) or not MACOS_VERSION_PATTERN.fullmatch(
        macos_version
    ):
        errors.append("environment.macos_version must be a dotted macOS version")
    return errors


def _read_app_identity(app_path: Path, codesign_tool: str) -> dict[str, str]:
    if not app_path.is_dir():
        raise WalkthroughToolError(f"bound app does not exist as a directory: {app_path}")
    info_plist = app_path / "Contents" / "Info.plist"
    if not info_plist.is_file():
        raise WalkthroughToolError(f"bound app Info.plist is missing: {info_plist}")
    try:
        with info_plist.open("rb") as handle:
            info = plistlib.load(handle)
    except (OSError, plistlib.InvalidFileException) as exc:
        raise WalkthroughToolError(f"could not read bound app Info.plist: {exc}") from exc
    bundle_id = str(info.get("CFBundleIdentifier", "")).strip()
    executable_name = str(info.get("CFBundleExecutable", "")).strip()
    executable_path = app_path / "Contents" / "MacOS" / executable_name
    if not bundle_id or not executable_name or not executable_path.is_file():
        raise WalkthroughToolError("bound app bundle id or executable is missing")

    try:
        verified = subprocess.run(
            [codesign_tool, "--verify", "--deep", "--strict", str(app_path)],
            text=True,
            capture_output=True,
            check=False,
        )
    except OSError as exc:
        raise WalkthroughToolError(f"could not verify bound app code signature: {exc}") from exc
    if verified.returncode != 0:
        detail = (verified.stderr or verified.stdout).strip()
        raise WalkthroughToolError(f"bound app strict code-signature verification failed: {detail}")

    try:
        completed = subprocess.run(
            [codesign_tool, "-dvvv", str(app_path)],
            text=True,
            capture_output=True,
            check=False,
        )
    except OSError as exc:
        raise WalkthroughToolError(f"could not inspect bound app code signature: {exc}") from exc
    output = "\n".join(part for part in (completed.stdout, completed.stderr) if part)
    match = CODESIGN_CDHASH_PATTERN.search(output)
    if completed.returncode != 0 or match is None:
        detail = output.strip() or f"exit {completed.returncode}"
        raise WalkthroughToolError(
            f"could not read a 40-character CDHash from the bound app signature: {detail}"
        )
    return {
        "path": str(app_path),
        "bundle_id": bundle_id,
        "cdhash": match.group(1).lower(),
        "executable_path": str(executable_path),
        "executable_sha256": _sha256_file(executable_path),
    }


def _sha256_file(path: Path) -> str:
    digest = hashlib.sha256()
    try:
        with path.open("rb") as handle:
            for block in iter(lambda: handle.read(1024 * 1024), b""):
                digest.update(block)
    except OSError as exc:
        raise WalkthroughToolError(f"retained task artifact could not be read: {path}: {exc}") from exc
    return digest.hexdigest()


def _directory_manifest(path: Path) -> dict[str, int | str]:
    digest = hashlib.sha256()
    file_count = 0
    total_bytes = 0
    try:
        for item in sorted(path.rglob("*"), key=lambda candidate: candidate.as_posix()):
            if item.is_symlink():
                raise WalkthroughToolError(f"retained task artifact contains a symlink: {item}")
            if item.is_dir():
                continue
            if not item.is_file():
                raise WalkthroughToolError(f"retained task artifact contains a non-file entry: {item}")
            relative = item.relative_to(path).as_posix()
            size = item.stat().st_size
            file_sha256 = _sha256_file(item)
            digest.update(f"{relative}\0{size}\0{file_sha256}\n".encode("utf-8"))
            file_count += 1
            total_bytes += size
    except OSError as exc:
        raise WalkthroughToolError(
            f"retained task artifact directory could not be read safely: {path}: {exc}"
        ) from exc
    if file_count == 0:
        raise WalkthroughToolError(f"retained task artifact directory is empty: {path}")
    return {
        "manifest_sha256": digest.hexdigest(),
        "file_count": file_count,
        "total_bytes": total_bytes,
    }


@functools.lru_cache(maxsize=1)
def current_trusted_task_toolchain() -> dict[str, Any]:
    resolved_xcode_tools: dict[str, Path] = {}
    for name in ("python3", "xcodebuild", "xcresulttool"):
        completed = subprocess.run(
            [str(TRUSTED_XCRUN), "--find", name],
            check=False,
            capture_output=True,
            text=True,
        )
        candidate = completed.stdout.strip()
        if completed.returncode != 0 or not candidate:
            detail = (completed.stderr or completed.stdout).strip()
            raise WalkthroughToolError(
                f"trusted xcrun could not resolve {name}: {detail or 'no path returned'}"
            )
        resolved_xcode_tools[name] = Path(candidate)
    paths = {
        "env": TRUSTED_ENV,
        "xcrun": TRUSTED_XCRUN,
        "python_launcher": TRUSTED_PYTHON_LAUNCHER,
        "python": resolved_xcode_tools["python3"],
        "xcodebuild": resolved_xcode_tools["xcodebuild"],
        "xcresulttool": resolved_xcode_tools["xcresulttool"],
        "codesign": TRUSTED_CODESIGN,
        "git": TRUSTED_GIT,
        "image_decoder": TRUSTED_IMAGE_DECODER,
    }
    identities: dict[str, dict[str, Any]] = {}
    for label, path in paths.items():
        try:
            resolved_path = path.resolve(strict=True)
        except OSError as exc:
            raise WalkthroughToolError(
                f"trusted task evidence tool could not be resolved safely: {label}: {path}: {exc}"
            ) from exc
        if (
            not path.is_absolute()
            or not path.is_file()
            or not os.access(path, os.X_OK)
            or not resolved_path.is_file()
            or not os.access(resolved_path, os.X_OK)
        ):
            raise WalkthroughToolError(
                "trusted task evidence tool does not resolve from an absolute executable "
                f"path to a regular executable: {label}: {path}"
            )
        verified = subprocess.run(
            [
                str(TRUSTED_CODESIGN),
                "--verify",
                "--strict",
                "--test-requirement",
                "=anchor apple",
                str(resolved_path),
            ],
            check=False,
            capture_output=True,
            text=True,
        )
        if verified.returncode != 0:
            detail = (verified.stderr or verified.stdout).strip()
            raise WalkthroughToolError(
                f"trusted task evidence tool is not Apple-anchor verified: {label}: {detail}"
            )
        identities[label] = {
            "path": str(path),
            "resolved_path": str(resolved_path),
            "sha256": _sha256_file(resolved_path),
            "apple_anchor_verified": True,
        }
    return {"mode": "trusted", "tools": identities}


def _validated_task_evidence(
    *,
    report_path: Path,
    subject: dict[str, Any],
    report_bytes: bytes | None = None,
) -> dict[str, str]:
    if report_bytes is None:
        if not report_path.is_file():
            raise WalkthroughToolError(f"task xcresult evidence report is missing: {report_path}")
        try:
            raw_report = report_path.read_bytes()
        except OSError as exc:
            raise WalkthroughToolError(f"task xcresult evidence report is unreadable: {exc}") from exc
    elif not isinstance(report_bytes, bytes):
        raise WalkthroughToolError("task xcresult evidence report bytes must be bytes")
    else:
        raw_report = report_bytes
    try:
        report = json.loads(raw_report.decode("utf-8"))
    except (UnicodeError, json.JSONDecodeError) as exc:
        raise WalkthroughToolError(f"task xcresult evidence report is unreadable: {exc}") from exc
    if not isinstance(report, dict):
        raise WalkthroughToolError("task xcresult evidence report must be a JSON object")
    required_summary = {
        "result": "Passed",
        "totalTestCount": 17,
        "passedTests": 17,
        "failedTests": 0,
        "skippedTests": 0,
        "expectedFailures": 0,
    }
    if report.get("schema_version") != 2 or report.get("release_gate") != "mvp1-task-xcresult-evidence":
        raise WalkthroughToolError("task xcresult evidence report has the wrong schema or gate")
    if report.get("passed") is not True or report.get("upstream_test_status") != 0:
        raise WalkthroughToolError("task xcresult evidence report must be a successful zero-exit report")
    task_toolchain = report.get("toolchain")
    if task_toolchain != current_trusted_task_toolchain():
        raise WalkthroughToolError(
            "task xcresult evidence report does not retain the current trusted Apple toolchain provenance"
        )
    if report.get("task_subject_paths_clean") is not True:
        raise WalkthroughToolError("task xcresult evidence report did not bind clean app/UI-test subject paths")
    subject_commit = subject.get("subject_commit")
    if (
        report.get("subject_commit") != subject_commit
        or report.get("subject_commit_before_test") != subject_commit
    ):
        raise WalkthroughToolError("task xcresult evidence report does not bind the walkthrough commit")
    prepared_fingerprint = report.get("prepared_input_fingerprint")
    if (
        not isinstance(prepared_fingerprint, str)
        or not re.fullmatch(r"[0-9a-f]{64}", prepared_fingerprint)
        or report.get("current_input_fingerprint_after_test") != prepared_fingerprint
    ):
        raise WalkthroughToolError("task xcresult evidence report has no stable app/UI-test fingerprint")
    app_identity = report.get("app_identity")
    if not isinstance(app_identity, dict) or {
        "path": app_identity.get("path"),
        "bundle_id": app_identity.get("bundle_id"),
        "cdhash": app_identity.get("cdhash"),
        "executable_sha256": app_identity.get("executable_sha256"),
    } != {
        "path": subject.get("tested_app_path"),
        "bundle_id": subject.get("tested_bundle_id"),
        "cdhash": subject.get("tested_app_cdhash"),
        "executable_sha256": subject.get("tested_app_executable_sha256"),
    }:
        raise WalkthroughToolError("task xcresult evidence report app identity does not match the walkthrough")
    if report.get("summary") != required_summary:
        raise WalkthroughToolError("task xcresult evidence report does not contain the exact 17/17 summary")
    verifier = report.get("verifier_snapshot")
    if not isinstance(verifier, dict):
        raise WalkthroughToolError("task xcresult evidence report is missing verifier provenance")
    verifier_path_value = verifier.get("path")
    verifier_source_value = verifier.get("source_path")
    verifier_expected_sha256 = verifier.get("expected_sha256")
    verifier_executed_sha256 = verifier.get("executed_sha256")
    if (
        not isinstance(verifier_path_value, str)
        or not isinstance(verifier_source_value, str)
        or not isinstance(verifier_expected_sha256, str)
        or not SHA256_PATTERN.fullmatch(verifier_expected_sha256)
        or verifier_executed_sha256 != verifier_expected_sha256
        or verifier.get("matched") is not True
    ):
        raise WalkthroughToolError("task xcresult evidence verifier provenance is incomplete")
    verifier_path = Path(verifier_path_value).expanduser().resolve()
    verifier_source_path = Path(verifier_source_value).expanduser().resolve()
    expected_verifier_source = repo_root_from_script() / "scripts" / "mvp1-task-xcresult.py"
    if verifier_source_path != expected_verifier_source.resolve():
        raise WalkthroughToolError("task xcresult evidence does not name the canonical verifier source")
    if not verifier_path.is_file() or _sha256_file(verifier_path) != verifier_expected_sha256:
        raise WalkthroughToolError("task xcresult frozen verifier snapshot is missing or changed")
    if not verifier_source_path.is_file() or _sha256_file(verifier_source_path) != verifier_expected_sha256:
        raise WalkthroughToolError("task xcresult canonical verifier source is missing or changed")
    attachments = report.get("attachments")
    screenshots = attachments.get("exported_screenshots") if isinstance(attachments, dict) else None
    if not isinstance(screenshots, list) or [item.get("name") for item in screenshots if isinstance(item, dict)] != [
        "00-meetings-recent",
        "01-meetings-empty",
        "02-new-recording-ready",
        "03-recording-live",
        "04-recording-saved",
        "05-processing",
        "06-transcript-ready",
        "07-diagnostics",
    ]:
        raise WalkthroughToolError("task xcresult evidence report does not contain the eight required screenshots")
    for screenshot in screenshots:
        if not isinstance(screenshot, dict):
            raise WalkthroughToolError("task xcresult evidence screenshot metadata is invalid")
        screenshot_path_value = screenshot.get("path")
        screenshot_sha256 = screenshot.get("sha256")
        if (
            not isinstance(screenshot_path_value, str)
            or not isinstance(screenshot_sha256, str)
            or not SHA256_PATTERN.fullmatch(screenshot_sha256)
            or not isinstance(screenshot.get("width"), int)
            or screenshot.get("width", 0) <= 0
            or not isinstance(screenshot.get("height"), int)
            or screenshot.get("height", 0) <= 0
        ):
            raise WalkthroughToolError("task xcresult evidence screenshot metadata is incomplete")
        screenshot_path = Path(screenshot_path_value).expanduser().resolve()
        if not screenshot_path.is_file() or _sha256_file(screenshot_path) != screenshot_sha256:
            raise WalkthroughToolError(
                f"task xcresult evidence screenshot is missing or changed: {screenshot.get('name')}"
            )
    xctestrun = report.get("xctestrun")
    if not isinstance(xctestrun, dict):
        raise WalkthroughToolError("task xcresult evidence report is missing xctestrun provenance")
    xctestrun_path_value = xctestrun.get("path")
    xctestrun_sha256 = xctestrun.get("sha256")
    if not isinstance(xctestrun_path_value, str) or not isinstance(xctestrun_sha256, str):
        raise WalkthroughToolError("task xcresult evidence report has incomplete xctestrun provenance")
    xctestrun_path = Path(xctestrun_path_value).expanduser().resolve()
    if not xctestrun_path.is_file() or _sha256_file(xctestrun_path) != xctestrun_sha256:
        raise WalkthroughToolError("task xcresult evidence xctestrun is missing or its SHA-256 changed")
    binding_file = report.get("artifact_binding_file")
    binding_path_value = binding_file.get("path") if isinstance(binding_file, dict) else None
    binding_sha256 = binding_file.get("sha256") if isinstance(binding_file, dict) else None
    if (
        not isinstance(binding_path_value, str)
        or not isinstance(binding_sha256, str)
        or not SHA256_PATTERN.fullmatch(binding_sha256)
        or binding_file.get("expected_sha256") != binding_sha256
        or binding_file.get("observed_sha256") != binding_sha256
        or binding_file.get("matched") is not True
    ):
        raise WalkthroughToolError("task xcresult evidence is missing its pre-test artifact binding")
    binding_before_test = report.get("artifact_binding_before_test")
    if (
        not isinstance(binding_before_test, dict)
        or binding_before_test.get("captured_by_verifier_sha256") != verifier_expected_sha256
        or binding_before_test.get("toolchain") != task_toolchain
    ):
        raise WalkthroughToolError(
            "task xcresult pre-test artifact binding was not captured by the frozen verifier"
        )
    binding_path = Path(binding_path_value).expanduser().resolve()
    if not binding_path.is_file() or _sha256_file(binding_path) != binding_sha256:
        raise WalkthroughToolError("task xcresult pre-test artifact binding is missing or changed")
    xcresult = report.get("xcresult")
    xcresult_path_value = xcresult.get("path") if isinstance(xcresult, dict) else None
    if not isinstance(xcresult_path_value, str):
        raise WalkthroughToolError("task xcresult evidence bundle is missing")
    xcresult_path = Path(xcresult_path_value).expanduser().resolve()
    if not xcresult_path.is_dir():
        raise WalkthroughToolError("task xcresult evidence bundle is missing")
    observed_xcresult = _directory_manifest(xcresult_path)
    expected_xcresult = {
        "manifest_sha256": xcresult.get("manifest_sha256"),
        "file_count": xcresult.get("file_count"),
        "total_bytes": xcresult.get("total_bytes"),
    }
    if observed_xcresult != expected_xcresult:
        raise WalkthroughToolError("task xcresult evidence bundle contents are missing or changed")
    return {
        "report_path": str(report_path),
        "report_sha256": hashlib.sha256(raw_report).hexdigest(),
        "prepared_input_fingerprint": prepared_fingerprint,
        "xctestrun_sha256": xctestrun_sha256,
    }


def _runtime_binding_errors(
    *,
    subject: dict[str, Any],
    environment: dict[str, Any],
    codesign_tool: str,
) -> list[str]:
    errors: list[str] = []
    recorded_commit = subject.get("subject_commit")
    head_commit = current_commit()
    if head_commit is None:
        errors.append("current Git HEAD could not be read; subject binding fails closed")
    elif recorded_commit != head_commit:
        errors.append(
            f"subject.subject_commit must match current Git HEAD {head_commit!r}; "
            f"observed {recorded_commit!r}"
        )

    recorded_macos = environment.get("macos_version")
    host_macos = current_macos_version()
    if host_macos is None:
        errors.append("current macOS version could not be read; environment binding fails closed")
    elif recorded_macos != host_macos:
        errors.append(
            f"environment.macos_version must match current macOS {host_macos!r}; "
            f"observed {recorded_macos!r}"
        )

    app_path_value = subject.get("tested_app_path")
    if isinstance(app_path_value, str) and Path(app_path_value).is_absolute():
        app_path = Path(app_path_value)
        try:
            actual_identity = _read_app_identity(app_path, codesign_tool)
        except WalkthroughToolError as exc:
            errors.append(str(exc))
        else:
            if subject.get("tested_bundle_id") != actual_identity["bundle_id"]:
                errors.append(
                    f"subject.tested_bundle_id does not match bound app identity "
                    f"{actual_identity['bundle_id']!r}"
                )
            if subject.get("tested_app_cdhash") != actual_identity["cdhash"]:
                errors.append(
                    f"subject.tested_app_cdhash does not match bound app CDHash "
                    f"{actual_identity['cdhash']!r}"
                )
            if (
                subject.get("tested_app_executable_sha256")
                != actual_identity["executable_sha256"]
            ):
                errors.append(
                    "subject.tested_app_executable_sha256 does not match the bound app executable"
                )
    return errors


def check_template(check_id: str) -> dict[str, Any]:
    return {
        "check_id": check_id,
        "requirement": CHECK_REQUIREMENTS[check_id],
        "result": None,
        "observation": "",
    }


def build_template(
    *,
    tested_app_path: str,
    tested_bundle_id: str,
    tested_app_cdhash: str,
    subject_commit: str | None = None,
    macos_version: str | None = None,
    walkthrough_id: str = "mvp1-accessibility-walkthrough",
    codesign_tool: str = "/usr/bin/codesign",
    task_evidence_report: str,
) -> dict[str, Any]:
    commit = subject_commit or current_commit()
    version = macos_version or current_macos_version()
    normalized_path = _normalize_app_path(tested_app_path)
    normalized_cdhash = tested_app_cdhash.lower()
    try:
        actual_identity = _read_app_identity(Path(normalized_path), codesign_tool)
        executable_sha256: str | None = actual_identity["executable_sha256"]
    except WalkthroughToolError as exc:
        actual_identity = None
        executable_sha256 = None
        identity_error = str(exc)
    errors = _binding_errors(
        subject_commit=commit,
        tested_app_path=normalized_path,
        tested_bundle_id=tested_bundle_id,
        tested_app_cdhash=normalized_cdhash,
        tested_app_executable_sha256=executable_sha256,
        macos_version=version,
    )
    if actual_identity is None:
        errors.append(identity_error)
    if not _is_nonempty_string(walkthrough_id):
        errors.append("walkthrough_id must be a non-empty string")
    if not errors:
        errors.extend(
            _runtime_binding_errors(
                subject={
                    "subject_commit": commit,
                    "tested_app_path": normalized_path,
                    "tested_bundle_id": tested_bundle_id,
                    "tested_app_cdhash": normalized_cdhash,
                    "tested_app_executable_sha256": executable_sha256,
                },
                environment={"macos_version": version},
                codesign_tool=codesign_tool,
            )
        )
    if errors:
        raise WalkthroughToolError("; ".join(errors))
    task_evidence = _validated_task_evidence(
        report_path=Path(task_evidence_report).expanduser().resolve(),
        subject={
            "subject_commit": commit,
            "tested_app_path": normalized_path,
            "tested_bundle_id": tested_bundle_id,
            "tested_app_cdhash": normalized_cdhash,
            "tested_app_executable_sha256": executable_sha256,
        },
    )
    return {
        "walkthrough_schema": WALKTHROUGH_SCHEMA,
        "walkthrough_id": walkthrough_id,
        "subject": {
            "subject_commit": commit,
            "tested_app_path": normalized_path,
            "tested_bundle_id": tested_bundle_id,
            "tested_app_cdhash": normalized_cdhash,
            "tested_app_executable_sha256": executable_sha256,
        },
        "environment": {
            "operating_system": "macOS",
            "macos_version": version,
        },
        "evidence_policy": dict(EVIDENCE_POLICY),
        "task_evidence": task_evidence,
        "observer_attestation": {
            "confirmed": False,
            "attested_at": None,
            "attested_by_role": None,
            "statement": ATTESTATION_STATEMENT,
            "synthetic_data_confirmed": False,
            "privacy_statement": PRIVACY_ATTESTATION_STATEMENT,
        },
        "checks": [check_template(check_id) for check_id in CHECK_IDS],
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
    for key in sorted(required - set(value)):
        errors.append(f"{path}.{key} is required")
    for key in sorted(set(value) - required - optional_keys):
        errors.append(f"{path}.{key} is not allowed")


def _validate_subject_and_environment(
    subject: Any,
    environment: Any,
    *,
    errors: list[str],
    codesign_tool: str,
) -> None:
    if not isinstance(subject, dict):
        errors.append("subject must be an object")
        subject = {}
    _expect_exact_keys(
        subject,
        required={
            "subject_commit",
            "tested_app_path",
            "tested_bundle_id",
            "tested_app_cdhash",
            "tested_app_executable_sha256",
        },
        optional=set(),
        path="subject",
        errors=errors,
    )
    if not isinstance(environment, dict):
        errors.append("environment must be an object")
        environment = {}
    _expect_exact_keys(
        environment,
        required={"operating_system", "macos_version"},
        optional=set(),
        path="environment",
        errors=errors,
    )
    if environment.get("operating_system") != "macOS":
        errors.append("environment.operating_system must be 'macOS'")
    errors.extend(
        _binding_errors(
            subject_commit=subject.get("subject_commit"),
            tested_app_path=subject.get("tested_app_path"),
            tested_bundle_id=subject.get("tested_bundle_id"),
            tested_app_cdhash=subject.get("tested_app_cdhash"),
            tested_app_executable_sha256=subject.get("tested_app_executable_sha256"),
            macos_version=environment.get("macos_version"),
        )
    )
    if not errors:
        errors.extend(
            _runtime_binding_errors(
                subject=subject,
                environment=environment,
                codesign_tool=codesign_tool,
            )
        )


def _validate_evidence_policy(value: Any, *, errors: list[str]) -> None:
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
    subject: Any,
    errors: list[str],
) -> None:
    if not isinstance(value, dict):
        errors.append("task_evidence must be an object")
        return
    _expect_exact_keys(
        value,
        required={
            "report_path",
            "report_sha256",
            "prepared_input_fingerprint",
            "xctestrun_sha256",
        },
        optional=set(),
        path="task_evidence",
        errors=errors,
    )
    report_path_value = value.get("report_path")
    if not isinstance(report_path_value, str) or not Path(report_path_value).is_absolute():
        errors.append("task_evidence.report_path must be an absolute path")
        return
    if not isinstance(subject, dict):
        return
    try:
        observed = _validated_task_evidence(
            report_path=Path(report_path_value).expanduser().resolve(),
            subject=subject,
        )
    except WalkthroughToolError as exc:
        errors.append(str(exc))
        return
    if value != observed:
        errors.append("task_evidence fields do not match the retained task xcresult report")


def _validate_attestation(value: Any, *, errors: list[str]) -> None:
    if not isinstance(value, dict):
        errors.append("observer_attestation must be an object")
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
        path="observer_attestation",
        errors=errors,
    )
    if value.get("confirmed") is not True:
        errors.append(
            "observer_attestation.confirmed must be true only after a human observer completes the real-app walkthrough"
        )
    if not _is_timezone_aware_iso8601(value.get("attested_at")):
        errors.append(
            "observer_attestation.attested_at must be a timezone-aware ISO-8601 timestamp"
        )
    if not _is_nonempty_string(value.get("attested_by_role")):
        errors.append("observer_attestation.attested_by_role must be a non-empty role or pseudonym")
    if value.get("statement") != ATTESTATION_STATEMENT:
        errors.append("observer_attestation.statement must match the manual observer statement")
    if value.get("synthetic_data_confirmed") is not True:
        errors.append(
            "observer_attestation.synthetic_data_confirmed must be true only after checking every note"
        )
    if value.get("privacy_statement") != PRIVACY_ATTESTATION_STATEMENT:
        errors.append("observer_attestation.privacy_statement must match the privacy statement")


def _validate_checks(
    value: Any,
    *,
    schema_errors: list[str],
    recording_errors: list[str],
) -> tuple[dict[str, str], set[str]]:
    if not isinstance(value, list):
        schema_errors.append("checks must be an array")
        return {}, set()

    seen: set[str] = set()
    results: dict[str, str] = {}
    failed: set[str] = set()
    for index, check in enumerate(value):
        path = f"checks[{index}]"
        if not isinstance(check, dict):
            schema_errors.append(f"{path} must be an object")
            continue
        _expect_exact_keys(
            check,
            required={"check_id", "requirement", "result", "observation"},
            optional=set(),
            path=path,
            errors=schema_errors,
        )
        check_id = check.get("check_id")
        if check_id not in CHECK_IDS:
            schema_errors.append(f"{path}.check_id must be one of {', '.join(CHECK_IDS)}")
            continue
        if check_id in seen:
            schema_errors.append(f"checks contains duplicate check_id {check_id!r}")
            continue
        seen.add(check_id)
        if check.get("requirement") != CHECK_REQUIREMENTS[check_id]:
            schema_errors.append(f"{path}.requirement must match the fixed walkthrough requirement")
        result = check.get("result")
        if result not in CHECK_RESULTS:
            recording_errors.append(f"{path}.result must be 'pass' or 'fail' after direct observation")
        else:
            results[check_id] = result
            if result == "fail":
                failed.add(check_id)
        _validate_private_text(
            check.get("observation"),
            path=f"{path}.observation",
            errors=recording_errors,
        )

    for check_id in CHECK_IDS:
        if check_id not in seen:
            schema_errors.append(f"checks is missing required check_id {check_id!r}")
    if len(value) > len(CHECK_IDS):
        schema_errors.append("checks must contain exactly the fixed walkthrough checks without extras")
    return results, failed


def _validate_retest(value: Any, *, path: str, errors: list[str]) -> bool:
    if not isinstance(value, dict):
        errors.append(f"{path} must be an object")
        return False
    _expect_exact_keys(
        value,
        required={"result", "retested_at", "observation"},
        optional=set(),
        path=path,
        errors=errors,
    )
    valid = True
    if value.get("result") != "pass":
        errors.append(f"{path}.result must be 'pass' before the finding can be closed")
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
    check_results: dict[str, str],
    schema_errors: list[str],
    closure_errors: list[str],
) -> tuple[list[dict[str, str]], set[str]]:
    if not isinstance(value, list):
        schema_errors.append("findings must be an array")
        return [], set()

    seen_ids: set[str] = set()
    referenced_checks: set[str] = set()
    open_p0_p1: list[dict[str, str]] = []
    for index, finding in enumerate(value):
        path = f"findings[{index}]"
        if not isinstance(finding, dict):
            schema_errors.append(f"{path} must be an object")
            continue
        _expect_exact_keys(
            finding,
            required={"finding_id", "severity", "status", "summary", "check_ids"},
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
        _validate_private_text(
            finding.get("summary"),
            path=f"{path}.summary",
            errors=schema_errors,
        )

        check_ids = finding.get("check_ids")
        valid_check_ids: list[str] = []
        if not isinstance(check_ids, list) or not check_ids:
            schema_errors.append(f"{path}.check_ids must be a non-empty array")
        elif not all(isinstance(check_id, str) for check_id in check_ids):
            schema_errors.append(f"{path}.check_ids must contain only check identifiers")
        else:
            if len(check_ids) != len(set(check_ids)):
                schema_errors.append(f"{path}.check_ids must not contain duplicates")
            for check_id in check_ids:
                if check_id not in CHECK_IDS:
                    schema_errors.append(f"{path}.check_ids references unknown check {check_id!r}")
                else:
                    valid_check_ids.append(check_id)
                    referenced_checks.add(check_id)

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
            if "retest" not in finding:
                closure_errors.append(f"{path}.retest is required for a closed {severity} finding")
            else:
                _validate_retest(
                    finding["retest"],
                    path=f"{path}.retest",
                    errors=closure_errors,
                )
            for check_id in valid_check_ids:
                if check_results.get(check_id) != "pass":
                    closure_errors.append(
                        f"{path} cannot close {severity} while referenced check {check_id!r} is not pass"
                    )
    return open_p0_p1, referenced_checks


def validate_walkthrough(
    walkthrough: Any,
    *,
    codesign_tool: str = "/usr/bin/codesign",
) -> dict[str, Any]:
    schema_errors: list[str] = []
    binding_errors: list[str] = []
    attestation_errors: list[str] = []
    recording_errors: list[str] = []
    finding_tracking_errors: list[str] = []
    closure_errors: list[str] = []
    blocker_errors: list[str] = []

    if not isinstance(walkthrough, dict):
        schema_errors.append("walkthrough document must be a JSON object")
        walkthrough = {}
    _expect_exact_keys(
        walkthrough,
        required={
            "walkthrough_schema",
            "walkthrough_id",
            "subject",
            "environment",
            "evidence_policy",
            "task_evidence",
            "observer_attestation",
            "checks",
            "findings",
        },
        optional=set(),
        path="walkthrough",
        errors=schema_errors,
    )
    schema = walkthrough.get("walkthrough_schema")
    if not isinstance(schema, int) or isinstance(schema, bool) or schema != WALKTHROUGH_SCHEMA:
        schema_errors.append(f"walkthrough_schema must be {WALKTHROUGH_SCHEMA}")
    if not _is_nonempty_string(walkthrough.get("walkthrough_id")):
        schema_errors.append("walkthrough_id must be a non-empty string")

    _validate_subject_and_environment(
        walkthrough.get("subject"),
        walkthrough.get("environment"),
        errors=binding_errors,
        codesign_tool=codesign_tool,
    )
    _validate_evidence_policy(walkthrough.get("evidence_policy"), errors=schema_errors)
    _validate_task_evidence(
        walkthrough.get("task_evidence"),
        subject=walkthrough.get("subject"),
        errors=binding_errors,
    )
    _validate_attestation(walkthrough.get("observer_attestation"), errors=attestation_errors)
    check_results, failed_checks = _validate_checks(
        walkthrough.get("checks"),
        schema_errors=schema_errors,
        recording_errors=recording_errors,
    )
    open_p0_p1, referenced_checks = _validate_findings(
        walkthrough.get("findings"),
        check_results=check_results,
        schema_errors=schema_errors,
        closure_errors=closure_errors,
    )
    for check_id in sorted(failed_checks - referenced_checks):
        finding_tracking_errors.append(
            f"failed check {check_id!r} must be referenced by a finding"
        )
    for finding in open_p0_p1:
        blocker_errors.append(
            f"open {finding['severity']} finding {finding['finding_id']}: {finding['summary']}"
        )

    structure_valid = not schema_errors
    subject_binding_valid = not binding_errors
    manual_observer_attestation_valid = not attestation_errors
    all_fixed_checks_recorded = not recording_errors and len(check_results) == len(CHECK_IDS)
    failed_checks_tracked = not finding_tracking_errors
    closed_p0_p1_resolution_and_retest_valid = not closure_errors
    no_open_p0_p1_findings = not open_p0_p1
    ready_for_review = all(
        (
            structure_valid,
            subject_binding_valid,
            manual_observer_attestation_valid,
            all_fixed_checks_recorded,
            failed_checks_tracked,
            closed_p0_p1_resolution_and_retest_valid,
            no_open_p0_p1_findings,
        )
    )
    return {
        "ready_for_review": ready_for_review,
        "checks": {
            "structure_valid": structure_valid,
            "subject_binding_valid": subject_binding_valid,
            "manual_observer_attestation_valid": manual_observer_attestation_valid,
            "all_fixed_checks_recorded": all_fixed_checks_recorded,
            "failed_checks_tracked": failed_checks_tracked,
            "closed_p0_p1_resolution_and_retest_valid": closed_p0_p1_resolution_and_retest_valid,
            "no_open_p0_p1_findings": no_open_p0_p1_findings,
            "usability_thresholds_applied": False,
            "structure_validity_is_product_acceptance": False,
        },
        "required_check_ids": list(CHECK_IDS),
        "recorded_check_count": len(check_results),
        "passed_check_ids": sorted(
            check_id for check_id, result in check_results.items() if result == "pass"
        ),
        "failed_check_ids": sorted(failed_checks),
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


def _finding_counts(findings: Any) -> dict[str, dict[str, int]]:
    values = findings if isinstance(findings, list) else []
    return {
        severity: {
            status: sum(
                1
                for finding in values
                if isinstance(finding, dict)
                and finding.get("severity") == severity
                and finding.get("status") == status
            )
            for status in FINDING_STATUSES
        }
        for severity in FINDING_SEVERITIES
    }


def build_report(
    walkthrough: Any,
    *,
    source: str | None = None,
    codesign_tool: str = "/usr/bin/codesign",
) -> dict[str, Any]:
    validation = validate_walkthrough(walkthrough, codesign_tool=codesign_tool)
    document = walkthrough if isinstance(walkthrough, dict) else {}
    raw_checks = document.get("checks", [])
    raw_findings = document.get("findings", [])
    return {
        "report_schema": REPORT_SCHEMA,
        "report_type": "mvp1-manual-accessibility-walkthrough",
        "source": source,
        "walkthrough_id": document.get("walkthrough_id"),
        "subject": document.get("subject") if isinstance(document.get("subject"), dict) else {},
        "environment": (
            document.get("environment")
            if isinstance(document.get("environment"), dict)
            else {}
        ),
        "task_evidence": (
            document.get("task_evidence")
            if isinstance(document.get("task_evidence"), dict)
            else {}
        ),
        "status": "ready_for_review" if validation["ready_for_review"] else "blocked",
        **validation,
        "walkthrough_checks": [check for check in raw_checks if isinstance(check, dict)]
        if isinstance(raw_checks, list)
        else [],
        "findings": [finding for finding in raw_findings if isinstance(finding, dict)]
        if isinstance(raw_findings, list)
        else [],
        "finding_counts": _finding_counts(raw_findings),
        "evidence_boundary": dict(EVIDENCE_BOUNDARY),
    }


def render_text(report: dict[str, Any]) -> str:
    status_text = "READY FOR REVIEW" if report["ready_for_review"] else "BLOCKED"
    subject = report.get("subject", {})
    environment = report.get("environment", {})
    lines = [
        f"MVP.1 manual accessibility walkthrough: {status_text}",
        f"Subject commit: {subject.get('subject_commit', '-')}",
        f"Tested app: {subject.get('tested_app_path', '-')}",
        f"Bundle ID: {subject.get('tested_bundle_id', '-')}",
        f"CDHash: {subject.get('tested_app_cdhash', '-')}",
        f"macOS: {environment.get('macos_version', '-')}",
        f"Task evidence: {report.get('task_evidence', {}).get('report_path', '-')}",
        f"Recorded checks: {report['recorded_check_count']}/{len(CHECK_IDS)}",
        f"Failed checks: {len(report['failed_check_ids'])}",
        f"Open P0/P1 findings: {len(report['open_p0_p1_findings'])}",
        "Usability thresholds applied: false (none are defined)",
        "Evidence boundary: structure validity and ready_for_review do not mean product acceptance or release readiness.",
        "Manual boundary: agents, source-contract tests, automation, screenshots, and XCUITest do not count as this walkthrough.",
        (
            "Privacy boundary: use synthetic meeting data; observations must not contain participant "
            "names, contact data, real meeting content, full transcript text, or raw session identifiers."
        ),
    ]
    if report["errors"]:
        lines.append("Errors:")
        lines.extend(f" - {error}" for error in report["errors"])
    return "\n".join(lines) + "\n"


def _markdown_escape(value: Any) -> str:
    return str(value).replace("|", "\\|").replace("\n", " ")


def render_markdown(report: dict[str, Any]) -> str:
    status_text = "可进入人工评审" if report["ready_for_review"] else "阻断"
    subject = report.get("subject", {})
    environment = report.get("environment", {})
    lines = [
        "# MVP.1 VoiceOver / 键盘实机走查报告",
        "",
        f"- 状态：**{status_text}**",
        f"- Subject commit：`{_markdown_escape(subject.get('subject_commit', '-'))}`",
        f"- Tested app：`{_markdown_escape(subject.get('tested_app_path', '-'))}`",
        f"- Bundle ID：`{_markdown_escape(subject.get('tested_bundle_id', '-'))}`",
        f"- CDHash：`{_markdown_escape(subject.get('tested_app_cdhash', '-'))}`",
        f"- macOS：`{_markdown_escape(environment.get('macos_version', '-'))}`",
        f"- Task evidence：`{_markdown_escape(report.get('task_evidence', {}).get('report_path', '-'))}`",
        f"- 固定检查记录：{report['recorded_check_count']}/{len(CHECK_IDS)}",
        f"- Open P0/P1：{len(report['open_p0_p1_findings'])}",
        "- 易用性通过阈值：未定义、未应用",
        "",
        "## 固定走查项",
        "",
        "| Check | Result | Requirement | Observation |",
        "|---|---|---|---|",
    ]
    recorded = {
        check.get("check_id"): check
        for check in report.get("walkthrough_checks", [])
        if isinstance(check, dict) and check.get("check_id") in CHECK_IDS
    }
    for check_id in CHECK_IDS:
        check = recorded.get(check_id, {})
        lines.append(
            f"| {_markdown_escape(check_id)} | "
            f"{_markdown_escape(check.get('result', '-'))} | "
            f"{_markdown_escape(CHECK_REQUIREMENTS[check_id])} | "
            f"{_markdown_escape(check.get('observation', '-'))} |"
        )

    lines.extend(["", "## Findings", ""])
    findings = report.get("findings", [])
    if findings:
        lines.extend(
            [
                "| ID | Severity | Status | Checks | Summary | Resolution / Retest |",
                "|---|---|---|---|---|---|",
            ]
        )
        for finding in findings:
            retest = finding.get("retest")
            retest_text = "-"
            if isinstance(retest, dict):
                retest_text = (
                    f"{retest.get('result', '-')} at {retest.get('retested_at', '-')}: "
                    f"{retest.get('observation', '-')}"
                )
            closure_text = f"{finding.get('resolution', '-')} / {retest_text}"
            check_ids = finding.get("check_ids", [])
            lines.append(
                f"| {_markdown_escape(finding.get('finding_id', '-'))} | "
                f"{_markdown_escape(finding.get('severity', '-'))} | "
                f"{_markdown_escape(finding.get('status', '-'))} | "
                f"{_markdown_escape(', '.join(check_ids) if isinstance(check_ids, list) else '-')} | "
                f"{_markdown_escape(finding.get('summary', '-'))} | "
                f"{_markdown_escape(closure_text)} |"
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
            (
                "本报告只整理人工观察者在绑定 app 的真实 macOS 窗口中，开启 VoiceOver "
                "并仅用键盘完成的走查。Agent、source-contract、自动化、截图和 XCUITest "
                "均不能计作本次实机走查。"
            ),
            (
                "工具只校验 subject 绑定、固定检查记录、人工声明与 finding 状态。"
                "结构有效或 `ready_for_review` 仅表示证据包可供人工评审，不表示产品验收通过或发布就绪。"
            ),
            "当前没有已确认的易用性阈值，因此工具不根据通过率、时长或其他自创指标作产品判断。",
            (
                "走查应使用合成会议数据；自由文本 observation 和 finding 不得记录参与者姓名、"
                "联系方式、真实会议内容、完整 transcript 或 raw session id。"
            ),
            "",
        ]
    )
    return "\n".join(lines)


def load_walkthrough(path: Path) -> Any:
    try:
        return json.loads(path.read_text(encoding="utf-8"))
    except FileNotFoundError as exc:
        raise WalkthroughToolError(f"walkthrough file not found: {path}") from exc
    except (OSError, UnicodeError) as exc:
        raise WalkthroughToolError(f"walkthrough file could not be read safely: {path}: {exc}") from exc
    except json.JSONDecodeError as exc:
        raise WalkthroughToolError(
            f"walkthrough file is not valid JSON at line {exc.lineno}, column {exc.colno}: {exc.msg}"
        ) from exc


def error_report(
    message: str,
    *,
    source: str | None = None,
    codesign_tool: str = "/usr/bin/codesign",
) -> dict[str, Any]:
    report = build_report({}, source=source, codesign_tool=codesign_tool)
    report["errors"] = [message]
    report["status"] = "blocked"
    report["ready_for_review"] = False
    for key in report["checks"]:
        if isinstance(report["checks"][key], bool):
            report["checks"][key] = False
    return report


def _resolve_path(value: str) -> Path:
    return Path(os.path.abspath(os.path.expanduser(value)))


def _prepare_atomic_file(target: Path, content: str) -> tuple[Path, int, int]:
    target.parent.mkdir(parents=True, exist_ok=True)
    descriptor, temporary_name = tempfile.mkstemp(
        prefix=f".{target.name}.", suffix=".tmp", dir=str(target.parent)
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
            raise WalkthroughToolError(f"failed to apply 0600 permissions to temporary output {temporary}")
        return temporary, metadata.st_dev, metadata.st_ino
    except Exception:
        if descriptor >= 0:
            os.close(descriptor)
        temporary.unlink(missing_ok=True)
        raise


def atomic_write_outputs(outputs: list[tuple[Path, str]]) -> None:
    if not outputs:
        return
    targets = [path for path, _ in outputs]
    if len({str(path) for path in targets}) != len(targets):
        raise WalkthroughToolError("output paths must be unique")
    for target in targets:
        if os.path.lexists(target):
            raise WalkthroughToolError(f"refused to overwrite existing output: {target}")

    prepared: list[tuple[Path, Path, int, int]] = []
    published: list[tuple[Path, int, int]] = []
    try:
        for target, content in outputs:
            temporary, device, inode = _prepare_atomic_file(target, content)
            prepared.append((target, temporary, device, inode))
        for target, temporary, device, inode in prepared:
            try:
                os.link(temporary, target)
            except FileExistsError as exc:
                raise WalkthroughToolError(f"refused to overwrite existing output: {target}") from exc
            except OSError as exc:
                raise WalkthroughToolError(f"failed to atomically publish output {target}: {exc}") from exc
            published.append((target, device, inode))
            mode = stat.S_IMODE(target.stat().st_mode)
            if mode != 0o600:
                raise WalkthroughToolError(f"output permissions must be 0600: {target} is {mode:04o}")
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


def _load_report(path_value: str, *, codesign_tool: str) -> dict[str, Any]:
    path = _resolve_path(path_value)
    try:
        walkthrough = load_walkthrough(path)
    except WalkthroughToolError as exc:
        return error_report(str(exc), source=str(path), codesign_tool=codesign_tool)
    return build_report(walkthrough, source=str(path), codesign_tool=codesign_tool)


def _print_format(report: dict[str, Any], output_format: str) -> None:
    if output_format == "json":
        print(json.dumps(report, ensure_ascii=False, indent=2, sort_keys=True))
    elif output_format == "markdown":
        print(render_markdown(report), end="")
    else:
        print(render_text(report), end="")


def _add_binding_arguments(parser: argparse.ArgumentParser) -> None:
    parser.add_argument("--subject-commit")
    parser.add_argument("--tested-app-path", required=True)
    parser.add_argument("--bundle-id", required=True)
    parser.add_argument("--cdhash", required=True)
    parser.add_argument("--macos-version")
    parser.add_argument("--walkthrough-id", default="mvp1-accessibility-walkthrough")
    parser.add_argument("--task-evidence-report", required=True)
    parser.add_argument("--codesign-tool", default="/usr/bin/codesign", help=argparse.SUPPRESS)


def parse_args(argv: list[str]) -> argparse.Namespace:
    parser = argparse.ArgumentParser(
        description=(
            "Create and validate strict MVP.1 manual VoiceOver and keyboard walkthrough evidence. "
            "Agents, source-contract tests, automation, screenshots, and XCUITest never count as the walkthrough."
        )
    )
    subparsers = parser.add_subparsers(dest="command", required=True)

    template_parser = subparsers.add_parser("template", help="Print a bound, unattested template.")
    _add_binding_arguments(template_parser)

    init_parser = subparsers.add_parser(
        "init", help="Atomically write a bound, unattested template without overwriting."
    )
    init_parser.add_argument("output")
    _add_binding_arguments(init_parser)

    validate_parser = subparsers.add_parser("validate", help="Validate walkthrough evidence.")
    validate_parser.add_argument("walkthrough")
    validate_parser.add_argument("--format", choices=("text", "json"), default="text")
    validate_parser.add_argument("--json-output")
    validate_parser.add_argument("--codesign-tool", default="/usr/bin/codesign", help=argparse.SUPPRESS)

    report_parser = subparsers.add_parser("report", help="Render a concise walkthrough report.")
    report_parser.add_argument("walkthrough")
    report_parser.add_argument(
        "--format", choices=("markdown", "text", "json"), default="markdown"
    )
    report_parser.add_argument("--json-output")
    report_parser.add_argument("--markdown-output")
    report_parser.add_argument("--codesign-tool", default="/usr/bin/codesign", help=argparse.SUPPRESS)
    return parser.parse_args(argv)


def main(argv: list[str]) -> int:
    args = parse_args(argv)
    if args.command in ("template", "init"):
        try:
            template = build_template(
                subject_commit=args.subject_commit,
                tested_app_path=args.tested_app_path,
                tested_bundle_id=args.bundle_id,
                tested_app_cdhash=args.cdhash,
                macos_version=args.macos_version,
                walkthrough_id=args.walkthrough_id,
                codesign_tool=args.codesign_tool,
                task_evidence_report=args.task_evidence_report,
            )
        except WalkthroughToolError as exc:
            print(f"MVP.1 accessibility walkthrough template failed: {exc}", file=sys.stderr)
            return 2
        if args.command == "template":
            print(json.dumps(template, ensure_ascii=False, indent=2, sort_keys=True))
            return 0
        output_path = _resolve_path(args.output)
        try:
            atomic_write_outputs([(output_path, _json_text(template))])
        except WalkthroughToolError as exc:
            print(f"MVP.1 accessibility walkthrough init failed: {exc}", file=sys.stderr)
            return 2
        print(f"unattested MVP.1 accessibility walkthrough template: {output_path}")
        print(
            "No real-app walkthrough evidence has been recorded; a human observer must complete every check and attest it."
        )
        return 0

    report = _load_report(args.walkthrough, codesign_tool=args.codesign_tool)
    outputs: list[tuple[Path, str]] = []
    if args.json_output:
        outputs.append((_resolve_path(args.json_output), _json_text(report)))
    if args.command == "report" and args.markdown_output:
        outputs.append((_resolve_path(args.markdown_output), render_markdown(report)))
    try:
        atomic_write_outputs(outputs)
    except WalkthroughToolError as exc:
        print(f"MVP.1 accessibility walkthrough output failed: {exc}", file=sys.stderr)
        return 2
    _print_format(report, args.format)
    return 0 if report["ready_for_review"] else 1


if __name__ == "__main__":
    raise SystemExit(main(sys.argv[1:]))
