#!/usr/bin/env bash
set -euo pipefail

component_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$component_dir"

mkdir -p build
tmp_dir="$(mktemp -d)"
trap 'rm -rf "$tmp_dir"' EXIT
ln -s "$component_dir/Sources" "$tmp_dir/Sources"
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
    ]
)
SWIFT

(cd "$tmp_dir" && swift build)
xcodebuild build \
  -configuration Debug \
  -project "$component_dir/MeetingAssistantNative.xcodeproj" \
  -scheme "MeetingAssistantNative" \
  -destination 'platform=macOS' \
  -derivedDataPath "$tmp_dir/DerivedData"
xcodebuild build \
  -configuration Release \
  -project "$component_dir/MeetingAssistantNative.xcodeproj" \
  -scheme "MeetingAssistantNative" \
  -destination 'platform=macOS' \
  -derivedDataPath "$tmp_dir/DerivedData"
test -d "$tmp_dir/DerivedData/Build/Products/Debug/MeetingAssistantNative.app"
test -d "$tmp_dir/DerivedData/Build/Products/Release/MeetingAssistantNative.app"
printf '%s\n' "native-app VS-MA-12/VS-MA-15/VS-MA-16/VS-MA-17/VS-MA-18/VS-MA-19 build: Swift permission/dependency status, fake recording target, controlled native capture artifact registration, Apple ScreenCaptureKit native capture adapter, processing state consumer, read-only workspace transcript loader, deterministic transcript actions with guarded process-runner hook, and Debug plus Release app bundles compiled." > build/build-report.txt

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
    "component_sbom": "COPY --chown=node:node sbom/native-app.cdx.json ./sbom/native-app.cdx.json",
    "validation_only_cmd": 'CMD ["sh", "-c", "test -f component.json && test -f sbom/native-app.cdx.json"]',
}
missing = [name for name, phrase in required_phrases.items() if phrase not in dockerfile]
if missing:
    raise SystemExit(f"native-app build failed: release validation Dockerfile evidence missing {missing}")
forbidden_phrases = (
    "curl" + " ",
    "wget" + " ",
    "brew" + " install",
    "pip" + " install",
    "npm" + " install",
)
for forbidden in forbidden_phrases:
    if forbidden in dockerfile:
        raise SystemExit(f"native-app build failed: Dockerfile must not install or download dependencies: {forbidden}")

component = json.loads(Path("component.json").read_text(encoding="utf-8"))
sbom = json.loads(Path("sbom/native-app.cdx.json").read_text(encoding="utf-8"))
report = {
    "component": component["id"],
    "release_gate_image": "validation-only",
    "digest_pinned_base": True,
    "non_root_user": True,
    "packages_macos_app": False,
    "packages_runtime_or_model": False,
    "auto_downloads": False,
    "sbom": sbom["metadata"]["component"]["name"],
}
Path("build/build-report.json").write_text(
    json.dumps(report, indent=2, sort_keys=True) + "\n",
    encoding="utf-8",
)
PY

echo "native-app build release evidence passed."
echo "native-app build passed."
