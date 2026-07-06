#!/usr/bin/env python3
from __future__ import annotations

import argparse
import json
import os
import subprocess
import sys
from pathlib import Path
from typing import Any


DEFAULT_RELEASE_ARCHIVE = ".harness/release-inputs/bundle/MeetingAssistantNative-Release.zip"
DEFAULT_BUNDLE_REPORT = ".harness/release-inputs/bundle/release-bundle-report.json"
DEFAULT_PROVENANCE_REPORT = ".harness/release-inputs/supply-chain/release-provenance-report.json"
DEFAULT_SIGNATURE_REPORT = ".harness/release-inputs/supply-chain/release-signature-report.json"
DEFAULT_SIDECAR_REPORT = ".harness/release-inputs/supply-chain/release-sidecar-report.json"


class ReleaseCandidateInputsError(Exception):
    pass


def repo_root_from_script() -> Path:
    return Path(__file__).resolve().parents[1]


def env_default(name: str) -> str | None:
    value = os.environ.get(name)
    if value is None or not value.strip():
        return None
    return value.strip()


def resolve_path(root: Path, value: str) -> Path:
    path = Path(value).expanduser()
    if not path.is_absolute():
        path = root / path
    return path.resolve()


def require_non_empty(value: str | None, label: str) -> str:
    if value is None or not value.strip():
        raise ReleaseCandidateInputsError(f"{label} is required")
    return value.strip()


def require_existing_file(path: Path, label: str) -> None:
    if not path.is_file():
        raise ReleaseCandidateInputsError(f"{label} must exist as a file: {path}")


def current_commit(root: Path) -> str:
    return run_command(["git", "-C", str(root), "rev-parse", "HEAD"], "git rev-parse HEAD").strip()


def source_repository(root: Path, configured: str | None) -> str:
    if configured is not None and configured.strip():
        return configured.strip()
    completed = subprocess.run(
        ["git", "-C", str(root), "config", "--get", "remote.origin.url"],
        text=True,
        capture_output=True,
        check=False,
    )
    if completed.returncode == 0 and completed.stdout.strip():
        return completed.stdout.strip()
    raise ReleaseCandidateInputsError(
        "source repository is required; pass --source-repository or configure git remote.origin.url"
    )


def run_command(
    command: list[str],
    label: str,
    *,
    cwd: Path | None = None,
    env: dict[str, str] | None = None,
) -> str:
    try:
        completed = subprocess.run(
            command,
            cwd=str(cwd) if cwd is not None else None,
            env=env,
            text=True,
            capture_output=True,
            check=False,
        )
    except FileNotFoundError as exc:
        raise ReleaseCandidateInputsError(f"{label} failed: {exc.filename} is not available") from exc
    output = completed.stdout + completed.stderr
    if completed.returncode != 0:
        lines = [line.strip() for line in output.strip().splitlines() if line.strip()]
        if len(lines) > 1 and lines[0].endswith("failed:"):
            detail = f"{lines[0]} {lines[1]}"
        else:
            detail = lines[0] if lines else f"exit {completed.returncode}"
        raise ReleaseCandidateInputsError(f"{label} failed: {detail}")
    return output


def load_json(path: Path, label: str) -> dict[str, Any]:
    require_existing_file(path, label)
    try:
        payload = json.loads(path.read_text(encoding="utf-8"))
    except json.JSONDecodeError as exc:
        raise ReleaseCandidateInputsError(f"{label} must be valid JSON: {path}: {exc}") from exc
    if not isinstance(payload, dict):
        raise ReleaseCandidateInputsError(f"{label} must be a JSON object: {path}")
    return payload


