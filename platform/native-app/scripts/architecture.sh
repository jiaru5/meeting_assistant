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
grep -q "VS-MA-26 through VS-MA-30 task-based meeting workflow boundary" tests/ArchitectureTest.md
grep -q "VS-MA-20 opt-in native app-bundle MVP full-stack smoke boundary" tests/ArchitectureTest.md
grep -q "MA_NATIVE_TRANSCRIPT_ACTION_CLIENT=process" tests/ArchitectureTest.md
grep -q "MA_NATIVE_RECORDING_CONTROLLED_MIXED_AUDIO=1" tests/ArchitectureTest.md
grep -q "Open Screen Recording Settings" tests/ArchitectureTest.md
grep -q "Open Microphone Settings" tests/ArchitectureTest.md
grep -q "NSWorkspace.shared.open" tests/ArchitectureTest.md
grep -q "ma.permissionDependency.appIdentity" tests/ArchitectureTest.md
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
grep -q "ma.meetings" tests/ArchitectureTest.md
grep -q "ma.newRecording" tests/ArchitectureTest.md
grep -q "ma.meetingDetail" tests/ArchitectureTest.md
grep -q "ma.diagnostics" tests/ArchitectureTest.md
test -f MeetingAssistantNative.xcodeproj/project.pbxproj
test -f MeetingAssistantNative.xcodeproj/xcshareddata/xcschemes/MeetingAssistantNative.xcscheme
test -x scripts/native-capture-smoke.sh
test -x scripts/run-local-app.sh
test -x scripts/install-local-app.sh
test -x scripts/local-app-permission-diagnostics.sh
test -x scripts/local-direct-smoke.sh
test -x scripts/local-direct-recording-smoke.sh
test -x scripts/local-direct-processing-smoke.sh
test -x scripts/local-direct-actions-smoke.sh
test -x scripts/local-direct-same-chain-smoke.sh
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
test -f Sources/MeetingAssistantNative/MeetingSessionWorkspaceRepository.swift
test -f Sources/MeetingAssistantNative/MeetingWorkspaceCoordinator.swift
test -x test-fixtures/processing-command-fixture.sh
test -x test-fixtures/transcript-action-command-fixture.sh
test -f tests/MeetingAssistantNativeTests/NativeRecordingCommandClientTests.swift
test -f tests/MeetingAssistantNativeTests/TranscriptReviewActionsViewModelTests.swift
test -f tests/MeetingAssistantNativeTests/ProcessingStateViewModelTests.swift
test -f tests/MeetingAssistantNativeTests/DesignedNativeShellViewModelTests.swift
test -f tests/MeetingAssistantNativeTests/MeetingSessionWorkspaceRepositoryTests.swift
test -f tests/MeetingAssistantNativeTests/MeetingWorkspaceCoordinatorTests.swift
test -f UITests/MeetingAssistantNativeUITests/NativeControlPlaneSmokeTests.swift
test -f UITests/MeetingAssistantNativeAppUITests/AppBundleLocatorSmokeTests.swift
test -f UITests/MeetingAssistantNativeAppUITests/DesignedNativeShellAppBundleTests.swift
test -x ../../scripts/mvp1-task-xcresult.py
test -x ../../scripts/mvp1-accessibility-walkthrough.py
test -x ../../scripts/mvp1-experience-study.py

