#!/usr/bin/env python3
from __future__ import annotations

import argparse
import base64
import binascii
import hashlib
import json
import re
import subprocess
import sys
import zipfile
from pathlib import Path
from typing import Any


SLSA_PROVENANCE_V1 = "https://slsa.dev/provenance/v1"
IN_TOTO_STATEMENT_V1 = "https://in-toto.io/Statement/v1"
DSSE_IN_TOTO_PAYLOAD_TYPE = "application/vnd.in-toto+json"
DEFAULT_BUNDLE_REPORT = ".harness/release-inputs/bundle/release-bundle-report.json"
DEFAULT_PROVENANCE_REPORT = ".harness/release-inputs/supply-chain/release-provenance-report.json"
DEFAULT_SIGNATURE_REPORT = ".harness/release-inputs/supply-chain/release-signature-report.json"


class ReportError(Exception):
    pass


def repo_root_from_script() -> Path:
    return Path(__file__).resolve().parents[1]


def current_commit(root: Path) -> str:
    completed = subprocess.run(
        ["git", "-C", str(root), "rev-parse", "HEAD"],
        text=True,
        capture_output=True,
        check=False,
    )
    if completed.returncode != 0 or not completed.stdout.strip():
        raise ReportError("unable to resolve current git commit")
    return completed.stdout.strip()


def resolve_path(root: Path, value: str) -> Path:
    path = Path(value).expanduser()
    if not path.is_absolute():
        path = root / path
    return path.resolve()


def sha256_file(path: Path) -> str:
    digest = hashlib.sha256()
    with path.open("rb") as handle:
        for chunk in iter(lambda: handle.read(1024 * 1024), b""):
            digest.update(chunk)
    return "sha256:" + digest.hexdigest()


def require_existing_file(path: Path, label: str) -> None:
    if not path.is_file():
        raise ReportError(f"{label} must exist as a file: {path}")


def load_manifest(root: Path) -> dict[str, Any]:
    manifest_path = root / "harness/project-manifest.json"
    try:
        manifest = json.loads(manifest_path.read_text(encoding="utf-8"))
    except json.JSONDecodeError as exc:
        raise ReportError(f"project manifest must be valid JSON: {exc}") from exc
    if not isinstance(manifest, dict):
        raise ReportError("project manifest must be a JSON object")
    return manifest


def validate_release_archive(archive_path: Path) -> None:
    require_existing_file(archive_path, "release archive")
    if not zipfile.is_zipfile(archive_path):
        raise ReportError("release archive must be a zip file")
    app_roots: set[str] = set()
    with zipfile.ZipFile(archive_path) as archive:
        for member in archive.infolist():
            filename = member.filename
            member_path = Path(filename)
            if member_path.is_absolute() or ".." in member_path.parts:
                raise ReportError(f"release archive contains unsafe path: {filename}")
            parts = member_path.parts
            for index, part in enumerate(parts):
                if part == "MeetingAssistantNative.app":
                    app_roots.add("/".join(parts[: index + 1]))
        expected_info_plists = {
            f"{app_root}/Contents/Info.plist" for app_root in app_roots
        }
        archive_names = {member.filename.rstrip("/") for member in archive.infolist()}
    if not app_roots:
        raise ReportError("release archive must contain MeetingAssistantNative.app")
    if len(app_roots) != 1:
        raise ReportError("release archive must contain exactly one MeetingAssistantNative.app")
    if not expected_info_plists.intersection(archive_names):
        raise ReportError("MeetingAssistantNative.app must include Contents/Info.plist")


def load_json_file(path: Path, label: str) -> dict[str, Any]:
    require_existing_file(path, label)
    try:
        payload = json.loads(path.read_text(encoding="utf-8"))
    except json.JSONDecodeError as exc:
        raise ReportError(f"{label} must be valid JSON: {path}: {exc}") from exc
    if not isinstance(payload, dict):
        raise ReportError(f"{label} must be a JSON object: {path}")
    return payload


def require_non_empty_string(value: Any, label: str) -> str:
    if not isinstance(value, str) or not value.strip():
        raise ReportError(f"{label} must be a non-empty string")
    return value.strip()


def validate_sigstore_bundle(path: Path) -> None:
    load_json_file(path, "Sigstore bundle")


def statement_from_dsse(path: Path) -> dict[str, Any]:
    envelope = load_json_file(path, "DSSE SLSA attestation")
    if envelope.get("payloadType") != DSSE_IN_TOTO_PAYLOAD_TYPE:
        raise ReportError(
            "DSSE SLSA attestation must set "
            f"payloadType={DSSE_IN_TOTO_PAYLOAD_TYPE!r}"
        )
    signatures = envelope.get("signatures")
    if not isinstance(signatures, list) or not signatures:
        raise ReportError("DSSE SLSA attestation must include at least one signature")
    payload = envelope.get("payload")
    if not isinstance(payload, str) or not payload:
        raise ReportError("DSSE SLSA attestation must include payload")
    try:
        decoded = base64.b64decode(payload, validate=True)
    except (binascii.Error, ValueError) as exc:
        raise ReportError(f"DSSE SLSA attestation payload must be base64: {exc}") from exc
    try:
        statement = json.loads(decoded.decode("utf-8"))
    except (UnicodeDecodeError, json.JSONDecodeError) as exc:
        raise ReportError(f"DSSE SLSA attestation payload must decode to JSON: {exc}") from exc
    if not isinstance(statement, dict):
        raise ReportError("DSSE SLSA attestation payload must decode to a JSON object")
    return statement


