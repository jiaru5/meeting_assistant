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
printf '%s\n' "native-app VS-MA-12/VS-MA-13 build: Swift permission/dependency status and fake recording target compiled." > build/build-report.txt

test -f component.json
test -f README.md

echo "native-app build passed."