grep -R -q "check_dependencies" Sources tests App
grep -R -q "ma.permissionDependency" Sources tests App UITests
grep -R -q "ma.permissionDependency.openPrivacySettingsButton" Sources tests App UITests
grep -R -q "ma.permissionDependency.openMicrophoneSettingsButton" Sources tests App UITests
grep -R -q "ma.permissionDependency.appIdentity" Sources tests App UITests
grep -R -q "LocalAppPermissionIdentity" Sources tests App UITests
grep -R -q "bundlePath" Sources tests App UITests
grep -R -q "codeSignatureHash" Sources tests App UITests
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
grep -R -q "ma.meetings" Sources tests App UITests
grep -R -q "ma.newRecording" Sources tests App UITests
grep -R -q "ma.meetingDetail" Sources tests App UITests
grep -R -q "ma.diagnostics" Sources tests App UITests
grep -R -q "MeetingSessionWorkspaceRepository" Sources tests App UITests
grep -R -q "MeetingWorkspaceCoordinator" Sources tests App UITests
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
grep -q "MA_NATIVE_APP_PREPARE_ONLY" scripts/test-app-bundle.sh
grep -q -- "-resultBundlePath" scripts/test-app-bundle.sh
grep -q "final-attempt-path.txt" scripts/test-app-bundle.sh
grep -q "verify_mvp1_task_xcresult" scripts/test-app-bundle.sh
grep -q "mvp1-task-xcresult.py" scripts/test-app-bundle.sh
grep -q "require_current_xctestrun_fingerprint_for_task_evidence" scripts/test-app-bundle.sh
grep -q "task-artifacts-before-test.json" scripts/test-app-bundle.sh
grep -q "app_bundle_lock_path" scripts/test-app-bundle.sh
grep -q "run_frozen_task_xcresult_verifier" scripts/test-app-bundle.sh
grep -q "require_trusted_mvp1_toolchain" scripts/test-app-bundle.sh
grep -q "anchor apple" scripts/test-app-bundle.sh
grep -q 'python_tool="/usr/bin/python3"' scripts/test-app-bundle.sh
test "$(grep -c '"$python_tool" -I -S' scripts/test-app-bundle.sh)" -eq 9
grep -Fqx '#!/usr/bin/env -S /usr/bin/python3 -I -S' ../../scripts/mvp1-task-xcresult.py
grep -Fqx '#!/usr/bin/env -S /usr/bin/python3 -I -S' ../../scripts/mvp1-accessibility-walkthrough.py
grep -Fqx '#!/usr/bin/env -S /usr/bin/python3 -I -S' ../../scripts/mvp1-experience-study.py
grep -q "run_clean_git" scripts/test-app-bundle.sh
grep -q "/usr/bin/env -i" scripts/test-app-bundle.sh
! grep -q "shasum" scripts/test-app-bundle.sh
grep -q "MVP1_ARTIFACT_BINDING_SHA256" scripts/test-app-bundle.sh
grep -q -- "--expected-verifier-sha256" scripts/test-app-bundle.sh
grep -q -- "--expected-artifact-binding-sha256" scripts/test-app-bundle.sh
grep -q -- "--xcodebuild-tool" scripts/test-app-bundle.sh
grep -q -- "--xctestrun" ../../scripts/mvp1-task-xcresult.py
grep -q -- "--upstream-test-status" ../../scripts/mvp1-task-xcresult.py
grep -q -- "--artifact-binding-file" ../../scripts/mvp1-task-xcresult.py
grep -q "strict code-signature verification" ../../scripts/mvp1-task-xcresult.py
grep -q "directory_manifest" ../../scripts/mvp1-task-xcresult.py
grep -q "full image decode" ../../scripts/mvp1-task-xcresult.py
grep -q "read_xctestrun_binding" ../../scripts/mvp1-task-xcresult.py
grep -q "captured_by_verifier_sha256" ../../scripts/mvp1-task-xcresult.py
grep -q "expected_artifact_binding_sha256" ../../scripts/mvp1-task-xcresult.py
grep -q "verifier_snapshot" ../../scripts/mvp1-task-xcresult.py
grep -q "validated_toolchain" ../../scripts/mvp1-task-xcresult.py
grep -q "clean_git_environment" ../../scripts/mvp1-task-xcresult.py
grep -q "fixture_checks_passed" ../../scripts/mvp1-task-xcresult.py
grep -q "screenshot_visual_review" ../../scripts/mvp1-task-xcresult.py
grep -q "EXPECTED_TEST_COUNT = 17" ../../scripts/mvp1-task-xcresult.py
grep -q "00-meetings-recent" ../../scripts/mvp1-task-xcresult.py
grep -q "07-diagnostics" ../../scripts/mvp1-task-xcresult.py
grep -q "passed_task_xcresult_provenance_required" ../../scripts/mvp1-accessibility-walkthrough.py
grep -q "current_trusted_task_toolchain" ../../scripts/mvp1-accessibility-walkthrough.py
grep -q "PRIVACY_ATTESTATION_STATEMENT" ../../scripts/mvp1-accessibility-walkthrough.py
grep -q "MA_NATIVE_APP_FOREIGN_INSTANCE_POLICY:-fail" scripts/test-app-bundle.sh
grep -Fq 'Test Case (' scripts/test-app-bundle.sh
grep -q ".meeting-assistant-xctestrun-inputs.sha256" scripts/test-app-bundle.sh
grep -q "compute_xctestrun_input_fingerprint" scripts/test-app-bundle.sh
grep -q "print_app_bundle_identity_diagnostics" scripts/test-app-bundle.sh
grep -q "print_ui_test_runner_identity_diagnostics" scripts/test-app-bundle.sh
grep -q "validate_prepared_app_bundle_artifacts" scripts/test-app-bundle.sh
grep -q 'prepare_xctestrun "full suite"' scripts/test-app-bundle.sh
grep -q 'run_app_bundle_test_without_building "full suite"' scripts/test-app-bundle.sh
grep -q "print_app_bundle_tcc_identity_diagnostics" scripts/test-app-bundle.sh
grep -q "MA_NATIVE_APP_TCC_IDENTITY_DIAGNOSTICS" scripts/test-app-bundle.sh
grep -q "same CFBundleIdentifier" scripts/test-app-bundle.sh
grep -q "App bundle cdhash" scripts/test-app-bundle.sh
grep -q "UI test runner cdhash" scripts/test-app-bundle.sh
grep -q "UI test runner designated requirement" scripts/test-app-bundle.sh
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
grep -R -q "init() {" App/MeetingAssistantNativeApp.swift
grep -R -q "Task { @MainActor in" App/MeetingAssistantNativeApp.swift
grep -R -q "NSApplication.didFinishLaunchingNotification" App/MeetingAssistantNativeApp.swift
grep -R -q "NSApplication.didBecomeActiveNotification" App/MeetingAssistantNativeApp.swift
grep -R -q "reopenMainWindowIfNeeded()" App/MeetingAssistantNativeApp.swift
grep -R -q "MeetingAssistantNativeMainWindow.shared.openMainWindow()" App/MeetingAssistantNativeApp.swift
grep -R -q "NativeLocalAppKeyboardShortcutView" App/MeetingAssistantNativeApp.swift
grep -R -q "NSEvent.addLocalMonitorForEvents(matching: .keyDown)" App/MeetingAssistantNativeApp.swift
grep -R -q "event.modifierFlags.intersection(.deviceIndependentFlagsMask)" App/MeetingAssistantNativeApp.swift
grep -R -q "startRecording()" App/MeetingAssistantNativeApp.swift
grep -R -q "stopRecording()" App/MeetingAssistantNativeApp.swift
grep -R -q "startProcessing()" App/MeetingAssistantNativeApp.swift
grep -R -q "copyTranscript()" App/MeetingAssistantNativeApp.swift
grep -R -q "exportTranscript()" App/MeetingAssistantNativeApp.swift
grep -R -q "requestDelete()" App/MeetingAssistantNativeApp.swift
grep -R -q "confirmDelete()" App/MeetingAssistantNativeApp.swift
grep -R -q "final class MeetingAssistantNativeMainWindow" App/MeetingAssistantNativeApp.swift
grep -R -q "private var windowController: NSWindowController" App/MeetingAssistantNativeApp.swift
grep -R -q "var hasVisibleWindow: Bool" App/MeetingAssistantNativeApp.swift
grep -R -q "NSHostingController(rootView: rootView)" App/MeetingAssistantNativeApp.swift
grep -R -q "NSWindow(" App/MeetingAssistantNativeApp.swift
grep -R -q "window.setAccessibilityElement(true)" App/MeetingAssistantNativeApp.swift
grep -R -q "window.setAccessibilityRole(.window)" App/MeetingAssistantNativeApp.swift
grep -R -q "window.setAccessibilitySubrole(.standardWindow)" App/MeetingAssistantNativeApp.swift
grep -R -q "window.setAccessibilityTitle(\"Meeting Assistant Native\")" App/MeetingAssistantNativeApp.swift
grep -R -q "hostingController.view.setAccessibilityElement(true)" App/MeetingAssistantNativeApp.swift
grep -R -q "hostingController.view.setAccessibilityRole(.group)" App/MeetingAssistantNativeApp.swift
grep -R -q "hostingController.view.setAccessibilityLabel(\"Meeting Assistant\")" App/MeetingAssistantNativeApp.swift
grep -R -q "window.setFrameAutosaveName(\"meeting-assistant-main\")" App/MeetingAssistantNativeApp.swift
grep -R -q "window.makeKeyAndOrderFront(nil)" App/MeetingAssistantNativeApp.swift
if grep -q "NSApplicationDelegateAdaptor\\|MeetingAssistantNativeAppDelegate\\|applicationDidFinishLaunching\\|WindowGroup(\"Meeting Assistant Native" App/MeetingAssistantNativeApp.swift; then
  echo "native-app architecture check failed: local-direct launch must use App.init plus a retained AppKit window controller, not AppDelegate or WindowGroup auto-open." >&2
  exit 1
