#!/usr/bin/env bash
set -euo pipefail

component_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$component_dir"

test -f tests/ArchitectureTest.md
grep -q "Component: \`native-app\`" tests/ArchitectureTest.md
grep -q "VS-MA-12 boundary" tests/ArchitectureTest.md
grep -q "VS-MA-13 fake recording boundary" tests/ArchitectureTest.md
grep -q "VS-MA-14/VS-MA-15 controlled native capture artifact registration boundary" tests/ArchitectureTest.md
grep -q "Apple ScreenCaptureKit native capture adapter exception" tests/ArchitectureTest.md
grep -q "opt-in real native capture smoke boundary" tests/ArchitectureTest.md
grep -q "opt-in real native capture app-bundle smoke boundary" tests/ArchitectureTest.md
grep -q "VS-MA-16 native processing state consumer boundary" tests/ArchitectureTest.md
grep -q "VS-MA-17 read-only transcript review boundary" tests/ArchitectureTest.md
grep -q "read-only workspace transcript loading boundary" tests/ArchitectureTest.md
grep -q "VS-MA-18/VS-MA-19 deterministic transcript action consumer boundary" tests/ArchitectureTest.md
grep -q "VS-MA-19A designed native shell boundary" tests/ArchitectureTest.md
grep -q "VS-MA-20 opt-in native app-bundle MVP full-stack smoke boundary" tests/ArchitectureTest.md
grep -q "MA_NATIVE_TRANSCRIPT_ACTION_CLIENT=process" tests/ArchitectureTest.md
grep -q "MA_NATIVE_RECORDING_CONTROLLED_MIXED_AUDIO=1" tests/ArchitectureTest.md
grep -q "check_dependencies" tests/ArchitectureTest.md
grep -q "session.json" tests/ArchitectureTest.md
grep -q "screen_video" tests/ArchitectureTest.md
grep -q "mixed_audio" tests/ArchitectureTest.md
grep -q "capture_failed" tests/ArchitectureTest.md
grep -q "MA_NATIVE_CAPTURE_SMOKE=1" tests/ArchitectureTest.md
grep -q "MA_NATIVE_APP_REAL_CAPTURE_SMOKE=1" tests/ArchitectureTest.md
grep -q "MA_NATIVE_RECORDING_CLIENT=apple_screencapturekit" tests/ArchitectureTest.md
grep -q "transcript.json" tests/ArchitectureTest.md
grep -q "speaker_labels.json" tests/ArchitectureTest.md
grep -q "ma.recording.artifact" tests/ArchitectureTest.md
grep -q "ma.processing" tests/ArchitectureTest.md
grep -q "ma.transcriptAction" tests/ArchitectureTest.md
grep -q "ma.shell" tests/ArchitectureTest.md
grep -q "ma.sessionArtifact" tests/ArchitectureTest.md
test -f MeetingAssistantNative.xcodeproj/project.pbxproj
test -f MeetingAssistantNative.xcodeproj/xcshareddata/xcschemes/MeetingAssistantNative.xcscheme
test -x scripts/native-capture-smoke.sh
test -f App/MeetingAssistantNativeApp.swift
test -f Sources/MeetingAssistantNative/DependencyCheckContract.swift
test -f Sources/MeetingAssistantNative/PermissionDependencyStatusViewModel.swift
test -f Sources/MeetingAssistantNative/PermissionDependencyStatusView.swift
test -f Sources/MeetingAssistantNative/RecordingCommandClient.swift
test -f Sources/MeetingAssistantNative/RecordingFakeCommandClient.swift
test -f Sources/MeetingAssistantNative/NativeCaptureAdapter.swift
test -f Sources/MeetingAssistantNative/ControlledNativeCaptureAdapter.swift
test -f Sources/MeetingAssistantNative/AppleScreenCaptureKitNativeCaptureAdapter.swift
test -f Sources/MeetingAssistantNative/RecordingSessionStore.swift
test -f Sources/MeetingAssistantNative/NativeRecordingCommandClient.swift
test -f Sources/MeetingAssistantNative/NativeCapturePermissionChecker.swift
test -f Sources/MeetingAssistantNative/RecordingControlViewModel.swift
test -f Sources/MeetingAssistantNative/RecordingControlView.swift
test -f Sources/MeetingAssistantNative/TranscriptReviewReadModel.swift
test -f Sources/MeetingAssistantNative/TranscriptReviewWorkspaceLoader.swift
test -f Sources/MeetingAssistantNative/TranscriptReviewViewModel.swift
test -f Sources/MeetingAssistantNative/TranscriptReviewView.swift
test -f Sources/MeetingAssistantNative/TranscriptActionCommandClient.swift
test -f Sources/MeetingAssistantNative/TranscriptActionFakeCommandClient.swift
test -f Sources/MeetingAssistantNative/TranscriptReviewActionsViewModel.swift
test -f Sources/MeetingAssistantNative/TranscriptReviewActionsView.swift
test -f Sources/MeetingAssistantNative/ProcessingCommandClient.swift
test -f Sources/MeetingAssistantNative/ProcessingCommandProcessRunner.swift
test -f Sources/MeetingAssistantNative/ProcessingCommandFakeClient.swift
test -f Sources/MeetingAssistantNative/ProcessingStateViewModel.swift
test -f Sources/MeetingAssistantNative/ProcessingStateView.swift
test -f Sources/MeetingAssistantNative/DesignedNativeShellViewModel.swift
test -f Sources/MeetingAssistantNative/DesignedNativeShellView.swift
test -x test-fixtures/processing-command-fixture.sh
test -x test-fixtures/transcript-action-command-fixture.sh
test -f tests/MeetingAssistantNativeTests/NativeRecordingCommandClientTests.swift
test -f tests/MeetingAssistantNativeTests/TranscriptReviewActionsViewModelTests.swift
test -f tests/MeetingAssistantNativeTests/ProcessingStateViewModelTests.swift
test -f tests/MeetingAssistantNativeTests/DesignedNativeShellViewModelTests.swift
test -f UITests/MeetingAssistantNativeUITests/NativeControlPlaneSmokeTests.swift
test -f UITests/MeetingAssistantNativeAppUITests/AppBundleLocatorSmokeTests.swift
test -f UITests/MeetingAssistantNativeAppUITests/DesignedNativeShellAppBundleTests.swift

