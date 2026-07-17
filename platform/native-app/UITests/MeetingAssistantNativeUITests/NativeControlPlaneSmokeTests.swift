import AppKit
import SwiftUI
import XCTest
@testable import MeetingAssistantNative

@MainActor
final class NativeControlPlaneSmokeTests: XCTestCase {
    func testPermissionDependencyBlockedStateIsHostedVisibleAndLocated() throws {
        let state = blockedReadinessState()
        let viewModel = PermissionDependencyStatusViewModel(
            runner: UnusedDependencyCheckRunner(),
            initialState: state
        )
        let host = HostedSwiftUIView(PermissionDependencyStatusView(viewModel: viewModel))

        host.assertHosted()
        XCTAssertEqual(viewModel.state.phase, .blocked)
        XCTAssertFalse(viewModel.state.canStartRecording)
        XCTAssertFalse(viewModel.state.canRunProcessing)
        XCTAssertEqual(
            viewModel.state.summary,
            "Recording and processing are blocked by missing permissions and dependencies."
        )
        XCTAssertEqual(viewModel.state.missingRequiredCheckIDs, ["media_tool.ffmpeg"])

        let screenPermission = try XCTUnwrap(
            viewModel.state.permissions.first { $0.id == "permission.screen_recording" }
        )
        XCTAssertEqual(screenPermission.title, "Screen Recording")
        XCTAssertEqual(screenPermission.state, .denied)
        XCTAssertEqual(
            screenPermission.message,
            "Screen Recording permission is denied. Open System Settings to grant access."
        )

        let ffmpeg = try XCTUnwrap(
            viewModel.state.dependencies.first { $0.id == "media_tool.ffmpeg" }
        )
        XCTAssertEqual(ffmpeg.title, "Media Tool")
        XCTAssertEqual(ffmpeg.status, "missing")
        XCTAssertFalse(ffmpeg.isPassing)
        XCTAssertEqual(ffmpeg.message, "FFmpeg executable was not found.")

        assertPermissionDependencyLocators()
        SwiftUIViewSourceContract.assertPermissionDependencyViewUsesAccessibleStates()
        SwiftUIViewSourceContract.assertAppBundleProductionDefaultsUseCommandClients()
        SwiftUIViewSourceContract.assertAppFixturesAreDebugXCTestOnlyAndReloadUsesWorkspace()
    }

    func testRecordingReadinessBlockedIsHostedAndDoesNotStart() async {
        let client = FakeRecordingCommandClient()
        let viewModel = RecordingControlViewModel(
            commandClient: client,
            readinessState: blockedReadinessState()
        )
        let host = HostedSwiftUIView(RecordingControlView(viewModel: viewModel))

        host.assertHosted()
        XCTAssertEqual(viewModel.state.phase, .idle)
        XCTAssertEqual(viewModel.state.statusText, "Run readiness checks before recording.")
        XCTAssertEqual(viewModel.canStart, false)
        XCTAssertEqual(viewModel.canStop, false)
        XCTAssertEqual(
            hostedReadinessStatusText(for: viewModel.state.phase),
            "Recording readiness is pending."
        )
        assertRecordingLocators()
        SwiftUIViewSourceContract.assertRecordingViewUsesAccessibleStates()

        await viewModel.start()

        let startRequests = await client.startRequests
        XCTAssertTrue(startRequests.isEmpty)
        XCTAssertEqual(viewModel.state.phase, .idle)
    }

    func testFakeRecordingStartRecordingAndStopSavedSummaryAreHosted() async {
        let client = FakeRecordingCommandClient(sessionID: "session-ui-smoke")
        let viewModel = RecordingControlViewModel(
            commandClient: client,
            readinessState: readyReadinessState()
        )
        let host = HostedSwiftUIView(RecordingControlView(viewModel: viewModel))

        host.assertHosted()
        XCTAssertEqual(viewModel.state.phase, .ready)
        XCTAssertEqual(viewModel.state.statusText, "Ready to start recording.")

        await viewModel.start()
        host.flush()

        XCTAssertEqual(viewModel.state.phase, .recording)
        XCTAssertEqual(viewModel.state.sessionID, "session-ui-smoke")
        XCTAssertEqual(viewModel.state.statusText, "Recording in progress.")
        XCTAssertFalse(viewModel.canStart)
        XCTAssertTrue(viewModel.canStop)
        XCTAssertEqual(
            hostedReadinessStatusText(for: viewModel.state.phase),
            "Recording command is active."
        )
        SwiftUIViewSourceContract.assertRecordingViewUsesAccessibleStates()

        await viewModel.stop()
        host.flush()

        XCTAssertEqual(viewModel.state.phase, .recorded)
        XCTAssertEqual(viewModel.state.sessionID, "session-ui-smoke")
        XCTAssertEqual(viewModel.state.statusText, "Recording saved.")
        XCTAssertEqual(viewModel.state.savedSummary, "Saved 2 recording artifacts.")
        XCTAssertEqual(viewModel.state.artifacts.map(\.artifactType), ["screen_video", "mixed_audio"])
        XCTAssertEqual(
            hostedReadinessStatusText(for: viewModel.state.phase),
            "Recording command is active."
        )
        SwiftUIViewSourceContract.assertRecordingViewUsesAccessibleStates()

        let startRequests = await client.startRequests
        let stopRequests = await client.stopRequests
        XCTAssertEqual(startRequests.count, 1)
        XCTAssertEqual(stopRequests, [StopRecordingRequest(sessionID: "session-ui-smoke")])
    }

    func testTaskBasedNativeShellIsHostedWithSingleNavigationAndFocusedRoutes() async {
        let transcriptInput = hostedTranscriptInput()
        let meeting = hostedMeetingSummary()
        let coordinator = MeetingWorkspaceCoordinator(
            workspaceURL: URL(
                fileURLWithPath: "/tmp/MeetingAssistantNative-Hosted-Shell",
                isDirectory: true
            ),
            initialSessions: [meeting]
        )
        let permissionViewModel = PermissionDependencyStatusViewModel(
            runner: UnusedDependencyCheckRunner(),
            initialState: readyReadinessState()
        )
        let recordingViewModel = RecordingControlViewModel(
            commandClient: FakeRecordingCommandClient(),
            readinessState: readyReadinessState()
        )
        let processingViewModel = ProcessingStateViewModel(
            commandClient: ProcessingCommandFakeClient(),
            readinessState: readyReadinessState(),
            defaultSessionID: "session-hosted-shell"
        )
        let transcriptViewModel = TranscriptReviewViewModel(input: transcriptInput)
        let actionViewModel = TranscriptReviewActionsViewModel(input: transcriptInput)
        let host = HostedSwiftUIView(
            DesignedNativeShellView(
                coordinator: coordinator,
                permissionViewModel: permissionViewModel,
                recordingViewModel: recordingViewModel,
                processingViewModel: processingViewModel,
                transcriptViewModel: transcriptViewModel,
                transcriptActionViewModel: actionViewModel
            )
        )

        host.assertHosted()
        XCTAssertEqual(coordinator.route, .meetings)
        XCTAssertEqual(coordinator.recentSessions, [meeting])

        coordinator.beginNewRecording()
        host.flush()
        XCTAssertEqual(coordinator.route, .newRecording)

        await coordinator.open(meeting)
        host.flush()
        XCTAssertEqual(coordinator.route, .meetingDetail)
        XCTAssertEqual(coordinator.currentSession, meeting)

        coordinator.navigate(to: .diagnostics)
        host.flush()
        XCTAssertEqual(coordinator.route, .diagnostics)

        assertShellLocators()
        SwiftUIViewSourceContract.assertDesignedNativeShellUsesAccessibleStates()
        SwiftUIViewSourceContract.assertAppRootUsesDesignedNativeShell()
    }