fi
grep -R -q "autoRefreshPreflightOnAppear" App/MeetingAssistantNativeApp.swift Sources/MeetingAssistantNative/DesignedNativeShellView.swift
grep -R -q "workspaceURL" App/MeetingAssistantNativeApp.swift Sources/MeetingAssistantNative/DesignedNativeShellView.swift
grep -R -q ".onChange(of: permissionViewModel.state)" Sources/MeetingAssistantNative/DesignedNativeShellView.swift
grep -R -q ".onChange(of: coordinator.recordingDraft.captureMicrophoneAudio)" Sources/MeetingAssistantNative/DesignedNativeShellView.swift
grep -R -q "synchronizeRecordingReadiness" Sources/MeetingAssistantNative/DesignedNativeShellView.swift
grep -R -q "readiness.canStartRecording" Sources/MeetingAssistantNative/DesignedNativeShellView.swift
grep -R -q "processingViewModel.updateReadiness(readiness)" Sources/MeetingAssistantNative/DesignedNativeShellView.swift
grep -R -q "ma.meetingDetail.audioSourcePicker" Sources tests App UITests
grep -R -q "ma.meetingDetail.transcriptToolbar" Sources tests App UITests
grep -R -q "LazyVStack" Sources/MeetingAssistantNative/DesignedNativeShellView.swift
grep -R -q "selectedProcessingAudioSourceID" Sources tests App UITests
grep -R -q "processingRequestSourceArtifactID" Sources tests App UITests
grep -R -q "processingIntegrityTypes" Sources tests App UITests
grep -R -q "processingIntegrityPasses" Sources tests App UITests
grep -R -q "transcriptWillLoad" Sources tests App UITests
grep -R -q "MeetingTranscriptLoadToken" Sources tests App UITests
grep -R -q "isCurrentTranscriptLoad" Sources tests App UITests
grep -R -q "Task.detached(priority: .userInitiated)" App/MeetingAssistantNativeApp.swift
grep -R -q ".onChange(of: workspaceCoordinator.recordingDraft)" App/MeetingAssistantNativeApp.swift
grep -R -q "captureMicrophoneAudio: workspaceCoordinator.recordingDraft.captureMicrophoneAudio" App/MeetingAssistantNativeApp.swift
grep -R -q '.keyboardShortcut("r", modifiers: \[.command, .option\])' Sources/MeetingAssistantNative/DesignedNativeShellView.swift
grep -R -q '.keyboardShortcut("s", modifiers: \[.command, .option\])' Sources/MeetingAssistantNative/DesignedNativeShellView.swift
grep -R -q '.keyboardShortcut("p", modifiers: \[.command, .option\])' Sources/MeetingAssistantNative/DesignedNativeShellView.swift
grep -R -q '.keyboardShortcut("c", modifiers: \[.command, .option\])' Sources/MeetingAssistantNative/DesignedNativeShellView.swift
grep -R -q '.keyboardShortcut("e", modifiers: \[.command, .option\])' Sources/MeetingAssistantNative/DesignedNativeShellView.swift
grep -R -q '.keyboardShortcut("d", modifiers: \[.command, .option\])' Sources/MeetingAssistantNative/DesignedNativeShellView.swift
grep -R -q "await permissionViewModel.refresh(workspaceURL: coordinator.workspaceURL)" Sources/MeetingAssistantNative/DesignedNativeShellView.swift
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
grep -q "MA_NATIVE_LOCAL_APP_INSTALL_APP_NAME" scripts/install-local-app.sh
grep -q "MA_NATIVE_LOCAL_APP_INSTALL_BUNDLE_ID" scripts/install-local-app.sh
grep -q "MA_NATIVE_LOCAL_APP_INSTALL_BUNDLE_NAME" scripts/install-local-app.sh
grep -q "MA_NATIVE_LOCAL_APP_INSTALL_DISPLAY_NAME" scripts/install-local-app.sh
grep -q "MA_NATIVE_LOCAL_APP_SOURCE_APP" scripts/install-local-app.sh
grep -q "MA_NATIVE_LOCAL_APP_INSTALL_REPORT" scripts/install-local-app.sh
grep -q "local-app-install-report.json" scripts/install-local-app.sh
grep -q '"release_gate": "local-direct-app-install"' scripts/install-local-app.sh
grep -q '"installed_app"' scripts/install-local-app.sh
grep -q "CFBundleIdentifier" scripts/install-local-app.sh
grep -q "local.meeting-assistant.native" scripts/install-local-app.sh
grep -q "local.meeting-assistant.native.localdirect" scripts/install-local-app.sh
grep -q "CFBundleName" scripts/install-local-app.sh
grep -q "MeetingAssistantNative" scripts/install-local-app.sh
grep -q "MeetingAssistantNativeLocal" scripts/install-local-app.sh
grep -q "Meeting Assistant Native Local" scripts/install-local-app.sh
grep -q "local_tcc_identity_strategy" scripts/install-local-app.sh
grep -q "codesign --force --deep --sign -" scripts/install-local-app.sh
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
grep -q "local-app-permission-diagnostics" scripts/local-app-permission-diagnostics.sh
grep -q "local-app-install-report.json" scripts/local-app-permission-diagnostics.sh
grep -q "local-direct-recording-smoke-report.json" scripts/local-app-permission-diagnostics.sh
grep -q "MA_NATIVE_LOCAL_APP_RECORDING_REPORT_SEARCH_ROOTS" scripts/local-app-permission-diagnostics.sh
grep -q "release-local-direct-target-smoke" scripts/local-app-permission-diagnostics.sh
grep -q '"recording_report_selection"' scripts/local-app-permission-diagnostics.sh
grep -q '"release_gate": "local-app-permission-diagnostics"' scripts/local-app-permission-diagnostics.sh
grep -q '"recommended_tcc_target"' scripts/local-app-permission-diagnostics.sh
grep -q '"same_app_as_recording_smoke"' scripts/local-app-permission-diagnostics.sh
grep -q '"screen_recording_permission_denied"' scripts/local-app-permission-diagnostics.sh
grep -q '"latest_matching_direct_success_recording_report"' scripts/local-app-permission-diagnostics.sh
grep -q '"latest_matching_open_permission_denied_recording_report"' scripts/local-app-permission-diagnostics.sh
grep -q '"launchservices_tcc_attribution_suspected"' scripts/local-app-permission-diagnostics.sh
grep -q "CFBundleDisplayName" scripts/local-app-permission-diagnostics.sh
grep -q "local_tcc_identity_strategy" scripts/local-app-permission-diagnostics.sh
grep -q '"user_action_required"' scripts/local-app-permission-diagnostics.sh
grep -q '"modifies_tcc_or_system_settings": False' scripts/local-app-permission-diagnostics.sh
grep -q '"requires_developer_id_or_notarization": False' scripts/local-app-permission-diagnostics.sh
grep -q '"not_release_readiness": True' scripts/local-app-permission-diagnostics.sh
if grep -q "x-apple.systempreferences\\|tccutil\\|security authorizationdb\\|notarytool\\|stapler\\|cosign" scripts/local-app-permission-diagnostics.sh; then
  echo "native-app architecture check failed: local app permission diagnostics must be read-only and must not require distribution gates." >&2
  exit 1