def load_bundle_defaults(report_path: Path) -> dict[str, str]:
    payload = load_json(report_path, "release bundle report")
    bundle = payload.get("bundle")
    if not isinstance(bundle, dict):
        raise ReleaseCandidateInputsError("release bundle report must include a bundle object")
    defaults: dict[str, str] = {}
    for key, label in (
        ("builder", "builder"),
        ("source_repository", "source repository"),
    ):
        value = payload.get(key)
        if isinstance(value, str) and value.strip():
            defaults[label] = value.strip()
    for key, label in (
        ("path", "archive"),
        ("signing_identity", "signing identity"),
        ("notarization_ticket", "notarization ticket"),
    ):
        value = bundle.get(key)
        if isinstance(value, str) and value.strip():
            defaults[label] = value.strip()
    return defaults


def run_release_bundle_create(
    root: Path,
    args: argparse.Namespace,
    *,
    archive_path: Path,
    bundle_report_path: Path,
    builder: str,
    source_repo: str,
) -> None:
    command = [
        sys.executable,
        str(root / "scripts/release-bundle-create.py"),
        "--root",
        str(root),
        "--output",
        str(archive_path),
        "--report",
        str(bundle_report_path),
        "--builder",
        builder,
        "--source-repository",
        source_repo,
    ]
    for option, value in (
        ("--signing-identity", args.signing_identity),
        ("--notary-profile", args.notary_profile),
        ("--identity-pattern", args.identity_pattern),
        ("--development-team", args.development_team),
        ("--destination", args.destination),
    ):
        if value is not None and str(value).strip():
            command.extend([option, str(value).strip()])
    run_command(command, "release bundle creation", cwd=root)


def run_release_inputs_report(
    root: Path,
    args: argparse.Namespace,
    *,
    archive_path: Path,
    attestation_path: Path,
    sigstore_bundle_path: Path,
    bundle_report_path: Path,
    provenance_report_path: Path,
    signature_report_path: Path,
    builder: str,
    source_repo: str,
    signing_identity: str,
    notarization_ticket: str,
) -> None:
    command = [
        sys.executable,
        str(root / "scripts/release-inputs-report.py"),
        "--root",
        str(root),
        "--archive",
        str(archive_path),
        "--attestation",
        str(attestation_path),
        "--sigstore-bundle",
        str(sigstore_bundle_path),
        "--builder",
        builder,
        "--source-repository",
        source_repo,
        "--signing-identity",
        signing_identity,
        "--notarization-ticket",
        notarization_ticket,
        "--certificate-identity",
        require_non_empty(args.certificate_identity, "OIDC certificate identity"),
        "--certificate-issuer",
        require_non_empty(args.certificate_issuer, "OIDC certificate issuer"),
        "--transparency-log-id",
        require_non_empty(args.transparency_log_id, "transparency log id"),
        "--transparency-log-index",
        str(args.transparency_log_index),
        "--verifier",
        args.verifier,
        "--verify-release-bundle",
        "--bundle-report",
        str(bundle_report_path),
        "--provenance-report",
        str(provenance_report_path),
        "--signature-report",
        str(signature_report_path),
    ]
    run_command(command, "release input report materialization", cwd=root)


def release_env(
    *,
    bundle_report_path: Path,
    provenance_report_path: Path,
    signature_report_path: Path,
    sidecar_report_path: Path,
) -> dict[str, str]:
    env = os.environ.copy()
    env["MEETING_ASSISTANT_RELEASE_BUNDLE_REPORT"] = str(bundle_report_path)
    env["MEETING_ASSISTANT_RELEASE_PROVENANCE_REPORT"] = str(provenance_report_path)
    env["MEETING_ASSISTANT_RELEASE_SIGNATURE_REPORT"] = str(signature_report_path)
    env["MEETING_ASSISTANT_RELEASE_SIDECAR_REPORT"] = str(sidecar_report_path)
    return env


