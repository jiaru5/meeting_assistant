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
    "scripts/test-app-bundle.sh",
    "scripts/native-capture-smoke.sh",
    "App/MeetingAssistantNativeApp.swift",
    "tests/ArchitectureTest.md",
    "Sources/MeetingAssistantNative/DependencyCheckContract.swift",
    "Sources/MeetingAssistantNative/DependencyCheckProcessRunner.swift",
    "Sources/MeetingAssistantNative/PermissionDependencyStatusViewModel.swift",
    "Sources/MeetingAssistantNative/PermissionDependencyStatusView.swift",
    "Sources/MeetingAssistantNative/RecordingCommandClient.swift",
    "Sources/MeetingAssistantNative/RecordingFakeCommandClient.swift",
    "Sources/MeetingAssistantNative/NativeCaptureAdapter.swift",
    "Sources/MeetingAssistantNative/ControlledNativeCaptureAdapter.swift",
    "Sources/MeetingAssistantNative/AppleScreenCaptureKitNativeCaptureAdapter.swift",
    "Sources/MeetingAssistantNative/RecordingSessionStore.swift",
    "Sources/MeetingAssistantNative/NativeRecordingCommandClient.swift",
    "Sources/MeetingAssistantNative/NativeCapturePermissionChecker.swift",
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
    "Sources/MeetingAssistantNative/DesignedNativeShellViewModel.swift",
    "Sources/MeetingAssistantNative/DesignedNativeShellView.swift",
    "test-fixtures/processing-command-fixture.sh",
    "test-fixtures/transcript-action-command-fixture.sh",
    "tests/MeetingAssistantNativeTests/PermissionDependencyStatusViewModelTests.swift",
    "tests/MeetingAssistantNativeTests/NativeRecordingCommandClientTests.swift",
    "tests/MeetingAssistantNativeTests/RecordingControlViewModelTests.swift",
    "tests/MeetingAssistantNativeTests/TranscriptReviewViewModelTests.swift",
    "tests/MeetingAssistantNativeTests/TranscriptReviewActionsViewModelTests.swift",
    "tests/MeetingAssistantNativeTests/ProcessingStateViewModelTests.swift",
    "tests/MeetingAssistantNativeTests/DesignedNativeShellViewModelTests.swift",
    "UITests/MeetingAssistantNativeUITests/NativeControlPlaneSmokeTests.swift",
    "UITests/MeetingAssistantNativeAppUITests/DesignedNativeShellAppBundleTests.swift",
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
expected_behavior = "permission_dependency_status_fake_recording_controlled_and_apple_screencapturekit_native_capture_artifact_registration_processing_state_transcript_review_actions_and_designed_native_shell"
if metadata.get("business_behavior") != expected_behavior:
    raise SystemExit(f"native-app lint failed: business behavior must be {expected_behavior}")
if "read_only_workspace_transcript_loading" not in metadata.get("allowed_capabilities", []):
    raise SystemExit("native-app lint failed: missing read-only workspace transcript loading capability")
if "fake_transcript_action_command_client" not in metadata.get("allowed_capabilities", []):
    raise SystemExit("native-app lint failed: missing fake transcript action capability")
if "transcript_action_process_runner" not in metadata.get("allowed_capabilities", []):
    raise SystemExit("native-app lint failed: missing transcript action process runner capability")
if "processing_command_consumer" not in metadata.get("allowed_capabilities", []):
    raise SystemExit("native-app lint failed: missing processing command consumer capability")
if "controlled_native_capture_adapter" not in metadata.get("allowed_capabilities", []):
    raise SystemExit("native-app lint failed: missing controlled native capture capability")
if "apple_screencapturekit_native_capture_adapter" not in metadata.get("allowed_capabilities", []):
    raise SystemExit("native-app lint failed: missing Apple ScreenCaptureKit native capture capability")
if "native_capture_combined_recording_spike" not in metadata.get("allowed_capabilities", []):
    raise SystemExit("native-app lint failed: missing combined recording spike capability")
if "opt_in_apple_screencapturekit_native_capture_smoke" not in metadata.get("allowed_capabilities", []):
    raise SystemExit("native-app lint failed: missing opt-in Apple ScreenCaptureKit native capture smoke capability")
if "native_capture_artifact_registration" not in metadata.get("allowed_capabilities", []):
    raise SystemExit("native-app lint failed: missing native capture artifact registration capability")
if "designed_native_shell" not in metadata.get("allowed_capabilities", []):
    raise SystemExit("native-app lint failed: missing designed native shell capability")

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
    "DesignedNativeShellViewModel.swift",
    "DesignedNativeShellView.swift",
    "DesignedNativeShellAppBundleTests.swift",
    "NativeCaptureAdapter.swift",
    "ControlledNativeCaptureAdapter.swift",
    "AppleScreenCaptureKitNativeCaptureAdapter.swift",
    "RecordingSessionStore.swift",
    "NativeRecordingCommandClient.swift",
    "NativeCapturePermissionChecker.swift",
]
missing_project_snippets = [snippet for snippet in required_project_snippets if snippet not in project]
if missing_project_snippets:
    raise SystemExit(f"native-app lint failed: xcodeproj missing {missing_project_snippets}")

app_source = (root / "App/MeetingAssistantNativeApp.swift").read_text(encoding="utf-8")
required_app_snippets = [
    "MA_NATIVE_RECORDING_CLIENT",
    "MA_NATIVE_RECORDING_WORKSPACE",
    "NativeRecordingCommandClient",
    "isRecordingClientTestHookAllowed",
    "MA_NATIVE_PROCESSING_CLIENT",
    "MA_NATIVE_TRANSCRIPT_ACTION_CLIENT",
    "isTranscriptActionClientTestHookAllowed",
]
missing_app_snippets = [snippet for snippet in required_app_snippets if snippet not in app_source]
if missing_app_snippets:
    raise SystemExit(f"native-app lint failed: app bundle missing test hook snippets {missing_app_snippets}")
PY

echo "native-app lint passed."