    func testUnavailableTranscribedMeetingIsHostedWithRepairOnlyBinding() async {
        let meeting = MeetingSessionSummary(
            id: "session-hosted-transcript-recovery",
            title: "Transcript recovery",
            status: "transcribed",
            startedAt: "2026-07-13T09:00:00Z",
            endedAt: "2026-07-13T09:30:00Z",
            updatedAt: "2026-07-13T09:31:00Z",
            durationLabel: "30:00",
            artifactCount: 2,
            hasTranscript: false,
            hasSpeakerLabels: false,
            hasProcessableAudio: true
        )
        let coordinator = MeetingWorkspaceCoordinator(
            workspaceURL: URL(
                fileURLWithPath: "/tmp/MeetingAssistantNative-Hosted-Transcript-Recovery",
                isDirectory: true
            ),
            initialSessions: [meeting]
        )
        await coordinator.open(meeting)
        if let loadToken = coordinator.transcriptWillLoad(for: meeting.id) {
            coordinator.transcriptDidFailToLoad(
                HostedTranscriptFailure(),
                token: loadToken
            )
        }
        let permissionViewModel = PermissionDependencyStatusViewModel(
            runner: UnusedDependencyCheckRunner(),
            initialState: readyReadinessState()
        )
        let recordingViewModel = RecordingControlViewModel(
            commandClient: FakeRecordingCommandClient(),
            readinessState: readyReadinessState()
        )
        let processingViewModel = ProcessingStateViewModel(
            commandClient: ProcessingCommandFakeClient(),
            readinessState: readyReadinessState()
        )
        processingViewModel.bindSession(
            sessionID: meeting.id,
            sessionStatus: meeting.status,
            processableAudioStatus: .available
        )
        let transcriptInput = TranscriptReviewInput(
            sessionTitle: meeting.title,
            transcript: nil
        )
        let actionViewModel = TranscriptReviewActionsViewModel(input: transcriptInput)
        actionViewModel.updateSession(
            sessionID: meeting.id,
            sessionTitle: meeting.title,
            transcript: nil
        )
        let host = HostedSwiftUIView(
            DesignedNativeShellView(
                coordinator: coordinator,
                permissionViewModel: permissionViewModel,
                recordingViewModel: recordingViewModel,
                processingViewModel: processingViewModel,
                transcriptViewModel: TranscriptReviewViewModel(input: transcriptInput),
                transcriptActionViewModel: actionViewModel
            )
        )

        host.assertHosted()
        XCTAssertEqual(coordinator.route, .meetingDetail)
        XCTAssertTrue(processingViewModel.canStart)
        XCTAssertTrue(coordinator.transcriptLoadError?.contains("will not replace a registered transcript") == true)
        SwiftUIViewSourceContract.assertDesignedNativeShellUsesAccessibleStates()
        SwiftUIViewSourceContract.assertAppRootUsesDesignedNativeShell()
    }

    func testStartFailureIsHostedWithStableFailureState() async {
        let client = FakeRecordingCommandClient(
            script: .startFailure(
                code: "permission_denied",
                message: "Screen Recording permission is missing."
            )
        )
        let viewModel = RecordingControlViewModel(
            commandClient: client,
            readinessState: readyReadinessState()
        )
        let host = HostedSwiftUIView(RecordingControlView(viewModel: viewModel))

        await viewModel.start()
        host.flush()

        XCTAssertEqual(viewModel.state.phase, .failed)
        XCTAssertEqual(viewModel.state.statusText, "Recording failed.")
        XCTAssertEqual(viewModel.state.sessionID, nil)
        XCTAssertEqual(viewModel.state.errorCode, .permissionDenied)
        XCTAssertTrue(viewModel.state.errorMessage?.contains("Screen Recording permission is missing.") == true)
        XCTAssertTrue(viewModel.state.errorMessage?.contains("System Settings > Privacy & Security") == true)
        XCTAssertEqual(
            hostedReadinessStatusText(for: viewModel.state.phase),
            "Recording command failed."
        )
        assertRecordingLocators()
        SwiftUIViewSourceContract.assertRecordingViewUsesAccessibleStates()
    }

    func testTranscriptReviewIsHostedWithStableReadOnlyState() {
        let viewModel = TranscriptReviewViewModel(
            input: TranscriptReviewInput(
                sessionTitle: "Hosted Transcript",
                transcript: TranscriptReviewTranscript(
                    id: "transcript-hosted",
                    sessionID: "session-hosted",
                    sourceArtifactID: "artifact-normalized-audio",
                    status: "succeeded",
                    segments: [
                        TranscriptReviewSegment(
                            segmentID: "seg-2",
                            startMS: 60_000,
                            endMS: 65_000,
                            text: "Second hosted segment.",
                            speakerLabel: "SPEAKER_02"
                        ),
                        TranscriptReviewSegment(
                            segmentID: "seg-1",
                            startMS: 0,
                            endMS: 3_000,
                            text: "First hosted segment.",
                            speakerLabel: "SPEAKER_01"
                        ),
                    ]
                ),
                speakerLabels: SpeakerLabelsReviewArtifact(
                    sessionID: "session-hosted",
                    labels: [
                        SpeakerLabelReviewEntry(
                            label: "SPEAKER_01",
                            sessionID: "session-hosted",
                            isVerifiedIdentity: false
                        ),
                        SpeakerLabelReviewEntry(
                            label: "SPEAKER_02",
                            sessionID: "session-hosted",
                            isVerifiedIdentity: false
                        ),
                    ],
                    segmentMapping: [
                        SpeakerLabelSegmentMapping(segmentID: "seg-1", label: "SPEAKER_01"),
                        SpeakerLabelSegmentMapping(segmentID: "seg-2", label: "SPEAKER_02"),
                    ]
                ),
                speakerLabelsDegradationReason: "speaker labeling runtime unavailable"
            )
        )
        let host = HostedSwiftUIView(TranscriptReviewView(viewModel: viewModel))

        host.assertHosted()
        XCTAssertEqual(viewModel.state.contentState, .available)
        XCTAssertEqual(viewModel.state.heading, "Hosted Transcript")
        XCTAssertEqual(viewModel.state.segments.map(\.id), ["seg-1", "seg-2"])
        XCTAssertEqual(viewModel.state.segments.first?.timestampLabel, "00:00-00:03")
        XCTAssertEqual(
            viewModel.state.segments.first?.speakerDisplayLabel,
            "Anonymous speaker SPEAKER_01 (not a verified identity)"
        )
        XCTAssertNil(viewModel.state.degradationReason)
        assertTranscriptLocators()
        SwiftUIViewSourceContract.assertTranscriptReviewViewUsesAccessibleStates()
    }

    func testTranscriptReviewMissingAndEmptyStatesAreHosted() {
        let missingViewModel = TranscriptReviewViewModel(
            input: TranscriptReviewInput(transcript: nil)
        )
        let missingHost = HostedSwiftUIView(TranscriptReviewView(viewModel: missingViewModel))
        missingHost.assertHosted()
        XCTAssertEqual(missingViewModel.state.contentState, .missing)
        XCTAssertEqual(missingViewModel.state.summary, "Transcript is missing for this session.")

        let transcriptOnlyViewModel = TranscriptReviewViewModel(
            input: TranscriptReviewInput(
                transcript: TranscriptReviewTranscript(
                    id: "transcript-only",
                    sessionID: "session-transcript-only",
                    sourceArtifactID: "artifact-normalized-audio",
                    status: "succeeded",
                    segments: [
                        TranscriptReviewSegment(
                            segmentID: "seg-plain",
                            startMS: 1_000,
                            endMS: 2_000,
                            text: "Transcript-only hosted segment."
                        ),
                    ]
                ),
                speakerLabelsDegradationReason: "speaker labeling runtime unavailable"
            )
        )
        let transcriptOnlyHost = HostedSwiftUIView(TranscriptReviewView(viewModel: transcriptOnlyViewModel))
        transcriptOnlyHost.assertHosted()
        XCTAssertEqual(transcriptOnlyViewModel.state.contentState, .available)
        XCTAssertNil(transcriptOnlyViewModel.state.segments.first?.speakerDisplayLabel)
        XCTAssertEqual(transcriptOnlyViewModel.state.degradationReason, "speaker labeling runtime unavailable")

        let emptyViewModel = TranscriptReviewViewModel(
            input: TranscriptReviewInput(
                transcript: TranscriptReviewTranscript(
                    id: "transcript-empty",
                    sessionID: "session-empty",
                    sourceArtifactID: "artifact-normalized-audio",
                    status: "succeeded",
                    segments: []
                ),
                speakerLabelsDegradationReason: "speaker labeling skipped"
            )
        )
        let emptyHost = HostedSwiftUIView(TranscriptReviewView(viewModel: emptyViewModel))
        emptyHost.assertHosted()
        XCTAssertEqual(emptyViewModel.state.contentState, .empty)
        XCTAssertEqual(emptyViewModel.state.summary, "Transcript has no segments to review.")
        XCTAssertEqual(emptyViewModel.state.degradationReason, "speaker labeling skipped")
        assertTranscriptLocators()
        SwiftUIViewSourceContract.assertTranscriptReviewViewUsesAccessibleStates()
    }