fi
grep -q "run-local-app.sh" scripts/local-direct-smoke.sh
grep -q "local-app-ax.swift" scripts/local-direct-smoke.sh
grep -q "AXUIElementCreateApplication" scripts/local-app-ax.swift
grep -q "concreteWindows.isEmpty ? values : concreteWindows" scripts/local-app-ax.swift
grep -q "return rawCandidates" scripts/local-app-ax.swift
grep -q "return \\[app\\]" scripts/local-app-ax.swift
grep -q "kAXWindowsAttribute" scripts/local-app-ax.swift
grep -q "kAXFocusedWindowAttribute" scripts/local-app-ax.swift
grep -q "kAXMainWindowAttribute" scripts/local-app-ax.swift
grep -q "AXUIElementCopyElementAtPosition" scripts/local-app-ax.swift
grep -q "windowCenterElement" scripts/local-app-ax.swift
grep -q "kAXRaiseAction" scripts/local-app-ax.swift
grep -q "kAXConfirmAction" scripts/local-app-ax.swift
grep -q "kAXFocusedAttribute" scripts/local-app-ax.swift
grep -q 'stringAttribute(element, kAXRoleAttribute) == "AXWindow"' scripts/local-app-ax.swift
grep -q 'stringAttribute(element, kAXRoleAttribute) == "AXSheet"' scripts/local-app-ax.swift
grep -q "kAXPressAction" scripts/local-app-ax.swift
grep -q "AXUIElementSetAttributeValue" scripts/local-app-ax.swift
grep -q "CGWindowListCopyWindowInfo" scripts/local-app-ax.swift
grep -q "MA_NATIVE_LOCAL_APP_SMOKE_STATE_REPORT" scripts/local-direct-smoke.sh
grep -q "local-direct-app-state-report.json" scripts/local-direct-smoke.sh
grep -q "local-direct-window-report.json" scripts/local-direct-smoke.sh
grep -q "verifies_app_state_report" scripts/local-direct-smoke.sh
grep -q "local-direct-ui-smoke" scripts/local-direct-smoke.sh
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
grep -q "Ready to start recording." scripts/local-direct-smoke.sh
grep -q "Choose a recorded meeting before generating a transcript." scripts/local-direct-smoke.sh
if grep -q "CGRequestScreenCaptureAccess\\|AVCaptureDevice\\.requestAccess\\|x-apple.systempreferences\\|tccutil\\|security authorizationdb\\|notarytool\\|stapler\\|cosign" scripts/local-direct-smoke.sh; then
  echo "native-app architecture check failed: local-direct smoke must not request permissions, open System Settings, or require distribution gates." >&2
  exit 1
