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

echo "supply-chain-check passed: phase=$phase."