def run_release_candidate_inputs(args: argparse.Namespace) -> None:
    root = resolve_path(repo_root_from_script(), args.root)
    archive_path = resolve_path(root, args.archive)
    bundle_report_path = resolve_path(root, args.bundle_report)
    provenance_report_path = resolve_path(root, args.provenance_report)
    signature_report_path = resolve_path(root, args.signature_report)
    sidecar_report_path = resolve_path(root, args.sidecar_report)
    attestation_path = resolve_path(root, require_non_empty(args.attestation, "DSSE/SLSA attestation"))
    sigstore_bundle_path = resolve_path(root, require_non_empty(args.sigstore_bundle, "Sigstore bundle"))
    require_existing_file(attestation_path, "DSSE/SLSA attestation")
    require_existing_file(sigstore_bundle_path, "Sigstore bundle")
    if args.transparency_log_index < 0:
        raise ReleaseCandidateInputsError("transparency log index must be non-negative")

    if not args.skip_bundle_create:
        source_repo = source_repository(root, args.source_repository)
        builder = require_non_empty(args.builder or "local-release-rehearsal", "builder")
        run_release_bundle_create(
            root,
            args,
            archive_path=archive_path,
            bundle_report_path=bundle_report_path,
            builder=builder,
            source_repo=source_repo,
        )

    bundle_defaults = load_bundle_defaults(bundle_report_path)
    if args.skip_bundle_create:
        builder = args.builder or bundle_defaults.get("builder") or "local-release-rehearsal"
        source_repo = (
            args.source_repository
            or bundle_defaults.get("source repository")
            or source_repository(root, None)
        )
    else:
        builder = args.builder or bundle_defaults.get("builder") or "local-release-rehearsal"
        source_repo = args.source_repository or bundle_defaults.get("source repository") or source_repo
    archive_from_report = bundle_defaults.get("archive")
    if archive_from_report:
        archive_path = resolve_path(root, archive_from_report)
    require_existing_file(archive_path, "release archive")
    signing_identity = args.signing_identity or bundle_defaults.get("signing identity")
    notarization_ticket = args.notarization_ticket or bundle_defaults.get("notarization ticket")
    builder = args.builder or bundle_defaults.get("builder") or builder
    source_repo = args.source_repository or bundle_defaults.get("source repository") or source_repo

    run_release_inputs_report(
        root,
        args,
        archive_path=archive_path,
        attestation_path=attestation_path,
        sigstore_bundle_path=sigstore_bundle_path,
        bundle_report_path=bundle_report_path,
        provenance_report_path=provenance_report_path,
        signature_report_path=signature_report_path,
        builder=require_non_empty(builder, "builder"),
        source_repo=require_non_empty(source_repo, "source repository"),
        signing_identity=require_non_empty(signing_identity, "signing identity"),
        notarization_ticket=require_non_empty(notarization_ticket, "notarization ticket"),
    )

    env = release_env(
        bundle_report_path=bundle_report_path,
        provenance_report_path=provenance_report_path,
        signature_report_path=signature_report_path,
        sidecar_report_path=sidecar_report_path,
    )
    run_command([str(root / "scripts/release-bundle-check.sh")], "release bundle check", cwd=root, env=env)
    run_command([str(root / "scripts/supply-chain-check.sh"), "release"], "release supply-chain check", cwd=root, env=env)
    if args.run_release_preflight:
        run_command([str(root / "scripts/release-preflight.sh")], "release preflight", cwd=root, env=env)

    print(f"release candidate inputs verified for commit {current_commit(root)}")
    print(f"release archive: {archive_path}")
    print(f"release bundle report: {bundle_report_path}")
    print(f"release provenance report: {provenance_report_path}")
    print(f"release signature report: {signature_report_path}")
    print(
        "VS-MA-23 release candidate inputs verified [non-bypass]: "
        "PV release and release-preflight still remain authoritative final gates"
    )


