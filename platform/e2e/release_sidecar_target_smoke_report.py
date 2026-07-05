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


EXPECTED_PROVIDER_MARKERS = {
    "real_dependency_json": (
        "VS-MA-22 release-provider smoke [non-contract]: "
        "real check_dependencies JSON accepted for runtime/model/hardware/no-auto-download."
    ),
    "runtime_local_path": "VS-MA-22 release-provider smoke [non-contract]: runtime .local path accepted:",
    "model_sha256": "VS-MA-22 release-provider smoke [non-contract]: model sha256 evidence verified",
    "model_license": "VS-MA-22 release-provider smoke [non-contract]: model license sidecar accepted:",
    "model_provenance": "VS-MA-22 release-provider smoke [non-contract]: model provenance sidecar accepted:",
    "model_local_path": "VS-MA-22 release-provider smoke [non-contract]: model .local large-v3 evidence path accepted:",
    "audio_fixture_local_path": (
        "VS-MA-22 release-provider smoke [non-contract]: mixed-language fixture .local path accepted:"
    ),
    "local_machine_scope": (
        "VS-MA-22 release-provider smoke [non-contract]: "
        "sidecar evidence is local-machine evidence only and does not prove all developer machines."
    ),
    "whisper_cpp_smoke": "whisper.cpp smoke passed.",
    "required_runtime_smoke": (
        "VS-MA-22 release-provider smoke [non-contract]: required whisper.cpp runtime smoke passed."
    ),
    "no_auto_download_upload": (
        "VS-MA-22 release-provider smoke [non-contract]: "
        "no-auto-download/no-auto-upload boundary remains unchanged."
    ),
    "pass_marker": "release provider smoke passed.",
}

RELEASE_BLOCKERS = [
    "single target-machine report only; does not prove all-target-machines sidecar portability",
    "does not produce signed or notarized release bundle",
    "does not produce DSSE/SLSA provenance attestation",
    "does not produce Sigstore signing bundle",
    "does not prove VS-MA-23 release readiness",
]

TRANSCRIPTION_RUNTIME_ENV = "MEETING_ASSISTANT_TRANSCRIPTION_RUNTIME"
TRANSCRIPTION_MODEL_ENV = "MEETING_ASSISTANT_TRANSCRIPTION_MODEL"
TRANSCRIPTION_SMOKE_AUDIO_ENV = "MEETING_ASSISTANT_WHISPER_SMOKE_AUDIO"
MODEL_LICENSE_FILE_ENV = "MEETING_ASSISTANT_TRANSCRIPTION_MODEL_LICENSE_FILE"
MODEL_PROVENANCE_FILE_ENV = "MEETING_ASSISTANT_TRANSCRIPTION_MODEL_PROVENANCE_FILE"


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


def default_target_id() -> str:
    host = socket.gethostname().split(".", 1)[0] or "local"
    return normalize_target_id(f"{host}-{default_target_os()}-{platform.machine().lower() or 'unknown'}")


def default_target_os() -> str:
    system = platform.system().lower()
    if system == "darwin":
        return "macos"
    return system or sys.platform


def resolve_existing_path(value: str | None, label: str, findings: list[str]) -> Path | None:
    if value is None or not value.strip():
        findings.append(f"{label} path is required")
        return None
    path = Path(value).expanduser()
    if not path.is_file():
        findings.append(f"{label} path must exist as a file: {path}")
        return None
    return path.resolve(strict=False)


def is_local_sidecar_path(path: Path) -> bool:
    display = str(path)
    return display.startswith("~/.local/") or "/.local/" in display


def validate_local_path(path: Path | None, label: str, findings: list[str]) -> None:
    if path is None:
        return
    display = str(path)
    if not is_local_sidecar_path(path):
        findings.append(f"{label} must be under a user .local root: {display}")
    for fragment in ("/Downloads/", "/Desktop/", "/Library/Caches/"):
        if fragment in display:
            findings.append(f"{label} must not be under Downloads, Desktop, or Library/Caches: {display}")


def artifact_from_path(path: Path | None, label: str, findings: list[str], *, source: str) -> dict[str, Any] | None:
    if path is None:
        return None
    try:
        digest = sha256_file(path)
    except OSError as exc:
        findings.append(f"{label} digest could not be computed: {exc.__class__.__name__}")
        return None
    return {
        "name": path.name,
        "path": str(path),
        "digest": digest,
        "source": source,
    }


