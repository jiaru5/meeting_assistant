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
grep -q "VS-MA-23 local-direct app run boundary" tests/ArchitectureTest.md
grep -q "VS-MA-16 native processing state consumer boundary" tests/ArchitectureTest.md
grep -q "VS-MA-17 read-only transcript review boundary" tests/ArchitectureTest.md
grep -q "read-only workspace transcript loading boundary" tests/ArchitectureTest.md
grep -q "VS-MA-18/VS-MA-19 deterministic transcript action consumer boundary" tests/ArchitectureTest.md
grep -q "VS-MA-19A designed native shell boundary" tests/ArchitectureTest.md
grep -q "VS-MA-20 opt-in native app-bundle MVP full-stack smoke boundary" tests/ArchitectureTest.md
grep -q "MA_NATIVE_TRANSCRIPT_ACTION_CLIENT=process" tests/ArchitectureTest.md
grep -q "MA_NATIVE_RECORDING_CONTROLLED_MIXED_AUDIO=1" tests/ArchitectureTest.md
grep -q "Open Privacy Settings" tests/ArchitectureTest.md
grep -q "NSWorkspace.shared.open" tests/ArchitectureTest.md
grep -q "must not grant permissions" tests/ArchitectureTest.md
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
test -x scripts/run-local-app.sh
test -x scripts/install-local-app.sh
test -x scripts/local-direct-smoke.sh
test -x scripts/local-direct-recording-smoke.sh
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
grep -R -q "ma.permissionDependency.openPrivacySettingsButton" Sources tests App UITests
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
grep -q "CoreGraphicsScreenRecordingPermissionProbe" scripts/native-capture-smoke.sh
grep -q "requestAccessWhenDenied: true" scripts/native-capture-smoke.sh
grep -q "AVFoundationMicrophonePermissionProbe" scripts/native-capture-smoke.sh
grep -q "requestAccessWhenUndetermined: true" scripts/native-capture-smoke.sh
grep -q "AppleScreenCaptureKitNativeCaptureAdapter" scripts/native-capture-smoke.sh
grep -q "RecordingSessionStore" scripts/native-capture-smoke.sh
grep -q "MA_NATIVE_CAPTURE_SMOKE_AUDIO_PLAYBACK_PATH" scripts/native-capture-smoke.sh
grep -q "/usr/bin/afplay" scripts/native-capture-smoke.sh
grep -q "playbackStarted" scripts/native-capture-smoke.sh
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
grep -R -q "MA_NATIVE_REAL_RUNTIME_BRIDGE_SMOKE" tests scripts
grep -R -q "processRunnerWithRealWhisperRuntimeWritesWorkspaceArtifactsLoadableByTranscriptReviewWhenEnabled" tests
grep -R -q "VS-MA-22 native-app real runtime bridge marker" tests
grep -R -q "MA_NATIVE_VSMA21_HARDENING_BRIDGE_SMOKE" tests scripts
grep -R -q "processRunnerWithVSMA21HardeningFixtureRetriesPathConflictPreservingCaptureArtifactWhenEnabled" tests
grep -R -q "VS-MA-21 native-app hardening bridge marker" tests
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
grep -q "MA_NATIVE_APP_REAL_RUNTIME_SMOKE" scripts/test-app-bundle.sh
grep -q "MA_NATIVE_APP_VSMA21_HARDENING_SMOKE" scripts/test-app-bundle.sh
grep -q "MA_NATIVE_APP_REAL_CAPTURE_SAME_CHAIN_SMOKE" scripts/test-app-bundle.sh
grep -q "MA_NATIVE_APP_REAL_CAPTURE_REAL_RUNTIME_SAME_CHAIN_SMOKE" scripts/test-app-bundle.sh
grep -q "MA_NATIVE_APP_MVP_FULL_STACK_SMOKE" scripts/test-app-bundle.sh
grep -q "MA_NATIVE_APP_REUSE_XCTESTRUN" scripts/test-app-bundle.sh
grep -q "MA_NATIVE_APP_REUSE_XCTESTRUN:-auto" scripts/test-app-bundle.sh
grep -q ".meeting-assistant-xctestrun-inputs.sha256" scripts/test-app-bundle.sh
grep -q "compute_xctestrun_input_fingerprint" scripts/test-app-bundle.sh
grep -q "print_app_bundle_identity_diagnostics" scripts/test-app-bundle.sh
grep -q "print_app_bundle_tcc_identity_diagnostics" scripts/test-app-bundle.sh
grep -q "MA_NATIVE_APP_TCC_IDENTITY_DIAGNOSTICS" scripts/test-app-bundle.sh
grep -q "same CFBundleIdentifier" scripts/test-app-bundle.sh
grep -q "App bundle cdhash" scripts/test-app-bundle.sh
grep -q "MA_NATIVE_APP_UI_AUTOMATION_RETRY_ATTEMPTS" scripts/test-app-bundle.sh
grep -q "reset_xctestrun_smoke_env" scripts/test-app-bundle.sh
grep -q "run_app_bundle_test_without_building" scripts/test-app-bundle.sh
grep -q "test-without-building" scripts/test-app-bundle.sh
grep -q "PlistBuddy" scripts/test-app-bundle.sh
grep -q "permission_denied" scripts/test-app-bundle.sh
grep -q "real-capture-app-bundle-smoke.log" scripts/test-app-bundle.sh
grep -q "real-processing-app-bundle-smoke.log" scripts/test-app-bundle.sh
grep -q "real-action-app-bundle-smoke.log" scripts/test-app-bundle.sh
grep -q "real-runtime-app-bundle-smoke.log" scripts/test-app-bundle.sh
grep -q "vs-ma-21-hardening-app-bundle-smoke.log" scripts/test-app-bundle.sh
grep -q "vs-ma-21-hardening-ui-automation-report.json" scripts/test-app-bundle.sh
grep -q "real-capture-same-chain-app-bundle-smoke.log" scripts/test-app-bundle.sh
grep -q "real-capture-real-runtime-same-chain-app-bundle-smoke.log" scripts/test-app-bundle.sh
grep -q "mvp-full-stack-app-bundle-smoke.log" scripts/test-app-bundle.sh
grep -R -q "MA_NATIVE_PROCESSING_CLIENT" App UITests/MeetingAssistantNativeAppUITests
grep -R -q "AppRealProcessingCLIFixture" UITests/MeetingAssistantNativeAppUITests
grep -R -q "AppRealRuntimeProcessingCLIFixture" UITests/MeetingAssistantNativeAppUITests
test -x ../e2e/ma-cli-local.sh
grep -q "meeting_assistant_cli" ../e2e/ma-cli-local.sh
grep -R -q "MA_NATIVE_APP_XCTEST" App UITests/MeetingAssistantNativeAppUITests
grep -R -q "isProcessClientTestHookAllowed" App/MeetingAssistantNativeApp.swift
grep -R -q "isRealRuntimeProcessingSmokeEnabled" App/MeetingAssistantNativeApp.swift
grep -R -q "MA_NATIVE_TRANSCRIPT_ACTION_CLIENT" App UITests/MeetingAssistantNativeAppUITests
grep -R -q "MA_NATIVE_APP_REAL_ACTION_SMOKE" UITests/MeetingAssistantNativeAppUITests
grep -R -q "MA_NATIVE_APP_REAL_RUNTIME_SMOKE" UITests/MeetingAssistantNativeAppUITests
grep -R -q "MA_NATIVE_APP_VSMA21_HARDENING_SMOKE" UITests/MeetingAssistantNativeAppUITests
grep -R -q "MA_NATIVE_APP_REAL_CAPTURE_SAME_CHAIN_SMOKE" UITests/MeetingAssistantNativeAppUITests
grep -R -q "MA_NATIVE_APP_REAL_CAPTURE_REAL_RUNTIME_SAME_CHAIN_SMOKE" UITests/MeetingAssistantNativeAppUITests
grep -R -q "MA_NATIVE_APP_MVP_FULL_STACK_SMOKE" UITests/MeetingAssistantNativeAppUITests
grep -R -q "isExplicitProcessingRuntimeConfigured" App/MeetingAssistantNativeApp.swift
grep -R -q "MA_NATIVE_PROCESSING_RUNTIME" App/MeetingAssistantNativeApp.swift
grep -R -q "ProcessingCLIDependencyCheckRunner(environment: environment)" App/MeetingAssistantNativeApp.swift
grep -R -q "usesStaticDependencyFixture" App/MeetingAssistantNativeApp.swift
grep -R -q "initialReadinessState" App/MeetingAssistantNativeApp.swift
grep -R -q "NSApplicationDelegateAdaptor(MeetingAssistantNativeAppDelegate.self)" App/MeetingAssistantNativeApp.swift
grep -R -q "NSHostingController(rootView: rootView)" App/MeetingAssistantNativeApp.swift
grep -R -q "NSWindow(" App/MeetingAssistantNativeApp.swift
grep -R -q "window.setFrameAutosaveName(\"meeting-assistant-main\")" App/MeetingAssistantNativeApp.swift
grep -R -q "window.makeKeyAndOrderFront(nil)" App/MeetingAssistantNativeApp.swift
if grep -q "WindowGroup(\"Meeting Assistant Native" App/MeetingAssistantNativeApp.swift; then
  echo "native-app architecture check failed: local-direct app must not create a parallel SwiftUI WindowGroup for the main window." >&2
  exit 1