    func testTranscriptActionsAreHostedWithStableUserTriggeredStates() async {
        let client = TranscriptActionFakeCommandClient(
            exportScript: .success(content: "Hosted copy content."),
            deleteScript: .success(
                deletedItems: [
                    "artifacts/transcript.json",
                    "logs/processing.log",
                ],
                retainedExternalExports: ["/tmp/hosted-export.md"]
            )
        )
        let clipboard = TranscriptActionMemoryClipboard()
        let selector = TranscriptActionStaticDestinationSelector(targetPath: "/tmp/hosted-export.md")
        let viewModel = TranscriptReviewActionsViewModel(
            input: transcriptActionInput(),
            commandClient: client,
            clipboard: clipboard,
            destinationSelector: selector,
            workspaceDir: "/tmp/hosted-workspace"
        )
        let host = HostedSwiftUIView(TranscriptReviewActionsView(viewModel: viewModel))

        host.assertHosted()
        XCTAssertEqual(viewModel.state.phase, .ready)
        XCTAssertEqual(viewModel.state.statusText, "Transcript actions are ready.")
        assertTranscriptActionLocators()
        SwiftUIViewSourceContract.assertTranscriptActionViewUsesAccessibleStates()

        await viewModel.copyTranscript()
        host.flush()

        let copiedContent = await clipboard.latestContentSnapshot()
        XCTAssertEqual(copiedContent, "Hosted copy content.")
        XCTAssertEqual(viewModel.state.statusText, "Copy complete.")
        XCTAssertEqual(
            viewModel.state.successSummary,
            "Transcript copied."
        )

        await viewModel.exportTranscript()
        host.flush()

        let destinationRequests = await selector.requestSnapshot()
        let exportRequests = await client.exportRequestSnapshot()
        XCTAssertEqual(destinationRequests.count, 1)
        XCTAssertEqual(exportRequests.count, 2)
        XCTAssertEqual(viewModel.state.statusText, "Export complete.")
        XCTAssertEqual(
            viewModel.state.successSummary,
            "Transcript exported."
        )

        viewModel.requestDeleteConfirmation()
        host.flush()

        XCTAssertTrue(viewModel.state.isDeletePromptVisible)
        XCTAssertEqual(
            viewModel.state.deletePromptText,
            "Delete session Hosted Action Transcript (session-actions)? This removes application-managed files in the session workspace. External exports are retained."
        )

        viewModel.cancelDelete()
        host.flush()

        let deleteRequestsAfterCancel = await client.deleteRequestSnapshot()
        XCTAssertTrue(deleteRequestsAfterCancel.isEmpty)
        XCTAssertEqual(viewModel.state.statusText, "Delete cancelled. No command was sent.")

        viewModel.requestDeleteConfirmation()
        let deletedSessionID = await viewModel.confirmDelete()
        host.flush()

        let deleteRequestsAfterConfirm = await client.deleteRequestSnapshot()
        XCTAssertEqual(deleteRequestsAfterConfirm.count, 1)
        XCTAssertEqual(deletedSessionID, "session-actions")
        XCTAssertEqual(viewModel.state.phase, .unavailable)
        XCTAssertNil(viewModel.state.sessionID)
    }

    func testTranscriptActionFailuresAreHostedWithPersistentDeleteFailure() async {
        let client = TranscriptActionFakeCommandClient(
            exportScript: .failure(
                code: "path_conflict",
                message: "Export target already exists."
            ),
            deleteScript: .failure(
                code: "path_conflict",
                message: "Session path escaped the workspace."
            )
        )
        let viewModel = TranscriptReviewActionsViewModel(
            input: transcriptActionInput(),
            commandClient: client,
            clipboard: TranscriptActionMemoryClipboard(),
            destinationSelector: TranscriptActionStaticDestinationSelector(targetPath: "/tmp/hosted-export.md")
        )
        let host = HostedSwiftUIView(TranscriptReviewActionsView(viewModel: viewModel))

        await viewModel.copyTranscript()
        host.flush()

        XCTAssertEqual(viewModel.state.statusText, "Copy failed.")
        XCTAssertEqual(
            viewModel.state.failureSummary,
            "Copy failed: Export target already exists."
        )

        viewModel.requestDeleteConfirmation()
        await viewModel.confirmDelete()
        host.flush()

        XCTAssertEqual(viewModel.state.statusText, "Delete failed.")
        XCTAssertEqual(
            viewModel.state.failureSummary,
            "Delete failed: Session path escaped the workspace."
        )

        viewModel.requestDeleteConfirmation()
        viewModel.cancelDelete()
        host.flush()

        XCTAssertEqual(
            viewModel.state.failureSummary,
            "Delete failed: Session path escaped the workspace."
        )
        assertTranscriptActionLocators()
        SwiftUIViewSourceContract.assertTranscriptActionViewUsesAccessibleStates()
    }

    func testProcessingStateIsHostedWithBlockedSuccessDegradedAndFailureStates() async {
        let blockedClient = ProcessingCommandFakeClient()
        let blockedViewModel = ProcessingStateViewModel(
            commandClient: blockedClient,
            readinessState: blockedReadinessState(),
            defaultSessionID: "session-processing-blocked"
        )
        let blockedHost = HostedSwiftUIView(ProcessingStateView(viewModel: blockedViewModel))
        blockedHost.assertHosted()
        XCTAssertEqual(blockedViewModel.state.phase, .blocked)
        XCTAssertFalse(blockedViewModel.canStart)

        await blockedViewModel.start()
        blockedHost.flush()

        let blockedTranscriptRequests = await blockedClient.transcriptRequestSnapshot()
        XCTAssertTrue(blockedTranscriptRequests.isEmpty)
        XCTAssertEqual(
            blockedViewModel.state.statusText,
            "Processing is blocked until required dependencies are available."
        )

        let successClient = ProcessingCommandFakeClient(
            transcriptScript: .success(
                transcriptID: "transcript-hosted-processing",
                artifactID: "artifact-hosted-transcript",
                segmentCount: 2
            ),
            speakerLabelsScript: .success(
                labelStatus: "labeled",
                speakerLabelsArtifactID: "artifact-hosted-speakers"
            )
        )
        let successViewModel = ProcessingStateViewModel(
            commandClient: successClient,
            readinessState: readyReadinessState(),
            defaultSessionID: "session-hosted-processing"
        )
        let successHost = HostedSwiftUIView(ProcessingStateView(viewModel: successViewModel))
        successViewModel.bindSession(
            sessionID: "session-hosted-processing",
            sessionStatus: "recorded",
            processableAudioStatus: .available
        )

        await successViewModel.start()
        successHost.flush()

        XCTAssertEqual(successViewModel.state.phase, .completed)
        XCTAssertEqual(successViewModel.state.statusText, "Processing complete.")
        XCTAssertEqual(
            successViewModel.state.successSummary,
            "Generated transcript and speaker labels for session session-hosted-processing."
        )

        let degradedClient = ProcessingCommandFakeClient(
            transcriptScript: .success(transcriptID: "transcript-hosted-processing"),
            speakerLabelsScript: .success(
                labelStatus: "transcript_only",
                speakerLabelsArtifactID: "artifact-hosted-speakers",
                degradationReason: "speaker labeling runtime unavailable"
            )
        )
        let degradedViewModel = ProcessingStateViewModel(
            commandClient: degradedClient,
            readinessState: readyReadinessState(),
            defaultSessionID: "session-hosted-processing"
        )
        let degradedHost = HostedSwiftUIView(ProcessingStateView(viewModel: degradedViewModel))
        degradedViewModel.bindSession(
            sessionID: "session-hosted-processing",
            sessionStatus: "recorded",
            processableAudioStatus: .available
        )

        await degradedViewModel.start()
        degradedHost.flush()

        XCTAssertEqual(degradedViewModel.state.phase, .degraded)
        XCTAssertEqual(degradedViewModel.state.degradationReason, "speaker labeling runtime unavailable")

        let failureClient = ProcessingCommandFakeClient(
            transcriptScript: .failure(
                code: "processing_failed",
                message: "Transcript adapter failed.",
                details: ["adapter exited with 5"]
            )
        )
        let failureViewModel = ProcessingStateViewModel(
            commandClient: failureClient,
            readinessState: readyReadinessState(),
            defaultSessionID: "session-hosted-processing"
        )
        let failureHost = HostedSwiftUIView(ProcessingStateView(viewModel: failureViewModel))
        failureViewModel.bindSession(
            sessionID: "session-hosted-processing",
            sessionStatus: "recorded",
            processableAudioStatus: .available
        )

        await failureViewModel.start()
        failureHost.flush()

        XCTAssertEqual(failureViewModel.state.phase, .failed)
        XCTAssertTrue(failureViewModel.canRetry)
        XCTAssertEqual(failureViewModel.state.errorCode?.rawValue, "processing_failed")
        XCTAssertEqual(failureViewModel.state.errorMessage, "Transcript adapter failed.")

        assertProcessingLocators()
        SwiftUIViewSourceContract.assertProcessingViewUsesAccessibleStates()
    }