fi
grep -q "run-local-app.sh" scripts/local-direct-recording-smoke.sh
grep -q "local-direct-recording-smoke" scripts/local-direct-recording-smoke.sh
grep -q "AXIdentifier" scripts/local-direct-recording-smoke.sh
grep -q "AXPress" scripts/local-direct-recording-smoke.sh
grep -q "ma.recording.startButton" scripts/local-direct-recording-smoke.sh
grep -q "ma.meetings.newRecordingButton" scripts/local-direct-recording-smoke.sh
grep -q "ma.recording.stopButton" scripts/local-direct-recording-smoke.sh
grep -q "identifier=ma.newRecording.readiness" scripts/local-direct-recording-smoke.sh
grep -q "identifier=ma.recording.startButton enabled=true" scripts/local-direct-recording-smoke.sh
grep -q "Recording in progress." scripts/local-direct-recording-smoke.sh
grep -q "Recording saved." scripts/local-direct-recording-smoke.sh
grep -q "identifier=ma.recording.artifact.screen_video.status" scripts/local-direct-recording-smoke.sh
grep -q "description=Screen recording, Ready." scripts/local-direct-recording-smoke.sh
grep -q "identifier=ma.recording.artifact.mixed_audio.status" scripts/local-direct-recording-smoke.sh
grep -q "description=Meeting audio, Ready." scripts/local-direct-recording-smoke.sh
grep -q 'wait_for_marker(marker, min(timeout_seconds, 60))' scripts/local-direct-recording-smoke.sh
grep -q '"blocker_detail_summary"' scripts/local-direct-recording-smoke.sh
grep -q "Full UI tree is written to the report ui_tree path." scripts/local-direct-recording-smoke.sh
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
grep -q "run-local-app.sh" scripts/local-direct-processing-smoke.sh
grep -q "local-direct-processing-smoke" scripts/local-direct-processing-smoke.sh
grep -q "System Events" scripts/local-direct-processing-smoke.sh
grep -q "AXIdentifier" scripts/local-direct-processing-smoke.sh
grep -q "AXPress" scripts/local-direct-processing-smoke.sh
grep -q "ma.processing.startButton" scripts/local-direct-processing-smoke.sh
grep -q "ma.meetings.row" scripts/local-direct-processing-smoke.sh
grep -q "identifier=ma.processing.startButton enabled=true" scripts/local-direct-processing-smoke.sh
grep -q "TRANSCRIPT READY" scripts/local-direct-processing-smoke.sh
grep -q "Processing complete." scripts/local-direct-processing-smoke.sh
grep -q "Processing completed with transcript-only speaker labels." scripts/local-direct-processing-smoke.sh
grep -q "normalized_audio" scripts/local-direct-processing-smoke.sh
grep -q "transcript_text" scripts/local-direct-processing-smoke.sh
grep -q "speaker_labels" scripts/local-direct-processing-smoke.sh
grep -q "workspace_precondition" scripts/local-direct-processing-smoke.sh
grep -q "recording_input_boundary" scripts/local-direct-processing-smoke.sh
grep -q '"starts_recording": False' scripts/local-direct-processing-smoke.sh
grep -q '"starts_processing": True' scripts/local-direct-processing-smoke.sh
grep -q '"may_request_macos_permissions": False' scripts/local-direct-processing-smoke.sh
grep -q '"requires_developer_id_or_notarization": False' scripts/local-direct-processing-smoke.sh
grep -q '"not_release_readiness": True' scripts/local-direct-processing-smoke.sh
if grep -q "CGRequestScreenCaptureAccess\\|AVCaptureDevice\\.requestAccess\\|x-apple.systempreferences\\|tccutil\\|security authorizationdb\\|notarytool\\|stapler\\|cosign" scripts/local-direct-processing-smoke.sh; then
  echo "native-app architecture check failed: local-direct processing smoke must not request permissions, open System Settings, modify TCC, or require distribution gates." >&2
  exit 1
