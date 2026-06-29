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
    "MeetingAssistantNative.xcodeproj/project.pbxproj",
    "MeetingAssistantNative.xcodeproj/xcshareddata/xcschemes/MeetingAssistantNative.xcscheme",
    "App/MeetingAssistantNativeApp.swift",
    "tests/ArchitectureTest.md",
    "Sources/MeetingAssistantNative/DependencyCheckContract.swift",
    "Sources/MeetingAssistantNative/DependencyCheckProcessRunner.swift",
    "Sources/MeetingAssistantNative/PermissionDependencyStatusViewModel.swift",
    "Sources/MeetingAssistantNative/PermissionDependencyStatusView.swift",
    "Sources/MeetingAssistantNative/RecordingCommandClient.swift",
    "Sources/MeetingAssistantNative/RecordingFakeCommandClient.swift",
    "Sources/MeetingAssistantNative/RecordingControlViewModel.swift",
    "Sources/MeetingAssistantNative/RecordingControlView.swift",
    "Sources/MeetingAssistantNative/TranscriptReviewReadModel.swift",
    "Sources/MeetingAssistantNative/TranscriptReviewViewModel.swift",
    "Sources/MeetingAssistantNative/TranscriptReviewView.swift",
    "tests/MeetingAssistantNativeTests/PermissionDependencyStatusViewModelTests.swift",
    "tests/MeetingAssistantNativeTests/RecordingControlViewModelTests.swift",
    "tests/MeetingAssistantNativeTests/TranscriptReviewViewModelTests.swift",
    "UITests/MeetingAssistantNativeUITests/NativeControlPlaneSmokeTests.swift",
    "UITests/MeetingAssistantNativeAppUITests/AppBundleLocatorSmokeTests.swift",
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
expected_behavior = "permission_dependency_status_fake_recording_and_transcript_review"
if metadata.get("business_behavior") != expected_behavior:
    raise SystemExit(f"native-app lint failed: business behavior must be {expected_behavior}")

project = (root / "MeetingAssistantNative.xcodeproj/project.pbxproj").read_text(encoding="utf-8")
required_project_snippets = [
    "MeetingAssistantNative.app",
    "MeetingAssistantNativeAppUITests.xctest",
    "AppBundleLocatorSmokeTests.swift",
    "MeetingAssistantNativeApp.swift",
    "TranscriptReviewReadModel.swift",
    "TranscriptReviewViewModel.swift",
    "TranscriptReviewView.swift",
]
missing_project_snippets = [snippet for snippet in required_project_snippets if snippet not in project]
if missing_project_snippets:
    raise SystemExit(f"native-app lint failed: xcodeproj missing {missing_project_snippets}")
PY

echo "native-app lint passed."