    func testStopFailureIsHostedWithStableFailureState() async {
        let client = FakeRecordingCommandClient(
            script: .stopFailure(
                code: "capture_failed",
                message: "Recording could not be saved."
            ),
            sessionID: "session-stop-failure"
        )
        let viewModel = RecordingControlViewModel(
            commandClient: client,
            readinessState: readyReadinessState()
        )
        let host = HostedSwiftUIView(RecordingControlView(viewModel: viewModel))

        await viewModel.start()
        await viewModel.stop()
        host.flush()

        XCTAssertEqual(viewModel.state.phase, .failed)
        XCTAssertEqual(viewModel.state.statusText, "Recording failed.")
        XCTAssertEqual(viewModel.state.sessionID, "session-stop-failure")
        XCTAssertEqual(viewModel.state.errorCode, .captureFailed)
        XCTAssertEqual(viewModel.state.errorMessage, "Recording could not be saved.")
        XCTAssertEqual(
            hostedReadinessStatusText(for: viewModel.state.phase),
            "Recording command failed."
        )
        assertRecordingLocators()
        SwiftUIViewSourceContract.assertRecordingViewUsesAccessibleStates()
    }

    func testStableAccessibilityIdentifierContract() {
        assertPermissionDependencyLocators()
        assertRecordingLocators()
        assertProcessingLocators()
        assertTranscriptLocators()
        assertTranscriptActionLocators()
        assertShellLocators()
    }

    private func assertPermissionDependencyLocators(
        file: StaticString = #filePath,
        line: UInt = #line
    ) {
        XCTAssertEqual(
            PermissionDependencyAccessibilityID.heading,
            "ma.permissionDependency.heading",
            file: file,
            line: line
        )
        XCTAssertEqual(
            PermissionDependencyAccessibilityID.summary,
            "ma.permissionDependency.summary",
            file: file,
            line: line
        )
        XCTAssertEqual(
            PermissionDependencyAccessibilityID.checkButton,
            "ma.permissionDependency.checkButton",
            file: file,
            line: line
        )
        XCTAssertEqual(
            PermissionDependencyAccessibilityID.openPrivacySettingsButton,
            "ma.permissionDependency.openPrivacySettingsButton",
            file: file,
            line: line
        )
        XCTAssertEqual(
            PermissionDependencyAccessibilityID.appIdentity,
            "ma.permissionDependency.appIdentity",
            file: file,
            line: line
        )
        XCTAssertEqual(
            PermissionDependencyAccessibilityID.permissionsSection,
            "ma.permissionDependency.permissions",
            file: file,
            line: line
        )
        XCTAssertEqual(
            PermissionDependencyAccessibilityID.dependenciesSection,
            "ma.permissionDependency.dependencies",
            file: file,
            line: line
        )
    }

    private func assertRecordingLocators(
        file: StaticString = #filePath,
        line: UInt = #line
    ) {
        XCTAssertEqual(
            RecordingAccessibilityID.heading,
            "ma.recording.heading",
            file: file,
            line: line
        )
        XCTAssertEqual(
            RecordingAccessibilityID.readinessStatus,
            "ma.recording.readinessStatus",
            file: file,
            line: line
        )
        XCTAssertEqual(
            RecordingAccessibilityID.status,
            "ma.recording.status",
            file: file,
            line: line
        )
        XCTAssertEqual(
            RecordingAccessibilityID.startButton,
            "ma.recording.startButton",
            file: file,
            line: line
        )
        XCTAssertEqual(
            RecordingAccessibilityID.stopButton,
            "ma.recording.stopButton",
            file: file,
            line: line
        )
        XCTAssertEqual(
            RecordingAccessibilityID.error,
            "ma.recording.error",
            file: file,
            line: line
        )
        XCTAssertEqual(
            RecordingAccessibilityID.savedSummary,
            "ma.recording.savedSummary",
            file: file,
            line: line
        )
        XCTAssertEqual(
            RecordingAccessibilityID.artifactStatus("screen_video"),
            "ma.recording.artifact.screen_video.status",
            file: file,
            line: line
        )
        XCTAssertEqual(
            RecordingAccessibilityID.artifactDegradation("mixed_audio"),
            "ma.recording.artifact.mixed_audio.degradation",
            file: file,
            line: line
        )
    }

    private func assertTranscriptLocators(
        file: StaticString = #filePath,
        line: UInt = #line
    ) {
        XCTAssertEqual(
            TranscriptReviewAccessibilityID.heading,
            "ma.transcript.heading",
            file: file,
            line: line
        )
        XCTAssertEqual(
            TranscriptReviewAccessibilityID.summary,
            "ma.transcript.summary",
            file: file,
            line: line
        )
        XCTAssertEqual(
            TranscriptReviewAccessibilityID.segmentRow("seg-1"),
            "ma.transcript.segmentRow.seg-1",
            file: file,
            line: line
        )
        XCTAssertEqual(
            TranscriptReviewAccessibilityID.timestamp("seg-1"),
            "ma.transcript.timestamp.seg-1",
            file: file,
            line: line
        )
        XCTAssertEqual(
            TranscriptReviewAccessibilityID.text("seg-1"),
            "ma.transcript.text.seg-1",
            file: file,
            line: line
        )
        XCTAssertEqual(
            TranscriptReviewAccessibilityID.speakerLabel("seg-1"),
            "ma.transcript.speakerLabel.seg-1",
            file: file,
            line: line
        )
        XCTAssertEqual(
            TranscriptReviewAccessibilityID.degradation,
            "ma.transcript.degradation",
            file: file,
            line: line
        )
        XCTAssertEqual(
            TranscriptReviewAccessibilityID.empty,
            "ma.transcript.empty",
            file: file,
            line: line
        )
        XCTAssertEqual(
            TranscriptReviewAccessibilityID.missing,
            "ma.transcript.missing",
            file: file,
            line: line
        )
    }

    private func assertProcessingLocators(
        file: StaticString = #filePath,
        line: UInt = #line
    ) {
        XCTAssertEqual(
            ProcessingAccessibilityID.heading,
            "ma.processing.heading",
            file: file,
            line: line
        )
        XCTAssertEqual(
            ProcessingAccessibilityID.status,
            "ma.processing.status",
            file: file,
            line: line
        )
        XCTAssertEqual(
            ProcessingAccessibilityID.startButton,
            "ma.processing.startButton",
            file: file,
            line: line
        )
        XCTAssertEqual(
            ProcessingAccessibilityID.retryButton,
            "ma.processing.retryButton",
            file: file,
            line: line
        )
        XCTAssertEqual(
            ProcessingAccessibilityID.transcriptStatus,
            "ma.processing.transcriptStatus",
            file: file,
            line: line
        )
        XCTAssertEqual(
            ProcessingAccessibilityID.speakerLabelStatus,
            "ma.processing.speakerLabelStatus",
            file: file,
            line: line
        )
        XCTAssertEqual(
            ProcessingAccessibilityID.success,
            "ma.processing.success",
            file: file,
            line: line
        )
        XCTAssertEqual(
            ProcessingAccessibilityID.error,
            "ma.processing.error",
            file: file,
            line: line
        )
        XCTAssertEqual(
            ProcessingAccessibilityID.degradation,
            "ma.processing.degradation",
            file: file,
            line: line
        )
        XCTAssertEqual(
            ProcessingAccessibilityID.warnings,
            "ma.processing.warnings",
            file: file,
            line: line
        )
    }

