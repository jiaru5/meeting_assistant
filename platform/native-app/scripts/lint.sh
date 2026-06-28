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
    "Sources/MeetingAssistantNative/DependencyCheckContract.swift",
    "Sources/MeetingAssistantNative/DependencyCheckProcessRunner.swift",
    "Sources/MeetingAssistantNative/PermissionDependencyStatusViewModel.swift",
    "Sources/MeetingAssistantNative/PermissionDependencyStatusView.swift",
    "tests/MeetingAssistantNativeTests/PermissionDependencyStatusViewModelTests.swift",
    "sbom/native-app.cdx.json",
]
missing = [path for path in required if not (root / path).is_file()]
if missing:
    raise SystemExit(f"native-app lint failed: missing {missing}")

metadata = json.loads((root / "component.json").read_text(encoding="utf-8"))
if metadata.get("id") != "native-app":
    raise SystemExit("native-app lint failed: component id mismatch")
if metadata.get("kind") != "project-component":
    raise SystemExit("native-app lint failed: component kind must be project-component")
if metadata.get("business_behavior") != "permission_dependency_status":
    raise SystemExit("native-app lint failed: business behavior must be permission_dependency_status")
PY

echo "native-app lint passed."
