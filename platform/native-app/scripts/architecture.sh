#!/usr/bin/env bash
set -euo pipefail

component_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$component_dir"

test -f tests/ArchitectureTest.md
grep -q "Component: \`native-app\`" tests/ArchitectureTest.md
grep -q "VS-MA-12 boundary" tests/ArchitectureTest.md
grep -q "check_dependencies" tests/ArchitectureTest.md
test -f Sources/MeetingAssistantNative/DependencyCheckContract.swift
test -f Sources/MeetingAssistantNative/PermissionDependencyStatusViewModel.swift
test -f Sources/MeetingAssistantNative/PermissionDependencyStatusView.swift

grep -R -q "check_dependencies" Sources tests
grep -R -q "ma.permissionDependency" Sources tests

if grep -R -n -E 'start_native_recording|stop_recording|ScreenCaptureKit|AVCapture|normalize_audio|URLSession|API_KEY|SECRET|TOKEN' Sources tests; then
  echo "native-app architecture check failed: VS-MA-12 must not implement recording, capture, public normalize audio, external network calls or secrets." >&2
  exit 1
fi

echo "native-app architecture check passed."