def first_text_line(path: Path, label: str, findings: list[str]) -> str | None:
    try:
        lines = path.read_text(encoding="utf-8").strip().splitlines()
    except (OSError, UnicodeDecodeError) as exc:
        findings.append(f"{label} could not be read as UTF-8 text: {exc.__class__.__name__}")
        return None
    if not lines:
        findings.append(f"{label} must not be empty")
        return None
    return lines[0]


def marker_results(provider_output: str) -> dict[str, bool]:
    return {
        key: marker in provider_output
        for key, marker in EXPECTED_PROVIDER_MARKERS.items()
    }


def build_report(
    root: Path,
    *,
    provider_output_path: Path,
    report_path: Path | None = None,
    provider_exit_code: int = 0,
    target_id: str | None = None,
    target_os: str | None = None,
    architecture: str | None = None,
    runtime_path: str | None = None,
    model_path: str | None = None,
    smoke_audio_path: str | None = None,
    model_license_file: str | None = None,
    model_provenance_file: str | None = None,
) -> dict[str, Any]:
    root = root.resolve(strict=False)
    findings: list[str] = []

    try:
        provider_output = provider_output_path.read_text(encoding="utf-8")
    except OSError as exc:
        provider_output = ""
        findings.append(f"provider output could not be read: {provider_output_path}: {exc.__class__.__name__}")

    if provider_exit_code != 0:
        findings.append(f"release-provider-smoke exited {provider_exit_code}")
    provider_marker_results = marker_results(provider_output)
    missing_provider_markers = [
        key for key, present in provider_marker_results.items() if not present
    ]
    if missing_provider_markers:
        findings.append(f"missing release-provider markers: {', '.join(missing_provider_markers)}")
    if "Traceback" in provider_output:
        findings.append("release-provider output contained a traceback")

    runtime = resolve_existing_path(runtime_path, "runtime", findings)
    model = resolve_existing_path(model_path, "model", findings)
    smoke_audio = resolve_existing_path(smoke_audio_path, "smoke audio fixture", findings)
    license_file = resolve_existing_path(model_license_file, "model license sidecar", findings)
    provenance_file = resolve_existing_path(model_provenance_file, "model provenance sidecar", findings)

    validate_local_path(runtime, "runtime", findings)
    validate_local_path(model, "model", findings)
    validate_local_path(smoke_audio, "smoke audio fixture", findings)
    validate_local_path(license_file, "model license sidecar", findings)
    validate_local_path(provenance_file, "model provenance sidecar", findings)

    runtime_artifact = artifact_from_path(
        runtime,
        "runtime",
        findings,
        source="user-prepared-local-runtime",
    )
    model_artifact = artifact_from_path(
        model,
        "model",
        findings,
        source="user-prepared-local-model",
    )
    smoke_audio_artifact = artifact_from_path(
        smoke_audio,
        "smoke audio fixture",
        findings,
        source="user-prepared-local-fixture",
    )
    license_artifact = artifact_from_path(
        license_file,
        "model license sidecar",
        findings,
        source="user-prepared-local-model-license",
    )
    provenance_artifact = artifact_from_path(
        provenance_file,
        "model provenance sidecar",
        findings,
        source="user-prepared-local-model-provenance",
    )

    if model_artifact is not None:
        if license_artifact is not None:
            license_name = first_text_line(license_file, "model license sidecar", findings)
            if license_name is not None:
                model_artifact["license"] = license_name
            model_artifact["license_ref"] = str(license_file)
            model_artifact["license_digest"] = license_artifact["digest"]
        if provenance_artifact is not None:
            model_artifact["provenance_ref"] = str(provenance_file)
            model_artifact["provenance_digest"] = provenance_artifact["digest"]

    smoke = {
        "check_dependencies_ok": (
            provider_exit_code == 0 and provider_marker_results.get("real_dependency_json") is True
        ),
        "whisper_cpp_smoke_passed": (
            provider_exit_code == 0
            and provider_marker_results.get("whisper_cpp_smoke") is True
            and provider_marker_results.get("required_runtime_smoke") is True
        ),
        "no_auto_downloads_observed": (
            provider_exit_code == 0 and provider_marker_results.get("no_auto_download_upload") is True
        ),
    }
    for key, value in smoke.items():
        if value is not True:
            findings.append(f"smoke must set {key}=True")

    report: dict[str, Any] = {
        "report_schema": 1,
        "release_gate": "release-sidecar-target-smoke",
        "subject_commit": current_commit(root),
        "target_id": normalize_target_id(target_id or default_target_id()),
        "os": target_os or default_target_os(),
        "architecture": architecture or platform.machine().lower() or "unknown",
        "packages_runtime_or_model": False,
        "auto_downloads": False,
        "external_network_access": False,
        "provider_output_path": str(provider_output_path),
        "provider_exit_code": provider_exit_code,
        "provider_marker_results": provider_marker_results,
        "missing_provider_markers": missing_provider_markers,
        "artifacts": {
            "runtime": runtime_artifact,
            "model": model_artifact,
            "smoke_audio_fixture": smoke_audio_artifact,
        },
        "sidecar_files": {
            "model_license": license_artifact,
            "model_provenance": provenance_artifact,
        },
        "smoke": smoke,
        "passed": not findings,
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


def default_sidecar_file(
    path_value: str | None,
    suffixes: tuple[str, ...],
    fallback_names: tuple[str, ...],
) -> str | None:
    if path_value is None or not path_value.strip():
        return None
    path = Path(path_value).expanduser()
    for suffix in suffixes:
        candidate = Path(str(path) + suffix)
        if candidate.is_file():
            return str(candidate)
    for filename in fallback_names:
        candidate = path.parent / filename
        if candidate.is_file():
            return str(candidate)
    return None


def main(argv: list[str] | None = None) -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("--root", default=os.environ.get("REPO_ROOT", "."))
    parser.add_argument("--provider-output", required=True)
    parser.add_argument("--report", required=True)
    parser.add_argument("--provider-exit-code", type=int, required=True)
    parser.add_argument("--target-id", default=os.environ.get("MA_RELEASE_SIDECAR_TARGET_ID"))
    parser.add_argument("--target-os", default=os.environ.get("MA_RELEASE_SIDECAR_TARGET_OS"))
    parser.add_argument("--architecture", default=os.environ.get("MA_RELEASE_SIDECAR_TARGET_ARCH"))
    parser.add_argument("--runtime", default=os.environ.get(TRANSCRIPTION_RUNTIME_ENV))
    parser.add_argument("--model", default=os.environ.get(TRANSCRIPTION_MODEL_ENV))
    parser.add_argument("--smoke-audio", default=os.environ.get(TRANSCRIPTION_SMOKE_AUDIO_ENV))
    parser.add_argument("--model-license-file", default=os.environ.get(MODEL_LICENSE_FILE_ENV))
    parser.add_argument("--model-provenance-file", default=os.environ.get(MODEL_PROVENANCE_FILE_ENV))
    args = parser.parse_args(argv)

    model_license_file = args.model_license_file or default_sidecar_file(
        args.model,
        (".license", ".license.txt", ".LICENSE"),
        ("LICENSE", "LICENSE.txt"),
    )
    model_provenance_file = args.model_provenance_file or default_sidecar_file(
        args.model,
        (".provenance.json", ".provenance", ".provenance.txt"),
        ("PROVENANCE.json", "provenance.json", "PROVENANCE.txt"),
    )

    report = build_report(
        Path(args.root),
        provider_output_path=Path(args.provider_output),
        report_path=Path(args.report),
        provider_exit_code=args.provider_exit_code,
        target_id=args.target_id,
        target_os=args.target_os,
        architecture=args.architecture,
        runtime_path=args.runtime,
        model_path=args.model,
        smoke_audio_path=args.smoke_audio,
        model_license_file=model_license_file,
        model_provenance_file=model_provenance_file,
    )
    print(f"release sidecar target smoke report: {args.report}", file=sys.stderr)
    if report["passed"]:
        print(
            "VS-MA-22 release sidecar target smoke marker [non-contract]: "
            f"{report['target_id']} passed release-sidecar-target-smoke"
        )
        return 0
    print("release sidecar target smoke failed:", file=sys.stderr)
    for finding in report["findings"]:
        print(f" - {finding}", file=sys.stderr)
    return 1


if __name__ == "__main__":
    raise SystemExit(main())
