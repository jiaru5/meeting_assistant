#!/usr/bin/env python3
from __future__ import annotations

import argparse
import hashlib
import json
import os
import re
import subprocess
from pathlib import Path
from typing import Any


TARGET_REPORTS_ENV = "MA_RELEASE_LOCAL_DIRECT_TARGET_SMOKE_REPORTS"
EXPECTED_TARGETS_ENV = "MA_RELEASE_LOCAL_DIRECT_EXPECTED_TARGETS"
REPORT_ENV = "MA_RELEASE_LOCAL_DIRECT_REPEATABILITY_REPORT"
BUILDER_ENV = "MA_RELEASE_LOCAL_DIRECT_BUILDER"
SOURCE_REPOSITORY_ENV = "MA_RELEASE_LOCAL_DIRECT_SOURCE_REPOSITORY"

RELEASE_BLOCKERS = [
    "local-direct repeatability evidence does not run product-validation release or release-preflight",
    "local-direct repeatability evidence does not prove Developer ID, notarization, App Store, or commercial distribution readiness",
    "local-direct repeatability evidence must be paired with PV closure before release readiness",
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


def source_repository(root: Path) -> str | None:
    completed = subprocess.run(
        ["git", "-C", str(root), "config", "--get", "remote.origin.url"],
        text=True,
        capture_output=True,
        check=False,
    )
    if completed.returncode != 0:
        return None
    value = completed.stdout.strip()
    return value or None


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


def split_list(value: str | None) -> list[str]:
    if value is None:
        return []
    return [item.strip() for item in re.split(r"[,\n]+", value) if item.strip()]


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


def is_sha256_digest(value: Any) -> bool:
    return isinstance(value, str) and re.fullmatch(r"sha256:[a-fA-F0-9]{64}", value) is not None


def validate_target_report(
    root: Path,
    path: Path,
    *,
    expected_commit: str | None,
    findings: list[str],
) -> dict[str, Any] | None:
    report = load_json_object(path, "release local-direct target smoke report", findings)
    if report is None:
        return None

    label = f"release local-direct target smoke report {path}"
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
    for key in ("packages_runtime_or_model", "auto_downloads", "external_network_access"):
        if report.get(key) is not False:
            findings.append(f"{label} must set {key}=False")

    target_id = report.get("target_id")
    target_os = report.get("os")
    architecture = report.get("architecture")
    if not isinstance(target_id, str) or not target_id:
        findings.append(f"{label} must include target_id")
        target_id = "unknown-target"
    if normalize_target_id(str(target_id)) != target_id:
        findings.append(f"{label} target_id must already be normalized")
    if not isinstance(target_os, str) or not target_os:
        findings.append(f"{label} must include os")
        target_os = "unknown"
    if not isinstance(architecture, str) or not architecture:
        findings.append(f"{label} must include architecture")
        architecture = "unknown"

    same_chain_report = report.get("same_chain_report")
    if not isinstance(same_chain_report, dict):
        findings.append(f"{label} must include same_chain_report")
        same_chain_report = {}
    if not isinstance(same_chain_report.get("path"), str) or not same_chain_report.get("path"):
        findings.append(f"{label} same_chain_report must include path")
    if not is_sha256_digest(same_chain_report.get("digest")):
        findings.append(f"{label} same_chain_report must include sha256 digest")

    smoke = report.get("smoke")
    if not isinstance(smoke, dict):
        findings.append(f"{label} smoke must be an object")
        smoke = {}
    if smoke.get("same_chain_passed") is not True:
        findings.append(f"{label} smoke must set same_chain_passed=True")
    if smoke.get("same_app_identity") is not True:
        findings.append(f"{label} smoke must set same_app_identity=True")
    if smoke.get("launch_modes") != ["open"]:
        findings.append(f"{label} smoke must set launch_modes=['open']")
    stage_passed = smoke.get("stage_passed")
    if not isinstance(stage_passed, dict):
        findings.append(f"{label} smoke must include stage_passed")
        stage_passed = {}
    for stage in ("recording", "processing", "actions"):
        if stage_passed.get(stage) is not True:
            findings.append(f"{label} smoke stage {stage} must pass")

    app_identity = report.get("local_direct_app")
    if not isinstance(app_identity, dict):
        findings.append(f"{label} must include local_direct_app")
        app_identity = {}
    for key in ("path", "CFBundleIdentifier"):
        if not isinstance(app_identity.get(key), str) or not app_identity.get(key):
            findings.append(f"{label} local_direct_app must include {key}")

    try:
        report_digest = sha256_file(path)
    except OSError as exc:
        findings.append(f"{label} digest could not be computed: {exc.__class__.__name__}")
        report_digest = "sha256:" + ("0" * 64)

    return {
        "target_id": str(target_id),
        "os": str(target_os),
        "architecture": str(architecture),
        "local_direct_app": app_identity,
        "same_chain_report": same_chain_report,
        "smoke": smoke,
        "target_smoke_report": {
            "path": str(path if path.is_absolute() else (root / path)),
            "digest": report_digest,
        },
    }


def build_report(
    root: Path,
    *,
    target_smoke_report_paths: list[Path],
    expected_targets: list[str],
    report_path: Path | None = None,
    builder: str | None = None,
    source_repository_value: str | None = None,
) -> dict[str, Any]:
    root = root.resolve(strict=False)
    findings: list[str] = []
    head = current_commit(root)
    if head is None:
        findings.append("current git commit could not be resolved")

    normalized_expected = [normalize_target_id(item) for item in expected_targets if item.strip()]
    if not normalized_expected:
        findings.append("expected target list is required before claiming all-target local-direct repeatability")
    if len(set(normalized_expected)) != len(normalized_expected):
        findings.append("expected target list must not contain duplicates")
    if not target_smoke_report_paths:
        findings.append("at least one release-local-direct-target-smoke report is required")
    if not builder:
        findings.append("builder is required")
    if not source_repository_value:
        findings.append("source_repository is required")

    targets_by_id: dict[str, dict[str, Any]] = {}
    duplicate_targets: set[str] = set()
    for raw_path in target_smoke_report_paths:
        path = raw_path if raw_path.is_absolute() else root / raw_path
        target = validate_target_report(
            root,
            path,
            expected_commit=head,
            findings=findings,
        )
        if target is None:
            continue
        target_id = target["target_id"]
        if target_id in targets_by_id:
            duplicate_targets.add(target_id)
        targets_by_id[target_id] = target

    if duplicate_targets:
        findings.append(f"duplicate target smoke reports: {', '.join(sorted(duplicate_targets))}")

    observed_targets = sorted(targets_by_id)
    expected_set = set(normalized_expected)
    observed_set = set(observed_targets)
    missing_targets = sorted(expected_set - observed_set)
    unexpected_targets = sorted(observed_set - expected_set) if normalized_expected else []
    if missing_targets:
        findings.append(f"missing expected target smoke reports: {', '.join(missing_targets)}")
    if unexpected_targets:
        findings.append(f"unexpected target smoke reports: {', '.join(unexpected_targets)}")

    ordered_targets = [
        targets_by_id[target_id]
        for target_id in normalized_expected
        if target_id in targets_by_id
    ]
    if not normalized_expected:
        ordered_targets = [targets_by_id[target_id] for target_id in observed_targets]

    passed = not findings
    report: dict[str, Any] = {
        "report_schema": 1,
        "release_gate": "release-local-direct-repeatability",
        "target_scope": "all-target-machines" if passed else "incomplete-target-set",
        "subject_commit": head,
        "builder": builder,
        "source_repository": source_repository_value,
        "packages_runtime_or_model": False,
        "auto_downloads": False,
        "external_network_access": False,
        "expected_targets": normalized_expected,
        "observed_targets": observed_targets,
        "target_machines": ordered_targets,
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
    parser.add_argument("--target-smoke-report", action="append", default=[])
    parser.add_argument("--target-smoke-reports", default=os.environ.get(TARGET_REPORTS_ENV))
    parser.add_argument("--expected-target", action="append", default=[])
    parser.add_argument("--expected-targets", default=os.environ.get(EXPECTED_TARGETS_ENV))
    parser.add_argument(
        "--report",
        default=os.environ.get(
            REPORT_ENV,
            ".harness/release-inputs/local-direct/release-local-direct-repeatability-report.json",
        ),
    )
    parser.add_argument("--builder", default=os.environ.get(BUILDER_ENV, "local-direct-release-rehearsal"))
    parser.add_argument(
        "--source-repository",
        default=os.environ.get(SOURCE_REPOSITORY_ENV),
    )
    args = parser.parse_args(argv)

    report_paths = [Path(value) for value in args.target_smoke_report]
    report_paths.extend(Path(value) for value in split_list(args.target_smoke_reports))
    expected_targets = list(args.expected_target)
    expected_targets.extend(split_list(args.expected_targets))
    root = Path(args.root)
    repository = args.source_repository or source_repository(root)
    report = build_report(
        root,
        target_smoke_report_paths=report_paths,
        expected_targets=expected_targets,
        report_path=Path(args.report) if args.report else None,
        builder=args.builder,
        source_repository_value=repository,
    )
    print(
        f"{report['release_gate']} target_scope={report['target_scope']} "
        f"passed={str(report['passed']).lower()}"
    )
    if args.report:
        print(args.report, file=os.sys.stderr)
    return 0 if report["passed"] else 1


if __name__ == "__main__":
    raise SystemExit(main())