grep -R -q "check_dependencies" Sources tests App
grep -R -q "ma.permissionDependency" Sources tests App UITests
grep -R -q "start_native_recording" Sources tests
grep -R -q "stop_recording" Sources tests
grep -R -q "ma.recording" Sources tests App UITests
grep -R -q "ma.recording.artifact" Sources tests App UITests
grep -R -q "NativeRecordingCommandClient" Sources tests
grep -R -q "RecordingSessionStore" Sources tests
grep -R -q "ControlledNativeCaptureAdapter" Sources tests
grep -R -q "AppleScreenCaptureKitNativeCaptureAdapter" Sources tests
grep -R -q "producesCombinedRecordingFile" Sources tests
grep -q "MA_NATIVE_CAPTURE_SMOKE" scripts/native-capture-smoke.sh
grep -q "NativeRecordingCommandClient" scripts/native-capture-smoke.sh
grep -q "MacOSNativeCapturePermissionChecker" scripts/native-capture-smoke.sh
grep -q "AppleScreenCaptureKitNativeCaptureAdapter" scripts/native-capture-smoke.sh
grep -q "RecordingSessionStore" scripts/native-capture-smoke.sh
grep -q "session.json" scripts/native-capture-smoke.sh
grep -q "screen_video" scripts/native-capture-smoke.sh
grep -R -q "ma.processing" Sources tests App UITests
grep -R -q "ma.transcript" Sources tests App UITests
grep -R -q "ma.transcriptAction" Sources tests App UITests
grep -R -q "TranscriptReviewViewModel" Sources tests App UITests
grep -R -q "TranscriptReviewWorkspaceLoader" Sources tests App UITests
grep -R -q "TranscriptReviewActionsViewModel" Sources tests App UITests
grep -R -q "TranscriptActionFakeCommandClient" Sources tests App UITests
grep -R -q "TranscriptActionProcessRunner" Sources tests
grep -R -q "TranscriptActionMemoryClipboard" Sources tests
grep -R -q "TranscriptActionStaticDestinationSelector" Sources tests
grep -R -q "ProcessingStateViewModel" Sources tests App UITests
grep -R -q "ProcessingCommandFakeClient" Sources tests App UITests
grep -R -q "ProcessingCommandProcessRunner" Sources tests App UITests
grep -R -q "DesignedNativeShellViewModel" Sources tests App UITests
grep -R -q "DesignedNativeShellView" Sources tests App UITests
grep -R -q "ma.shell" Sources tests App UITests
grep -R -q "ma.sessionArtifact" Sources tests App UITests
grep -R -q "MA_NATIVE_RECORDING_CLIENT" App UITests/MeetingAssistantNativeAppUITests
grep -R -q "MA_NATIVE_RECORDING_WORKSPACE" App UITests/MeetingAssistantNativeAppUITests
grep -R -q "isRecordingClientTestHookAllowed" App/MeetingAssistantNativeApp.swift
grep -R -q "isRealNativeCaptureSmokeEnabled" App/MeetingAssistantNativeApp.swift
grep -R -q "MA_NATIVE_CAPTURE_SMOKE" App UITests/MeetingAssistantNativeAppUITests
grep -R -q "MA_NATIVE_APP_REAL_CAPTURE_SMOKE" UITests/MeetingAssistantNativeAppUITests
grep -q "MA_NATIVE_APP_REAL_CAPTURE_SMOKE" scripts/test-app-bundle.sh
grep -q "MA_NATIVE_APP_REAL_PROCESSING_SMOKE" scripts/test-app-bundle.sh
grep -q "MA_NATIVE_APP_REAL_ACTION_SMOKE" scripts/test-app-bundle.sh
grep -q "MA_NATIVE_APP_MVP_FULL_STACK_SMOKE" scripts/test-app-bundle.sh
grep -q "test-without-building" scripts/test-app-bundle.sh
grep -q "PlistBuddy" scripts/test-app-bundle.sh
grep -q "permission_denied" scripts/test-app-bundle.sh
grep -q "real-capture-app-bundle-smoke.log" scripts/test-app-bundle.sh
grep -q "real-processing-app-bundle-smoke.log" scripts/test-app-bundle.sh
grep -q "real-action-app-bundle-smoke.log" scripts/test-app-bundle.sh
grep -q "mvp-full-stack-app-bundle-smoke.log" scripts/test-app-bundle.sh
grep -R -q "MA_NATIVE_PROCESSING_CLIENT" App UITests/MeetingAssistantNativeAppUITests
grep -R -q "AppRealProcessingCLIFixture" UITests/MeetingAssistantNativeAppUITests
test -x ../e2e/ma-cli-local.sh
grep -q "meeting_assistant_cli" ../e2e/ma-cli-local.sh
grep -R -q "MA_NATIVE_APP_XCTEST" App UITests/MeetingAssistantNativeAppUITests
grep -R -q "isProcessClientTestHookAllowed" App/MeetingAssistantNativeApp.swift
grep -R -q "MA_NATIVE_TRANSCRIPT_ACTION_CLIENT" App UITests/MeetingAssistantNativeAppUITests
grep -R -q "MA_NATIVE_APP_REAL_ACTION_SMOKE" UITests/MeetingAssistantNativeAppUITests
grep -R -q "MA_NATIVE_APP_MVP_FULL_STACK_SMOKE" UITests/MeetingAssistantNativeAppUITests
grep -R -q "isTranscriptActionClientTestHookAllowed" App/MeetingAssistantNativeApp.swift
grep -R -q "#if DEBUG" App/MeetingAssistantNativeApp.swift
grep -q "SWIFT_ACTIVE_COMPILATION_CONDITIONS = DEBUG;" MeetingAssistantNative.xcodeproj/project.pbxproj
python3 - <<'PY'
import re
from pathlib import Path

