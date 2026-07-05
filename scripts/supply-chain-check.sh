#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT_DIR"

phase="${1:-current}"
case "$phase" in
  current|release) ;;
  *)
    echo "usage: $0 [current|release]" >&2
    exit 2
    ;;
esac

python3 scripts/action-pin-check.py
./scripts/project-manifest-check.sh "$phase"

python3 - "$ROOT_DIR" <<'PY'
from __future__ import annotations

import json
import sys
from pathlib import Path

root = Path(sys.argv[1])
manifest = json.loads((root / "harness/project-manifest.json").read_text(encoding="utf-8"))

for component in manifest.get("components", []):
    if not isinstance(component, dict) or component.get("production") is not True:
        continue
    component_path = component.get("path")
    if isinstance(component_path, str):
        report_path = root / component_path / "supply-chain/supply-chain-report.json"
        report_path.unlink(missing_ok=True)
PY

python3 scripts/harness-runtime.py run-gate sbom

python3 - "$ROOT_DIR" <<'PY'
from __future__ import annotations

import json
import sys
from pathlib import Path

root = Path(sys.argv[1])
manifest = json.loads((root / "harness/project-manifest.json").read_text(encoding="utf-8"))
failures: list[str] = []

for component in manifest.get("components", []):
    if not isinstance(component, dict) or component.get("production") is not True:
        continue

    component_id = component.get("id")
    component_path = component.get("path")
    if not isinstance(component_id, str) or not isinstance(component_path, str):
        continue

    component_root = root / component_path
    report_path = component_root / "supply-chain/supply-chain-report.json"
    if not report_path.is_file():
        failures.append(f"missing supply-chain report for production component {component_id}: {report_path.relative_to(root)}")
        continue

    try:
        report = json.loads(report_path.read_text(encoding="utf-8"))
    except json.JSONDecodeError as exc:
        failures.append(f"invalid supply-chain report JSON for production component {component_id}: {exc}")
        continue
    if not isinstance(report, dict):
        failures.append(f"supply-chain report for production component {component_id} must be a JSON object")
        continue

    expected_values = {
        "component": component_id,
        "report_schema": 1,
        "release_gate": "validation-only",
        "sbom_format": "cyclonedx-json",
        "first_party_license": "Apache-2.0",
        "packaged_third_party_runtime_components": "none",
        "sca_dependency_review": True,
        "license_review": True,
        "packages_runtime_or_model": False,
        "auto_downloads": False,
        "provenance_scope": "validation-only",
        "release_provenance_attestation": "not-produced",
    }
    for key, expected in expected_values.items():
        if report.get(key) != expected:
            failures.append(
                f"supply-chain report for production component {component_id} must set {key}={expected!r}"
            )

    if report.get("findings") != []:
        failures.append(f"supply-chain report for production component {component_id} must report zero findings")

    sbom_reference = report.get("sbom")
    if not isinstance(sbom_reference, str) or not sbom_reference:
        failures.append(f"supply-chain report for production component {component_id} must reference a component SBOM")
        continue

    sbom_names: list[str] = []
    for sbom_path in sorted((component_root / "sbom").glob("*.cdx.json")):
        relative_sbom_path = sbom_path.relative_to(root)
        try:
            sbom = json.loads(sbom_path.read_text(encoding="utf-8"))
        except json.JSONDecodeError as exc:
            failures.append(
                f"invalid component SBOM JSON for production component {component_id}: "
                f"{relative_sbom_path}: {exc}"
            )
            continue
        if not isinstance(sbom, dict):
            failures.append(
                f"component SBOM for production component {component_id} must be a JSON object: "
                f"{relative_sbom_path}"
            )
            continue
        metadata = sbom.get("metadata")
        sbom_component = metadata.get("component") if isinstance(metadata, dict) else None
        sbom_name = sbom_component.get("name") if isinstance(sbom_component, dict) else None
        if isinstance(sbom_name, str) and sbom_name:
            sbom_names.append(sbom_name)
    if not sbom_names or sbom_reference not in sbom_names:
        failures.append(
            f"supply-chain report for production component {component_id} must reference a generated component SBOM name"
        )

if failures:
    print("supply-chain evidence reports failed:", file=sys.stderr)
    for failure in failures:
        print(f" - {failure}", file=sys.stderr)
    raise SystemExit(1)

print("supply-chain evidence reports passed.")
PY

if [ "$phase" = "release" ]; then
  python3 - "$ROOT_DIR" <<'PY'
from __future__ import annotations

