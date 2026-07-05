#!/usr/bin/env bash
set -euo pipefail

component_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$component_dir"

python3 - <<'PY'
import json
from pathlib import Path

sbom = json.loads(Path("sbom/processing-cli.cdx.json").read_text(encoding="utf-8"))
metadata = sbom.get("metadata", {})
component = metadata.get("component", {})
if sbom.get("bomFormat") != "CycloneDX":
    raise SystemExit("processing-cli sbom failed: bomFormat must be CycloneDX")
if sbom.get("specVersion") != "1.5":
    raise SystemExit("processing-cli sbom failed: specVersion must be 1.5")
if component.get("name") != "meeting-assistant-processing-cli":
    raise SystemExit("processing-cli sbom failed: component name mismatch")
if component.get("type") != "application":
    raise SystemExit("processing-cli sbom failed: component type must be application")
component_license_ids = {
    entry.get("license", {}).get("id")
    for entry in component.get("licenses", [])
    if isinstance(entry, dict)
}
if "Apache-2.0" not in component_license_ids:
    raise SystemExit("processing-cli sbom failed: component license evidence must include Apache-2.0")
if not str(sbom.get("serialNumber", "")).startswith("urn:uuid:"):
    raise SystemExit("processing-cli sbom failed: serialNumber must be a stable urn:uuid")
if sbom.get("components") != []:
    raise SystemExit("processing-cli sbom failed: packaged third-party components must remain explicit")

properties = {
    prop.get("name"): prop.get("value")
    for prop in metadata.get("properties", [])
    if isinstance(prop, dict)
}
required_properties = {
    "meeting-assistant:license-evidence": "Apache-2.0",
    "meeting-assistant:packaged-third-party-runtime-components": "none",
    "meeting-assistant:release-gate-image": "validation-only",
}
for name, expected in required_properties.items():
    if properties.get(name) != expected:
        raise SystemExit(f"processing-cli sbom failed: metadata property {name} must be {expected}")

dockerfile = Path("Dockerfile").read_text(encoding="utf-8")
if "COPY --chown=node:node sbom/processing-cli.cdx.json ./sbom/processing-cli.cdx.json" not in dockerfile:
    raise SystemExit("processing-cli sbom failed: release validation image must copy the component SBOM")
if "FROM node@sha256:" not in dockerfile or "USER node" not in dockerfile:
    raise SystemExit("processing-cli sbom failed: release validation image must be digest-pinned and non-root")
PY

echo "processing-cli sbom release evidence passed."
echo "processing-cli sbom check passed."
