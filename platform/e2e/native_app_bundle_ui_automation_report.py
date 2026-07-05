#!/usr/bin/env python3
from __future__ import annotations

import argparse
import json
import re
import sys
from datetime import datetime, timezone
from pathlib import Path
from typing import Any


SIGNALS = {
    "local_authentication_in_progress": (
        re.compile(r"LocalAuthentication", re.IGNORECASE),
        re.compile(r"System authentication is running", re.IGNORECASE),
    ),
    "automation_mode_unavailable": (
        re.compile(r"Timed out while enabling automation mode", re.IGNORECASE),
        re.compile(r"Failed to enable Automation Mode", re.IGNORECASE),
        re.compile(r"_XCT_enableAutomationModeWithReply", re.IGNORECASE),
    ),
    "ui_testing_initialization_failed": (
        re.compile(r"Failed to initialize for UI testing", re.IGNORECASE),
        re.compile(r"failed to initialize for UI testing", re.IGNORECASE),
    ),
    "real_runtime_processing_timeout": (
        re.compile(
            r"Expected real runtime processing to complete from the launched app bundle",
            re.IGNORECASE,
        ),
    ),
}

REMEDIATION = [
    "Resolve or dismiss any pending macOS loginwindow, Touch ID, or password authentication prompt.",
    "Keep the display awake and unlocked before rerunning the app-bundle smoke.",
    "Check Accessibility and Developer Tools permissions for Xcode and the UI test runner if macOS prompts for automation control.",
    "Rerun the same command after XCTest Automation Mode can initialize without another LocalAuthentication request or timeout.",
]

RESIDUAL_RISKS = [
    "does not prove app-bundle UI clicked the processing start button",
    "does not prove provider-owned CLI or whisper.cpp runtime behavior",
    "does not prove transcript review consumed a real runtime transcript",
    "does not prove release bundle or release readiness",
]

REAL_RUNTIME_TIMEOUT_REMEDIATION = [
    "Inspect the captured xcodebuild log and app workspace artifacts for processing status and provider output.",
    "Confirm the provider-owned CLI can complete the same runtime/model/audio path outside the app-bundle UI smoke.",
    "Rerun the same app-bundle smoke after confirming no stale app process or long-running provider process remains.",
]

REAL_RUNTIME_TIMEOUT_RESIDUAL_RISKS = [
    "does not prove real runtime processing completed from the launched app bundle",
    "does not prove transcript review consumed a real runtime transcript",
    "does not prove release bundle or release readiness",
]


class NativeAppBundleUIAutomationReportError(AssertionError):
    pass


def detect_signals(log_text: str) -> dict[str, bool]:
    return {
        name: any(pattern.search(log_text) for pattern in patterns)
        for name, patterns in SIGNALS.items()
    }


def classify_blocker(signals: dict[str, bool]) -> str:
    if signals.get("local_authentication_in_progress"):
        return "local_authentication_in_progress"
    if signals.get("automation_mode_unavailable"):
        return "automation_mode_unavailable"
    if signals.get("ui_testing_initialization_failed"):
        return "ui_testing_initialization_failed"
    if signals.get("real_runtime_processing_timeout"):
        return "real_runtime_processing_timeout"
    return "unknown_ui_automation_blocker"


def build_report(
    *,
    smoke_name: str,
    log_path: Path,
    report_path: Path,
    exit_code: int,
    destination: str,
) -> dict[str, Any]:
    if not log_path.is_file():
        raise NativeAppBundleUIAutomationReportError(f"xcodebuild log is missing: {log_path}")

    log_text = log_path.read_text(encoding="utf-8", errors="replace")
    signals = detect_signals(log_text)
    blocked = any(signals.values())
    blocker_type = classify_blocker(signals) if blocked else "not_detected"
    blocked_before_test_body = blocker_type in {
        "local_authentication_in_progress",
        "automation_mode_unavailable",
        "ui_testing_initialization_failed",
    }
    processing_start_clicked = bool(
        re.search(r'Click "ma\.processing\.startButton"', log_text, re.IGNORECASE)
    )
    processing_completed = False
    if blocker_type != "real_runtime_processing_timeout":
        processing_completed = bool(
            re.search(r"Processing completed with transcript-only speaker labels\.", log_text)
        )
    remediation = list(REMEDIATION)
    residual_risks = list(RESIDUAL_RISKS)
    if blocker_type == "real_runtime_processing_timeout":
        remediation = REAL_RUNTIME_TIMEOUT_REMEDIATION
        residual_risks = REAL_RUNTIME_TIMEOUT_RESIDUAL_RISKS
    report = {
        "report_schema": 1,
        "component": "native-app",
        "release_gate": "opt-in-native-app-bundle-ui-automation",
        "smoke": smoke_name,
        "destination": destination,
        "generated_at": datetime.now(timezone.utc).isoformat(timespec="seconds"),
        "passed": False,
        "blocked": blocked,
        "blocker_type": blocker_type,
        "blocked_before_test_body": blocked_before_test_body,
        "xcodebuild_exit_code": exit_code,
        "xcodebuild_log": str(log_path),
        "signals": signals,
        "test_body_started": "Test Case" in log_text,
        "processing_start_clicked": processing_start_clicked,
        "processing_completed": processing_completed,
        "proves_ui_or_provider_behavior": False,
        "not_release_readiness": True,
        "remediation": remediation,
        "residual_risks": residual_risks,
        "findings": [],
    }
    if not blocked:
        report["findings"].append("xcodebuild failed but no known UI automation blocker signal was detected")
    elif blocker_type == "local_authentication_in_progress":
        report["findings"].append("macOS LocalAuthentication was active before XCTest UI testing initialized")
    elif blocker_type == "automation_mode_unavailable":
        report["findings"].append("XCTest Automation Mode could not be enabled before the test body")
    elif blocker_type == "real_runtime_processing_timeout":
        report["findings"].append(
            "the app-bundle smoke entered the test body and clicked processing start, "
            "but real runtime processing did not reach the expected completion state"
        )
    else:
        report["findings"].append("XCTest UI testing failed to initialize before the test body")

    report_path.parent.mkdir(parents=True, exist_ok=True)
    report_path.write_text(json.dumps(report, indent=2, sort_keys=True) + "\n", encoding="utf-8")
    return report


def parse_args(argv: list[str]) -> argparse.Namespace:
    parser = argparse.ArgumentParser()
    parser.add_argument("--smoke-name", required=True)
    parser.add_argument("--log", required=True, type=Path)
    parser.add_argument("--report", required=True, type=Path)
    parser.add_argument("--exit-code", required=True, type=int)
    parser.add_argument("--destination", required=True)
    return parser.parse_args(argv)


def main(argv: list[str]) -> int:
    args = parse_args(argv)
    report = build_report(
        smoke_name=args.smoke_name,
        log_path=args.log,
        report_path=args.report,
        exit_code=args.exit_code,
        destination=args.destination,
    )
    print(f"native app-bundle UI automation blocker report written: {args.report}", file=sys.stderr)
    print(f"blocker_type={report['blocker_type']} blocked={str(report['blocked']).lower()}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main(sys.argv[1:]))
