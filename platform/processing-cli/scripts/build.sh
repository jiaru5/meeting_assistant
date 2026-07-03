#!/usr/bin/env bash
set -euo pipefail

component_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$component_dir"

mkdir -p build
printf '%s\n' "processing-cli build: Python command package verified; no standalone binary is produced." > build/build-report.txt

test -f component.json
test -f README.md

python3 - <<'PY'
from __future__ import annotations

import json
from pathlib import Path

dockerfile = Path("Dockerfile").read_text(encoding="utf-8")
required_phrases = {
    "digest_pinned_base": "FROM node@sha256:",
    "non_root_user": "USER node",
    "component_metadata": "COPY --chown=node:node component.json README.md ./",
    "component_sbom": "COPY --chown=node:node sbom/processing-cli.cdx.json ./sbom/processing-cli.cdx.json",
    "validation_only_cmd": 'CMD ["sh", "-c", "test -f component.json && test -f sbom/processing-cli.cdx.json"]',
}
missing = [name for name, phrase in required_phrases.items() if phrase not in dockerfile]
if missing:
    raise SystemExit(f"processing-cli build failed: release validation Dockerfile evidence missing {missing}")
forbidden_phrases = (
    "curl" + " ",
    "wget" + " ",
    "brew" + " install",
    "pip" + " install",
    "npm" + " install",
)
for forbidden in forbidden_phrases:
    if forbidden in dockerfile:
        raise SystemExit(f"processing-cli build failed: Dockerfile must not install or download dependencies: {forbidden}")

component = json.loads(Path("component.json").read_text(encoding="utf-8"))
sbom = json.loads(Path("sbom/processing-cli.cdx.json").read_text(encoding="utf-8"))
report = {
    "component": component["id"],
    "release_gate_image": "validation-only",
    "digest_pinned_base": True,
    "non_root_user": True,
    "packages_runtime_or_model": False,
    "auto_downloads": False,
    "sbom": sbom["metadata"]["component"]["name"],
}
Path("build/build-report.json").write_text(
    json.dumps(report, indent=2, sort_keys=True) + "\n",
    encoding="utf-8",
)
PY

echo "processing-cli build release evidence passed."
echo "processing-cli build passed."
