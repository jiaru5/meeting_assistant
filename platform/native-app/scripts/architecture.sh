#!/usr/bin/env bash
set -euo pipefail

component_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$component_dir"

test -f tests/ArchitectureTest.md
grep -q "Component: \`native-app\`" tests/ArchitectureTest.md
grep -q "VS-MA-12 boundary" tests/ArchitectureTest.md
grep -q "VS-MA-13 fake recording boundary" tests/ArchitectureTest.md
grep -q "VS-MA-16 native processing state consumer boundary" tests/ArchitectureTest.md
grep -q "VS-MA-17 read-only transcript review boundary" tests/ArchitectureTest.md
grep -q "read-only workspace transcript loading boundary" tests/ArchitectureTest.md
grep -q "VS-MA-18/VS-MA-19 deterministic transcript action consumer boundary" tests/ArchitectureTest.md
grep -q "check_dependencies" tests/ArchitectureTest.md
grep -q "session.json" tests/ArchitectureTest.md
grep -q "transcript.json" tests/ArchitectureTest.md
grep -q "speaker_labels.json" tests/ArchitectureTest.md
grep -q "ma.processing" tests/ArchitectureTest.md
grep -q "ma.transcriptAction" tests/ArchitectureTest.md
test -f MeetingAssistantNative.xcodeproj/project.pbxproj
test -f MeetingAssistantNative.xcodeproj/xcshareddata/xcschemes/MeetingAssistantNative.xcscheme
test -f App/MeetingAssistantNativeApp.swift
test -f Sources/MeetingAssistantNative/DependencyCheckContract.swift
test -f Sources/MeetingAssistantNative/PermissionDependencyStatusViewModel.swift
test -f Sources/MeetingAssistantNative/PermissionDependencyStatusView.swift
test -f Sources/MeetingAssistantNative/RecordingCommandClient.swift
test -f Sources/MeetingAssistantNative/RecordingFakeCommandClient.swift
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
test -x test-fixtures/processing-command-fixture.sh
test -f tests/MeetingAssistantNativeTests/TranscriptReviewActionsViewModelTests.swift
test -f tests/MeetingAssistantNativeTests/ProcessingStateViewModelTests.swift
test -f UITests/MeetingAssistantNativeUITests/NativeControlPlaneSmokeTests.swift
test -f UITests/MeetingAssistantNativeAppUITests/AppBundleLocatorSmokeTests.swift

grep -R -q "check_dependencies" Sources tests App
grep -R -q "ma.permissionDependency" Sources tests App UITests
grep -R -q "start_native_recording" Sources tests
grep -R -q "stop_recording" Sources tests
grep -R -q "ma.recording" Sources tests App UITests
grep -R -q "ma.processing" Sources tests App UITests
grep -R -q "ma.transcript" Sources tests App UITests
grep -R -q "ma.transcriptAction" Sources tests App UITests
grep -R -q "TranscriptReviewViewModel" Sources tests App UITests
grep -R -q "TranscriptReviewWorkspaceLoader" Sources tests App UITests
grep -R -q "TranscriptReviewActionsViewModel" Sources tests App UITests
grep -R -q "TranscriptActionFakeCommandClient" Sources tests App UITests
grep -R -q "ProcessingStateViewModel" Sources tests App UITests
grep -R -q "ProcessingCommandFakeClient" Sources tests App UITests
grep -R -q "ProcessingCommandProcessRunner" Sources tests App UITests
grep -R -q "MA_NATIVE_PROCESSING_CLIENT" App UITests/MeetingAssistantNativeAppUITests
grep -R -q "MA_NATIVE_APP_XCTEST" App UITests/MeetingAssistantNativeAppUITests
grep -R -q "isProcessClientTestHookAllowed" App/MeetingAssistantNativeApp.swift
grep -R -q "#if DEBUG" App/MeetingAssistantNativeApp.swift
grep -q "SWIFT_ACTIVE_COMPILATION_CONDITIONS = DEBUG;" MeetingAssistantNative.xcodeproj/project.pbxproj
grep -q '"command": "generate_transcript"' test-fixtures/processing-command-fixture.sh
grep -q '"command": "generate_speaker_labels"' test-fixtures/processing-command-fixture.sh
grep -R -q "MA_NATIVE_TRANSCRIPT_WORKSPACE" App UITests/MeetingAssistantNativeAppUITests
grep -R -q "XCTest" UITests
grep -R -q "NSHostingController" UITests/MeetingAssistantNativeUITests
grep -R -q "XCUIApplication" UITests/MeetingAssistantNativeAppUITests
grep -R -q "MA_NATIVE_APP_SMOKE_FIXTURE" App UITests/MeetingAssistantNativeAppUITests
grep -R -q "MeetingAssistantNativeAppUITests" MeetingAssistantNative.xcodeproj/project.pbxproj

