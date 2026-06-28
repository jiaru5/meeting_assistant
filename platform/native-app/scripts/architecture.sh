#!/usr/bin/env bash
set -euo pipefail

component_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$component_dir"

test -f tests/ArchitectureTest.md
grep -q "Component: \`native-app\`" tests/ArchitectureTest.md
grep -q "VS-MA-12 boundary" tests/ArchitectureTest.md
grep -q "VS-MA-13 fake recording boundary" tests/ArchitectureTest.md
grep -q "check_dependencies" tests/ArchitectureTest.md
test -f Sources/MeetingAssistantNative/DependencyCheckContract.swift
test -f Sources/MeetingAssistantNative/PermissionDependencyStatusViewModel.swift
test -f Sources/MeetingAssistantNative/PermissionDependencyStatusView.swift
test -f Sources/MeetingAssistantNative/RecordingCommandClient.swift
test -f Sources/MeetingAssistantNative/RecordingFakeCommandClient.swift
test -f Sources/MeetingAssistantNative/RecordingControlViewModel.swift
test -f Sources/MeetingAssistantNative/RecordingControlView.swift

grep -R -q "check_dependencies" Sources tests
grep -R -q "ma.permissionDependency" Sources tests
grep -R -q "start_native_recording" Sources tests
grep -R -q "stop_recording" Sources tests
grep -R -q "ma.recording" Sources tests

if grep -R --include '*.swift' -n -E 'ScreenCaptureKit|AVCapture|CGDisplayStream|SCStream|AVAudioEngine|AVAudioRecorder|generate_transcript|generate_speaker_labels|normalize_audio|URLSession|API_KEY|SECRET|TOKEN' Sources tests; then
  echo "native-app architecture check failed: VS-MA-13 may only implement fake recording UI/state and must not implement real capture, processing, external network calls or secrets." >&2
  exit 1
fi

recording_boundary_forbidden='(^[[:space:]]*import[[:space:]]+(ScreenCaptureKit|AVFoundation|CoreAudio|CoreMediaIO|ReplayKit|Network)\b|Process\b|ProcessInfo\b|NSTask\b|posix_spawn|execv|system[[:space:]]*\(|popen[[:space:]]*\(|meeting_assistant_cli|ProcessingCLIDependencyCheckRunner|DependencyCheckProcessRunner|native-helper|processing-cli|helper[[:space:]]+tool|ScreenCaptureKit|AVCapture|CGDisplayStream|SCStream|SCShareableContent|AVAudioEngine|AVAudioRecorder|RPScreenRecorder|CGWindowListCreate|CGDisplayCreateImage|AudioQueue|AudioUnit|AudioDevice|FileManager\b|FileHandle\b|OutputStream\b|InputStream\b|createFile[[:space:]]*\(|createDirectory[[:space:]]*\(|removeItem[[:space:]]*\(|copyItem[[:space:]]*\(|moveItem[[:space:]]*\(|\.(write|write(to|Bytes))[[:space:]]*\(|generate_transcript|generate_speaker_labels|normalize_audio|import_media|export_transcript|delete_session|check_dependencies|URLSession|URLRequest|URLSessionConfiguration|NWConnection|NWListener|WebSocket|https?://)'

if grep -R --include 'Recording*.swift' -n -E "$recording_boundary_forbidden" Sources tests; then
  echo "native-app architecture check failed: Recording*.swift must stay on the fake recording boundary and must not call processes, real helpers/CLIs, file writes, capture frameworks, processing commands or network APIs." >&2
  exit 1
fi

echo "native-app architecture check passed."
