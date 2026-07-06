#!/usr/bin/env python3
from __future__ import annotations

import argparse
import json
import os
import re
import sys
from pathlib import Path
from typing import Any


EXPECTED_MARKERS = {
    "real_capture_pass_marker": "native-app real capture app-bundle XCUITest passed.",
    "real_capture_test_name": "testOptInAppleScreenCaptureKitRecordsFromDesignedShellWhenExplicitlyEnabled",
    "hardening_pass_marker": "native-app VS-MA-21 hardening app-bundle XCUITest passed.",
    "hardening_test_name": "testVSMA21AppBundleProcessingPathConflictRetryPreservesOriginalCaptureArtifactWhenExplicitlyEnabled",
    "hardening_path_conflict": "path_conflict",
    "hardening_failed_state": "Processing failed.",
    "hardening_completed_state": "Processing complete.",
}

ADAPTER_SOURCE_RELATIVE_PATH = Path(
    "platform/native-app/Sources/MeetingAssistantNative/AppleScreenCaptureKitNativeCaptureAdapter.swift"
)

RELEASE_SCOPE_RESIDUAL_RISKS = [
    "does not prove full real capture -> transcript/export/delete same-chain success",
    "does not prove independent system_audio or microphone_audio artifacts",
    "does not prove mixed_audio was extracted from a real ScreenCaptureKit recording in this release-scope gate",
    "does not prove all macOS TCC/display target machines",
    "does not prove release bundle, signing, notarization, SLSA provenance, or VS-MA-23 release readiness",
]

TCC_REMEDIATION = [
    "Open System Settings > Privacy & Security > Screen Recording / Screen & System Audio Recording.",
    "Enable MeetingAssistantNative for the app bundle recorded in real_capture_app_bundle_under_test.",
    "Quit and relaunch the app if macOS asks, then rerun the same release native UI hardening gate.",
    'Optional shortcut: open "x-apple.systempreferences:com.apple.preference.security?Privacy_ScreenCapture"',
]


def _read_text(path: Path) -> str:
    if not path.is_file():
        return ""
    return path.read_text(encoding="utf-8", errors="replace")


def _extract_line_value(text: str, label: str) -> str | None:
    match = re.search(rf"^{re.escape(label)}:\s*(.+)$", text, re.MULTILINE)
    if not match:
        return None
    value = match.group(1).strip()
    if not value or value.startswith("not found"):
        return None
    return value


def _extract_xcresult_path(text: str) -> str | None:
    match = re.search(r"Test session results, code coverage, and logs:\n\s*(.+?\.xcresult)", text)
    if not match:
        return None
    return match.group(1).strip()


def _extract_bool_argument(text: str, label: str) -> bool | None:
    match = re.search(rf"{re.escape(label)}:\s*(true|false)", text)
    if not match:
        return None
    return match.group(1) == "true"


def _adapter_capability_report(source_root: Path | None = None) -> dict[str, Any]:
    root = source_root if source_root is not None else Path(__file__).resolve().parents[2]
    source_path = root / ADAPTER_SOURCE_RELATIVE_PATH
    source_text = _read_text(source_path)
    combined_recording = _extract_bool_argument(source_text, "producesCombinedRecordingFile")
    separate_audio = _extract_bool_argument(source_text, "producesSeparateAudioArtifacts")
    mixed_audio_extraction = _extract_bool_argument(source_text, "attemptsMixedAudioExtractionFromCombinedRecording")
    source_present = source_path.is_file()
    source_contract_ok = (
        source_present
        and 'public static let identity = "apple_screencapturekit"' in source_text
        and "framework: \"ScreenCaptureKit\"" in source_text
        and combined_recording is True
        and separate_audio is False
        and mixed_audio_extraction is True
    )
    return {
        "adapter_id": "apple_screencapturekit",
        "framework": "ScreenCaptureKit",
        "source_path": str(ADAPTER_SOURCE_RELATIVE_PATH),
        "source_present": source_present,
        "combined_recording_file_supported": combined_recording,
        "separate_audio_artifacts_supported": separate_audio,
        "mixed_audio_extraction_from_combined_recording_supported": mixed_audio_extraction,
        "source_contract_ok": source_contract_ok,
        "report_update_required_if_contract_changes": True,
    }