    private func assertTranscriptActionLocators(
        file: StaticString = #filePath,
        line: UInt = #line
    ) {
        XCTAssertEqual(
            TranscriptActionAccessibilityID.heading,
            "ma.transcriptAction.heading",
            file: file,
            line: line
        )
        XCTAssertEqual(
            TranscriptActionAccessibilityID.status,
            "ma.transcriptAction.status",
            file: file,
            line: line
        )
        XCTAssertEqual(
            TranscriptActionAccessibilityID.copyButton,
            "ma.transcriptAction.copyButton",
            file: file,
            line: line
        )
        XCTAssertEqual(
            TranscriptActionAccessibilityID.exportButton,
            "ma.transcriptAction.exportButton",
            file: file,
            line: line
        )
        XCTAssertEqual(
            TranscriptActionAccessibilityID.deleteButton,
            "ma.transcriptAction.deleteButton",
            file: file,
            line: line
        )
        XCTAssertEqual(
            TranscriptActionAccessibilityID.successSummary,
            "ma.transcriptAction.success",
            file: file,
            line: line
        )
        XCTAssertEqual(
            TranscriptActionAccessibilityID.errorSummary,
            "ma.transcriptAction.error",
            file: file,
            line: line
        )
        XCTAssertEqual(
            TranscriptActionAccessibilityID.deletePrompt,
            "ma.transcriptAction.deletePrompt",
            file: file,
            line: line
        )
        XCTAssertEqual(
            TranscriptActionAccessibilityID.deletePromptHeading,
            "ma.transcriptAction.deletePromptHeading",
            file: file,
            line: line
        )
        XCTAssertEqual(
            TranscriptActionAccessibilityID.deleteConfirmButton,
            "ma.transcriptAction.deleteConfirmButton",
            file: file,
            line: line
        )
        XCTAssertEqual(
            TranscriptActionAccessibilityID.deleteCancelButton,
            "ma.transcriptAction.deleteCancelButton",
            file: file,
            line: line
        )
    }

    private func assertShellLocators(
        file: StaticString = #filePath,
        line: UInt = #line
    ) {
        XCTAssertEqual(
            DesignedNativeShellAccessibilityID.root,
            "ma.shell.root",
            file: file,
            line: line
        )
        XCTAssertEqual(
            MeetingTaskAccessibilityID.navigation,
            "ma.shell.navigation",
            file: file,
            line: line
        )
        XCTAssertEqual(
            MeetingTaskAccessibilityID.routeStatus,
            "ma.shell.selectedSection",
            file: file,
            line: line
        )
        XCTAssertEqual(
            MeetingTaskAccessibilityID.meetingsNavigation,
            "ma.navigation.meetings",
            file: file,
            line: line
        )
        XCTAssertEqual(
            MeetingTaskAccessibilityID.newRecordingNavigation,
            "ma.navigation.newRecording",
            file: file,
            line: line
        )
        XCTAssertEqual(
            MeetingTaskAccessibilityID.currentMeetingNavigation,
            "ma.navigation.currentMeeting",
            file: file,
            line: line
        )
        XCTAssertEqual(
            MeetingTaskAccessibilityID.diagnosticsNavigation,
            "ma.navigation.diagnostics",
            file: file,
            line: line
        )
        XCTAssertEqual(
            MeetingTaskAccessibilityID.meetingsHeading,
            "ma.meetings.heading",
            file: file,
            line: line
        )
        XCTAssertEqual(
            MeetingTaskAccessibilityID.newRecordingHeading,
            "ma.newRecording.heading",
            file: file,
            line: line
        )
        XCTAssertEqual(
            MeetingTaskAccessibilityID.detailHeading,
            "ma.meetingDetail.heading",
            file: file,
            line: line
        )
        XCTAssertEqual(
            MeetingTaskAccessibilityID.recoveryStatus,
            "ma.meetingDetail.recoveryStatus",
            file: file,
            line: line
        )
        XCTAssertEqual(
            MeetingTaskAccessibilityID.startNewRecording,
            "ma.meetingDetail.startNewRecording",
            file: file,
            line: line
        )
        XCTAssertEqual(
            MeetingTaskAccessibilityID.diagnosticsHeading,
            "ma.diagnostics.heading",
            file: file,
            line: line
        )
        XCTAssertEqual(
            MeetingTaskAccessibilityID.meetingRow("session-hosted-shell"),
            "ma.meetings.row.session-hosted-shell",
            file: file,
            line: line
        )
    }
}

private struct UnusedDependencyCheckRunner: DependencyCheckRunning {
    func checkDependencies(workspaceURL: URL?) async throws -> DependencyCheckResponse {
        throw XCTSkip("The hosted UI smoke uses an injected initial state.")
    }
}

private struct HostedTranscriptFailure: Error {}

@MainActor
private final class HostedSwiftUIView<Content: View> {
    private let controller: NSHostingController<Content>
    private let window: NSWindow

    init(_ rootView: Content) {
        controller = NSHostingController(rootView: rootView)
        window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 900, height: 700),
            styleMask: [.titled],
            backing: .buffered,
            defer: false
        )
        window.contentViewController = controller
        window.makeKeyAndOrderFront(nil)
        controller.view.setFrameSize(NSSize(width: 900, height: 700))
        flush()
    }

    func flush() {
        controller.view.needsLayout = true
        controller.view.layoutSubtreeIfNeeded()
        controller.view.displayIfNeeded()
        window.displayIfNeeded()
        RunLoop.main.run(until: Date(timeIntervalSinceNow: 0.02))
    }

    func assertHosted(
        file: StaticString = #filePath,
        line: UInt = #line
    ) {
        flush()
        XCTAssertFalse(controller.view.frame.isEmpty, file: file, line: line)
    }
}

private enum SwiftUIViewSourceContract {
    static func assertPermissionDependencyViewUsesAccessibleStates(
        file: StaticString = #filePath,
        line: UInt = #line
    ) {
        let source = readSource("PermissionDependencyStatusView.swift", file: file, line: line)
        assertSource(
            source,
            contains: [
                "Text(\"Meeting Assistant Readiness\")",
                "Button(\"Open Screen Recording Settings\")",
                "Button(\"Open Microphone Settings\")",
                "appIdentity.permissionRepairSummary",
                "appIdentity.staleIdentityRepairSummary",
                "openPrivacySettings()",
                "openMicrophoneSettings()",
                ".accessibilityIdentifier(PermissionDependencyAccessibilityID.heading)",
                ".accessibilityIdentifier(PermissionDependencyAccessibilityID.summary)",
                ".accessibilityIdentifier(PermissionDependencyAccessibilityID.checkButton)",
                ".accessibilityIdentifier(PermissionDependencyAccessibilityID.openPrivacySettingsButton)",
                ".accessibilityIdentifier(PermissionDependencyAccessibilityID.openMicrophoneSettingsButton)",
                ".accessibilityIdentifier(PermissionDependencyAccessibilityID.appIdentity)",
                "identifier: PermissionDependencyAccessibilityID.permissionsSection",
                "identifier: PermissionDependencyAccessibilityID.dependenciesSection",
                ".accessibilityIdentifier(identifier)",
                "\"ma.permission.\\(item.id).status\"",
                "\"ma.dependency.\\(item.id).status\"",
            ],
            file: file,
            line: line
        )
    }

    static func assertRecordingViewUsesAccessibleStates(
        file: StaticString = #filePath,
        line: UInt = #line
    ) {
        let source = readSource("RecordingControlView.swift", file: file, line: line)
        assertSource(
            source,
            contains: [
                "Text(\"Recording\")",
                "Button(\"Start Recording\")",
                "Button(\"Stop Recording\")",
                "\"Recording readiness is pending.\"",
                "\"Recording command is active.\"",
                "\"Recording command failed.\"",
                ".accessibilityIdentifier(RecordingControlAccessibilityID.heading)",
                ".accessibilityIdentifier(RecordingControlAccessibilityID.readinessStatus)",
                ".accessibilityIdentifier(RecordingControlAccessibilityID.status)",
                ".accessibilityIdentifier(RecordingControlAccessibilityID.startButton)",
                ".accessibilityIdentifier(RecordingControlAccessibilityID.stopButton)",
                ".accessibilityIdentifier(RecordingControlAccessibilityID.sessionID)",
                ".accessibilityIdentifier(RecordingControlAccessibilityID.success)",
                ".accessibilityIdentifier(RecordingControlAccessibilityID.failure)",
                ".accessibilityIdentifier(",
                "RecordingControlAccessibilityID.artifactStatus(artifact.artifactType)",
                "RecordingControlAccessibilityID.artifactDegradation(artifact.artifactType)",
            ],
            file: file,
            line: line
        )
    }

    static func assertTranscriptReviewViewUsesAccessibleStates(
        file: StaticString = #filePath,
        line: UInt = #line
    ) {
        let source = readSource("TranscriptReviewView.swift", file: file, line: line)
        assertSource(
            source,
            contains: [
                ".accessibilityIdentifier(TranscriptReviewAccessibilityID.heading)",
                ".accessibilityIdentifier(TranscriptReviewAccessibilityID.summary)",
                ".accessibilityIdentifier(TranscriptReviewAccessibilityID.missing)",
                ".accessibilityIdentifier(TranscriptReviewAccessibilityID.empty)",
                ".accessibilityIdentifier(TranscriptReviewAccessibilityID.degradation)",
                ".accessibilityIdentifier(TranscriptReviewAccessibilityID.timestamp(segment.id))",
                ".accessibilityIdentifier(TranscriptReviewAccessibilityID.speakerLabel(segment.id))",
                ".accessibilityIdentifier(TranscriptReviewAccessibilityID.text(segment.id))",
                ".accessibilityIdentifier(TranscriptReviewAccessibilityID.segmentRow(segment.id))",
                "Speaker labels unavailable:",
            ],
            file: file,
            line: line
        )
    }