def validate_dsse_statement(path: Path, bundle_digest: str, bundle_names: set[str]) -> None:
    statement = statement_from_dsse(path)
    if statement.get("_type") != IN_TOTO_STATEMENT_V1:
        raise ReportError(f"DSSE statement must set _type={IN_TOTO_STATEMENT_V1!r}")
    if statement.get("predicateType") != SLSA_PROVENANCE_V1:
        raise ReportError(f"DSSE statement must set predicateType={SLSA_PROVENANCE_V1!r}")
    subjects = statement.get("subject")
    if not isinstance(subjects, list) or not subjects:
        raise ReportError("DSSE statement must include at least one subject")
    expected_hex = bundle_digest.split(":", 1)[1]
    for subject in subjects:
        if not isinstance(subject, dict):
            continue
        if subject.get("name") not in bundle_names:
            continue
        digest = subject.get("digest")
        if isinstance(digest, dict) and digest.get("sha256") == expected_hex:
            predicate = statement.get("predicate")
            if not isinstance(predicate, dict):
                raise ReportError("DSSE statement predicate must be an object")
            build_definition = predicate.get("buildDefinition")
            run_details = predicate.get("runDetails")
            if not isinstance(build_definition, dict) or not build_definition.get("buildType"):
                raise ReportError("DSSE SLSA predicate must include buildDefinition.buildType")
            if not isinstance(run_details, dict):
                raise ReportError("DSSE SLSA predicate must include runDetails")
            builder = run_details.get("builder")
            if not isinstance(builder, dict) or not builder.get("id"):
                raise ReportError("DSSE SLSA predicate must include runDetails.builder.id")
            return
    names = ", ".join(sorted(bundle_names))
    raise ReportError(f"DSSE statement subject must include {bundle_digest} for {names}")


def require_sha256_digest(value: str, label: str) -> str:
    if re.fullmatch(r"sha256:[a-fA-F0-9]{64}", value) is None:
        raise ReportError(f"{label} must be a sha256:<64 hex> digest")
    return value.lower()


def artifact_reference(path: Path) -> dict[str, str]:
    return {
        "path": str(path),
        "digest": sha256_file(path),
    }


def build_reports(args: argparse.Namespace) -> tuple[dict[str, Any], dict[str, Any], dict[str, Any]]:
    root = resolve_path(repo_root_from_script(), args.root)
    manifest = load_manifest(root)
    supply_chain = manifest.get("supply_chain")
    if not isinstance(supply_chain, dict):
        raise ReportError("project manifest must include supply_chain object")
    provenance_target = supply_chain.get("provenance_target")
    sbom_format = supply_chain.get("sbom_format")
    artifact_signing = supply_chain.get("artifact_signing")
    if not isinstance(provenance_target, str) or not provenance_target:
        raise ReportError("project manifest supply_chain.provenance_target is required")
    if not isinstance(sbom_format, str) or not sbom_format:
        raise ReportError("project manifest supply_chain.sbom_format is required")
    if not isinstance(artifact_signing, str) or not artifact_signing:
        raise ReportError("project manifest supply_chain.artifact_signing is required")

    builder = require_non_empty_string(args.builder, "builder")
    source_repository = require_non_empty_string(args.source_repository, "source repository")
    signing_identity = require_non_empty_string(args.signing_identity, "signing identity")
    notarization_ticket = require_non_empty_string(args.notarization_ticket, "notarization ticket")
    certificate_identity = require_non_empty_string(args.certificate_identity, "certificate identity")
    certificate_issuer = require_non_empty_string(args.certificate_issuer, "certificate issuer")
    transparency_log_id = require_non_empty_string(args.transparency_log_id, "transparency log id")
    verifier = require_non_empty_string(args.verifier, "verifier")
    if args.transparency_log_index < 0:
        raise ReportError("transparency log index must be non-negative")

    archive_path = resolve_path(root, args.archive)
    attestation_path = resolve_path(root, args.attestation)
    sigstore_bundle_path = resolve_path(root, args.sigstore_bundle)
    validate_release_archive(archive_path)
    require_existing_file(attestation_path, "DSSE SLSA attestation")
    validate_sigstore_bundle(sigstore_bundle_path)

    subject_commit = current_commit(root)
    bundle_digest = sha256_file(archive_path)
    require_sha256_digest(bundle_digest, "release archive digest")
    bundle_names = {archive_path.name, "MeetingAssistantNative.app"}
    validate_dsse_statement(attestation_path, bundle_digest, bundle_names)

    bundle_report = {
        "report_schema": 1,
        "release_gate": "release-bundle",
        "subject_commit": subject_commit,
        "builder": builder,
        "source_repository": source_repository,
        "bundle": {
            "name": archive_path.name,
            "path": str(archive_path),
            "digest": bundle_digest,
            "artifact_type": "macos-app-archive",
            "archive_format": "zip",
            "app_bundle": "MeetingAssistantNative.app",
            "build_configuration": "Release",
            "code_signed": True,
            "signing_identity": signing_identity,
            "notarized": True,
            "notarization_ticket": notarization_ticket,
            "stapled": True,
            "packages_runtime_or_model": False,
            "auto_downloads": False,
            "contains_meeting_data": False,
        },
    }
    provenance_report = {
        "report_schema": 1,
        "provenance_target": provenance_target,
        "release_provenance_attestation": "produced",
        "sbom_format": sbom_format,
        "subject_commit": subject_commit,
        "builder": builder,
        "source_repository": source_repository,
        "artifacts": [
            {
                "name": archive_path.name,
                "digest": bundle_digest,
            }
        ],
        "attestation": {
            "format": "dsse-in-toto-slsa-provenance-v1",
            "predicate_type": SLSA_PROVENANCE_V1,
            **artifact_reference(attestation_path),
        },
    }
    signature_report = {
        "report_schema": 1,
        "artifact_signing": artifact_signing,
        "signing_status": "signed",
        "subject_commit": subject_commit,
        "verifier": verifier,
        "signed_artifacts": [
            {
                "name": archive_path.name,
                "digest": bundle_digest,
                "signature_type": artifact_signing,
                "certificate_identity": certificate_identity,
                "certificate_issuer": certificate_issuer,
                "transparency_log": {
                    "log_id": transparency_log_id,
                    "log_index": args.transparency_log_index,
                },
                "signature_bundle": {
                    "format": "sigstore-bundle-json",
                    **artifact_reference(sigstore_bundle_path),
                },
            }
        ],
    }
    return bundle_report, provenance_report, signature_report


