#!/usr/bin/env python3
from __future__ import annotations

import argparse
import hashlib
import json
import os
import subprocess
from pathlib import Path
from typing import Any


EXPECTED_TERMS = ["HTTP", "LLM", "clean architecture"]
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


def build_report(
    root: Path,
    *,
    target_smoke_report_path: Path,
    repeatability_report_path: Path,
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
    parser.add_argument("--report")
    args = parser.parse_args(argv)

    report = build_report(
        Path(args.root),
        target_smoke_report_path=Path(args.target_smoke_report),
        repeatability_report_path=Path(args.repeatability_report),
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