project = Path("MeetingAssistantNative.xcodeproj/project.pbxproj").read_text(encoding="utf-8")
configuration_pattern = re.compile(
    r"/\* (Debug|Release) \*/ = \{\n"
    r"\t\t\tisa = XCBuildConfiguration;\n"
    r"\t\t\tbuildSettings = \{(.*?)\n"
    r"\t\t\t\};\n"
    r"\t\t\tname = \1;",
    re.S,
)
debug_settings = []
release_settings = []
for match in configuration_pattern.finditer(project):
    name, settings = match.groups()
    if name == "Debug":
        debug_settings.append(settings)
    else:
        release_settings.append(settings)

if len(debug_settings) < 3 or len(release_settings) < 3:
    raise SystemExit("native-app architecture check failed: expected Debug and Release build configurations for project, app, and UI test targets.")

missing_debug = [settings for settings in debug_settings if "SWIFT_ACTIVE_COMPILATION_CONDITIONS = DEBUG;" not in settings]
if missing_debug:
    raise SystemExit("native-app architecture check failed: every Debug configuration must define DEBUG for XCTest-only hooks.")

leaking_release = [settings for settings in release_settings if "SWIFT_ACTIVE_COMPILATION_CONDITIONS" in settings and "DEBUG" in settings]
if leaking_release:
    raise SystemExit("native-app architecture check failed: Release configurations must not define DEBUG or enable XCTest-only hooks.")

