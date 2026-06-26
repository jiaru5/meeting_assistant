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
    "tests/ArchitectureTest.md",
    "sbom/processing-cli.cdx.json",
]
missing = [path for path in required if not (root / path).is_file()]
if missing:
    raise SystemExit(f"processing-cli lint failed: missing {missing}")

metadata = json.loads((root / "component.json").read_text(encoding="utf-8"))
if metadata.get("id") != "processing-cli":
    raise SystemExit("processing-cli lint failed: component id mismatch")
if metadata.get("business_behavior") != "none":
    raise SystemExit("processing-cli lint failed: business behavior must remain none")
PY

echo "processing-cli lint passed."