fi
grep -R -q "autoRefreshPreflightOnAppear" App/MeetingAssistantNativeApp.swift Sources/MeetingAssistantNative/DesignedNativeShellView.swift
grep -R -q "preflightWorkspaceURL" App/MeetingAssistantNativeApp.swift Sources/MeetingAssistantNative/DesignedNativeShellView.swift
grep -R -q ".onChange(of: permissionViewModel.state)" Sources/MeetingAssistantNative/DesignedNativeShellView.swift
grep -R -q "recordingViewModel.updateReadiness(readiness)" Sources/MeetingAssistantNative/DesignedNativeShellView.swift
grep -R -q "processingViewModel.updateReadiness(readiness)" Sources/MeetingAssistantNative/DesignedNativeShellView.swift
grep -R -q "await permissionViewModel.refresh(workspaceURL: preflightWorkspaceURL)" Sources/MeetingAssistantNative/DesignedNativeShellView.swift
grep -q "release-bundle-create.py" scripts/run-local-app.sh
grep -q "Contents/MacOS/MeetingAssistantNative" scripts/run-local-app.sh
grep -q "MA_NATIVE_LOCAL_APP_LAUNCH_MODE" scripts/run-local-app.sh
grep -q "launchctl setenv" scripts/run-local-app.sh
grep -q "launchctl unsetenv" scripts/run-local-app.sh
grep -q "open_args=(-n -W -F" scripts/run-local-app.sh
grep -q "MEETING_ASSISTANT_CLI_PATH" scripts/run-local-app.sh
grep -q "platform/e2e/ma-cli-local.sh" scripts/run-local-app.sh
grep -q "MEETING_ASSISTANT_TRANSCRIPTION_RUNTIME" scripts/run-local-app.sh
grep -q "MEETING_ASSISTANT_TRANSCRIPTION_MODEL" scripts/run-local-app.sh
grep -q "MA_NATIVE_PROCESSING_RUNTIME" scripts/run-local-app.sh
grep -q "MA_NATIVE_PROCESSING_LANGUAGE" scripts/run-local-app.sh
grep -q 'MA_NATIVE_CAPTURE_SMOKE_SYSTEM_AUDIO="${MA_NATIVE_CAPTURE_SMOKE_SYSTEM_AUDIO:-true}"' scripts/run-local-app.sh
grep -q 'MA_NATIVE_CAPTURE_SMOKE_MICROPHONE_AUDIO="${MA_NATIVE_CAPTURE_SMOKE_MICROPHONE_AUDIO:-false}"' scripts/run-local-app.sh
grep -q "MA_NATIVE_LOCAL_APP_REQUIRE_REAL_RUNTIME" scripts/run-local-app.sh
grep -q "MA_NATIVE_LOCAL_APP_DRY_RUN" scripts/run-local-app.sh
grep -q "local-direct" scripts/run-local-app.sh
grep -q "unset MA_NATIVE_APP_XCTEST" scripts/run-local-app.sh
if grep -q "Developer ID\\|notarytool\\|stapler\\|sigstore\\|cosign" scripts/run-local-app.sh; then
  echo "native-app architecture check failed: run-local-app.sh must not require Developer ID, notarization, stapling or Sigstore." >&2
  exit 1
