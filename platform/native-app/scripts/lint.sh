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
    "Sources/MeetingAssistantNative/TranscriptReviewWorkspaceLoader.swift",
    "Sources/MeetingAssistantNative/TranscriptReviewViewModel.swift",
    "Sources/MeetingAssistantNative/TranscriptReviewView.swift",
    "Sources/MeetingAssistantNative/TranscriptActionCommandClient.swift",
    "Sources/MeetingAssistantNative/TranscriptActionFakeCommandClient.swift",
    "Sources/MeetingAssistantNative/TranscriptReviewActionsViewModel.swift",
    "Sources/MeetingAssistantNative/TranscriptReviewActionsView.swift",
    "Sources/MeetingAssistantNative/ProcessingCommandClient.swift",
    "Sources/MeetingAssistantNative/ProcessingCommandProcessRunner.swift",
    "Sources/MeetingAssistantNative/ProcessingCommandFakeClient.swift",
    "Sources/MeetingAssistantNative/ProcessingStateViewModel.swift",
    "Sources/MeetingAssistantNative/ProcessingStateView.swift",
    "test-fixtures/processing-command-fixture.sh",
    "tests/MeetingAssistantNativeTests/PermissionDependencyStatusViewModelTests.swift",
    "tests/MeetingAssistantNativeTests/RecordingControlViewModelTests.swift",
    "tests/MeetingAssistantNativeTests/TranscriptReviewViewModelTests.swift",
    "tests/MeetingAssistantNativeTests/TranscriptReviewActionsViewModelTests.swift",
    "tests/MeetingAssistantNativeTests/ProcessingStateViewModelTests.swift",
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
expected_behavior = "permission_dependency_status_fake_recording_processing_state_transcript_review_and_actions"
if metadata.get("business_behavior") != expected_behavior:
    raise SystemExit(f"native-app lint failed: business behavior must be {expected_behavior}")
if "read_only_workspace_transcript_loading" not in metadata.get("allowed_capabilities", []):
    raise SystemExit("native-app lint failed: missing read-only workspace transcript loading capability")
if "fake_transcript_action_command_client" not in metadata.get("allowed_capabilities", []):
    raise SystemExit("native-app lint failed: missing fake transcript action capability")
if "processing_command_consumer" not in metadata.get("allowed_capabilities", []):
    raise SystemExit("native-app lint failed: missing processing command consumer capability")

project = (root / "MeetingAssistantNative.xcodeproj/project.pbxproj").read_text(encoding="utf-8")
required_project_snippets = [
    "MeetingAssistantNative.app",
    "MeetingAssistantNativeAppUITests.xctest",
    "AppBundleLocatorSmokeTests.swift",
    "MeetingAssistantNativeApp.swift",
    "TranscriptReviewReadModel.swift",
    "TranscriptReviewWorkspaceLoader.swift",
    "TranscriptReviewViewModel.swift",
    "TranscriptReviewView.swift",
    "TranscriptActionCommandClient.swift",
    "TranscriptActionFakeCommandClient.swift",
    "TranscriptReviewActionsViewModel.swift",
    "TranscriptReviewActionsView.swift",
    "ProcessingCommandClient.swift",
    "ProcessingCommandProcessRunner.swift",
    "ProcessingCommandFakeClient.swift",
    "ProcessingStateViewModel.swift",
    "ProcessingStateView.swift",
]
missing_project_snippets = [snippet for snippet in required_project_snippets if snippet not in project]
if missing_project_snippets:
    raise SystemExit(f"native-app lint failed: xcodeproj missing {missing_project_snippets}")
PY

echo "native-app lint passed."
