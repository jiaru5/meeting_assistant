#!/usr/bin/env bash
set -euo pipefail

component_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$component_dir"

python3 - <<'PY'
import json
from pathlib import Path

metadata = json.loads(Path("component.json").read_text(encoding="utf-8"))
if metadata.get("kind") != "project-component":
    raise SystemExit("native-app test failed: component kind must be project-component")
if metadata.get("business_behavior") != "none":
    raise SystemExit("native-app test failed: project skeleton must not claim business behavior")
if metadata.get("allowed_before_project_mode") is not False:
    raise SystemExit("native-app test failed: project component cannot be allowed before project mode")

architecture = Path("tests/ArchitectureTest.md").read_text(encoding="utf-8")
required_phrases = (
    "Component: `native-app`",
    "non-business project skeleton",
    "must not implement recording",
)
missing = [phrase for phrase in required_phrases if phrase not in architecture]
if missing:
    raise SystemExit(f"native-app test failed: missing architecture phrases {missing}")
PY

echo "native-app tests passed."