    static func assertProcessingViewUsesAccessibleStates(
        file: StaticString = #filePath,
        line: UInt = #line
    ) {
        let source = readSource("ProcessingStateView.swift", file: file, line: line)
        assertSource(
            source,
            contains: [
                "Text(\"Processing\")",
                "Button(\"Start Processing\")",
                "Button(\"Retry Processing\")",
                ".accessibilityIdentifier(ProcessingAccessibilityID.heading)",
                ".accessibilityIdentifier(ProcessingAccessibilityID.status)",
                ".accessibilityIdentifier(ProcessingAccessibilityID.startButton)",
                ".accessibilityIdentifier(ProcessingAccessibilityID.retryButton)",
                ".accessibilityIdentifier(ProcessingAccessibilityID.transcriptStatus)",
                ".accessibilityIdentifier(ProcessingAccessibilityID.speakerLabelStatus)",
                ".accessibilityIdentifier(ProcessingAccessibilityID.success)",
                ".accessibilityIdentifier(ProcessingAccessibilityID.error)",
                ".accessibilityIdentifier(ProcessingAccessibilityID.degradation)",
                ".accessibilityIdentifier(ProcessingAccessibilityID.warnings)",
            ],
            file: file,
            line: line
        )
    }

    static func assertTranscriptActionViewUsesAccessibleStates(
        file: StaticString = #filePath,
        line: UInt = #line
    ) {
        let source = readSource("TranscriptReviewActionsView.swift", file: file, line: line)
        assertSource(
            source,
            contains: [
                "Text(\"Transcript Actions\")",
                "Button(\"Copy Transcript\")",
                "Button(\"Export Markdown\")",
                "Button(\"Delete Session\")",
                "Button(\"Confirm Delete\")",
                "Button(\"Cancel Delete\")",
                ".accessibilityIdentifier(TranscriptActionAccessibilityID.heading)",
                ".accessibilityIdentifier(TranscriptActionAccessibilityID.status)",
                ".accessibilityIdentifier(TranscriptActionAccessibilityID.copyButton)",
                ".accessibilityIdentifier(TranscriptActionAccessibilityID.exportButton)",
                ".accessibilityIdentifier(TranscriptActionAccessibilityID.deleteButton)",
                ".accessibilityIdentifier(TranscriptActionAccessibilityID.successSummary)",
                ".accessibilityIdentifier(TranscriptActionAccessibilityID.errorSummary)",
                ".accessibilityIdentifier(TranscriptActionAccessibilityID.deletePrompt)",
                ".accessibilityIdentifier(TranscriptActionAccessibilityID.deletePromptText)",
                ".accessibilityIdentifier(TranscriptActionAccessibilityID.deleteConfirmButton)",
                ".accessibilityIdentifier(TranscriptActionAccessibilityID.deleteCancelButton)",
            ],
            file: file,
            line: line
        )
    }

    static func assertDesignedNativeShellUsesAccessibleStates(
        file: StaticString = #filePath,
        line: UInt = #line
    ) {
        let source = readSource("DesignedNativeShellView.swift", file: file, line: line)
        assertSource(
            source,
            contains: [
                "Text(\"Meeting Assistant\")",
                ".accessibilityIdentifier(DesignedNativeShellAccessibilityID.root)",
                ".accessibilityIdentifier(MeetingTaskAccessibilityID.navigation)",
                ".accessibilityIdentifier(MeetingTaskAccessibilityID.routeStatus)",
                "identifier: MeetingTaskAccessibilityID.meetingsNavigation",
                "identifier: MeetingTaskAccessibilityID.newRecordingNavigation",
                "identifier: MeetingTaskAccessibilityID.currentMeetingNavigation",
                "identifier: MeetingTaskAccessibilityID.diagnosticsNavigation",
                "identifier: MeetingTaskAccessibilityID.meetingsHeading",
                "identifier: MeetingTaskAccessibilityID.newRecordingHeading",
                "identifier: MeetingTaskAccessibilityID.detailHeading",
                "identifier: MeetingTaskAccessibilityID.diagnosticsHeading",
                ".accessibilityIdentifier(MeetingTaskAccessibilityID.newRecordingButton)",
                ".accessibilityIdentifier(MeetingTaskAccessibilityID.meetingRow(meeting.id))",
                ".accessibilityIdentifier(MeetingTaskAccessibilityID.titleField)",
                ".accessibilityIdentifier(MeetingTaskAccessibilityID.target)",
                ".accessibilityIdentifier(MeetingTaskAccessibilityID.systemAudioToggle)",
                ".accessibilityIdentifier(MeetingTaskAccessibilityID.microphoneToggle)",
                ".accessibilityIdentifier(MeetingTaskAccessibilityID.audioSourcePicker)",
                ".accessibilityIdentifier(MeetingTaskAccessibilityID.transcriptToolbar)",
                "@State private var showTechnicalDetails = false",
                "@AccessibilityFocusState private var accessibilityFocus",
                "@FocusState private var keyboardFocus",
                "NSAccessibility.post(",
                "notification: .announcementRequested",
                ".accessibilityAddTraits(isSelected ? .isSelected",
                "Image(systemName: \"checkmark\")",
                ".accessibilityFocused($accessibilityFocus, equals: .pageHeading)",
                ".accessibilityFocused($accessibilityFocus, equals: .deleteConfirmation)",
                ".focused($keyboardFocus, equals: .primaryAction)",
                ".focused($keyboardFocus, equals: .copyTranscript)",
                ".focused($keyboardFocus, equals: .deleteAction)",
                ".focused($keyboardFocus, equals: .deleteCancel)",
                ".focused($keyboardFocus, equals: .deleteConfirm)",
                "DisclosureGroup(\"Technical details\", isExpanded: $showTechnicalDetails)",
                ".accessibilityIdentifier(MeetingTaskAccessibilityID.technicalDetails)",
                "Text(\"Delete \\(coordinator.currentMeetingTitle)?\")",
                ".accessibilityIdentifier(TranscriptActionAccessibilityID.deleteCancelButton)",
                ".accessibilityIdentifier(TranscriptActionAccessibilityID.deleteConfirmButton)",
                "Transcript text was created. Adding anonymous speaker labels before final review.",
                "LazyVStack(spacing: 0)",
                "Picker(",
                "Button(\"Retry transcript\")",
                "switch coordinator.route",
                "case .meetings:",
                "case .newRecording:",
                "case .meetingDetail:",
                "case .diagnostics:",
                "title: \"Meetings\"",
                "title: \"New recording\"",
                "title: \"Set up your recording\"",
                "title: \"Settings & diagnostics\"",
                "PermissionDependencyStatusView(",
                "captureMicrophoneAudio: coordinator.recordingDraft.captureMicrophoneAudio",
                ".accessibilityIdentifier(TranscriptReviewAccessibilityID.segmentRow(segment.id))",
                ".accessibilityIdentifier(TranscriptActionAccessibilityID.copyButton)",
                ".accessibilityIdentifier(TranscriptActionAccessibilityID.exportButton)",
                ".accessibilityIdentifier(TranscriptActionAccessibilityID.deleteButton)",
                "Button(\"Reload transcript\", action: reloadTranscript)",
                "return \"Transcript unavailable\"",
                "historicalMeetingRecoveryStatus(sessionStatus) != nil",
                "historicalMeetingRecoveryView(status: sessionStatus)",
                "hasUnconfirmedCapturePermissions(",
                "return \"Confirm recording permission\"",
                "Start recording will ask macOS to confirm access",
                "Recording permission will be confirmed when you start.",
                "return \"Recording not started\"",
                "return \"Recording interrupted\"",
                "return \"Transcript interrupted\"",
                "return \"Meeting date unavailable\"",
                "Label(\"Meeting needs attention\", systemImage: \"exclamationmark.triangle.fill\")",
                "subtitle: \"Existing meeting files were not changed.\"",
                "Button(\"Start a new recording\")",
                ".accessibilityIdentifier(MeetingTaskAccessibilityID.startNewRecording)",
                ".accessibilityIdentifier(MeetingTaskAccessibilityID.recoveryStatus)",
                "secondaryMeetingActions",
                "technicalDetailsDisclosure",
                ".onChange(of: permissionViewModel.state)",
                "synchronizeRecordingReadiness(readiness)",
                "processingViewModel.updateReadiness(readiness)",
                ".onChange(of: coordinator.recordingDraft.captureMicrophoneAudio)",
                "readiness.canStartRecording(",
                ".keyboardShortcut(\"r\", modifiers: [.command, .option])",
                ".keyboardShortcut(\"s\", modifiers: [.command, .option])",
                ".keyboardShortcut(\"p\", modifiers: [.command, .option])",
                ".keyboardShortcut(\"c\", modifiers: [.command, .option])",
                ".keyboardShortcut(\"e\", modifiers: [.command, .option])",
                ".task {",
                "coordinator.refreshSessions()",
                "await autoRefreshPreflightIfNeeded()",
                "autoRefreshPreflightOnAppear",
                "await permissionViewModel.refresh(workspaceURL: coordinator.workspaceURL)",
            ],
            file: file,
            line: line
        )
        assertSource(
            source,
            excludes: [
                "commandRail",
                "statusBoard",
                "DesignedNativeShellSection.allCases",
                "ForEach(shellViewModel.sections)",
                "DesignedNativeShellAccessibilityID.section(",
                "DesignedNativeShellAccessibilityID.navButton(",
                "if hasTranscript || status == \"transcribed\"",
                "return \"Saved meeting\"",
                "return \"Saved\"",
                "Button(\"Regenerate transcript\", action: startProcessing)",
                "announcement = processingViewModel.state.successSummary",
            ],
            file: file,
            line: line
        )
        assertOccurrenceCount(
            source,
            snippet: ".accessibilityIdentifier(MeetingTaskAccessibilityID.navigation)",
            expected: 1,
            file: file,
            line: line
        )
    }