def parse_args(argv: list[str]) -> argparse.Namespace:
    parser = argparse.ArgumentParser(
        description=(
            "Orchestrate VS-MA-23 release candidate inputs from a signed/notarized "
            "bundle, DSSE/SLSA attestation, Sigstore bundle, and sidecar report."
        )
    )
    parser.add_argument("--root", default=str(repo_root_from_script()))
    parser.add_argument(
        "--archive",
        default=env_default("MEETING_ASSISTANT_RELEASE_ARCHIVE") or DEFAULT_RELEASE_ARCHIVE,
    )
    parser.add_argument(
        "--attestation",
        default=env_default("MEETING_ASSISTANT_RELEASE_ATTESTATION"),
        help="DSSE in-toto SLSA provenance v1 attestation for the release archive.",
    )
    parser.add_argument(
        "--sigstore-bundle",
        default=env_default("MEETING_ASSISTANT_RELEASE_SIGSTORE_BUNDLE"),
        help="Sigstore bundle JSON for the release archive.",
    )
    parser.add_argument("--bundle-report", default=DEFAULT_BUNDLE_REPORT)
    parser.add_argument("--provenance-report", default=DEFAULT_PROVENANCE_REPORT)
    parser.add_argument("--signature-report", default=DEFAULT_SIGNATURE_REPORT)
    parser.add_argument("--sidecar-report", default=DEFAULT_SIDECAR_REPORT)
    parser.add_argument(
        "--skip-bundle-create",
        action="store_true",
        help="Use an existing signed/notarized archive and bundle report instead of running release-bundle-create.py.",
    )
    parser.add_argument(
        "--run-release-preflight",
        action="store_true",
        help="Run release-preflight.sh after release bundle and supply-chain checks pass.",
    )
    parser.add_argument(
        "--signing-identity",
        default=env_default("MEETING_ASSISTANT_RELEASE_SIGNING_IDENTITY"),
    )
    parser.add_argument(
        "--identity-pattern",
        default=env_default("MEETING_ASSISTANT_RELEASE_IDENTITY_PATTERN"),
    )
    parser.add_argument(
        "--development-team",
        default=env_default("MEETING_ASSISTANT_RELEASE_DEVELOPMENT_TEAM"),
    )
    parser.add_argument(
        "--notary-profile",
        default=env_default("MEETING_ASSISTANT_NOTARYTOOL_PROFILE"),
    )
    parser.add_argument(
        "--destination",
        default=env_default("MA_NATIVE_RELEASE_XCODE_DESTINATION"),
    )
    parser.add_argument(
        "--notarization-ticket",
        default=env_default("MEETING_ASSISTANT_RELEASE_NOTARIZATION_TICKET"),
    )
    parser.add_argument(
        "--builder",
        default=env_default("MEETING_ASSISTANT_RELEASE_BUILDER"),
    )
    parser.add_argument(
        "--source-repository",
        default=env_default("MEETING_ASSISTANT_RELEASE_SOURCE_REPOSITORY"),
    )
    parser.add_argument(
        "--certificate-identity",
        default=env_default("MEETING_ASSISTANT_RELEASE_CERTIFICATE_IDENTITY"),
    )
    parser.add_argument(
        "--certificate-issuer",
        default=env_default("MEETING_ASSISTANT_RELEASE_CERTIFICATE_ISSUER"),
    )
    parser.add_argument(
        "--transparency-log-id",
        default=env_default("MEETING_ASSISTANT_RELEASE_TRANSPARENCY_LOG_ID"),
    )
    parser.add_argument(
        "--transparency-log-index",
        default=int(env_default("MEETING_ASSISTANT_RELEASE_TRANSPARENCY_LOG_INDEX") or "-1"),
        type=int,
    )
    parser.add_argument("--verifier", default=env_default("MEETING_ASSISTANT_RELEASE_VERIFIER") or "sigstore")
    return parser.parse_args(argv)


def main(argv: list[str]) -> int:
    args = parse_args(argv)
    run_release_candidate_inputs(args)
    return 0


if __name__ == "__main__":
    try:
        raise SystemExit(main(sys.argv[1:]))
    except ReleaseCandidateInputsError as exc:
        print(f"release candidate inputs failed: {exc}", file=sys.stderr)
        raise SystemExit(1)
