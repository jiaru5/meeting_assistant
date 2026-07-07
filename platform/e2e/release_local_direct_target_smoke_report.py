#!/usr/bin/env python3
from __future__ import annotations

import argparse
import hashlib
import json
import os
import platform
import re
import socket
import subprocess
import sys
from pathlib import Path
from typing import Any


EXPECTED_TERMS = ["HTTP", "LLM", "clean architecture"]
RELEASE_BLOCKERS = [
    "single target-machine report only; does not prove all-target local-direct repeatability",
    "does not run product-validation release or release-preflight",
    "does not prove Developer ID, notarization, App Store, or commercial distribution readiness",
]


def current_commit(root: Path) -> str | None:
    completed = subprocess.run(
        ["git", "-C", str(root), "rev-parse", "HEAD"],
        text=True,
        capture_output=True,
        check=False,
    )
    if completed.returncode != 0:
        return None
    return completed.stdout.strip()


def sha256_file(path: Path) -> str:
    digest = hashlib.sha256()
    with path.open("rb") as handle:
        for chunk in iter(lambda: handle.read(1024 * 1024), b""):
            digest.update(chunk)
    return "sha256:" + digest.hexdigest()


def normalize_target_id(value: str) -> str:
    normalized = re.sub(r"[^A-Za-z0-9_.-]+", "-", value.strip())
    normalized = normalized.strip("-._")
    return normalized or "unknown-target"


def default_target_os() -> str:
    system = platform.system().lower()
    if system == "darwin":
        return "macos"
    return system or sys.platform


def default_target_id() -> str:
    host = socket.gethostname().split(".", 1)[0] or "local"
    arch = platform.machine().lower() or "unknown"
    return normalize_target_id(f"{host}-{default_target_os()}-{arch}")


def load_json_object(path: Path, label: str, findings: list[str]) -> dict[str, Any] | None:
    try:
        payload = json.loads(path.read_text(encoding="utf-8"))
    except OSError as exc:
        findings.append(f"{label} could not be read: {path}: {exc.__class__.__name__}")
        return None
    except json.JSONDecodeError as exc:
        findings.append(f"{label} must be valid JSON: {path}: {exc.__class__.__name__}")
        return None
    if not isinstance(payload, dict):
        findings.append(f"{label} must be a JSON object: {path}")
        return None
    return payload


def validate_same_chain_report(report: dict[str, Any], findings: list[str]) -> dict[str, Any]:
    label = "local-direct same-chain smoke report"
    if report.get("report_schema") != 1:
        findings.append(f"{label} must set report_schema=1")
    if report.get("release_gate") != "local-direct-same-chain-smoke":
        findings.append(f"{label} must set release_gate='local-direct-same-chain-smoke'")
    if report.get("passed") is not True:
        findings.append(f"{label} must set passed=True")
    if report.get("same_app_identity") is not True:
        findings.append(f"{label} must prove same_app_identity=True")
    if report.get("launch_modes") != ["open"]:
        findings.append(f"{label} must use LaunchServices open only")
    for key in (
        "starts_recording",
        "starts_processing",
        "uses_system_pasteboard",
        "uses_save_panel",
        "requires_clean_app_processes",
    ):
        if report.get(key) is not True:
            findings.append(f"{label} must set {key}=True")
    for key in (
        "opens_system_settings",
        "modifies_tcc_or_system_settings",
        "requires_developer_id_or_notarization",
    ):
        if report.get(key) is not False:
            findings.append(f"{label} must set {key}=False")
    if report.get("not_release_readiness") is not True:
        findings.append(f"{label} must keep not_release_readiness=True")

    stage_exit_codes = report.get("stage_exit_codes")
    stage_passed = report.get("stage_passed")
    if not isinstance(stage_exit_codes, dict):
        findings.append(f"{label} must include stage_exit_codes")
        stage_exit_codes = {}
    if not isinstance(stage_passed, dict):
        findings.append(f"{label} must include stage_passed")
        stage_passed = {}
    for stage in ("recording", "processing", "actions"):
        if stage_exit_codes.get(stage) != 0:
            findings.append(f"{label} stage {stage} must exit 0")
        if stage_passed.get(stage) is not True:
            findings.append(f"{label} stage {stage} must set passed=True")

    app_identity = report.get("app_identity")
    if not isinstance(app_identity, dict):
        findings.append(f"{label} must include app_identity")
        app_identity = {}
    for key in ("path", "CFBundleIdentifier", "CFBundleName"):
        if not isinstance(app_identity.get(key), str) or not app_identity.get(key):
            findings.append(f"{label} app_identity must include {key}")
    codesign = app_identity.get("codesign")
    if not isinstance(codesign, dict):
        findings.append(f"{label} app_identity must include codesign")
        codesign = {}
    if not isinstance(codesign.get("CDHash"), str) or not codesign.get("CDHash"):
        findings.append(f"{label} app_identity.codesign must include CDHash")

    processing_artifacts = report.get("processing_artifacts")
    if not isinstance(processing_artifacts, dict):
        findings.append(f"{label} must include processing_artifacts")
        processing_artifacts = {}
    transcript = processing_artifacts.get("transcript_text")
    if not isinstance(transcript, dict):
        findings.append(f"{label} must include transcript_text artifact")
        transcript = {}
    expected_found = transcript.get("expected_terms_found")
    if not isinstance(expected_found, list):
        findings.append(f"{label} transcript_text must include expected_terms_found")
        expected_found = []
    missing_terms = [term for term in EXPECTED_TERMS if term not in expected_found]
    if missing_terms:
        findings.append(f"{label} transcript_text missing expected terms: {', '.join(missing_terms)}")
    if processing_artifacts.get("normalized_audio", {}).get("status") != "available":
        findings.append(f"{label} must include available normalized_audio")
    if processing_artifacts.get("speaker_labels", {}).get("status") not in {"available", "degraded"}:
        findings.append(f"{label} must include available or degraded speaker_labels")

    action_markers = report.get("actions_markers")
    if not isinstance(action_markers, list):
        findings.append(f"{label} must include actions_markers")
        action_markers = []
    for marker in ("Copy complete.", "Export complete.", "Delete complete."):
        if marker not in action_markers:
            findings.append(f"{label} missing action marker: {marker}")
    if report.get("export_exists") is not True:
        findings.append(f"{label} must keep exported Markdown outside deleted session")
    if report.get("session_root_exists_after_delete") is not False:
        findings.append(f"{label} must remove session root after delete")
    if not isinstance(report.get("delete_event_path"), str) or not report.get("delete_event_path"):
        findings.append(f"{label} must include delete_event_path")

    return {
        "app_identity": app_identity,
        "stage_exit_codes": dict(stage_exit_codes),
        "stage_passed": dict(stage_passed),
        "launch_modes": report.get("launch_modes", []),
        "same_app_identity": report.get("same_app_identity") is True,
        "recording_markers": report.get("recording_markers", []),
        "processing_artifacts": processing_artifacts,
        "actions_markers": action_markers,
        "export_path": report.get("export_path", ""),
        "delete_event_path": report.get("delete_event_path", ""),
        "expected_terms_found": expected_found,
    }