scheme = Path("MeetingAssistantNative.xcodeproj/xcshareddata/xcschemes/MeetingAssistantNative.xcscheme").read_text(encoding="utf-8")
required_scheme_markers = [
    '<TestAction\n      buildConfiguration = "Debug"',
    '<LaunchAction\n      buildConfiguration = "Debug"',
    '<ProfileAction\n      buildConfiguration = "Release"',
    '<ArchiveAction\n      buildConfiguration = "Release"',
]
missing_markers = [marker for marker in required_scheme_markers if marker not in scheme]
if missing_markers:
    raise SystemExit(f"native-app architecture check failed: scheme Debug/Release boundary markers are missing: {missing_markers}")
PY
grep -q '"command": "generate_transcript"' test-fixtures/processing-command-fixture.sh
grep -q '"command": "generate_speaker_labels"' test-fixtures/processing-command-fixture.sh
grep -q '"command": "export_transcript"' test-fixtures/transcript-action-command-fixture.sh
grep -q '"command": "delete_session"' test-fixtures/transcript-action-command-fixture.sh
grep -R -q "MA_NATIVE_TRANSCRIPT_WORKSPACE" App UITests/MeetingAssistantNativeAppUITests
grep -R -q "XCTest" UITests
grep -R -q "NSHostingController" UITests/MeetingAssistantNativeUITests
grep -R -q "XCUIApplication" UITests/MeetingAssistantNativeAppUITests
grep -R -q "DesignedNativeShellAppBundleTests" MeetingAssistantNative.xcodeproj/project.pbxproj
grep -R -q "MA_NATIVE_APP_SMOKE_FIXTURE" App UITests/MeetingAssistantNativeAppUITests
grep -R -q "MeetingAssistantNativeAppUITests" MeetingAssistantNative.xcodeproj/project.pbxproj

apple_adapter_file='Sources/MeetingAssistantNative/AppleScreenCaptureKitNativeCaptureAdapter.swift'
apple_framework_forbidden='(^[[:space:]]*import[[:space:]]+(ScreenCaptureKit|AVFoundation|CoreAudio|CoreMediaIO|ReplayKit|Network)\b|SCStream\b|SCRecordingOutput\b|SCContentFilter\b|SCShareableContent\b|AVCapture|CGDisplayStream|AVAudioEngine|AVAudioRecorder|AudioQueue|AudioUnit|AudioDevice)'