fi
grep -q "run-local-app.sh" scripts/local-direct-actions-smoke.sh
grep -q "local-direct-actions-smoke" scripts/local-direct-actions-smoke.sh
grep -q "AXIdentifier" scripts/local-direct-actions-smoke.sh
grep -q "AXPress" scripts/local-direct-actions-smoke.sh
grep -q "ma.transcriptAction.copyButton" scripts/local-direct-actions-smoke.sh
grep -q "ma.meetings.row" scripts/local-direct-actions-smoke.sh
grep -q "ma.transcriptAction.exportButton" scripts/local-direct-actions-smoke.sh
grep -q "ma.transcriptAction.deleteButton" scripts/local-direct-actions-smoke.sh
grep -q "ma.transcriptAction.deleteConfirmButton" scripts/local-direct-actions-smoke.sh
grep -q "requested_export_path" scripts/local-direct-actions-smoke.sh
grep -q "actual_export_path" scripts/local-direct-actions-smoke.sh
grep -q "Exported markdown transcript to" scripts/local-direct-actions-smoke.sh
grep -q "Export path: " scripts/local-direct-actions-smoke.sh
grep -q "exported_path_from_snapshot" scripts/local-direct-actions-smoke.sh
grep -q "ma.meetingDetail.technicalDetails" scripts/local-direct-actions-smoke.sh
grep -q "identifier=ma.transcriptAction.success" scripts/local-direct-actions-smoke.sh
grep -q "value=Transcript exported." scripts/local-direct-actions-smoke.sh
grep -q "Transcript actions are ready." scripts/local-direct-actions-smoke.sh
grep -q "Copy complete." scripts/local-direct-actions-smoke.sh
grep -q "Transcript exported." scripts/local-direct-actions-smoke.sh
grep -q "Delete complete." scripts/local-direct-actions-smoke.sh
grep -q "pbpaste" scripts/local-direct-actions-smoke.sh
grep -q "NSSavePanel" scripts/local-direct-actions-smoke.sh
grep -q "workspace_precondition" scripts/local-direct-actions-smoke.sh
grep -q "actions_boundary" scripts/local-direct-actions-smoke.sh
grep -q '"starts_recording": False' scripts/local-direct-actions-smoke.sh
grep -q '"starts_processing": False' scripts/local-direct-actions-smoke.sh
grep -q '"uses_system_pasteboard": True' scripts/local-direct-actions-smoke.sh
grep -q '"uses_save_panel": True' scripts/local-direct-actions-smoke.sh
grep -q '"may_request_macos_permissions": False' scripts/local-direct-actions-smoke.sh
grep -q '"requires_developer_id_or_notarization": False' scripts/local-direct-actions-smoke.sh
grep -q '"not_release_readiness": True' scripts/local-direct-actions-smoke.sh
if grep -q "CGRequestScreenCaptureAccess\\|AVCaptureDevice\\.requestAccess\\|x-apple.systempreferences\\|tccutil\\|security authorizationdb\\|notarytool\\|stapler\\|cosign" scripts/local-direct-actions-smoke.sh; then
  echo "native-app architecture check failed: local-direct actions smoke must not request permissions, open System Settings, modify TCC, or require distribution gates." >&2
  exit 1