fi
grep -q "release-bundle-create.py" scripts/install-local-app.sh
grep -q "local-direct" scripts/install-local-app.sh
grep -q "MA_NATIVE_LOCAL_APP_INSTALL_PATH" scripts/install-local-app.sh
grep -q "MA_NATIVE_LOCAL_APP_SOURCE_APP" scripts/install-local-app.sh
grep -q "MA_NATIVE_LOCAL_APP_INSTALL_REPORT" scripts/install-local-app.sh
grep -q "local-app-install-report.json" scripts/install-local-app.sh
grep -q '"release_gate": "local-direct-app-install"' scripts/install-local-app.sh
grep -q '"installed_app"' scripts/install-local-app.sh
grep -q "CFBundleIdentifier" scripts/install-local-app.sh
grep -q "local.meeting-assistant.native" scripts/install-local-app.sh
grep -q "CFBundleName" scripts/install-local-app.sh
grep -q "MeetingAssistantNative" scripts/install-local-app.sh
grep -q "modifies tcc or system settings: false" scripts/install-local-app.sh
grep -q "requires developer id or notarization: false" scripts/install-local-app.sh
grep -q '"modifies_tcc_or_system_settings": False' scripts/install-local-app.sh
grep -q '"requires_developer_id_or_notarization": False' scripts/install-local-app.sh
grep -q '"not_release_readiness": True' scripts/install-local-app.sh
grep -q "codesign --verify --deep --strict" scripts/install-local-app.sh
if grep -q "x-apple.systempreferences\\|tccutil\\|security authorizationdb\\|notarytool\\|stapler\\|cosign" scripts/install-local-app.sh; then
  echo "native-app architecture check failed: local app installer must not open System Settings, modify TCC, or require distribution gates." >&2
  exit 1