if grep -R --include '*.swift' -n -E "$apple_framework_forbidden" Sources tests App UITests |
  grep -v -F "$apple_adapter_file"; then
  echo "native-app architecture check failed: Apple capture framework usage is allowed only in AppleScreenCaptureKitNativeCaptureAdapter.swift." >&2
  exit 1
fi

action_os_boundary_file='Sources/MeetingAssistantNative/TranscriptActionOSClients.swift'

if grep -R --include '*.swift' -n -E 'normalize_audio|URLSession|URLRequest|URLSessionConfiguration|NWConnection|NWListener|WebSocket|https?://|NSPasteboard|API_KEY|SECRET|TOKEN' Sources tests App UITests |
  grep -v -F "$action_os_boundary_file"; then
  echo "native-app architecture check failed: native-app must not implement processing normalization, external network calls, real pasteboard, or secrets." >&2
  exit 1
fi

if grep -R --include '*.swift' -n -E 'generate_transcript|generate_speaker_labels' Sources tests App UITests |
  grep -v -E 'Processing(Command|State)'; then
  echo "native-app architecture check failed: raw processing command strings are only allowed in the processing bridge files and tests." >&2
  exit 1
fi

if grep -R --include 'Processing*.swift' -n -E 'Process\b|ProcessInfo\b|Pipe\b|standardOutput|standardError' Sources/MeetingAssistantNative |
  grep -v 'ProcessingCommandProcessRunner.swift'; then
  echo "native-app architecture check failed: Process usage is only allowed in ProcessingCommandProcessRunner.swift." >&2
  exit 1
fi

processing_boundary_forbidden='(^[[:space:]]*import[[:space:]]+(AppKit|ScreenCaptureKit|AVFoundation|CoreAudio|CoreMediaIO|ReplayKit|Network)\b|NSTask\b|posix_spawn|execv|system[[:space:]]*\(|popen[[:space:]]*\(|meeting_assistant_cli|native-helper|processing-cli|helper[[:space:]]+tool|ScreenCaptureKit|AVCapture|CGDisplayStream|SCStream|AVAudioEngine|AVAudioRecorder|NSPasteboard|NSOpenPanel|NSSavePanel|URLSession|URLRequest|URLSessionConfiguration|NWConnection|NWListener|WebSocket|https?://|import_media|export_transcript|delete_session|check_dependencies|normalize_audio|removeItem[[:space:]]*\(|copyItem[[:space:]]*\(|moveItem[[:space:]]*\(|createFile[[:space:]]*\(|createDirectory[[:space:]]*\()'

if grep -R --include 'Processing*.swift' -n -E "$processing_boundary_forbidden" Sources/MeetingAssistantNative; then
  echo "native-app architecture check failed: processing consumer must not call provider internals, capture APIs, action surfaces, network APIs, file mutation, or non-VS-MA-16 commands." >&2
  exit 1
fi

recording_boundary_forbidden='(^[[:space:]]*import[[:space:]]+(ScreenCaptureKit|AVFoundation|CoreAudio|CoreMediaIO|ReplayKit|Network)\b|Process\b|ProcessInfo\b|NSTask\b|posix_spawn|execv|system[[:space:]]*\(|popen[[:space:]]*\(|meeting_assistant_cli|ProcessingCLIDependencyCheckRunner|DependencyCheckProcessRunner|native-helper|processing-cli|helper[[:space:]]+tool|ScreenCaptureKit|AVCapture|CGDisplayStream|SCStream|SCShareableContent|AVAudioEngine|AVAudioRecorder|RPScreenRecorder|CGWindowListCreate|CGDisplayCreateImage|AudioQueue|AudioUnit|AudioDevice|FileManager\b|FileHandle\b|OutputStream\b|InputStream\b|createFile[[:space:]]*\(|createDirectory[[:space:]]*\(|removeItem[[:space:]]*\(|copyItem[[:space:]]*\(|moveItem[[:space:]]*\(|\.(write|write(to|Bytes))[[:space:]]*\(|generate_transcript|generate_speaker_labels|normalize_audio|import_media|export_transcript|delete_session|check_dependencies|URLSession|URLRequest|URLSessionConfiguration|NWConnection|NWListener|WebSocket|https?://)'