import base64
import binascii
import hashlib
import json
import os
import re
import subprocess
import sys
from pathlib import Path
from typing import Any


root = Path(sys.argv[1])
manifest = json.loads((root / "harness/project-manifest.json").read_text(encoding="utf-8"))
supply_chain = manifest.get("supply_chain", {})
failures: list[str] = []
SLSA_PROVENANCE_V1 = "https://slsa.dev/provenance/v1"
IN_TOTO_STATEMENT_V1 = "https://in-toto.io/Statement/v1"
DSSE_IN_TOTO_PAYLOAD_TYPE = "application/vnd.in-toto+json"


def resolve_evidence_path(env_name: str, default_relative: str) -> Path:
    configured = os.environ.get(env_name, "").strip()
    path = Path(configured) if configured else root / default_relative
    if not path.is_absolute():
        path = root / path
    return path


def load_report(path: Path, label: str) -> dict[str, Any] | None:
    if not path.is_file():
        failures.append(f"{label} report is required for release supply-chain gate: {path}")
        return None
    try:
        payload = json.loads(path.read_text(encoding="utf-8"))
    except json.JSONDecodeError as exc:
        failures.append(f"{label} report must be valid JSON: {path}: {exc}")
        return None
    if not isinstance(payload, dict):
        failures.append(f"{label} report must be a JSON object: {path}")
        return None
    return payload


def load_json_file(path: Path, label: str) -> dict[str, Any] | None:
    try:
        payload = json.loads(path.read_text(encoding="utf-8"))
    except json.JSONDecodeError as exc:
        failures.append(f"{label} must be valid JSON: {path}: {exc}")
        return None
    if not isinstance(payload, dict):
        failures.append(f"{label} must be a JSON object: {path}")
        return None
    return payload


def current_commit() -> str | None:
    completed = subprocess.run(
        ["git", "-C", str(root), "rev-parse", "HEAD"],
        text=True,
        capture_output=True,
        check=False,
    )
    if completed.returncode != 0:
        return None
    return completed.stdout.strip()


def require_equal(report: dict[str, Any], key: str, expected: Any, label: str) -> None:
    if report.get(key) != expected:
        failures.append(f"{label} report must set {key}={expected!r}")


def require_non_empty_string(report: dict[str, Any], key: str, label: str) -> None:
    if not isinstance(report.get(key), str) or not report.get(key):
        failures.append(f"{label} report must include {key}")


def require_local_sidecar_path(value: Any, label: str) -> None:
    if not isinstance(value, str) or not value:
        failures.append(f"{label} must include path")
        return
    if not (value.startswith("~/.local/") or "/.local/" in value):
        failures.append(f"{label} path must be under a user .local root")
    disallowed_fragments = ("/Downloads/", "/Desktop/", "/Library/Caches/")
    if any(fragment in value for fragment in disallowed_fragments):
        failures.append(f"{label} path must not be under Downloads, Desktop, or Library/Caches")


def require_sha256_digest(value: Any, label: str) -> str | None:
    if not isinstance(value, str) or re.fullmatch(r"sha256:[a-fA-F0-9]{64}", value) is None:
        failures.append(f"{label} must be a sha256:<64 hex> digest")
        return None
    return value.lower()


def sha256_file(path: Path) -> str:
    digest = hashlib.sha256()
    with path.open("rb") as handle:
        for chunk in iter(lambda: handle.read(1024 * 1024), b""):
            digest.update(chunk)
    return "sha256:" + digest.hexdigest()


def resolve_report_artifact_path(value: Any, label: str) -> Path | None:
    if not isinstance(value, str) or not value:
        failures.append(f"{label} must include path")
        return None
    path = Path(value)
    if not path.is_absolute():
        path = root / path
    return path


def validate_report_artifact_reference(reference: Any, label: str) -> Path | None:
    if not isinstance(reference, dict):
        failures.append(f"{label} must be an object")
        return None
    path = resolve_report_artifact_path(reference.get("path"), label)
    expected_digest = require_sha256_digest(reference.get("digest"), f"{label} digest")
    if path is None:
        return None
    if not path.is_file():
        failures.append(f"{label} must exist as a file: {path}")
        return None
    if expected_digest is not None and sha256_file(path) != expected_digest:
        failures.append(f"{label} digest mismatch: {path}")
    return path


