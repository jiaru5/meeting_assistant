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
    "src/meeting_assistant_cli/cli.py",
    "src/meeting_assistant_cli/dependency_check.py",
    "tests/ArchitectureTest.md",
    "tests/test_dependency_check.py",
    "sbom/processing-cli.cdx.json",
]
missing = [path for path in required if not (root / path).is_file()]
if missing:
    raise SystemExit(f"processing-cli lint failed: missing {missing}")

metadata = json.loads((root / "component.json").read_text(encoding="utf-8"))
if metadata.get("id") != "processing-cli":
    raise SystemExit("processing-cli lint failed: component id mismatch")
if metadata.get("business_behavior") != "dependency_check":
    raise SystemExit("processing-cli lint failed: business behavior must be dependency_check")
PY

python3 -m py_compile src/meeting_assistant_cli/*.py tests/*.py

echo "processing-cli lint passed."