if grep -R --include 'Recording*.swift' -n -E "$recording_boundary_forbidden" Sources tests |
  grep -v -E 'Sources/MeetingAssistantNative/RecordingSessionStore.swift' ||
  grep -R --include '*.swift' -n -E "$recording_boundary_forbidden" UITests/MeetingAssistantNativeUITests; then
  echo "native-app architecture check failed: recording UI/state and UITests must stay off processes, real helpers/CLIs, broad file writes, capture frameworks, processing commands or network APIs; file writes are limited to RecordingSessionStore.swift." >&2
  exit 1
fi

native_capture_forbidden='(^[[:space:]]*import[[:space:]]+(AppKit|ScreenCaptureKit|AVFoundation|CoreAudio|CoreMediaIO|ReplayKit|Network)\b|Process\b|ProcessInfo\b|NSTask\b|posix_spawn|execv|system[[:space:]]*\(|popen[[:space:]]*\(|meeting_assistant_cli|native-helper|processing-cli|helper[[:space:]]+tool|ScreenCaptureKit|AVCapture|CGDisplayStream|SCStream|SCShareableContent|AVAudioEngine|AVAudioRecorder|RPScreenRecorder|CGWindowListCreate|CGDisplayCreateImage|AudioQueue|AudioUnit|AudioDevice|[Oo][Bb][Ss]|[Bb]lack[Hh]ole|[Ff][Ff]mpeg|generate_transcript|generate_speaker_labels|normalize_audio|import_media|export_transcript|delete_session|check_dependencies|URLSession|URLRequest|URLSessionConfiguration|NWConnection|NWListener|WebSocket|https?://|NSPasteboard|NSOpenPanel|NSSavePanel)'

if grep -R --include '*.swift' -n -E "$native_capture_forbidden" \
  Sources/MeetingAssistantNative/NativeCapture*.swift \
  Sources/MeetingAssistantNative/ControlledNativeCaptureAdapter.swift \
  Sources/MeetingAssistantNative/NativeRecordingCommandClient.swift \
  Sources/MeetingAssistantNative/RecordingSessionStore.swift; then
  echo "native-app architecture check failed: controlled native capture slice must not call capture frameworks, helpers/CLIs, processing commands, auxiliary capture tools, network APIs, pasteboard, or file pickers." >&2
  exit 1
fi

native_capture_file_api_forbidden='FileManager\b|FileHandle\b|OutputStream\b|InputStream\b|createFile[[:space:]]*\(|createDirectory[[:space:]]*\(|removeItem[[:space:]]*\(|copyItem[[:space:]]*\(|moveItem[[:space:]]*\(|Data[[:space:]]*\([[:space:]]*contentsOf:|\.(write|write(to|Bytes))[[:space:]]*\('

if grep -R --include '*.swift' -n -E "$native_capture_file_api_forbidden" \
  Sources/MeetingAssistantNative/NativeCapture*.swift \
  Sources/MeetingAssistantNative/ControlledNativeCaptureAdapter.swift \
  Sources/MeetingAssistantNative/NativeRecordingCommandClient.swift; then
  echo "native-app architecture check failed: native capture file mutation/checksum IO must stay inside RecordingSessionStore.swift." >&2
  exit 1
fi

apple_adapter_forbidden='Process\b|ProcessInfo\b|NSTask\b|posix_spawn|execv|system[[:space:]]*\(|popen[[:space:]]*\(|meeting_assistant_cli|native-helper|processing-cli|helper[[:space:]]+tool|[Oo][Bb][Ss]|[Bb]lack[Hh]ole|[Ff][Ff]mpeg|generate_transcript|generate_speaker_labels|normalize_audio|import_media|export_transcript|delete_session|check_dependencies|URLSession|URLRequest|URLSessionConfiguration|NWConnection|NWListener|WebSocket|https?://|NSPasteboard|NSOpenPanel|NSSavePanel|RecordingSessionStore|session\.json|artifacts/|sha256|checksum'