fi
grep -q "run-local-app.sh" scripts/local-direct-same-chain-smoke.sh
grep -q "local-direct-same-chain-smoke" scripts/local-direct-same-chain-smoke.sh
grep -q "local-direct-recording-smoke.sh" scripts/local-direct-same-chain-smoke.sh
grep -q "local-direct-processing-smoke.sh" scripts/local-direct-same-chain-smoke.sh
grep -q "local-direct-actions-smoke.sh" scripts/local-direct-same-chain-smoke.sh
grep -q "local-direct-same-chain-smoke-report.json" scripts/local-direct-same-chain-smoke.sh
grep -q "same_chain_boundary" scripts/local-direct-same-chain-smoke.sh
grep -q "stage_reports" scripts/local-direct-same-chain-smoke.sh
grep -q "same_app_identity" scripts/local-direct-same-chain-smoke.sh
grep -q "launch_modes" scripts/local-direct-same-chain-smoke.sh
grep -q "requires_clean_app_processes" scripts/local-direct-same-chain-smoke.sh
grep -q '"starts_recording": True' scripts/local-direct-same-chain-smoke.sh
grep -q '"starts_processing": True' scripts/local-direct-same-chain-smoke.sh
grep -q '"uses_system_pasteboard": True' scripts/local-direct-same-chain-smoke.sh
grep -q '"uses_save_panel": True' scripts/local-direct-same-chain-smoke.sh
grep -q '"may_request_macos_permissions": True' scripts/local-direct-same-chain-smoke.sh
grep -q '"requires_developer_id_or_notarization": False' scripts/local-direct-same-chain-smoke.sh
grep -q '"not_release_readiness": True' scripts/local-direct-same-chain-smoke.sh
if grep -q "x-apple.systempreferences\\|tccutil\\|security authorizationdb\\|notarytool\\|stapler\\|cosign" scripts/local-direct-same-chain-smoke.sh; then
  echo "native-app architecture check failed: local-direct same-chain smoke must not open System Settings, modify TCC, or require distribution gates." >&2
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
import plistlib
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

invalid_info_plist_settings = [
    settings
    for settings in app_settings
    if "GENERATE_INFOPLIST_FILE = NO;" not in settings
    or "INFOPLIST_FILE = App/Info.plist;" not in settings
]
if invalid_info_plist_settings:
    raise SystemExit(
        "native-app architecture check failed: Debug and Release app targets must use the explicit App/Info.plist."
    )

info_plist_path = Path("App/Info.plist")
with info_plist_path.open("rb") as info_plist_file:
    info_plist = plistlib.load(info_plist_file)