def build_report(
    root: Path,
    *,
    same_chain_report_path: Path,
    report_path: Path | None = None,
    smoke_exit_code: int = 0,
    target_id: str | None = None,
    target_os: str | None = None,
    architecture: str | None = None,
) -> dict[str, Any]:
    root = root.resolve(strict=False)
    findings: list[str] = []
    head = current_commit(root)
    if head is None:
        findings.append("current git commit could not be resolved")
    if smoke_exit_code != 0:
        findings.append(f"local-direct-same-chain-smoke exited {smoke_exit_code}")

    same_chain_report = load_json_object(
        same_chain_report_path,
        "local-direct same-chain smoke report",
        findings,
    )
    same_chain_summary: dict[str, Any] = {}
    if same_chain_report is not None:
        same_chain_summary = validate_same_chain_report(same_chain_report, findings)

    try:
        same_chain_digest = sha256_file(same_chain_report_path)
    except OSError as exc:
        findings.append(f"same-chain report digest could not be computed: {exc.__class__.__name__}")
        same_chain_digest = "sha256:" + ("0" * 64)

    normalized_target_id = normalize_target_id(target_id or default_target_id())
    target_os_value = target_os or default_target_os()
    architecture_value = architecture or (platform.machine().lower() or "unknown")
    passed = not findings
    report: dict[str, Any] = {
        "report_schema": 1,
        "release_gate": "release-local-direct-target-smoke",
        "target_scope": "single-target-machine",
        "subject_commit": head,
        "target_id": normalized_target_id,
        "os": target_os_value,
        "architecture": architecture_value,
        "packages_runtime_or_model": False,
        "auto_downloads": False,
        "external_network_access": False,
        "same_chain_report": {
            "path": str(same_chain_report_path),
            "digest": same_chain_digest,
        },
        "local_direct_app": same_chain_summary.get("app_identity", {}),
        "smoke": {
            "same_chain_passed": passed,
            "stage_exit_codes": same_chain_summary.get("stage_exit_codes", {}),
            "stage_passed": same_chain_summary.get("stage_passed", {}),
            "launch_modes": same_chain_summary.get("launch_modes", []),
            "same_app_identity": same_chain_summary.get("same_app_identity") is True,
            "expected_terms_found": same_chain_summary.get("expected_terms_found", []),
            "recording_markers": same_chain_summary.get("recording_markers", []),
            "actions_markers": same_chain_summary.get("actions_markers", []),
            "export_path": same_chain_summary.get("export_path", ""),
            "delete_event_path": same_chain_summary.get("delete_event_path", ""),
        },
        "passed": passed,
        "not_release_readiness": True,
        "release_blockers": RELEASE_BLOCKERS,
        "findings": findings,
    }
    if report_path is not None:
        report_path.parent.mkdir(parents=True, exist_ok=True)
        report_path.write_text(
            json.dumps(report, ensure_ascii=False, indent=2, sort_keys=True) + "\n",
            encoding="utf-8",
        )
    return report


def main(argv: list[str] | None = None) -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("--root", default=os.environ.get("REPO_ROOT", "."))
    parser.add_argument("--same-chain-report", required=True)
    parser.add_argument("--report")
    parser.add_argument("--smoke-exit-code", type=int, default=0)
    parser.add_argument("--target-id", default=os.environ.get("MA_RELEASE_LOCAL_DIRECT_TARGET_ID"))
    parser.add_argument("--target-os", default=os.environ.get("MA_RELEASE_LOCAL_DIRECT_TARGET_OS"))
    parser.add_argument("--architecture", default=os.environ.get("MA_RELEASE_LOCAL_DIRECT_TARGET_ARCH"))
    args = parser.parse_args(argv)

    report = build_report(
        Path(args.root),
        same_chain_report_path=Path(args.same_chain_report),
        report_path=Path(args.report) if args.report else None,
        smoke_exit_code=args.smoke_exit_code,
        target_id=args.target_id,
        target_os=args.target_os,
        architecture=args.architecture,
    )
    print(
        f"{report['release_gate']} target={report['target_id']} "
        f"passed={str(report['passed']).lower()}"
    )
    if args.report:
        print(args.report, file=sys.stderr)
    return 0 if report["passed"] else 1


if __name__ == "__main__":
    raise SystemExit(main())
