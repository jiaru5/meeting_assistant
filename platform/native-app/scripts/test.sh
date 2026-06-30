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
if metadata.get("business_behavior") != "permission_dependency_status_fake_recording_transcript_review_and_actions":
    raise SystemExit("native-app test failed: business behavior must be permission_dependency_status_fake_recording_transcript_review_and_actions")
if metadata.get("allowed_before_project_mode") is not False:
    raise SystemExit("native-app test failed: project component cannot be allowed before project mode")
if "read_only_workspace_transcript_loading" not in metadata.get("allowed_capabilities", []):
    raise SystemExit("native-app test failed: missing read-only workspace transcript loading capability")
if "fake_transcript_action_command_client" not in metadata.get("allowed_capabilities", []):
    raise SystemExit("native-app test failed: missing fake transcript action capability")

architecture = Path("tests/ArchitectureTest.md").read_text(encoding="utf-8")
required_phrases = (
    "Component: `native-app`",
    "VS-MA-12 boundary",
    "VS-MA-13 fake recording boundary",
    "VS-MA-17 read-only transcript review boundary",
    "read-only workspace transcript loading boundary",
    "VS-MA-18/VS-MA-19 deterministic transcript action consumer boundary",
    "ma.transcriptAction.*",
    "check_dependencies",
    "session.json",
    "transcript.json",
    "speaker_labels.json",
    "must not implement real capture",
)
missing = [phrase for phrase in required_phrases if phrase not in architecture]
if missing:
    raise SystemExit(f"native-app test failed: missing architecture phrases {missing}")

required_paths = (
    Path("MeetingAssistantNative.xcodeproj/project.pbxproj"),
    Path("MeetingAssistantNative.xcodeproj/xcshareddata/xcschemes/MeetingAssistantNative.xcscheme"),
    Path("App/MeetingAssistantNativeApp.swift"),
    Path("Sources/MeetingAssistantNative/DependencyCheckContract.swift"),
    Path("Sources/MeetingAssistantNative/DependencyCheckProcessRunner.swift"),
    Path("Sources/MeetingAssistantNative/PermissionDependencyStatusViewModel.swift"),
    Path("Sources/MeetingAssistantNative/PermissionDependencyStatusView.swift"),
    Path("Sources/MeetingAssistantNative/RecordingCommandClient.swift"),
    Path("Sources/MeetingAssistantNative/RecordingFakeCommandClient.swift"),
    Path("Sources/MeetingAssistantNative/RecordingControlViewModel.swift"),
    Path("Sources/MeetingAssistantNative/RecordingControlView.swift"),
    Path("Sources/MeetingAssistantNative/TranscriptReviewReadModel.swift"),
    Path("Sources/MeetingAssistantNative/TranscriptReviewWorkspaceLoader.swift"),
    Path("Sources/MeetingAssistantNative/TranscriptReviewViewModel.swift"),
    Path("Sources/MeetingAssistantNative/TranscriptReviewView.swift"),
    Path("Sources/MeetingAssistantNative/TranscriptActionCommandClient.swift"),
    Path("Sources/MeetingAssistantNative/TranscriptActionFakeCommandClient.swift"),
    Path("Sources/MeetingAssistantNative/TranscriptReviewActionsViewModel.swift"),
    Path("Sources/MeetingAssistantNative/TranscriptReviewActionsView.swift"),
    Path("tests/MeetingAssistantNativeTests/PermissionDependencyStatusViewModelTests.swift"),
    Path("tests/MeetingAssistantNativeTests/RecordingControlViewModelTests.swift"),
    Path("tests/MeetingAssistantNativeTests/TranscriptReviewViewModelTests.swift"),
    Path("tests/MeetingAssistantNativeTests/TranscriptReviewActionsViewModelTests.swift"),
    Path("UITests/MeetingAssistantNativeUITests/NativeControlPlaneSmokeTests.swift"),
    Path("UITests/MeetingAssistantNativeAppUITests/AppBundleLocatorSmokeTests.swift"),
)
missing_paths = [str(path) for path in required_paths if not path.is_file()]
if missing_paths:
    raise SystemExit(f"native-app test failed: missing Swift status surface, app bundle, or UI smoke files {missing_paths}")
PY

tmp_dir="$(mktemp -d)"
trap 'rm -rf "$tmp_dir"' EXIT
ln -s "$component_dir/Sources" "$tmp_dir/Sources"
ln -s "$component_dir/tests" "$tmp_dir/tests"
ln -s "$component_dir/UITests" "$tmp_dir/UITests"
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
        .testTarget(
            name: "MeetingAssistantNativeUITests",
            dependencies: ["MeetingAssistantNative"],
            path: "UITests/MeetingAssistantNativeUITests"
        ),
    ]
)
SWIFT

(cd "$tmp_dir" && swift test)

xcodebuild test \
  -project "$component_dir/MeetingAssistantNative.xcodeproj" \
  -scheme "MeetingAssistantNative" \
  -destination 'platform=macOS' \
  -derivedDataPath "$tmp_dir/DerivedData"

echo "native-app tests passed."