    static func assertAppRootUsesDesignedNativeShell(
        file: StaticString = #filePath,
        line: UInt = #line
    ) {
        let source = readAppSource("MeetingAssistantNativeApp.swift", file: file, line: line)
        assertSource(
            source,
            contains: [
                "@StateObject private var workspaceCoordinator: MeetingWorkspaceCoordinator",
                "_workspaceCoordinator = StateObject(",
                "wrappedValue: MeetingWorkspaceCoordinator(",
                "workspaceURL: recordingWorkspaceURL",
                "initialSessions: initialSessions",
                "recordingDraft: MeetingRecordingDraft(",
                "let readinessState = configuration.initialReadinessState()",
                "let autoRefreshPreflightOnAppear = configuration.autoRefreshPreflightOnAppear()",
                "captureSystemAudio: configuration.captureSystemAudio",
                "captureMicrophoneAudio: configuration.captureMicrophoneAudio",
                "let dependencyCheckRunner = configuration.makeDependencyCheckRunner()",
                "runner: dependencyCheckRunner",
                "MeetingAssistantNativeLaunchCoordinator.shared.install()",
                "private final class MeetingAssistantNativeLaunchCoordinator",
                "NSApplication.didFinishLaunchingNotification",
                "NSApplication.didBecomeActiveNotification",
                "reopenMainWindowIfNeeded()",
                "MeetingAssistantNativeMainWindow.shared.openMainWindow()",
                "NativeLocalAppKeyboardShortcutView",
                "NSEvent.addLocalMonitorForEvents(matching: .keyDown)",
                "event.modifierFlags.intersection(.deviceIndependentFlagsMask)",
                "startRecording()",
                "stopRecording()",
                "startProcessing()",
                "copyTranscript()",
                "exportTranscript()",
                "requestDelete()",
                "cancelDelete()",
                "transcriptActionViewModel.state.isDeletePromptVisible",
                "transcriptActionViewModel.cancelDelete()",
                "return cancelDelete() ? nil : event",
                "private var windowController: NSWindowController?",
                "var hasVisibleWindow: Bool",
                "NSHostingController(rootView: rootView)",
                "NSWindow(",
                "window.appearance = NSAppearance(named: .aqua)",
                "window.setAccessibilityElement(true)",
                "window.setAccessibilityRole(.window)",
                "window.setAccessibilitySubrole(.standardWindow)",
                "window.setAccessibilityTitle(\"Meeting Assistant Native\")",
                "hostingController.view.setAccessibilityElement(true)",
                "hostingController.view.setAccessibilityRole(.group)",
                "hostingController.view.setAccessibilityLabel(\"Meeting Assistant\")",
                "window.setFrameAutosaveName(\"meeting-assistant-main\")",
                "window.makeKeyAndOrderFront(nil)",
                "MA_NATIVE_LOCAL_APP_SMOKE_STATE_REPORT",
                "DesignedNativeShellView(",
                "coordinator: workspaceCoordinator",
                "permissionViewModel: permissionViewModel",
                "recordingViewModel: recordingViewModel",
                "processingViewModel: processingViewModel",
                "transcriptViewModel: transcriptViewModel",
                "transcriptActionViewModel: transcriptActionViewModel",
                "autoRefreshPreflightOnAppear: autoRefreshPreflightOnAppear",
                "startRecording: beginRecording",
                "openMeeting: openMeeting",
                "reloadTranscript: reloadCurrentTranscript",
                "confirmDelete: confirmCurrentMeetingDeletion",
                "processingViewModel.bindSession(",
                "sessionStatus: \"recorded\"",
                "sessionStatus: session.status",
                "workspaceCoordinator.processingRequestSourceArtifactID",
                "!currentSession.hasRegisteredTranscript",
                "workspaceCoordinator.transcriptLoadError == nil",
                "sourceArtifactID: sourceArtifactID",
                "Task.detached(priority: .userInitiated)",
                "workspaceCoordinator.transcriptWillLoad(for:",
                "workspaceCoordinator.isCurrentTranscriptLoad(loadToken)",
                "workspaceCoordinator.transcriptDidLoad(",
                "hasSpeakerLabels: input.speakerLabels != nil",
                ".onChange(of: workspaceCoordinator.recordingDraft)",
                "captureSystemAudio: workspaceCoordinator.recordingDraft.captureSystemAudio",
                "captureMicrophoneAudio: workspaceCoordinator.recordingDraft.captureMicrophoneAudio",
                "let reconciliation = await workspaceCoordinator.reconcileDeletionAttempt(",
                "switch reconciliation",
                "case .sessionPresent(let session):",
                "case .sessionMissing, .workspaceUnreadable:",
                "contentRect: NSRect(x: 0, y: 0, width: 1180, height: 760)",
            ],
            file: file,
            line: line
        )
        assertSource(
            source,
            excludes: [
                "return confirmDelete() ? nil : event",
            ],
            file: file,
            line: line
        )
    }

    static func assertAppBundleProductionDefaultsUseCommandClients(
        file: StaticString = #filePath,
        line: UInt = #line
    ) {
        let source = readAppSource("MeetingAssistantNativeApp.swift", file: file, line: line)
        assertSource(
            source,
            contains: [
                "MA_NATIVE_RECORDING_CLIENT",
                "MA_NATIVE_PROCESSING_CLIENT",
                "MA_NATIVE_TRANSCRIPT_ACTION_CLIENT",
                "isRecordingClientTestHookAllowed",
                "isProcessClientTestHookAllowed",
                "isTranscriptActionClientTestHookAllowed",
                "#if DEBUG",
                "#else",
                "return false",
                "#endif",
                "case \"fake\":",
                "return isRecordingClientTestHookAllowed(environment) ? .fake : defaultRecordingClientMode(environment)",
                "case \"controlled\":",
                "workspaceURL != nil",
                "return defaultRecordingClientMode(environment)",
                "return .apple" + "Screen" + "Capture" + "Kit",
                "isNativeAppXCTestEnvironment(environment) ? .fake : .apple" + "Screen" + "Capture" + "Kit",
                "case .apple" + "Screen" + "Capture" + "Kit:",
                "MacOSNativeCapturePermissionChecker(",
                "CoreGraphicsScreenRecordingPermissionProbe(",
                "requestAccessWhenDenied: true",
                "AVFoundationMicrophonePermissionProbe(",
                "requestAccessWhenUndetermined: true",
                "Apple" + "Screen" + "Capture" + "Kit" + "NativeCaptureAdapter()",
                "case .some(\"fake\"):",
                "case .some(\"process\"):",
                "return isProcessClientTestHookAllowed(environment) ? .fake : .process",
                "return isTranscriptActionClientTestHookAllowed(environment) ? .fake : .process",
                "return isNativeAppXCTestEnvironment(environment) ? .fake : .process",
                "ProcessingCommandProcessRunner(environment: environment)",
                "TranscriptActionProcessRunner(environment: environment)",
                "usesStaticDependencyFixture",
                "isNativeAppXCTestEnvironment(environment)",
            ],
            file: file,
            line: line
        )
        XCTAssertFalse(
            source.contains("guard let rawValue,\n              workspaceURL != nil,\n              isRecordingClientTestHookAllowed(environment) else {\n            return .fake"),
            "Production recording client must not fall back to fake only because the Debug/XCTest recording hook is absent.",
            file: file,
            line: line
        )
        XCTAssertFalse(
            source.contains("guard rawValue == \"process\", isProcessClientTestHookAllowed(environment)"),
            "Processing command client must not require a Debug/XCTest-only hook to use the process runner by default.",
            file: file,
            line: line
        )
        XCTAssertFalse(
            source.contains("guard rawValue == \"process\", isTranscriptActionClientTestHookAllowed(environment)"),
            "Transcript action client must not require a Debug/XCTest-only hook to use the process runner by default.",
            file: file,
            line: line
        )
    }

