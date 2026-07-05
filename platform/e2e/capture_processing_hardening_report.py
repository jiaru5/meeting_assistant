#!/usr/bin/env python3
from __future__ import annotations

import argparse
import json
import os
import sys
from pathlib import Path
from typing import Any


EXPECTED_MARKERS = {
    "no_auto_download_dependency_preflight": (
        "VS-MA-20 provider/e2e marker [non-contract]: "
        "native_recording-style provider artifact chain - no-auto-download dependency preflight verified"
    ),
    "default_capture_pipeline": (
        "VS-MA-20 provider/e2e marker [non-contract]: "
        "native_recording-style provider artifact chain - default mixed_audio, no-auto-upload boundary, and export/delete retention verified"
    ),
    "fallback_system_audio": (
        "VS-MA-20 provider/e2e marker [non-contract]: "
        "native_recording-style provider artifact chain - fallback system_audio artifact verified"
    ),
    "fallback_microphone_audio": (
        "VS-MA-20 provider/e2e marker [non-contract]: "
        "native_recording-style provider artifact chain - fallback microphone_audio artifact verified"
    ),
    "path_rollback": (
        "VS-MA-20 provider/e2e marker [non-contract]: "
        "native_recording-style provider artifact chain - path rollback boundary verified"
    ),
    "lock_rollback": (
        "VS-MA-20 provider/e2e marker [non-contract]: "
        "native_recording-style provider artifact chain - lock rollback boundary verified"
    ),
    "temp_hardlink_rollback": (
        "VS-MA-20 provider/e2e marker [non-contract]: "
        "native_recording-style provider artifact chain - temp hardlink rollback boundary verified"
    ),
    "checksum_rollback": (
        "VS-MA-20 provider/e2e marker [non-contract]: "
        "native_recording-style provider artifact chain - checksum rollback boundary verified"
    ),
    "concurrency_retry": (
        "VS-MA-21 provider/e2e marker [non-contract]: "
        "capture-style concurrency/retry fixture - lock conflict exit 3 then retry success with capture checksums preserved verified"
    ),
    "dependency_missing_redaction": (
        "VS-MA-21 provider/e2e marker [non-contract]: "
        "capture-style provider failure fixture - dependency_missing exit 4 without derived artifact pollution verified"
    ),
    "processing_failed_retry": (
        "VS-MA-21 provider/e2e marker [non-contract]: "
        "capture-style provider failure fixture - processing_failed exit 5 redaction and retry success verified"
    ),
    "pass_marker": "capture-style processing e2e smoke passed.",
}

PARTIAL_EVIDENCE_BLOCKERS = [
    "not a release-scope provider hardening gate",
    "does not prove real ScreenCaptureKit native capture artifacts",
    "does not prove native UI release-scope concurrency",
    "does not prove release bundle or VS-MA-23 release readiness",
]

RELEASE_SCOPE_RESIDUAL_RISKS = [
    "does not prove real ScreenCaptureKit native capture artifacts",
    "does not prove native UI release-scope concurrency beyond provider-owned command fixtures",
    "does not prove release bundle or VS-MA-23 release readiness",
]


def build_report(
    output_path: Path,
    *,
    report_path: Path | None = None,
    exit_code: int = 0,
    release_scope: bool = False,
) -> dict[str, Any]:
    output = output_path.read_text(encoding="utf-8")
    marker_results = {key: marker in output for key, marker in EXPECTED_MARKERS.items()}
    missing_markers = [key for key, present in marker_results.items() if not present]
    traceback_seen = "Traceback" in output
    passed = exit_code == 0 and not missing_markers and not traceback_seen
    release_gate = "release-scope-provider-hardening" if release_scope else "partial-evidence-only"
    release_blockers = RELEASE_SCOPE_RESIDUAL_RISKS if release_scope else PARTIAL_EVIDENCE_BLOCKERS
    findings: list[str] = []
    if exit_code != 0:
        findings.append(f"capture-processing-smoke exited {exit_code}")
    if missing_markers:
        findings.append(f"missing expected markers: {', '.join(missing_markers)}")
    if traceback_seen:
        findings.append("smoke output contained a traceback")

    report: dict[str, Any] = {
        "report_schema": 1,
        "component": "platform/e2e/capture-processing-smoke",
        "scope": "validation-only",
        "release_gate": release_gate,
        "release_scope_provider_hardening": release_scope,
        "vs_ma": ["VS-MA-21"],
        "pv": ["PV-MA-009"],
        "related_pv": ["PV-MA-006", "PV-MA-007", "PV-MA-011", "PV-MA-012"],
        "output_path": str(output_path),
        "smoke_exit_code": exit_code,
        "passed": passed,
        "marker_results": marker_results,
        "missing_markers": missing_markers,
        "traceback_seen": traceback_seen,
        "not_release_readiness": True,
        "release_blockers": release_blockers,
        "findings": findings,
    }
    if report_path is not None:
        report_path.parent.mkdir(parents=True, exist_ok=True)
        report_path.write_text(json.dumps(report, ensure_ascii=False, indent=2, sort_keys=True) + "\n", encoding="utf-8")
    return report


def main(argv: list[str] | None = None) -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("--output", default=os.environ.get("MA_CAPTURE_PROCESSING_HARDENING_OUTPUT"))
    parser.add_argument("--report", default=os.environ.get("MA_CAPTURE_PROCESSING_HARDENING_REPORT"))
    parser.add_argument("--exit-code", type=int, required=True)
    parser.add_argument("--release-scope", action="store_true")
    args = parser.parse_args(argv)
    if not args.output:
        print("capture processing hardening report failed: --output is required", file=sys.stderr)
        return 2

    report = build_report(
        Path(args.output),
        report_path=Path(args.report) if args.report else None,
        exit_code=args.exit_code,
        release_scope=args.release_scope,
    )
    if args.report:
        print(f"capture processing hardening report: {args.report}", file=sys.stderr)
    print(
        "VS-MA-21 provider hardening report marker [non-contract]: "
        f"report_schema={report['report_schema']} release_gate={report['release_gate']}."
    )
    if args.release_scope and report["passed"]:
        print("VS-MA-21 release-scope provider hardening gate passed.")
    if report["passed"]:
        return 0
    for finding in report["findings"]:
        print(f"capture processing hardening report failed: {finding}", file=sys.stderr)
    return 1


if __name__ == "__main__":
    raise SystemExit(main())
