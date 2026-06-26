#!/usr/bin/env bash
set -euo pipefail

component_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$component_dir"

python3 - <<'PY'
import json
from pathlib import Path

sbom = json.loads(Path("sbom/processing-cli.cdx.json").read_text(encoding="utf-8"))
if sbom.get("bomFormat") != "CycloneDX":
    raise SystemExit("processing-cli sbom failed: bomFormat must be CycloneDX")
if sbom.get("metadata", {}).get("component", {}).get("name") != "meeting-assistant-processing-cli":
    raise SystemExit("processing-cli sbom failed: component name mismatch")
PY

echo "processing-cli sbom check passed."
