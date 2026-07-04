#!/usr/bin/env bash
set -euo pipefail

component_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$component_dir"

python3 - <<'PY'
import json
from pathlib import Path

sbom = json.loads(Path("sbom/native-app.cdx.json").read_text(encoding="utf-8"))
if sbom.get("bomFormat") != "CycloneDX":
    raise SystemExit("native-app sbom failed: bomFormat must be CycloneDX")
if sbom.get("specVersion") != "1.5":
    raise SystemExit("native-app sbom failed: specVersion must be 1.5")
if sbom.get("metadata", {}).get("component", {}).get("name") != "meeting-assistant-native-app":
    raise SystemExit("native-app sbom failed: component name mismatch")
if sbom.get("metadata", {}).get("component", {}).get("type") != "application":
    raise SystemExit("native-app sbom failed: component type must be application")
if not str(sbom.get("serialNumber", "")).startswith("urn:uuid:"):
    raise SystemExit("native-app sbom failed: serialNumber must be a stable urn:uuid")
if sbom.get("components") != []:
    raise SystemExit("native-app sbom failed: packaged third-party components must remain explicit")

dockerfile = Path("Dockerfile").read_text(encoding="utf-8")
if "COPY --chown=node:node sbom/native-app.cdx.json ./sbom/native-app.cdx.json" not in dockerfile:
    raise SystemExit("native-app sbom failed: release validation image must copy the component SBOM")
if "FROM node@sha256:" not in dockerfile or "USER node" not in dockerfile:
    raise SystemExit("native-app sbom failed: release validation image must be digest-pinned and non-root")
PY

echo "native-app sbom release evidence passed."
echo "native-app sbom check passed."
