#!/usr/bin/env bash
set -euo pipefail

component_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$component_dir"

for script in scripts/*.sh; do
  bash -n "$script"
done

python3 - <<'PY'
import json
from pathlib import Path

root = Path(".")
required = [
    "README.md",
    "component.json",
    "src/meeting_assistant_cli/__main__.py",
    "src/meeting_assistant_cli/audio_processing.py",
    "src/meeting_assistant_cli/cli.py",
    "src/meeting_assistant_cli/dependency_check.py",
    "src/meeting_assistant_cli/import_media.py",
    "src/meeting_assistant_cli/settings.py",
    "src/meeting_assistant_cli/workspace_contract.py",
    "tests/ArchitectureTest.md",
    "tests/test_audio_processing.py",
    "tests/test_dependency_check.py",
    "tests/test_import_media.py",
    "tests/test_workspace_contract.py",
    "sbom/processing-cli.cdx.json",
]
missing = [path for path in required if not (root / path).is_file()]
if missing:
    raise SystemExit(f"processing-cli lint failed: missing {missing}")

metadata = json.loads((root / "component.json").read_text(encoding="utf-8"))
if metadata.get("id") != "processing-cli":
    raise SystemExit("processing-cli lint failed: component id mismatch")
if metadata.get("business_behavior") != "dependency_check_artifact_contract_import_media_audio_normalization":
    raise SystemExit("processing-cli lint failed: business behavior must be dependency_check_artifact_contract_import_media_audio_normalization")
implemented_contracts = set(metadata.get("implemented_contracts", []))
if {
    "check_dependencies",
    "workspace_artifact_contract",
    "import_media",
    "audio_source_selection",
    "normalized_audio_stage",
} - implemented_contracts:
    raise SystemExit("processing-cli lint failed: implemented contract list is incomplete")
PY

python3 -m py_compile src/meeting_assistant_cli/*.py tests/*.py

echo "processing-cli lint passed."
