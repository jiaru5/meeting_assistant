#!/usr/bin/env bash
set -euo pipefail

component_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$component_dir"

PYTHONPATH=src python3 -m unittest discover -s tests

python3 - <<'PY'
import json
from pathlib import Path

metadata = json.loads(Path("component.json").read_text(encoding="utf-8"))
if metadata.get("business_behavior") != "dependency_check_artifact_contract_import_media":
    raise SystemExit("processing-cli test failed: dependency_check_artifact_contract_import_media behavior is missing")
implemented_contracts = set(metadata.get("implemented_contracts", []))
required_contracts = {"check_dependencies", "workspace_artifact_contract", "import_media"}
if not required_contracts.issubset(implemented_contracts):
    raise SystemExit("processing-cli test failed: implemented contracts are incomplete")
if metadata.get("allowed_before_project_mode") is not False:
    raise SystemExit("processing-cli test failed: project behavior cannot be allowed before project mode")

architecture = Path("tests/ArchitectureTest.md").read_text(encoding="utf-8")
required_phrases = (
    "Component: `processing-cli`",
    "implements the `check_dependencies` command contract",
    "implements the workspace artifact contract kernel",
    "implements the `import_media` command contract",
    "must not implement media processing",
    "must not transcode",
    "Missing required dependencies must be reported as `ok: false`",
)
missing = [phrase for phrase in required_phrases if phrase not in architecture]
if missing:
    raise SystemExit(f"processing-cli test failed: missing architecture phrases {missing}")
PY

echo "processing-cli tests passed."