fi
grep -q "run-local-app.sh" scripts/local-direct-smoke.sh
grep -q "System Events" scripts/local-direct-smoke.sh
grep -q "local-direct-ui-smoke" scripts/local-direct-smoke.sh
grep -q "AXIdentifier" scripts/local-direct-smoke.sh
grep -q "AXEnabled" scripts/local-direct-smoke.sh
grep -q "ma.recording.startButton" scripts/local-direct-smoke.sh
grep -q "ma.recording.stopButton" scripts/local-direct-smoke.sh
grep -q "ma.processing.startButton" scripts/local-direct-smoke.sh
grep -q "ma.processing.retryButton" scripts/local-direct-smoke.sh
grep -q "verifies_action_control_identifiers" scripts/local-direct-smoke.sh
grep -q "recording_setup_marker_for_request" scripts/local-direct-smoke.sh
grep -q "checked_recording_setup_text" scripts/local-direct-smoke.sh
grep -q "System audio capture is requested; microphone capture is not requested for this run." scripts/local-direct-smoke.sh
grep -q '"opens_system_settings": False' scripts/local-direct-smoke.sh
grep -q '"starts_recording": False' scripts/local-direct-smoke.sh
grep -q '"requires_developer_id_or_notarization": False' scripts/local-direct-smoke.sh
grep -q "Preflight: Ready" scripts/local-direct-smoke.sh
grep -q "Recording readiness is ready." scripts/local-direct-smoke.sh
grep -q "Processing is ready to run." scripts/local-direct-smoke.sh
if grep -q "CGRequestScreenCaptureAccess\\|AVCaptureDevice\\.requestAccess\\|x-apple.systempreferences\\|tccutil\\|security authorizationdb\\|notarytool\\|stapler\\|cosign" scripts/local-direct-smoke.sh; then
  echo "native-app architecture check failed: local-direct smoke must not request permissions, open System Settings, or require distribution gates." >&2
  exit 1