def build_report(
    real_capture_output_path: Path,
    hardening_output_path: Path,
    *,
    report_path: Path | None = None,
    real_capture_exit_code: int = 0,
    hardening_exit_code: int = 0,
    release_scope: bool = False,
    source_root: Path | None = None,
) -> dict[str, Any]:
    real_capture_output = _read_text(real_capture_output_path)
    hardening_output = _read_text(hardening_output_path)
    combined_output = real_capture_output + "\n" + hardening_output
    adapter_capability = _adapter_capability_report(source_root)
    real_capture_derived_data_path = _extract_line_value(real_capture_output, "DerivedData path")
    real_capture_app_bundle_under_test = _extract_line_value(real_capture_output, "App bundle under test")
    real_capture_xcodebuild_log_path = _extract_line_value(real_capture_output, "Captured xcodebuild log")
    real_capture_xcresult_path = _extract_xcresult_path(real_capture_output)
    marker_sources = {
        "real_capture_pass_marker": real_capture_output,
        "real_capture_test_name": real_capture_output,
        "hardening_pass_marker": hardening_output,
        "hardening_test_name": hardening_output,
        "hardening_path_conflict": hardening_output,
        "hardening_failed_state": hardening_output,
        "hardening_completed_state": hardening_output,
    }
    marker_results = {
        key: marker in marker_sources[key]
        for key, marker in EXPECTED_MARKERS.items()
    }
    real_capture_permission_denied = "permission_denied" in real_capture_output
    ui_automation_blocked = any(
        marker in combined_output
        for marker in [
            "LocalAuthentication",
            "System authentication is running",
            "Timed out while enabling automation mode",
            "Failed to enable Automation Mode",
        ]
    )
    missing_markers = [key for key, present in marker_results.items() if not present]
    traceback_seen = "Traceback" in combined_output
    adapter_capability_contract_ok = bool(adapter_capability["source_contract_ok"])
    passed = (
        real_capture_exit_code == 0
        and hardening_exit_code == 0
        and not missing_markers
        and not traceback_seen
        and adapter_capability_contract_ok
    )
    release_gate = "release-scope-native-ui-hardening" if release_scope else "partial-evidence-only"
    findings: list[str] = []
    if real_capture_exit_code != 0:
        findings.append(f"real capture app-bundle smoke exited {real_capture_exit_code}")
    if hardening_exit_code != 0:
        findings.append(f"VS-MA-21 hardening app-bundle smoke exited {hardening_exit_code}")
    if missing_markers:
        findings.append(f"missing expected markers: {', '.join(missing_markers)}")
    if traceback_seen:
        findings.append("smoke output contained a traceback")
    if not adapter_capability_contract_ok:
        findings.append(
            "ScreenCaptureKit adapter capability source contract changed or could not be verified; update the release native UI hardening report before using this evidence"
        )
    blocker_type = "none"
    if not passed:
        if real_capture_permission_denied:
            blocker_type = "real_capture_permission_denied"
        elif ui_automation_blocked:
            blocker_type = "ui_automation_unavailable"
        elif real_capture_exit_code != 0:
            blocker_type = "real_capture_app_bundle_failed"
        elif hardening_exit_code != 0:
            blocker_type = "hardening_app_bundle_failed"
        elif not adapter_capability_contract_ok:
            blocker_type = "adapter_capability_contract_changed"
        else:
            blocker_type = "marker_validation_failed"

    report: dict[str, Any] = {
        "report_schema": 1,
        "component": "platform/e2e/release-native-ui-hardening-smoke",
        "scope": "validation-only",
        "release_gate": release_gate,
        "release_scope_native_ui_hardening": release_scope,
        "vs_ma": ["VS-MA-21"],
        "pv": ["PV-MA-009"],
        "related_pv": ["PV-MA-002", "PV-MA-003", "PV-MA-006", "PV-MA-007"],
        "real_capture_output_path": str(real_capture_output_path),
        "hardening_output_path": str(hardening_output_path),
        "real_capture_exit_code": real_capture_exit_code,
        "hardening_exit_code": hardening_exit_code,
        "real_capture_derived_data_path": real_capture_derived_data_path,
        "real_capture_app_bundle_under_test": real_capture_app_bundle_under_test,
        "real_capture_xcodebuild_log_path": real_capture_xcodebuild_log_path,
        "real_capture_xcresult_path": real_capture_xcresult_path,
        "real_capture_adapter_capability": adapter_capability,
        "real_capture_combined_recording_file_supported": adapter_capability["combined_recording_file_supported"],
        "real_capture_separate_audio_artifacts_supported": adapter_capability["separate_audio_artifacts_supported"],
        "real_capture_mixed_audio_extraction_supported": adapter_capability["mixed_audio_extraction_from_combined_recording_supported"],
        "real_capture_independent_audio_artifacts_proven": False,
        "real_capture_mixed_audio_artifact_proven": False,
        "real_capture_to_processing_same_chain_proven": False,
        "passed": passed,
        "blocked": not passed,
        "blocker_type": blocker_type,
        "real_capture_permission_denied": real_capture_permission_denied,
        "real_capture_tcc_remediation": TCC_REMEDIATION if real_capture_permission_denied else [],
        "ui_automation_blocked": ui_automation_blocked,
        "marker_results": marker_results,
        "missing_markers": missing_markers,
        "traceback_seen": traceback_seen,
        "not_release_readiness": True,
        "release_blockers": RELEASE_SCOPE_RESIDUAL_RISKS,
        "findings": findings,
    }
    if report_path is not None:
        report_path.parent.mkdir(parents=True, exist_ok=True)
        report_path.write_text(json.dumps(report, ensure_ascii=False, indent=2, sort_keys=True) + "\n", encoding="utf-8")
    return report