def write_json(path: Path, payload: dict[str, Any]) -> None:
    path.parent.mkdir(parents=True, exist_ok=True)
    path.write_text(json.dumps(payload, indent=2, sort_keys=True) + "\n", encoding="utf-8")


def parse_args(argv: list[str]) -> argparse.Namespace:
    parser = argparse.ArgumentParser(
        description=(
            "Materialize release bundle, provenance, and signature input reports "
            "from already-produced release artifacts."
        )
    )
    parser.add_argument("--root", default=str(repo_root_from_script()))
    parser.add_argument("--archive", required=True, help="Signed, notarized MeetingAssistantNative.app zip archive")
    parser.add_argument("--attestation", required=True, help="DSSE in-toto SLSA provenance v1 attestation")
    parser.add_argument("--sigstore-bundle", required=True, help="Sigstore bundle JSON for the release archive")
    parser.add_argument("--builder", required=True)
    parser.add_argument("--source-repository", required=True)
    parser.add_argument("--signing-identity", required=True)
    parser.add_argument("--notarization-ticket", required=True)
    parser.add_argument("--certificate-identity", required=True)
    parser.add_argument("--certificate-issuer", required=True)
    parser.add_argument("--transparency-log-id", required=True)
    parser.add_argument("--transparency-log-index", required=True, type=int)
    parser.add_argument("--verifier", default="sigstore")
    parser.add_argument("--bundle-report", default=DEFAULT_BUNDLE_REPORT)
    parser.add_argument("--provenance-report", default=DEFAULT_PROVENANCE_REPORT)
    parser.add_argument("--signature-report", default=DEFAULT_SIGNATURE_REPORT)
    return parser.parse_args(argv)


def main(argv: list[str]) -> int:
    args = parse_args(argv)
    root = resolve_path(repo_root_from_script(), args.root)
    bundle_report, provenance_report, signature_report = build_reports(args)
    bundle_report_path = resolve_path(root, args.bundle_report)
    provenance_report_path = resolve_path(root, args.provenance_report)
    signature_report_path = resolve_path(root, args.signature_report)
    write_json(bundle_report_path, bundle_report)
    write_json(provenance_report_path, provenance_report)
    write_json(signature_report_path, signature_report)
    print(f"release bundle report: {bundle_report_path}", file=sys.stderr)
    print(f"release provenance report: {provenance_report_path}", file=sys.stderr)
    print(f"release signature report: {signature_report_path}", file=sys.stderr)
    print(
        "VS-MA-23 release input reports materialized [non-bypass]: "
        "run release-bundle-check.sh and supply-chain-check.sh release",
    )
    return 0


if __name__ == "__main__":
    try:
        raise SystemExit(main(sys.argv[1:]))
    except ReportError as exc:
        print(f"release input report failed: {exc}", file=sys.stderr)
        raise SystemExit(1)
