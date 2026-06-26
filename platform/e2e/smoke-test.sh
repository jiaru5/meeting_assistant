#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
cd "$ROOT_DIR"

test -f platform/native-app/component.json
test -f platform/processing-cli/component.json
test -f platform/native-app/tests/ArchitectureTest.md
test -f platform/processing-cli/tests/ArchitectureTest.md

python3 - <<'PY'
import json
from pathlib import Path

manifest = json.loads(Path("harness/project-manifest.json").read_text(encoding="utf-8"))
component_ids = {component["id"] for component in manifest["components"]}
required = {"native-app", "processing-cli"}
missing = required - component_ids
if missing:
    raise SystemExit(f"local smoke failed: missing manifest components {sorted(missing)}")
PY

echo "local e2e smoke passed."
