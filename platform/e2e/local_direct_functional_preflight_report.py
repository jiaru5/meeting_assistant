#!/usr/bin/env python3
from __future__ import annotations

import argparse
import hashlib
import json
import os
import shutil
import subprocess
import tempfile
from pathlib import Path
from typing import Any


EXPECTED_TERMS = ["HTTP", "LLM", "clean architecture"]
DEFAULT_SOURCE_APP = ".harness/release-build/native-app/DerivedData/Build/Products/Release/MeetingAssistantNative.app"
DEFAULT_RELEASE_BUNDLE_REPORT = ".harness/release-inputs/bundle/release-bundle-report.json"
RELEASE_BLOCKERS = [
    "local-direct functional preflight proves only the explicitly tested local machine",
    "local-direct functional preflight does not run product-validation release or release-preflight",
    "local-direct functional preflight does not prove Developer ID, notarization, App Store, or commercial distribution readiness",
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


def resolve_path(root: Path, value: str | Path) -> Path:
    path = Path(value).expanduser()
    if not path.is_absolute():
        path = root / path
    return path.resolve(strict=False)


def executable_path(app: Path) -> Path:
    return app / "Contents/MacOS/MeetingAssistantNative"


def sha256_unsigned_executable(path: Path) -> str:
    with tempfile.TemporaryDirectory() as directory:
        copy_path = Path(directory) / path.name
        shutil.copy2(path, copy_path)
        try:
            subprocess.run(
                ["/usr/bin/codesign", "--remove-signature", str(copy_path)],
                text=True,
                capture_output=True,
                check=False,
            )
        except FileNotFoundError:
            pass
        return sha256_file(copy_path)


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


def validate_target_report(
    report: dict[str, Any],
    *,
    expected_commit: str | None,
    findings: list[str],
) -> dict[str, Any]:
    label = "release local-direct target smoke report"
    if report.get("report_schema") != 1:
        findings.append(f"{label} must set report_schema=1")
    if report.get("release_gate") != "release-local-direct-target-smoke":
        findings.append(f"{label} must set release_gate='release-local-direct-target-smoke'")
    if report.get("target_scope") != "single-target-machine":
        findings.append(f"{label} must set target_scope='single-target-machine'")
    if expected_commit is not None and report.get("subject_commit") != expected_commit:
        findings.append(f"{label} must bind subject_commit={expected_commit}")
    if report.get("passed") is not True:
        findings.append(f"{label} must set passed=True")
        failure_context = report.get("failure_context")
        if isinstance(failure_context, list):
            for item in failure_context:
                if isinstance(item, str) and item:
                    findings.append(f"{label} blocker: {item}")
    if report.get("not_release_readiness") is not True:
        findings.append(f"{label} must keep not_release_readiness=True")
    for key in ("packages_runtime_or_model", "auto_downloads", "external_network_access"):
        if report.get(key) is not False:
            findings.append(f"{label} must set {key}=False")

    target_id = report.get("target_id")
    if not isinstance(target_id, str) or not target_id:
        findings.append(f"{label} must include target_id")
        target_id = "unknown-target"

    app_identity = report.get("local_direct_app")
    if not isinstance(app_identity, dict):
        findings.append(f"{label} must include local_direct_app")
        app_identity = {}
    for key in ("path", "CFBundleIdentifier"):
        if not isinstance(app_identity.get(key), str) or not app_identity.get(key):
            findings.append(f"{label} local_direct_app must include {key}")

    smoke = report.get("smoke")
    if not isinstance(smoke, dict):
        findings.append(f"{label} smoke must be an object")
        smoke = {}
    if smoke.get("same_chain_passed") is not True:
        findings.append(f"{label} smoke must set same_chain_passed=True")
    if smoke.get("same_app_identity") is not True:
        findings.append(f"{label} smoke must set same_app_identity=True")
    if smoke.get("launch_modes") != ["open"]:
        findings.append(f"{label} smoke must use LaunchServices open only")

    stage_passed = smoke.get("stage_passed")
    if not isinstance(stage_passed, dict):
        findings.append(f"{label} smoke must include stage_passed")
        stage_passed = {}
    for stage in ("recording", "processing", "actions"):
        if stage_passed.get(stage) is not True:
            findings.append(f"{label} smoke stage {stage} must pass")

    expected_terms_found = smoke.get("expected_terms_found")
    if not isinstance(expected_terms_found, list):
        findings.append(f"{label} smoke must include expected_terms_found")
        expected_terms_found = []
    missing_terms = [term for term in EXPECTED_TERMS if term not in expected_terms_found]
    if missing_terms:
        findings.append(f"{label} smoke missing expected terms: {', '.join(missing_terms)}")

    return {
        "target_id": target_id,
        "os": report.get("os"),
        "architecture": report.get("architecture"),
        "local_direct_app": app_identity,
        "smoke": smoke,
    }


def validate_repeatability_report(
    report: dict[str, Any],
    *,
    expected_commit: str | None,
    target_id: str,
    target_report_digest: str,
    findings: list[str],
) -> dict[str, Any]:
    label = "release local-direct repeatability report"
    if report.get("report_schema") != 1:
        findings.append(f"{label} must set report_schema=1")
    if report.get("release_gate") != "release-local-direct-repeatability":
        findings.append(f"{label} must set release_gate='release-local-direct-repeatability'")
    if expected_commit is not None and report.get("subject_commit") != expected_commit:
        findings.append(f"{label} must bind subject_commit={expected_commit}")
    if report.get("passed") is not True:
        findings.append(f"{label} must set passed=True")
    if report.get("target_scope") != "all-target-machines":
        findings.append(f"{label} must set target_scope='all-target-machines' for its explicit expected set")
    if report.get("not_release_readiness") is not True:
        findings.append(f"{label} must keep not_release_readiness=True")

    expected_targets = report.get("expected_targets")
    observed_targets = report.get("observed_targets")
    if expected_targets != [target_id]:
        findings.append(f"{label} expected_targets must be exactly the local target: {target_id}")
    if observed_targets != [target_id]:
        findings.append(f"{label} observed_targets must be exactly the local target: {target_id}")

    target_machines = report.get("target_machines")
    if not isinstance(target_machines, list) or len(target_machines) != 1:
        findings.append(f"{label} must include exactly one target_machines entry for local functional preflight")
        target_machines = []
    target_machine = target_machines[0] if target_machines else {}
    if not isinstance(target_machine, dict):
        findings.append(f"{label} target_machines[0] must be an object")
        target_machine = {}
    if target_machine.get("target_id") != target_id:
        findings.append(f"{label} target_machines[0].target_id must match {target_id}")
    smoke_report = target_machine.get("target_smoke_report")
    if not isinstance(smoke_report, dict):
        findings.append(f"{label} target_machines[0] must include target_smoke_report")
        smoke_report = {}
    if smoke_report.get("digest") != target_report_digest:
        findings.append(f"{label} target_smoke_report digest must match target report digest")

    return {
        "target_scope": report.get("target_scope"),
        "expected_targets": expected_targets if isinstance(expected_targets, list) else [],
        "observed_targets": observed_targets if isinstance(observed_targets, list) else [],
        "target_machine": target_machine,
    }


def validate_local_direct_app_source(
    *,
    source_app_path: Path,
    release_bundle_report_path: Path,
    installed_app_identity: dict[str, Any],
    expected_commit: str | None,
    findings: list[str],
) -> dict[str, Any]:
    label = "local-direct source app check"
    release_bundle_report = load_json_object(
        release_bundle_report_path,
        "release bundle report",
        findings,
    )
    release_bundle_summary: dict[str, Any] = {
        "path": str(release_bundle_report_path),
    }
    if release_bundle_report is not None:
        if release_bundle_report.get("report_schema") != 1:
            findings.append("release bundle report must set report_schema=1")
        if release_bundle_report.get("release_gate") != "release-bundle":
            findings.append("release bundle report must set release_gate='release-bundle'")
        if expected_commit is not None and release_bundle_report.get("subject_commit") != expected_commit:
            findings.append(f"release bundle report must bind subject_commit={expected_commit}")
        bundle = release_bundle_report.get("bundle")
        if not isinstance(bundle, dict):
            findings.append("release bundle report must include bundle")
            bundle = {}
        if bundle.get("distribution_mode") != "local-direct":
            findings.append("release bundle report must use distribution_mode='local-direct'")
        if bundle.get("install_method") != "direct-local-app":
            findings.append("release bundle report must use install_method='direct-local-app'")
        if bundle.get("app_bundle") != "MeetingAssistantNative.app":
            findings.append("release bundle report must describe MeetingAssistantNative.app")
        for key in ("packages_runtime_or_model", "auto_downloads", "contains_meeting_data"):
            if bundle.get(key) is not False:
                findings.append(f"release bundle report bundle must set {key}=False")
        release_bundle_summary.update(
            {
                "digest": sha256_file(release_bundle_report_path),
                "subject_commit": release_bundle_report.get("subject_commit"),
                "distribution_mode": bundle.get("distribution_mode"),
                "bundle_digest": bundle.get("digest"),
                "archive_path": bundle.get("path"),
            }
        )
    else:
        release_bundle_summary["digest"] = "sha256:" + ("0" * 64)

    installed_app_path_value = installed_app_identity.get("path")
    if not isinstance(installed_app_path_value, str) or not installed_app_path_value:
        findings.append(f"{label} requires installed app path from target smoke report")
        installed_app_path = Path("")
    else:
        installed_app_path = Path(installed_app_path_value).expanduser().resolve(strict=False)

    source_executable = executable_path(source_app_path)
    installed_executable = executable_path(installed_app_path)
    source_hash = ""
    installed_hash = ""
    source_unsigned_hash = ""
    installed_unsigned_hash = ""

    if not source_app_path.is_dir():
        findings.append(f"{label} source app does not exist: {source_app_path}")
    elif not source_executable.is_file():
        findings.append(f"{label} source executable does not exist: {source_executable}")
    else:
        source_hash = sha256_file(source_executable)
        source_unsigned_hash = sha256_unsigned_executable(source_executable)

    if not installed_app_path.is_dir():
        findings.append(f"{label} installed app does not exist: {installed_app_path}")
    elif not installed_executable.is_file():
        findings.append(f"{label} installed executable does not exist: {installed_executable}")
    else:
        installed_hash = sha256_file(installed_executable)
        installed_unsigned_hash = sha256_unsigned_executable(installed_executable)

    executable_match = bool(
        source_unsigned_hash
        and installed_unsigned_hash
        and source_unsigned_hash == installed_unsigned_hash
    )
    if source_unsigned_hash and installed_unsigned_hash and not executable_match:
        findings.append(
            "installed local-direct app unsigned executable content must match the current source Release app; "
            "rerun platform/native-app/scripts/install-local-app.sh --rebuild"
        )

    return {
        "release_bundle_report": release_bundle_summary,
        "source_app": {
            "path": str(source_app_path),
            "executable_path": str(source_executable),
            "executable_sha256": source_hash,
            "unsigned_executable_sha256": source_unsigned_hash,
        },
        "installed_app": {
            "path": str(installed_app_path),
            "executable_path": str(installed_executable),
            "executable_sha256": installed_hash,
            "unsigned_executable_sha256": installed_unsigned_hash,
            "CFBundleIdentifier": installed_app_identity.get("CFBundleIdentifier", ""),
        },
        "source_and_installed_executable_match": executable_match,
        "source_and_installed_unsigned_executable_match": executable_match,
    }


def build_report(
    root: Path,
    *,
    target_smoke_report_path: Path,
    repeatability_report_path: Path,
    source_app_path: Path | None = None,
    release_bundle_report_path: Path | None = None,
    report_path: Path | None = None,
) -> dict[str, Any]:
    root = root.resolve(strict=False)
    findings: list[str] = []
    head = current_commit(root)
    if head is None:
        findings.append("current git commit could not be resolved")

    target_report = load_json_object(target_smoke_report_path, "target smoke report", findings)
    try:
        target_digest = sha256_file(target_smoke_report_path)
    except OSError as exc:
        findings.append(f"target smoke report digest could not be computed: {exc.__class__.__name__}")
        target_digest = "sha256:" + ("0" * 64)

    target_summary: dict[str, Any] = {}
    if target_report is not None:
        target_summary = validate_target_report(
            target_report,
            expected_commit=head,
            findings=findings,
        )
    target_id = str(target_summary.get("target_id") or "unknown-target")

    repeatability_report = load_json_object(
        repeatability_report_path,
        "repeatability report",
        findings,
    )
    try:
        repeatability_digest = sha256_file(repeatability_report_path)
    except OSError as exc:
        findings.append(f"repeatability report digest could not be computed: {exc.__class__.__name__}")
        repeatability_digest = "sha256:" + ("0" * 64)

    repeatability_summary: dict[str, Any] = {}
    if repeatability_report is not None:
        repeatability_summary = validate_repeatability_report(
            repeatability_report,
            expected_commit=head,
            target_id=target_id,
            target_report_digest=target_digest,
            findings=findings,
        )

    source_app = resolve_path(root, source_app_path or DEFAULT_SOURCE_APP)
    release_bundle_report = resolve_path(root, release_bundle_report_path or DEFAULT_RELEASE_BUNDLE_REPORT)
    local_direct_app_source = validate_local_direct_app_source(
        source_app_path=source_app,
        release_bundle_report_path=release_bundle_report,
        installed_app_identity=target_summary.get("local_direct_app", {}),
        expected_commit=head,
        findings=findings,
    )

    passed = not findings
    report: dict[str, Any] = {
        "report_schema": 1,
        "release_gate": "local-direct-functional-preflight",
        "target_scope": "local-machine-only",
        "subject_commit": head,
        "target_id": target_id,
        "target_smoke_report": {
            "path": str(target_smoke_report_path),
            "digest": target_digest,
        },
        "repeatability_report": {
            "path": str(repeatability_report_path),
            "digest": repeatability_digest,
            "target_scope": repeatability_summary.get("target_scope"),
            "expected_targets": repeatability_summary.get("expected_targets", []),
            "observed_targets": repeatability_summary.get("observed_targets", []),
        },
        "local_direct_app": target_summary.get("local_direct_app", {}),
        "local_direct_app_source": local_direct_app_source,
        "functional_checks": {
            "launch_modes": target_summary.get("smoke", {}).get("launch_modes", []),
            "same_app_identity": target_summary.get("smoke", {}).get("same_app_identity") is True,
            "stage_passed": target_summary.get("smoke", {}).get("stage_passed", {}),
            "expected_terms_found": target_summary.get("smoke", {}).get("expected_terms_found", []),
            "actions_markers": target_summary.get("smoke", {}).get("actions_markers", []),
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
    parser.add_argument("--target-smoke-report", required=True)
    parser.add_argument("--repeatability-report", required=True)
    parser.add_argument("--source-app", default=os.environ.get("MA_LOCAL_DIRECT_FUNCTIONAL_SOURCE_APP"))
    parser.add_argument(
        "--release-bundle-report",
        default=os.environ.get("MA_LOCAL_DIRECT_FUNCTIONAL_RELEASE_BUNDLE_REPORT"),
    )
    parser.add_argument("--report")
    args = parser.parse_args(argv)

    report = build_report(
        Path(args.root),
        target_smoke_report_path=Path(args.target_smoke_report),
        repeatability_report_path=Path(args.repeatability_report),
        source_app_path=Path(args.source_app) if args.source_app else None,
        release_bundle_report_path=Path(args.release_bundle_report) if args.release_bundle_report else None,
        report_path=Path(args.report) if args.report else None,
    )
    print(
        f"{report['release_gate']} target={report['target_id']} "
        f"passed={str(report['passed']).lower()}"
    )
    if args.report:
        print(args.report, file=os.sys.stderr)
    return 0 if report["passed"] else 1


if __name__ == "__main__":
    raise SystemExit(main())