def subject_includes_bundle(subjects: Any, digest: str, names: set[str], label: str) -> bool:
    expected_hex = digest.split(":", 1)[1]
    if not isinstance(subjects, list) or not subjects:
        failures.append(f"{label} must include at least one subject")
        return False
    for subject in subjects:
        if not isinstance(subject, dict):
            continue
        subject_name = subject.get("name")
        if names and subject_name not in names:
            continue
        subject_digest = subject.get("digest")
        if not isinstance(subject_digest, dict):
            continue
        if subject_digest.get("sha256") == expected_hex:
            return True
    return False


def statement_from_dsse_envelope(envelope: dict[str, Any], label: str) -> dict[str, Any] | None:
    if envelope.get("payloadType") != DSSE_IN_TOTO_PAYLOAD_TYPE:
        failures.append(f"{label} DSSE envelope must set payloadType={DSSE_IN_TOTO_PAYLOAD_TYPE!r}")
    signatures = envelope.get("signatures")
    if not isinstance(signatures, list) or not signatures:
        failures.append(f"{label} DSSE envelope must include at least one signature")
    payload = envelope.get("payload")
    if not isinstance(payload, str) or not payload:
        failures.append(f"{label} DSSE envelope must include payload")
        return None
    try:
        decoded = base64.b64decode(payload, validate=True)
    except (binascii.Error, ValueError) as exc:
        failures.append(f"{label} DSSE payload must be base64: {exc}")
        return None
    try:
        statement = json.loads(decoded.decode("utf-8"))
    except (UnicodeDecodeError, json.JSONDecodeError) as exc:
        failures.append(f"{label} DSSE payload must decode to JSON: {exc}")
        return None
    if not isinstance(statement, dict):
        failures.append(f"{label} DSSE payload must decode to a JSON object")
        return None
    return statement


def validate_slsa_attestation(
    attestation: Any,
    digest: str | None,
    names: set[str],
    label: str = "release provenance attestation",
) -> None:
    if not isinstance(attestation, dict):
        failures.append(f"{label} must be an object")
        return
    if attestation.get("format") != "dsse-in-toto-slsa-provenance-v1":
        failures.append(f"{label} must set format='dsse-in-toto-slsa-provenance-v1'")
    if attestation.get("predicate_type") != SLSA_PROVENANCE_V1:
        failures.append(f"{label} must set predicate_type={SLSA_PROVENANCE_V1!r}")
    path = validate_report_artifact_reference(attestation, label)
    if path is None:
        return
    envelope = load_json_file(path, f"{label} file")
    if envelope is None:
        return
    statement = statement_from_dsse_envelope(envelope, label)
    if statement is None:
        return
    if statement.get("_type") != IN_TOTO_STATEMENT_V1:
        failures.append(f"{label} statement must set _type={IN_TOTO_STATEMENT_V1!r}")
    if statement.get("predicateType") != SLSA_PROVENANCE_V1:
        failures.append(f"{label} statement must set predicateType={SLSA_PROVENANCE_V1!r}")
    if digest is not None and not subject_includes_bundle(statement.get("subject"), digest, names, label):
        name_hint = ""
        if names:
            name_hint = f" with name one of {', '.join(sorted(names))}"
        failures.append(f"{label} statement must include release bundle subject digest {digest}{name_hint}")
    predicate = statement.get("predicate")
    if not isinstance(predicate, dict):
        failures.append(f"{label} statement must include predicate object")
        return
    build_definition = predicate.get("buildDefinition")
    if not isinstance(build_definition, dict):
        failures.append(f"{label} predicate must include buildDefinition")
    elif not isinstance(build_definition.get("buildType"), str) or not build_definition.get("buildType"):
        failures.append(f"{label} predicate buildDefinition must include buildType")
    run_details = predicate.get("runDetails")
    builder = run_details.get("builder") if isinstance(run_details, dict) else None
    if not isinstance(builder, dict) or not isinstance(builder.get("id"), str) or not builder.get("id"):
        failures.append(f"{label} predicate runDetails must include builder.id")


def validate_sidecar_artifact(artifact: Any, label: str, *, require_license: bool = False) -> str | None:
    if not isinstance(artifact, dict):
        failures.append(f"{label} must be an object")
        return None
    if not isinstance(artifact.get("name"), str) or not artifact.get("name"):
        failures.append(f"{label} must include name")
    require_local_sidecar_path(artifact.get("path"), label)
    artifact_digest = require_sha256_digest(artifact.get("digest"), f"{label} digest")
    if not isinstance(artifact.get("source"), str) or not artifact.get("source"):
        failures.append(f"{label} must include source")
    if require_license:
        if not isinstance(artifact.get("license"), str) or not artifact.get("license"):
            failures.append(f"{label} must include license")
        if not isinstance(artifact.get("provenance_ref"), str) or not artifact.get("provenance_ref"):
            failures.append(f"{label} must include provenance_ref")
    return artifact_digest


