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
if metadata.get("business_behavior") != "permission_dependency_status":
    raise SystemExit("native-app test failed: business behavior must be permission_dependency_status")
if metadata.get("allowed_before_project_mode") is not False:
    raise SystemExit("native-app test failed: project component cannot be allowed before project mode")

architecture = Path("tests/ArchitectureTest.md").read_text(encoding="utf-8")
required_phrases = (
    "Component: `native-app`",
    "VS-MA-12 boundary",
    "check_dependencies",
    "must not implement recording",
)
missing = [phrase for phrase in required_phrases if phrase not in architecture]
if missing:
    raise SystemExit(f"native-app test failed: missing architecture phrases {missing}")

required_paths = (
    Path("Sources/MeetingAssistantNative/DependencyCheckContract.swift"),
    Path("Sources/MeetingAssistantNative/DependencyCheckProcessRunner.swift"),
    Path("Sources/MeetingAssistantNative/PermissionDependencyStatusViewModel.swift"),
    Path("Sources/MeetingAssistantNative/PermissionDependencyStatusView.swift"),
    Path("tests/MeetingAssistantNativeTests/PermissionDependencyStatusViewModelTests.swift"),
)
missing_paths = [str(path) for path in required_paths if not path.is_file()]
if missing_paths:
    raise SystemExit(f"native-app test failed: missing Swift status surface files {missing_paths}")
PY

tmp_dir="$(mktemp -d)"
trap 'rm -rf "$tmp_dir"' EXIT
ln -s "$component_dir/Sources" "$tmp_dir/Sources"
ln -s "$component_dir/tests" "$tmp_dir/tests"
cat > "$tmp_dir/Package.swift" <<'SWIFT'
// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "MeetingAssistantNativePackage",
    platforms: [.macOS(.v14)],
    products: [
        .library(name: "MeetingAssistantNative", targets: ["MeetingAssistantNative"]),
    ],
    targets: [
        .target(name: "MeetingAssistantNative"),
        .testTarget(
            name: "MeetingAssistantNativeTests",
            dependencies: ["MeetingAssistantNative"],
            path: "tests/MeetingAssistantNativeTests"
        ),
    ]
)
SWIFT

(cd "$tmp_dir" && swift test)

echo "native-app tests passed."