def main(argv: list[str] | None = None) -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("--real-capture-output", default=os.environ.get("MA_RELEASE_NATIVE_UI_REAL_CAPTURE_OUTPUT"))
    parser.add_argument("--hardening-output", default=os.environ.get("MA_RELEASE_NATIVE_UI_HARDENING_OUTPUT"))
    parser.add_argument("--report", default=os.environ.get("MA_RELEASE_NATIVE_UI_HARDENING_REPORT"))
    parser.add_argument("--real-capture-exit-code", type=int, required=True)
    parser.add_argument("--hardening-exit-code", type=int, required=True)
    parser.add_argument("--release-scope", action="store_true")
    args = parser.parse_args(argv)
    if not args.real_capture_output:
        print("release native UI hardening report failed: --real-capture-output is required", file=sys.stderr)
        return 2
    if not args.hardening_output:
        print("release native UI hardening report failed: --hardening-output is required", file=sys.stderr)
        return 2

    report = build_report(
        Path(args.real_capture_output),
        Path(args.hardening_output),
        report_path=Path(args.report) if args.report else None,
        real_capture_exit_code=args.real_capture_exit_code,
        hardening_exit_code=args.hardening_exit_code,
        release_scope=args.release_scope,
    )
    if args.report:
        print(f"release native UI hardening report: {args.report}", file=sys.stderr)
    print(
        "VS-MA-21 native UI hardening report marker [non-contract]: "
        f"report_schema={report['report_schema']} release_gate={report['release_gate']}."
    )
    if args.release_scope and report["passed"]:
        print("VS-MA-21 release-scope native UI hardening gate passed.")
    if report["passed"]:
        return 0
    for finding in report["findings"]:
        print(f"release native UI hardening report failed: {finding}", file=sys.stderr)
    return 1


if __name__ == "__main__":
    raise SystemExit(main())