if grep -n -E "$apple_adapter_forbidden" "$apple_adapter_file"; then
  echo "native-app architecture check failed: Apple ScreenCaptureKit adapter must stay inside capture framework/temp-file boundary and must not call helpers/CLIs, processing commands, auxiliary capture tools, network APIs, pasteboard, file pickers, or store-owned metadata/checksum paths." >&2
  exit 1
fi

if grep -n -E 'MA_NATIVE_RECORDING_CLIENT=apple_screencapturekit|[Oo][Bb][Ss]|[Bb]lack[Hh]ole|[Ff][Ff]mpeg|curl[[:space:]]|wget[[:space:]]|brew install|pip install|npm install|generate_transcript|generate_speaker_labels|normalize_audio|import_media|export_transcript|delete_session|processing-cli|meeting_assistant_cli|URLSession|URLRequest|NWConnection|NWListener|https?://|NSPasteboard|NSOpenPanel|NSSavePanel' scripts/native-capture-smoke.sh; then
  echo "native-app architecture check failed: opt-in native capture smoke must stay on NativeRecordingCommandClient, Apple adapter, permission checker, and session artifact validation only." >&2
  exit 1
fi

if grep -R --include '*.swift' -n -E 'AppleScreenCaptureKitNativeCaptureAdapter|apple_screencapturekit' App | grep -v 'App/MeetingAssistantNativeApp.swift'; then
  echo "native-app architecture check failed: only the app root may select the opt-in Apple ScreenCaptureKit app-bundle smoke hook." >&2
  exit 1
fi

if ! grep -q 'case "apple_screencapturekit", "apple-screencapturekit"' App/MeetingAssistantNativeApp.swift ||
   ! grep -q 'isRealNativeCaptureSmokeEnabled(environment)' App/MeetingAssistantNativeApp.swift ||
   ! grep -q 'AppleScreenCaptureKitNativeCaptureAdapter()' App/MeetingAssistantNativeApp.swift ||
   ! grep -q 'MacOSNativeCapturePermissionChecker()' App/MeetingAssistantNativeApp.swift; then
  echo "native-app architecture check failed: Apple ScreenCaptureKit app-bundle hook must stay explicit, permission-checked, and smoke-gated." >&2
  exit 1
fi

app_bundle_forbidden='meeting_assistant_cli|ProcessingCLIDependencyCheckRunner|DependencyCheckProcessRunner|native-helper|processing-cli|helper[[:space:]]+tool|AVCapture|CGDisplayStream|SCStream|AVAudioEngine|AVAudioRecorder|generate_transcript|generate_speaker_labels|normalize_audio|import_media|export_transcript|delete_session|URLSession|URLRequest|NWConnection|NWListener|https?://|curl|wget'

if grep -R --include '*.swift' -n -E "$app_bundle_forbidden" App UITests/MeetingAssistantNativeAppUITests |
  grep -v -E 'MA_NATIVE_APP_REAL_PROCESSING_SMOKE|MA_NATIVE_APP_REAL_ACTION_SMOKE|MA_NATIVE_APP_MVP_FULL_STACK_SMOKE|real processing-cli app-bundle smoke|MVP full-stack'; then
  echo "native-app architecture check failed: app-bundle smoke must keep processing command strings inside the native-owned shell fixture or the explicit real-processing CLI shim, and must not call capture frameworks, downloads, network APIs, or raw provider commands." >&2
  exit 1
fi