fi
grep -q "run-local-app.sh" scripts/local-direct-recording-smoke.sh
grep -q "local-direct-recording-smoke" scripts/local-direct-recording-smoke.sh
grep -q "AXIdentifier" scripts/local-direct-recording-smoke.sh
grep -q "AXPress" scripts/local-direct-recording-smoke.sh
grep -q "ma.recording.startButton" scripts/local-direct-recording-smoke.sh
grep -q "ma.recording.stopButton" scripts/local-direct-recording-smoke.sh
grep -q "Recording in progress." scripts/local-direct-recording-smoke.sh
grep -q "Recording saved." scripts/local-direct-recording-smoke.sh
grep -q "recording_request" scripts/local-direct-recording-smoke.sh
grep -q "permission_failure_details" scripts/local-direct-recording-smoke.sh
grep -q "tcc_identity_mismatch_hint" scripts/local-direct-recording-smoke.sh
grep -q '"starts_recording": True' scripts/local-direct-recording-smoke.sh
grep -q '"may_request_macos_permissions": True' scripts/local-direct-recording-smoke.sh
grep -q '"not_release_readiness": True' scripts/local-direct-recording-smoke.sh
if grep -q "x-apple.systempreferences\\|tccutil\\|security authorizationdb\\|notarytool\\|stapler\\|cosign" scripts/local-direct-recording-smoke.sh; then
  echo "native-app architecture check failed: local-direct recording smoke must not open System Settings, modify TCC, or require distribution gates." >&2
  exit 1
fi
grep -q "Production/default app runtime may pass an explicitly configured" tests/ArchitectureTest.md
python3 - <<'PY'
import sys
from pathlib import Path

source = Path("UITests/MeetingAssistantNativeAppUITests/AppBundleLocatorSmokeTests.swift").read_text(
    encoding="utf-8"
)
test_start = source.find("func testVSMA21RealScreenCaptureKitProcessingTranscriptActionsSameChainWhenExplicitlyEnabled")
next_test = source.find("\n    func test", test_start + 1)
fixture_start = source.find("private final class AppRealCaptureSameChainCLIFixture")
next_fixture = source.find("\nprivate final class", fixture_start + 1)

same_chain_test = source[test_start:next_test]
same_chain_fixture = source[fixture_start:next_fixture]

if 'assertElement("ma.recording.artifact.microphone_audio.status", in: app, contains: "microphone_audio: available")' in same_chain_test:
    print(
        "native-app architecture check failed: VS-MA-21 same-chain smoke must not require independent microphone_audio availability.",
        file=sys.stderr,
    )
    sys.exit(1)

if "captureSystemAudio: true" not in same_chain_fixture or "captureMicrophoneAudio: false" not in same_chain_fixture:
    print(
        "native-app architecture check failed: VS-MA-21 same-chain smoke must request system audio while keeping microphone audio disabled.",
        file=sys.stderr,
    )
    sys.exit(1)
PY
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

app_settings = [
    settings
    for settings in debug_settings + release_settings
    if 'PRODUCT_BUNDLE_IDENTIFIER = "local.meeting-assistant.native";' in settings
]
if len(app_settings) != 2:
    raise SystemExit("native-app architecture check failed: expected Debug and Release app target configurations.")

missing_microphone_usage = [
    settings
    for settings in app_settings
    if "INFOPLIST_KEY_NSMicrophoneUsageDescription" not in settings
]
if missing_microphone_usage:
    raise SystemExit(
        "native-app architecture check failed: app target must declare NSMicrophoneUsageDescription so macOS can prompt for microphone permission."
    )

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

