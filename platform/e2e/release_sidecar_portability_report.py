#!/usr/bin/env python3
from __future__ import annotations

import argparse
import hashlib
import json
import os
import re
import subprocess
import sys
from pathlib import Path
from typing import Any


TARGET_REPORTS_ENV = "MA_RELEASE_SIDECAR_TARGET_SMOKE_REPORTS"
EXPECTED_TARGETS_ENV = "MA_RELEASE_SIDECAR_EXPECTED_TARGETS"
REPORT_ENV = "MA_RELEASE_SIDECAR_REPORT"
BUILDER_ENV = "MA_RELEASE_SIDECAR_BUILDER"
SOURCE_REPOSITORY_ENV = "MA_RELEASE_SIDECAR_SOURCE_REPOSITORY"

RELEASE_BLOCKERS = [
    "sidecar portability evidence does not prove signed or notarized release bundle",
    "sidecar portability evidence does not produce DSSE/SLSA provenance attestation",
    "sidecar portability evidence does not produce Sigstore signing bundle",
    "sidecar portability evidence does not prove real ScreenCaptureKit capture",
    "sidecar portability evidence alone does not prove VS-MA-23 release readiness",
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


def is_local_sidecar_path(value: Any) -> bool:
    return isinstance(value, str) and (value.startswith("~/.local/") or "/.local/" in value)


def validate_local_artifact(
    artifact: Any,
    label: str,
    findings: list[str],
    *,
    require_license: bool = False,
) -> dict[str, Any] | None:
    if not isinstance(artifact, dict):
        findings.append(f"{label} must be an object")
        return None
    if not isinstance(artifact.get("name"), str) or not artifact.get("name"):
        findings.append(f"{label} must include name")
    if not is_local_sidecar_path(artifact.get("path")):
        findings.append(f"{label} path must be under a user .local root")
    else:
        path_value = artifact["path"]
        for fragment in ("/Downloads/", "/Desktop/", "/Library/Caches/"):
            if fragment in path_value:
                findings.append(f"{label} path must not be under Downloads, Desktop, or Library/Caches")
    if not is_sha256_digest(artifact.get("digest")):
        findings.append(f"{label} digest must be a sha256:<64 hex> digest")
    if not isinstance(artifact.get("source"), str) or not artifact.get("source"):
        findings.append(f"{label} must include source")
    if require_license:
        if not isinstance(artifact.get("license"), str) or not artifact.get("license"):
            findings.append(f"{label} must include license")
        if not isinstance(artifact.get("provenance_ref"), str) or not artifact.get("provenance_ref"):
            findings.append(f"{label} must include provenance_ref")
    return dict(artifact)


def validate_target_smoke_report(
    root: Path,
    path: Path,
    *,
    expected_commit: str | None,
    findings: list[str],
) -> dict[str, Any] | None:
    report = load_json_object(path, "release sidecar target smoke report", findings)
    if report is None:
        return None

    label = f"release sidecar target smoke report {path}"
    if report.get("report_schema") != 1:
        findings.append(f"{label} must set report_schema=1")
    if report.get("release_gate") != "release-sidecar-target-smoke":
        findings.append(f"{label} must set release_gate='release-sidecar-target-smoke'")
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

    artifacts = report.get("artifacts")
    if not isinstance(artifacts, dict):
        findings.append(f"{label} artifacts must be an object")
        artifacts = {}
    runtime = validate_local_artifact(artifacts.get("runtime"), f"{label} runtime", findings)
    model = validate_local_artifact(
        artifacts.get("model"),
        f"{label} model",
        findings,
        require_license=True,
    )
    smoke_audio = validate_local_artifact(
        artifacts.get("smoke_audio_fixture"),
        f"{label} smoke_audio_fixture",
        findings,
    )

    smoke = report.get("smoke")
    if not isinstance(smoke, dict):
        findings.append(f"{label} smoke must be an object")
        smoke = {}
    for key in ("check_dependencies_ok", "whisper_cpp_smoke_passed", "no_auto_downloads_observed"):
        if smoke.get(key) is not True:
            findings.append(f"{label} smoke must set {key}=True")

    try:
        report_digest = sha256_file(path)
    except OSError as exc:
        findings.append(f"{label} digest could not be computed: {exc.__class__.__name__}")
        report_digest = "sha256:" + ("0" * 64)

    return {
        "target_id": str(target_id),
        "os": str(target_os),
        "architecture": str(architecture),
        "runtime": runtime,
        "model": model,
        "smoke_audio_fixture": smoke_audio,
        "smoke": {
            "check_dependencies_ok": smoke.get("check_dependencies_ok") is True,
            "whisper_cpp_smoke_passed": smoke.get("whisper_cpp_smoke_passed") is True,
            "no_auto_downloads_observed": smoke.get("no_auto_downloads_observed") is True,
        },
        "smoke_report": {
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
        findings.append("expected target list is required before claiming all-target sidecar portability")
    if len(set(normalized_expected)) != len(normalized_expected):
        findings.append("expected target list must not contain duplicates")
    if not target_smoke_report_paths:
        findings.append("at least one release-sidecar-target-smoke report is required")
    if not builder:
        findings.append("builder is required")
    if not source_repository_value:
        findings.append("source_repository is required")

    targets_by_id: dict[str, dict[str, Any]] = {}
    duplicate_targets: set[str] = set()
    for raw_path in target_smoke_report_paths:
        path = raw_path if raw_path.is_absolute() else root / raw_path
        target = validate_target_smoke_report(
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
        "release_gate": "release-sidecar-portability",
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
            ".harness/release-inputs/supply-chain/release-sidecar-report.json",
        ),
    )
    parser.add_argument("--builder", default=os.environ.get(BUILDER_ENV))
    parser.add_argument("--source-repository", default=os.environ.get(SOURCE_REPOSITORY_ENV))
    args = parser.parse_args(argv)

    root = Path(args.root)
    target_report_values = list(args.target_smoke_report)
    target_report_values.extend(split_list(args.target_smoke_reports))
    expected_target_values = list(args.expected_target)
    expected_target_values.extend(split_list(args.expected_targets))
    repository = args.source_repository or source_repository(root)

    report = build_report(
        root,
        target_smoke_report_paths=[Path(item) for item in target_report_values],
        expected_targets=expected_target_values,
        report_path=Path(args.report),
        builder=args.builder,
        source_repository_value=repository,
    )
    print(f"release sidecar portability report: {args.report}", file=sys.stderr)
    if report["passed"]:
        print(
            "VS-MA-22 release sidecar portability marker [non-contract]: "
            "release-sidecar-portability all expected targets covered by release-sidecar-target-smoke reports"
        )
        return 0
    print("release sidecar portability failed:", file=sys.stderr)
    for finding in report["findings"]:
        print(f" - {finding}", file=sys.stderr)
    return 1


if __name__ == "__main__":
    raise SystemExit(main())
