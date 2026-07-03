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

echo "native-app build passed."