permission_privacy_settings_file='Sources/MeetingAssistantNative/PermissionDependencyStatusView.swift'
grep -q 'Button("Open Privacy Settings")' "$permission_privacy_settings_file"
grep -q 'openPrivacySettings()' "$permission_privacy_settings_file"
grep -q 'NSWorkspace.shared.open(url)' "$permission_privacy_settings_file"
grep -q 'x-apple.systempreferences:com.apple.preference.security?Privacy_ScreenCapture' "$permission_privacy_settings_file"
grep -q 'PermissionDependencyAccessibilityID.openPrivacySettingsButton' "$permission_privacy_settings_file"

if grep -R --include '*.swift' -n -E 'NSWorkspace\b|x-apple\.systempreferences' Sources tests App UITests |
  grep -v -F "$permission_privacy_settings_file"; then
  echo "native-app architecture check failed: opening macOS privacy settings is allowed only from PermissionDependencyStatusView.swift." >&2
  exit 1
fi

if grep -n -E 'tccutil|AuthorizationExecute|authorizationdb|SMJobBless|osascript|do shell script|defaults[[:space:]]+write|security[[:space:]]+authorizationdb|Process\b|NSTask\b|posix_spawn|execv|system[[:space:]]*\(|popen[[:space:]]*\(|CGRequestScreenCaptureAccess|AVCaptureDevice\.requestAccess' "$permission_privacy_settings_file"; then
  echo "native-app architecture check failed: permission remediation may only open System Settings and must not mutate TCC, authorization databases, or system settings." >&2
  exit 1
fi

apple_adapter_file='Sources/MeetingAssistantNative/AppleScreenCaptureKitNativeCaptureAdapter.swift'
native_permission_file='Sources/MeetingAssistantNative/NativeCapturePermissionChecker.swift'
apple_framework_forbidden='(^[[:space:]]*import[[:space:]]+(ScreenCaptureKit|AVFoundation|CoreAudio|CoreMediaIO|ReplayKit|Network)\b|SCStream\b|SCStreamOutput\b|SCRecordingOutput\b|SCContentFilter\b|SCShareableContent\b|AVAssetWriter\b|AVCapture|CGDisplayStream|AVAudioEngine|AVAudioRecorder|AudioQueue|AudioUnit|AudioDevice)'
permission_checker_capture_forbidden='(ScreenCaptureKit\b|SCStream\b|SCStreamOutput\b|SCRecordingOutput\b|SCContentFilter\b|SCShareableContent\b|CoreAudio\b|CoreMediaIO\b|ReplayKit\b|Network\b|CGDisplayStream\b|AVAssetWriter\b|AVAudioEngine\b|AVAudioRecorder\b|AudioQueue\b|AudioUnit\b|AudioDevice\b)'

grep -q 'producesSeparateAudioArtifacts: true' "$apple_adapter_file"
grep -q 'attemptsMixedAudioExtractionFromCombinedRecording: true' "$apple_adapter_file"
grep -q 'AppleScreenCaptureKitMixedAudioExtracting' "$apple_adapter_file"
grep -q 'AVAssetExportSession' "$apple_adapter_file"
grep -q 'SCStreamOutput' "$apple_adapter_file"
grep -q 'AVAssetWriter' "$apple_adapter_file"
grep -q 'AVFoundationMicrophonePermissionProbe' "$native_permission_file"
grep -q 'AVCaptureDevice.authorizationStatus(for: .audio)' "$native_permission_file"
grep -q 'AVCaptureDevice.requestAccess(for: .audio)' "$native_permission_file"

if grep -R --include '*.swift' -n -E "$apple_framework_forbidden" Sources tests App UITests |
  grep -v -F "$apple_adapter_file" |
  grep -v -F "$native_permission_file"; then
  echo "native-app architecture check failed: Apple capture framework usage is allowed only in AppleScreenCaptureKitNativeCaptureAdapter.swift and microphone permission checks in NativeCapturePermissionChecker.swift." >&2
  exit 1
fi

if grep -n -E "$permission_checker_capture_forbidden" "$native_permission_file"; then
  echo "native-app architecture check failed: NativeCapturePermissionChecker.swift may use AVFoundation only for microphone authorization status/request access." >&2
  exit 1
fi

action_os_boundary_file='Sources/MeetingAssistantNative/TranscriptActionOSClients.swift'

