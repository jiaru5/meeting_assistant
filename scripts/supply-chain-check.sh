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


def require_sha256_digest(value: Any, label: str) -> None:
    if not isinstance(value, str) or re.fullmatch(r"sha256:[a-fA-F0-9]{64}", value) is None:
        failures.append(f"{label} must be a sha256:<64 hex> digest")


provenance_path = resolve_evidence_path(
    "MEETING_ASSISTANT_RELEASE_PROVENANCE_REPORT",
    ".harness/release-inputs/supply-chain/release-provenance-report.json",
)
signature_path = resolve_evidence_path(
    "MEETING_ASSISTANT_RELEASE_SIGNATURE_REPORT",
    ".harness/release-inputs/supply-chain/release-signature-report.json",
)

head = current_commit()
provenance = load_report(provenance_path, "release provenance")
signature = load_report(signature_path, "release signature")

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

if failures:
    print("release supply-chain provenance/signing evidence failed:", file=sys.stderr)
    for failure in failures:
        print(f" - {failure}", file=sys.stderr)
    raise SystemExit(1)

print("release supply-chain provenance/signing evidence passed.")
PY
fi

echo "supply-chain-check passed: phase=$phase."