if grep -R --include '*.swift' -n -E 'ScreenCaptureKit|AVCapture|CGDisplayStream|SCStream|AVAudioEngine|AVAudioRecorder|normalize_audio|URLSession|NSPasteboard|API_KEY|SECRET|TOKEN' Sources tests App UITests; then
  echo "native-app architecture check failed: VS-MA-13 may only implement fake recording UI/state and must not implement real capture, processing, external network calls or secrets." >&2
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

if grep -R --include 'Recording*.swift' -n -E "$recording_boundary_forbidden" Sources tests ||
  grep -R --include '*.swift' -n -E "$recording_boundary_forbidden" UITests/MeetingAssistantNativeUITests; then
  echo "native-app architecture check failed: recording UI/state and UITests must stay on the fake recording boundary and must not call processes, real helpers/CLIs, file writes, capture frameworks, processing commands or network APIs." >&2
  exit 1
fi

app_bundle_forbidden='meeting_assistant_cli|ProcessingCLIDependencyCheckRunner|DependencyCheckProcessRunner|native-helper|processing-cli|helper[[:space:]]+tool|ScreenCaptureKit|AVCapture|CGDisplayStream|SCStream|AVAudioEngine|AVAudioRecorder|generate_transcript|generate_speaker_labels|normalize_audio|import_media|export_transcript|delete_session|URLSession|URLRequest|NWConnection|NWListener|https?://|curl|wget'

if grep -R --include '*.swift' -n -E "$app_bundle_forbidden" App UITests/MeetingAssistantNativeAppUITests; then
  echo "native-app architecture check failed: app-bundle smoke must keep processing command strings inside the native-owned shell fixture and must not call provider internals, capture frameworks, downloads, or network APIs." >&2
  exit 1
fi

action_boundary_forbidden='(^[[:space:]]*import[[:space:]]+(AppKit|ScreenCaptureKit|AVFoundation|CoreAudio|CoreMediaIO|ReplayKit|Network)\b|Process\b|NSTask\b|posix_spawn|execv|system[[:space:]]*\(|popen[[:space:]]*\(|meeting_assistant_cli|ProcessingCLIDependencyCheckRunner|DependencyCheckProcessRunner|native-helper|processing-cli|helper[[:space:]]+tool|ScreenCaptureKit|AVCapture|CGDisplayStream|SCStream|AVAudioEngine|AVAudioRecorder|NSPasteboard|NSOpenPanel|NSSavePanel|FileManager\b|FileHandle\b|OutputStream\b|InputStream\b|createFile[[:space:]]*\(|createDirectory[[:space:]]*\(|removeItem[[:space:]]*\(|copyItem[[:space:]]*\(|moveItem[[:space:]]*\(|\.(write|write(to|Bytes))[[:space:]]*\(|URLSession|URLRequest|URLSessionConfiguration|NWConnection|NWListener|WebSocket|https?://)'

if grep -R --include 'TranscriptAction*.swift' --include 'TranscriptReviewActions*.swift' -n -E "$action_boundary_forbidden" Sources; then
  echo "native-app architecture check failed: transcript action consumer must stay on deterministic fake/injected boundaries and must not call helpers/CLIs, real pasteboard, file pickers, file deletion, processing internals or network APIs." >&2
  exit 1
fi

echo "native-app architecture check passed."