def validate_sidecar_target_smoke_report(
    target: dict[str, Any],
    artifact_digests: dict[str, str | None],
    label: str,
    head: str | None,
) -> None:
    smoke_report_path = validate_report_artifact_reference(target.get("smoke_report"), f"{label} smoke_report")
    if smoke_report_path is None:
        return
    report = load_json_file(smoke_report_path, f"{label} smoke_report file")
    if report is None:
        return

    require_equal(report, "report_schema", 1, f"{label} smoke_report")
    require_equal(report, "release_gate", "release-sidecar-target-smoke", f"{label} smoke_report")
    if head is not None:
        require_equal(report, "subject_commit", head, f"{label} smoke_report")
    require_equal(report, "packages_runtime_or_model", False, f"{label} smoke_report")
    require_equal(report, "auto_downloads", False, f"{label} smoke_report")
    require_equal(report, "external_network_access", False, f"{label} smoke_report")
    for key in ("target_id", "os", "architecture"):
        expected = target.get(key)
        if isinstance(expected, str) and expected:
            require_equal(report, key, expected, f"{label} smoke_report")

    artifacts = report.get("artifacts")
    if not isinstance(artifacts, dict):
        failures.append(f"{label} smoke_report artifacts must be an object")
    else:
        for artifact_key in ("runtime", "model", "smoke_audio_fixture"):
            artifact = artifacts.get(artifact_key)
            if not isinstance(artifact, dict):
                failures.append(f"{label} smoke_report artifacts.{artifact_key} must be an object")
                continue
            target_artifact = target.get(artifact_key)
            expected_name = target_artifact.get("name") if isinstance(target_artifact, dict) else None
            if isinstance(expected_name, str) and expected_name:
                require_equal(artifact, "name", expected_name, f"{label} smoke_report {artifact_key}")
            actual_digest = require_sha256_digest(
                artifact.get("digest"),
                f"{label} smoke_report {artifact_key} digest",
            )
            expected_digest = artifact_digests.get(artifact_key)
            if expected_digest is not None and actual_digest is not None and actual_digest != expected_digest:
                failures.append(
                    f"{label} smoke_report {artifact_key} digest must match target machine {artifact_key} digest"
                )

    smoke = report.get("smoke")
    if not isinstance(smoke, dict):
        failures.append(f"{label} smoke_report smoke must be an object")
    else:
        for key in ("check_dependencies_ok", "whisper_cpp_smoke_passed", "no_auto_downloads_observed"):
            if smoke.get(key) is not True:
                failures.append(f"{label} smoke_report smoke must set {key}=True")


def validate_release_bundle_report(report: dict[str, Any], head: str | None) -> tuple[str | None, set[str]]:
    bundle_digest: str | None = None
    bundle_names: set[str] = set()
    require_equal(report, "report_schema", 1, "release bundle")
    require_equal(report, "release_gate", "release-bundle", "release bundle")
    if head is not None:
        require_equal(report, "subject_commit", head, "release bundle")
    require_non_empty_string(report, "builder", "release bundle")
    require_non_empty_string(report, "source_repository", "release bundle")

    bundle = report.get("bundle")
    if not isinstance(bundle, dict):
        failures.append("release bundle report must include a bundle object")
        return bundle_digest, bundle_names

    bundle_name = bundle.get("name")
    if isinstance(bundle_name, str) and bundle_name:
        bundle_names.add(bundle_name)
    else:
        failures.append("release bundle must include name")
    app_bundle = bundle.get("app_bundle")
    if isinstance(app_bundle, str) and app_bundle:
        bundle_names.add(app_bundle)
    require_equal(bundle, "artifact_type", "macos-app-archive", "release bundle")
    require_equal(bundle, "archive_format", "zip", "release bundle")
    require_equal(bundle, "app_bundle", "MeetingAssistantNative.app", "release bundle")
    bundle_digest = require_sha256_digest(bundle.get("digest"), "release bundle digest")
    return bundle_digest, bundle_names


def find_release_bundle_artifact(artifacts: Any, digest: str, names: set[str]) -> dict[str, Any] | None:
    if not isinstance(artifacts, list):
        return None
    for artifact in artifacts:
        if not isinstance(artifact, dict):
            continue
        artifact_digest = artifact.get("digest")
        if not isinstance(artifact_digest, str) or artifact_digest.lower() != digest:
            continue
        artifact_name = artifact.get("name")
        if names and artifact_name not in names:
            continue
        return artifact
    return None