grep -q "TranscriptActionProcessRunner" Sources/MeetingAssistantNative/TranscriptActionCommandClient.swift
grep -q "TranscriptActionMemoryClipboard" Sources/MeetingAssistantNative/TranscriptActionFakeCommandClient.swift
grep -q "TranscriptActionStaticDestinationSelector" Sources/MeetingAssistantNative/TranscriptActionFakeCommandClient.swift
grep -q "TranscriptActionPasteboardClipboard" "$action_os_boundary_file"
grep -q "TranscriptActionSavePanelDestinationSelector" "$action_os_boundary_file"
grep -q "NSPasteboard.general" "$action_os_boundary_file"
grep -q "NSSavePanel" "$action_os_boundary_file"
grep -q "TranscriptActionPasteboardClipboard" App/MeetingAssistantNativeApp.swift
grep -q "TranscriptActionSavePanelDestinationSelector" App/MeetingAssistantNativeApp.swift

action_process_boundary_file='Sources/MeetingAssistantNative/TranscriptActionCommandClient.swift'
action_os_boundary_forbidden='(^[[:space:]]*import[[:space:]]+(AppKit|ScreenCaptureKit|AVFoundation|CoreAudio|CoreMediaIO|ReplayKit|Network)\b|NSTask\b|posix_spawn|execv|system[[:space:]]*\(|popen[[:space:]]*\(|meeting_assistant_cli|ProcessingCLIDependencyCheckRunner|DependencyCheckProcessRunner|native-helper|processing-cli|helper[[:space:]]+tool|ScreenCaptureKit|AVCapture|CGDisplayStream|SCStream|AVAudioEngine|AVAudioRecorder|NSPasteboard|NSOpenPanel|NSSavePanel|FileManager\b|OutputStream\b|InputStream\b|createFile[[:space:]]*\(|createDirectory[[:space:]]*\(|removeItem[[:space:]]*\(|copyItem[[:space:]]*\(|moveItem[[:space:]]*\(|\.(write|write(to|Bytes))[[:space:]]*\(|URLSession|URLRequest|URLSessionConfiguration|NWConnection|NWListener|WebSocket|https?://)'

if grep -R --include 'TranscriptAction*.swift' --include 'TranscriptReviewActions*.swift' -n -E "$action_os_boundary_forbidden" Sources |
  grep -v -F "$action_os_boundary_file"; then
  echo "native-app architecture check failed: transcript action consumer must keep OS effects behind injected boundaries and must not call helpers/provider internals, real pasteboard, file pickers, direct file mutation/deletion, capture APIs, or network APIs." >&2
  exit 1
fi

action_os_client_forbidden='(^[[:space:]]*import[[:space:]]+(ScreenCaptureKit|AVFoundation|CoreAudio|CoreMediaIO|ReplayKit|Network)\b|NSTask\b|Process\b|Pipe\b|ProcessInfo\b|posix_spawn|execv|system[[:space:]]*\(|popen[[:space:]]*\(|meeting_assistant_cli|ProcessingCLIDependencyCheckRunner|DependencyCheckProcessRunner|native-helper|processing-cli|helper[[:space:]]+tool|NSOpenPanel|FileManager\b|FileHandle\b|OutputStream\b|InputStream\b|createFile[[:space:]]*\(|createDirectory[[:space:]]*\(|removeItem[[:space:]]*\(|copyItem[[:space:]]*\(|moveItem[[:space:]]*\(|\.(write|write(to|Bytes))[[:space:]]*\(|URLSession|URLRequest|URLSessionConfiguration|NWConnection|NWListener|WebSocket|https?://)'

if grep -n -E "$action_os_client_forbidden" "$action_os_boundary_file"; then
  echo "native-app architecture check failed: transcript action OS clients may only use NSPasteboard and NSSavePanel behind injected protocols." >&2
  exit 1
fi

if grep -R --include 'TranscriptAction*.swift' --include 'TranscriptReviewActions*.swift' -n -E 'Process\b|ProcessInfo\b|Pipe\b|standardOutput|standardError|FileHandle\b' Sources |
  grep -v -F "$action_process_boundary_file"; then
  echo "native-app architecture check failed: transcript action Process/Pipe usage is allowed only inside TranscriptActionProcessRunner." >&2
  exit 1
fi

echo "native-app architecture check passed."