if grep -R --include '*.swift' -n -E 'normalize_audio|URLSession|URLRequest|URLSessionConfiguration|NWConnection|NWListener|WebSocket|https?://|NSPasteboard|API_KEY|SECRET|TOKEN' Sources tests App UITests |
  grep -v -F "$action_os_boundary_file" |
  grep -v -E 'UITests/MeetingAssistantNativeAppUITests/AppBundleLocatorSmokeTests.swift:[0-9]+:.*NSPasteboard'; then
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
  Sources/MeetingAssistantNative/RecordingSessionStore.swift |
  grep -v -F "$native_permission_file"; then
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
   ! grep -q 'case "fake":' App/MeetingAssistantNativeApp.swift ||
   ! grep -q 'isRealNativeCaptureSmokeEnabled(environment)' App/MeetingAssistantNativeApp.swift ||
   ! grep -q 'defaultRecordingClientMode(environment)' App/MeetingAssistantNativeApp.swift ||
   ! grep -q 'isNativeAppXCTestEnvironment(environment) ? .fake : .appleScreenCaptureKit' App/MeetingAssistantNativeApp.swift ||
   ! grep -q 'return isRecordingClientTestHookAllowed(environment) ? .fake : defaultRecordingClientMode(environment)' App/MeetingAssistantNativeApp.swift ||
   ! grep -q 'AppleScreenCaptureKitNativeCaptureAdapter()' App/MeetingAssistantNativeApp.swift ||
   ! grep -q 'MacOSNativeCapturePermissionChecker(' App/MeetingAssistantNativeApp.swift ||
   ! grep -q 'CoreGraphicsScreenRecordingPermissionProbe(' App/MeetingAssistantNativeApp.swift ||
   ! grep -q 'requestAccessWhenDenied: true' App/MeetingAssistantNativeApp.swift ||
   ! grep -q 'AVFoundationMicrophonePermissionProbe(' App/MeetingAssistantNativeApp.swift ||
   ! grep -q 'requestAccessWhenUndetermined: true' App/MeetingAssistantNativeApp.swift; then
  echo "native-app architecture check failed: production recording default must use the Apple adapter while XCTest hooks stay explicit, permission-checked, and smoke-gated." >&2
  exit 1
fi

if grep -q 'guard let rawValue,' App/MeetingAssistantNativeApp.swift &&
   grep -q 'isRecordingClientTestHookAllowed(environment) else' App/MeetingAssistantNativeApp.swift; then
  echo "native-app architecture check failed: production recording default must not fall back to fake only because the Debug/XCTest recording hook is absent." >&2
  exit 1
fi

app_bundle_forbidden='meeting_assistant_cli|ProcessingCLIDependencyCheckRunner|DependencyCheckProcessRunner|native-helper|processing-cli|helper[[:space:]]+tool|AVCapture|CGDisplayStream|SCStream|AVAudioEngine|AVAudioRecorder|generate_transcript|generate_speaker_labels|normalize_audio|import_media|export_transcript|delete_session|URLSession|URLRequest|NWConnection|NWListener|https?://|curl|wget'

if grep -R --include '*.swift' -n -E "$app_bundle_forbidden" App UITests/MeetingAssistantNativeAppUITests |
  grep -v -E 'App/MeetingAssistantNativeApp.swift:.*ProcessingCLIDependencyCheckRunner' |
  grep -v -E 'MA_NATIVE_APP_REAL_PROCESSING_SMOKE|MA_NATIVE_APP_REAL_ACTION_SMOKE|MA_NATIVE_APP_VSMA21_HARDENING_SMOKE|MA_NATIVE_APP_REAL_CAPTURE_SAME_CHAIN_SMOKE|MA_NATIVE_APP_REAL_CAPTURE_REAL_RUNTIME_SAME_CHAIN_SMOKE|MA_NATIVE_APP_MVP_FULL_STACK_SMOKE|real processing-cli app-bundle smoke|VS-MA-21 app-bundle hardening smoke|real capture same-chain|real capture \+ real runtime|MVP full-stack'; then
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