def require_release_bundle_artifact(artifacts: Any, label: str, digest: str | None, names: set[str]) -> None:
    if digest is None or not isinstance(artifacts, list) or not artifacts:
        return
    if find_release_bundle_artifact(artifacts, digest, names) is not None:
        return
    name_hint = ""
    if names:
        name_hint = f" with name one of {', '.join(sorted(names))}"
    failures.append(f"{label} report must include release bundle artifact digest {digest}{name_hint}")


def require_release_signature_evidence(artifacts: Any, digest: str | None, names: set[str]) -> None:
    if digest is None:
        return
    artifact = find_release_bundle_artifact(artifacts, digest, names)
    if artifact is None:
        return
    if artifact.get("signature_type") != supply_chain.get("artifact_signing"):
        failures.append(
            "release signature artifact for release bundle must set "
            f"signature_type={supply_chain.get('artifact_signing')!r}"
        )
    if not isinstance(artifact.get("certificate_identity"), str) or not artifact.get("certificate_identity"):
        failures.append("release signature artifact for release bundle must include certificate_identity")
    if not isinstance(artifact.get("certificate_issuer"), str) or not artifact.get("certificate_issuer"):
        failures.append("release signature artifact for release bundle must include certificate_issuer")
    transparency_log = artifact.get("transparency_log")
    if not isinstance(transparency_log, dict):
        failures.append("release signature artifact for release bundle must include transparency_log object")
    else:
        if not isinstance(transparency_log.get("log_id"), str) or not transparency_log.get("log_id"):
            failures.append("release signature artifact transparency_log must include log_id")
        if not isinstance(transparency_log.get("log_index"), int) or transparency_log.get("log_index") < 0:
            failures.append("release signature artifact transparency_log must include non-negative log_index")
    signature_bundle = artifact.get("signature_bundle")
    if isinstance(signature_bundle, dict) and signature_bundle.get("format") != "sigstore-bundle-json":
        failures.append("release signature artifact signature_bundle must set format='sigstore-bundle-json'")
    validate_report_artifact_reference(signature_bundle, "release signature artifact signature_bundle")


bundle_report_path = resolve_evidence_path(
    "MEETING_ASSISTANT_RELEASE_BUNDLE_REPORT",
    ".harness/release-inputs/bundle/release-bundle-report.json",
)
provenance_path = resolve_evidence_path(
    "MEETING_ASSISTANT_RELEASE_PROVENANCE_REPORT",
    ".harness/release-inputs/supply-chain/release-provenance-report.json",
)
signature_path = resolve_evidence_path(
    "MEETING_ASSISTANT_RELEASE_SIGNATURE_REPORT",
    ".harness/release-inputs/supply-chain/release-signature-report.json",
)
sidecar_path = resolve_evidence_path(
    "MEETING_ASSISTANT_RELEASE_SIDECAR_REPORT",
    ".harness/release-inputs/supply-chain/release-sidecar-report.json",
)

head = current_commit()
bundle_report = load_report(bundle_report_path, "release bundle")
provenance = load_report(provenance_path, "release provenance")
signature = load_report(signature_path, "release signature")
sidecar = load_report(sidecar_path, "release sidecar")

release_bundle_digest: str | None = None
release_bundle_names: set[str] = set()
if bundle_report is not None:
    release_bundle_digest, release_bundle_names = validate_release_bundle_report(bundle_report, head)

if provenance is not None:
    require_equal(provenance, "report_schema", 1, "release provenance")
    require_equal(provenance, "provenance_target", supply_chain.get("provenance_target"), "release provenance")
    require_equal(provenance, "release_provenance_attestation", "produced", "release provenance")
    require_equal(provenance, "sbom_format", supply_chain.get("sbom_format"), "release provenance")
    if head is not None:
        require_equal(provenance, "subject_commit", head, "release provenance")
    if not isinstance(provenance.get("builder"), str) or not provenance.get("builder"):
        failures.append("release provenance report must identify builder")
    if not isinstance(provenance.get("source_repository"), str) or not provenance.get("source_repository"):
        failures.append("release provenance report must identify source_repository")
    artifacts = provenance.get("artifacts")
    if not isinstance(artifacts, list) or not artifacts:
        failures.append("release provenance report must include at least one artifact")
    else:
        for index, artifact in enumerate(artifacts):
            if not isinstance(artifact, dict):
                failures.append(f"release provenance artifact #{index} must be an object")
                continue
            if not isinstance(artifact.get("name"), str) or not artifact.get("name"):
                failures.append(f"release provenance artifact #{index} must include name")
            require_sha256_digest(artifact.get("digest"), f"release provenance artifact #{index} digest")
        require_release_bundle_artifact(
            artifacts,
            "release provenance",
            release_bundle_digest,
            release_bundle_names,
        )
        validate_slsa_attestation(
            provenance.get("attestation"),
            release_bundle_digest,
            release_bundle_names,
        )