required_usage_description_keys = {
    "NSMicrophoneUsageDescription",
    "NSScreenCaptureUsageDescription",
}
missing_usage_descriptions = sorted(
    key
    for key in required_usage_description_keys
    if not isinstance(info_plist.get(key), str) or not info_plist[key].strip()
)
if missing_usage_descriptions:
    missing_keys = ", ".join(missing_usage_descriptions)
    raise SystemExit(
        "native-app architecture check failed: App/Info.plist must declare non-empty macOS permission usage descriptions: "
        + missing_keys
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
permission_view_model_file='Sources/MeetingAssistantNative/PermissionDependencyStatusViewModel.swift'
grep -q 'Button("Open Screen Recording Settings")' "$permission_privacy_settings_file"
grep -q 'Button("Open Microphone Settings")' "$permission_privacy_settings_file"
grep -q 'openPrivacySettings()' "$permission_privacy_settings_file"
grep -q 'openMicrophoneSettings()' "$permission_privacy_settings_file"
grep -q 'NSWorkspace.shared.open(url)' "$permission_privacy_settings_file"
grep -q 'x-apple.systempreferences:com.apple.preference.security?Privacy_ScreenCapture' "$permission_privacy_settings_file"
grep -q 'x-apple.systempreferences:com.apple.preference.security?Privacy_Microphone' "$permission_privacy_settings_file"
grep -q 'PermissionDependencyAccessibilityID.openPrivacySettingsButton' "$permission_privacy_settings_file"
grep -q 'PermissionDependencyAccessibilityID.openMicrophoneSettingsButton' "$permission_privacy_settings_file"
grep -q 'kSecCodeInfoDesignatedRequirement' "$permission_view_model_file"
grep -q 'SecRequirementCopyString' "$permission_view_model_file"
grep -q 'kSecCodeInfoCertificates' "$permission_view_model_file"
grep -q 'designated requirement' "$permission_view_model_file"
grep -q 'signingAuthority' "$permission_view_model_file"

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

if grep -R --include 'Processing*.swift' -n -E 'Process\b|ProcessInfo\b|Pipe\b|standardOutput|standardError|posix_spawn|execv|system[[:space:]]*\(|popen[[:space:]]*\(' Sources/MeetingAssistantNative |
  grep -v 'ProcessingCommandProcessRunner.swift'; then
  echo "native-app architecture check failed: process execution primitives are only allowed in ProcessingCommandProcessRunner.swift." >&2
  exit 1
fi

processing_boundary_forbidden='(^[[:space:]]*import[[:space:]]+(AppKit|ScreenCaptureKit|AVFoundation|CoreAudio|CoreMediaIO|ReplayKit|Network)\b|NSTask\b|meeting_assistant_cli|native-helper|processing-cli|helper[[:space:]]+tool|ScreenCaptureKit|AVCapture|CGDisplayStream|SCStream|AVAudioEngine|AVAudioRecorder|NSPasteboard|NSOpenPanel|NSSavePanel|URLSession|URLRequest|URLSessionConfiguration|NWConnection|NWListener|WebSocket|https?://|import_media|export_transcript|delete_session|check_dependencies|normalize_audio|removeItem[[:space:]]*\(|copyItem[[:space:]]*\(|moveItem[[:space:]]*\(|createFile[[:space:]]*\(|createDirectory[[:space:]]*\()'

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
action_os_boundary_forbidden='(^[[:space:]]*import[[:space:]]+(AppKit|ScreenCaptureKit|AVFoundation|CoreAudio|CoreMediaIO|ReplayKit|Network)\b|NSTask\b|meeting_assistant_cli|ProcessingCLIDependencyCheckRunner|DependencyCheckProcessRunner|native-helper|processing-cli|helper[[:space:]]+tool|ScreenCaptureKit|AVCapture|CGDisplayStream|SCStream|AVAudioEngine|AVAudioRecorder|NSPasteboard|NSOpenPanel|NSSavePanel|FileManager\b|OutputStream\b|InputStream\b|createFile[[:space:]]*\(|createDirectory[[:space:]]*\(|removeItem[[:space:]]*\(|copyItem[[:space:]]*\(|moveItem[[:space:]]*\(|\.(write|write(to|Bytes))[[:space:]]*\(|URLSession|URLRequest|URLSessionConfiguration|NWConnection|NWListener|WebSocket|https?://)'

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

if grep -R --include 'TranscriptAction*.swift' --include 'TranscriptReviewActions*.swift' -n -E 'Process\b|ProcessInfo\b|Pipe\b|standardOutput|standardError|FileHandle\b|posix_spawn|execv|system[[:space:]]*\(|popen[[:space:]]*\(' Sources |
  grep -v -F "$action_process_boundary_file"; then
  echo "native-app architecture check failed: transcript action process execution primitives are allowed only inside TranscriptActionProcessRunner." >&2
  exit 1
fi

echo "native-app architecture check passed."