    static func assertAppFixturesAreDebugXCTestOnlyAndReloadUsesWorkspace(
        file: StaticString = #filePath,
        line: UInt = #line
    ) {
        let source = readAppSource("MeetingAssistantNativeApp.swift", file: file, line: line)
        assertSource(
            source,
            contains: [
                "let fixture = smokeFixtureName(environment: environment, arguments: arguments)",
                "private static func smokeFixtureName(",
                "guard isNativeAppXCTestEnvironment(environment) else {",
                "private func isNativeAppXCTestEnvironment(_ environment: [String: String]) -> Bool {\n    #if DEBUG\n    return environment[\"MA_NATIVE_APP_XCTEST\"] == \"1\"",
                "#else\n        return \"blocked\"\n        #endif",
                "#else\n    return false\n    #endif",
                "let input = try await transcriptInput(",
                "try TranscriptReviewWorkspaceLoader.load(",
            ],
            file: file,
            line: line
        )
        assertSource(
            source,
            excludes: [
                "let fixture = environment[\"MA_NATIVE_APP_SMOKE_FIXTURE\"]",
                "let input = try transcriptInput(for: sessionID, allowGeneratedTestFixture: usesTestFixture)",
            ],
            file: file,
            line: line
        )
    }

    private static func readSource(
        _ filename: String,
        file: StaticString,
        line: UInt
    ) -> String {
        let path = "Sources/MeetingAssistantNative/\(filename)"
        do {
            return try String(contentsOfFile: path, encoding: .utf8)
        } catch {
            XCTFail("Could not read \(path): \(error)", file: file, line: line)
            return ""
        }
    }

    private static func readAppSource(
        _ filename: String,
        file: StaticString,
        line: UInt
    ) -> String {
        let path = "App/\(filename)"
        do {
            return try String(contentsOfFile: path, encoding: .utf8)
        } catch {
            XCTFail("Could not read \(path): \(error)", file: file, line: line)
            return ""
        }
    }

    private static func assertSource(
        _ source: String,
        contains snippets: [String],
        file: StaticString,
        line: UInt
    ) {
        for snippet in snippets {
            XCTAssertTrue(
                source.contains(snippet),
                "Missing SwiftUI source snippet: \(snippet)",
                file: file,
                line: line
            )
        }
    }

    private static func assertSource(
        _ source: String,
        excludes snippets: [String],
        file: StaticString,
        line: UInt
    ) {
        for snippet in snippets {
            XCTAssertFalse(
                source.contains(snippet),
                "Obsolete SwiftUI source snippet is still present: \(snippet)",
                file: file,
                line: line
            )
        }
    }

    private static func assertOccurrenceCount(
        _ source: String,
        snippet: String,
        expected: Int,
        file: StaticString,
        line: UInt
    ) {
        let count = source.components(separatedBy: snippet).count - 1
        XCTAssertEqual(
            count,
            expected,
            "Expected \(expected) occurrence(s) of SwiftUI source snippet: \(snippet)",
            file: file,
            line: line
        )
    }
}

private func hostedTranscriptInput() -> TranscriptReviewInput {
    TranscriptReviewInput(
        sessionTitle: "Hosted Shell Transcript",
        transcript: TranscriptReviewTranscript(
            id: "transcript-hosted-shell",
            sessionID: "session-hosted-shell",
            sourceArtifactID: "artifact-normalized-audio",
            status: "succeeded",
            segments: [
                TranscriptReviewSegment(
                    segmentID: "seg-hosted-shell",
                    startMS: 1_000,
                    endMS: 3_000,
                    text: "Hosted shell transcript segment.",
                    speakerLabel: "SPEAKER_01"
                ),
            ]
        ),
        speakerLabels: SpeakerLabelsReviewArtifact(
            sessionID: "session-hosted-shell",
            labels: [
                SpeakerLabelReviewEntry(
                    label: "SPEAKER_01",
                    sessionID: "session-hosted-shell",
                    isVerifiedIdentity: false
                ),
            ],
            segmentMapping: [
                SpeakerLabelSegmentMapping(segmentID: "seg-hosted-shell", label: "SPEAKER_01"),
            ]
        )
    )
}

private func hostedMeetingSummary() -> MeetingSessionSummary {
    MeetingSessionSummary(
        id: "session-hosted-shell",
        title: "Hosted Shell Transcript",
        status: "transcribed",
        startedAt: "2026-07-13T09:00:00Z",
        endedAt: "2026-07-13T09:30:00Z",
        updatedAt: "2026-07-13T09:31:00Z",
        durationLabel: "30:00",
        artifactCount: 4,
        hasTranscript: true,
        hasSpeakerLabels: true,
        hasProcessableAudio: true
    )
}

private func hostedReadinessStatusText(for phase: RecordingControlPhase) -> String {
    switch phase {
    case .idle:
        return "Recording readiness is pending."
    case .ready:
        return "Recording readiness is ready."
    case .starting, .recording, .stopping, .recorded:
        return "Recording command is active."
    case .failed:
        return "Recording command failed."
    }
}

private func readyReadinessState() -> PermissionDependencyStatusState {
    PermissionDependencyStatusState.from(
        DependencyCheckResponse(
            ok: true,
            requestID: "local-ui-ready",
            checks: [
                dependencyCheck("platform.os", status: "supported", required: true, ok: true),
                dependencyCheck("platform.macos_version", status: "supported", required: true, ok: true),
                dependencyCheck("platform.cpu_arch", status: "supported", required: true, ok: true),
                dependencyCheck("workspace.writable", status: "writable", required: true, ok: true),
                dependencyCheck("permission.screen_recording", status: "granted", required: false, ok: true),
                dependencyCheck("permission.microphone", status: "granted", required: false, ok: true),
                dependencyCheck("media_tool.ffmpeg", status: "available", required: true, ok: true),
                dependencyCheck("dependency_downloads.automatic", status: "not_attempted", required: true, ok: true),
            ]
        )
    )
}

private func blockedReadinessState() -> PermissionDependencyStatusState {
    PermissionDependencyStatusState.from(
        DependencyCheckResponse(
            ok: false,
            requestID: "local-ui-blocked",
            code: "dependency_missing",
            message: "One or more required dependencies are missing or unsupported.",
            checks: [
                dependencyCheck(
                    "permission.screen_recording",
                    status: "denied",
                    required: false,
                    ok: false,
                    message: "Screen Recording permission is denied. Open System Settings to grant access."
                ),
                dependencyCheck(
                    "permission.microphone",
                    status: "granted",
                    required: false,
                    ok: true,
                    message: "Microphone permission is granted."
                ),
                dependencyCheck(
                    "media_tool.ffmpeg",
                    status: "missing",
                    required: true,
                    ok: false,
                    message: "FFmpeg executable was not found."
                ),
            ]
        )
    )
}

private func dependencyCheck(
    _ id: String,
    status: String,
    required: Bool,
    ok: Bool,
    message: String? = nil
) -> DependencyCheckItem {
    DependencyCheckItem(
        id: id,
        status: status,
        required: required,
        ok: ok,
        message: message ?? "\(id) is \(status)."
    )
}

private func transcriptActionInput() -> TranscriptReviewInput {
    TranscriptReviewInput(
        sessionTitle: "Hosted Action Transcript",
        transcript: TranscriptReviewTranscript(
            id: "transcript-actions",
            sessionID: "session-actions",
            sourceArtifactID: "artifact-normalized-audio",
            status: "succeeded",
            segments: [
                TranscriptReviewSegment(
                    segmentID: "seg-action",
                    startMS: 0,
                    endMS: 2_000,
                    text: "Hosted transcript action text."
                ),
            ]
        )
    )
}