if signature is not None:
    require_equal(signature, "report_schema", 1, "release signature")
    require_equal(signature, "artifact_signing", supply_chain.get("artifact_signing"), "release signature")
    require_equal(signature, "signing_status", "signed", "release signature")
    if head is not None:
        require_equal(signature, "subject_commit", head, "release signature")
    if not isinstance(signature.get("verifier"), str) or not signature.get("verifier"):
        failures.append("release signature report must identify verifier")
    signed_artifacts = signature.get("signed_artifacts")
    if not isinstance(signed_artifacts, list) or not signed_artifacts:
        failures.append("release signature report must include at least one signed_artifact")
    else:
        for index, artifact in enumerate(signed_artifacts):
            if not isinstance(artifact, dict):
                failures.append(f"release signature artifact #{index} must be an object")
                continue
            if not isinstance(artifact.get("name"), str) or not artifact.get("name"):
                failures.append(f"release signature artifact #{index} must include name")
            require_sha256_digest(artifact.get("digest"), f"release signature artifact #{index} digest")
            if not isinstance(artifact.get("signature_type"), str) or not artifact.get("signature_type"):
                failures.append(f"release signature artifact #{index} must include signature_type")
        require_release_bundle_artifact(
            signed_artifacts,
            "release signature",
            release_bundle_digest,
            release_bundle_names,
        )
        require_release_signature_evidence(
            signed_artifacts,
            release_bundle_digest,
            release_bundle_names,
        )

if sidecar is not None:
    require_equal(sidecar, "report_schema", 1, "release sidecar")
    require_equal(sidecar, "release_gate", "release-sidecar-portability", "release sidecar")
    require_equal(sidecar, "target_scope", "all-target-machines", "release sidecar")
    require_equal(sidecar, "packages_runtime_or_model", False, "release sidecar")
    require_equal(sidecar, "auto_downloads", False, "release sidecar")
    require_equal(sidecar, "external_network_access", False, "release sidecar")
    if head is not None:
        require_equal(sidecar, "subject_commit", head, "release sidecar")
    require_non_empty_string(sidecar, "builder", "release sidecar")
    require_non_empty_string(sidecar, "source_repository", "release sidecar")
    target_machines = sidecar.get("target_machines")
    if not isinstance(target_machines, list) or not target_machines:
        failures.append("release sidecar report must include at least one target_machine")
    else:
        for index, target in enumerate(target_machines):
            label = f"release sidecar target_machine #{index}"
            if not isinstance(target, dict):
                failures.append(f"{label} must be an object")
                continue
            for key in ("target_id", "os", "architecture"):
                if not isinstance(target.get(key), str) or not target.get(key):
                    failures.append(f"{label} must include {key}")
            artifact_digests = {
                "runtime": validate_sidecar_artifact(target.get("runtime"), f"{label} runtime"),
                "model": validate_sidecar_artifact(target.get("model"), f"{label} model", require_license=True),
                "smoke_audio_fixture": validate_sidecar_artifact(
                    target.get("smoke_audio_fixture"),
                    f"{label} smoke_audio_fixture",
                ),
            }
            smoke = target.get("smoke")
            if not isinstance(smoke, dict):
                failures.append(f"{label} smoke must be an object")
            else:
                for key in ("check_dependencies_ok", "whisper_cpp_smoke_passed", "no_auto_downloads_observed"):
                    if smoke.get(key) is not True:
                        failures.append(f"{label} smoke must set {key}=True")
            validate_sidecar_target_smoke_report(target, artifact_digests, label, head)

if failures:
    print("release supply-chain bundle/provenance/signing/sidecar evidence failed:", file=sys.stderr)
    for failure in failures:
        print(f" - {failure}", file=sys.stderr)
    raise SystemExit(1)

print("release supply-chain bundle/provenance/signing/sidecar evidence passed.")
PY
fi

echo "supply-chain-check passed: phase=$phase."
