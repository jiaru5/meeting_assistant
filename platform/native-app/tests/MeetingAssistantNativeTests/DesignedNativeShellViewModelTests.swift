import Foundation
import Testing
@testable import MeetingAssistantNative

@Suite("Designed native shell")
@MainActor
struct DesignedNativeShellViewModelTests {
    @Test
    func exposesStableSectionsAndNavigationIdentifiers() {
        let viewModel = DesignedNativeShellViewModel()

        #expect(viewModel.sections == [
            .preflight,
            .recording,
            .artifacts,
            .processing,
            .transcript,
            .actions,
        ])
        #expect(viewModel.selectedSection == .preflight)
        #expect(viewModel.selectedSectionLabel == "Preflight selected.")
        #expect(DesignedNativeShellAccessibilityID.root == "ma.shell.root")
        #expect(DesignedNativeShellAccessibilityID.heading == "ma.shell.heading")
        #expect(DesignedNativeShellAccessibilityID.navigation == "ma.shell.navigation")
        #expect(DesignedNativeShellAccessibilityID.commandRail == "ma.shell.commandRail")
        #expect(DesignedNativeShellAccessibilityID.navButton(.recording) == "ma.shell.nav.recording")
        #expect(DesignedNativeShellAccessibilityID.section(.artifacts) == "ma.shell.section.artifacts")
        #expect(
            DesignedNativeShellAccessibilityID.artifactStatus("screen_video")
                == "ma.sessionArtifact.screen_video.status"
        )
        #expect(
            DesignedNativeShellAccessibilityID.processingStep("speakerLabels")
                == "ma.shell.processingStep.speakerLabels"
        )
    }

    @Test
    func selectingSectionUpdatesAccessibleSelectionLabel() {
        let viewModel = DesignedNativeShellViewModel(initialSection: .recording)

        #expect(viewModel.selectedSectionLabel == "Record meeting selected.")

        viewModel.select(.actions)

        #expect(viewModel.selectedSection == .actions)
        #expect(viewModel.selectedSectionLabel == "Export and delete selected.")
    }

    @Test
    func projectsStatusBoardFromExistingViewModelStates() {
        let items = DesignedNativeShellViewModel.statusItems(
            readiness: readyReadinessState(),
            recording: .recording(sessionID: "session-shell"),
            processing: completedProcessingState(),
            transcript: availableTranscriptState(),
            actions: readyActionState()
        )

        #expect(items.map(\.id) == ["preflight", "recording", "processing", "transcript", "actions"])
        #expect(items.map(\.value) == ["Ready", "Recording", "Complete", "Available", "Ready"])
        #expect(items.map(\.tone) == ["success", "recording", "success", "success", "neutral"])
    }

    @Test
    func projectsBlockedAndDegradedStatesWithoutPromotingReleaseEvidence() {
        let items = DesignedNativeShellViewModel.statusItems(
            readiness: blockedReadinessState(),
            recording: RecordingControlState(
                phase: .failed,
                statusText: "Recording failed.",
                sessionID: "session-shell",
                artifacts: [],
                errorCode: .captureFailed,
                errorMessage: "Recording could not be saved.",
                savedSummary: nil,
                warnings: []
            ),
            processing: degradedProcessingState(),
            transcript: degradedTranscriptState(),
            actions: .unavailable
        )

        #expect(items.map(\.value) == ["Blocked", "Failed", "Transcript-only", "Available", "Unavailable"])
        #expect(items.map(\.tone) == ["error", "error", "fallback", "fallback", "neutral"])
    }

    @Test
    func artifactRowsCoverAllRequiredArtifactTypesAndDegradationReasons() {
        let rows = DesignedNativeShellViewModel.artifactRows(
            from: [
                RecordingCommandArtifact(
                    id: "artifact-screen",
                    sessionID: "session-shell",
                    artifactType: "screen_video",
                    format: "mov",
                    path: "sessions/session-shell/artifacts/screen_video.mov"
                ),
                RecordingCommandArtifact(
                    id: "artifact-microphone",
                    sessionID: "session-shell",
                    artifactType: "microphone_audio",
                    captureStatus: "degraded",
                    degradationReason: "microphone input clipped"
                ),
            ]
        )

        #expect(rows.map(\.artifactType) == ["screen_video", "system_audio", "microphone_audio", "mixed_audio"])
        #expect(rows.map(\.status) == ["available", "pending", "degraded", "pending"])
        #expect(rows[0].detail == "sessions/session-shell/artifacts/screen_video.mov")
        #expect(rows[1].detail == "Pending until recording stops.")
        #expect(rows[2].detail == "microphone input clipped")
    }

    @Test
    func processingStepsExposePipelineReadinessFailureAndFallback() {
        let completed = DesignedNativeShellViewModel.processingSteps(from: completedProcessingState())
        #expect(completed.map(\.id) == ["normalizedAudio", "transcript", "speakerLabels", "exportReady"])
        #expect(completed[0].status == "Processing input selected through command contract.")
        #expect(completed[1].status == "Transcript transcript-shell generated with 2 segments.")
        #expect(completed[2].status == "Speaker labels artifact artifact-speakers-shell is available.")
        #expect(completed[3].status == "Transcript can be reviewed before user-triggered export.")

        let degraded = DesignedNativeShellViewModel.processingSteps(from: degradedProcessingState())
        #expect(degraded[2].status == "Speaker labels degraded: speaker labeling runtime unavailable")
        #expect(degraded[3].status == "Transcript can be reviewed before user-triggered export.")

        let failed = DesignedNativeShellViewModel.processingSteps(from: failedProcessingState())
        #expect(failed[0].status == "Retained for retry; original media remains protected.")
        #expect(failed[3].status == "Export blocked until processing succeeds or transcript is loaded.")
    }

    @Test
    func recordingSetupTextMatchesRequestedAudioFlags() {
        #expect(
            DesignedNativeShellViewModel.recordingSetupText(
                captureSystemAudio: true,
                captureMicrophoneAudio: true
            )
            == "Capture target: screen. System audio and microphone capture are requested through the recording command client."
        )
        #expect(
            DesignedNativeShellViewModel.recordingSetupText(
                captureSystemAudio: true,
                captureMicrophoneAudio: false
            )
            == "Capture target: screen. System audio capture is requested; microphone capture is not requested for this run."
        )
        #expect(
            DesignedNativeShellViewModel.recordingSetupText(
                captureSystemAudio: false,
                captureMicrophoneAudio: true
            )
            == "Capture target: screen. Microphone capture is requested; system audio capture is not requested for this run."
        )
        #expect(
            DesignedNativeShellViewModel.recordingSetupText(
                captureSystemAudio: false,
                captureMicrophoneAudio: false
            )
            == "Capture target: screen. Audio capture is not requested for this run; unavailable audio artifacts must stay missing with reasons."
        )
    }
}

private func readyReadinessState() -> PermissionDependencyStatusState {
    PermissionDependencyStatusState.from(
        DependencyCheckResponse(
            ok: true,
            requestID: "local-ready",
            checks: [
                dependencyCheck("permission.screen_recording", status: "granted", required: false, ok: true),
                dependencyCheck("permission.microphone", status: "granted", required: false, ok: true),
                dependencyCheck("media_tool.ffmpeg", status: "available", required: true, ok: true),
            ]
        )
    )
}

private func blockedReadinessState() -> PermissionDependencyStatusState {
    PermissionDependencyStatusState.from(
        DependencyCheckResponse(
            ok: true,
            requestID: "local-blocked",
            checks: [
                dependencyCheck("permission.screen_recording", status: "denied", required: false, ok: false),
                dependencyCheck("permission.microphone", status: "granted", required: false, ok: true),
                dependencyCheck("media_tool.ffmpeg", status: "missing", required: true, ok: false),
            ]
        )
    )
}

private func dependencyCheck(
    _ id: String,
    status: String,
    required: Bool,
    ok: Bool
) -> DependencyCheckItem {
    DependencyCheckItem(
        id: id,
        status: status,
        required: required,
        ok: ok,
        message: "\(id) is \(status)."
    )
}

private func completedProcessingState() -> ProcessingState {
    ProcessingState(
        phase: .completed,
        statusText: "Processing complete.",
        sessionID: "session-shell",
        transcriptID: "transcript-shell",
        transcriptArtifactID: "artifact-transcript-shell",
        transcriptStatus: "Transcript transcript-shell generated with 2 segments.",
        segmentCount: 2,
        labelStatus: "labeled",
        speakerLabelsArtifactID: "artifact-speakers-shell",
        speakerLabelStatus: "Speaker labels artifact artifact-speakers-shell is available.",
        successSummary: "Generated transcript and speaker labels for session session-shell.",
        degradationReason: nil,
        errorCode: nil,
        errorMessage: nil,
        errorDetails: [],
        warnings: []
    )
}

private func degradedProcessingState() -> ProcessingState {
    ProcessingState(
        phase: .degraded,
        statusText: "Processing completed with transcript-only speaker labels.",
        sessionID: "session-shell",
        transcriptID: "transcript-shell",
        transcriptArtifactID: "artifact-transcript-shell",
        transcriptStatus: "Transcript transcript-shell generated with 2 segments.",
        segmentCount: 2,
        labelStatus: "transcript_only",
        speakerLabelsArtifactID: "artifact-speakers-shell",
        speakerLabelStatus: "Speaker labels degraded: speaker labeling runtime unavailable",
        successSummary: nil,
        degradationReason: "speaker labeling runtime unavailable",
        errorCode: nil,
        errorMessage: nil,
        errorDetails: [],
        warnings: []
    )
}

private func failedProcessingState() -> ProcessingState {
    ProcessingState(
        phase: .failed,
        statusText: "Processing failed.",
        sessionID: "session-shell",
        transcriptID: "transcript-shell",
        transcriptArtifactID: "artifact-transcript-shell",
        transcriptStatus: "Transcript transcript-shell generated with 2 segments.",
        segmentCount: 2,
        labelStatus: nil,
        speakerLabelsArtifactID: nil,
        speakerLabelStatus: nil,
        successSummary: nil,
        degradationReason: nil,
        errorCode: .processingFailed,
        errorMessage: "Transcript adapter failed.",
        errorDetails: [],
        warnings: []
    )
}

private func availableTranscriptState() -> TranscriptReviewState {
    TranscriptReviewState(
        contentState: .available,
        heading: "Shell transcript",
        summary: "Transcript has 1 segment for review.",
        segments: [
            TranscriptReviewVisibleSegment(
                id: "seg-shell",
                timestampLabel: "00:01-00:03",
                text: "Shell transcript segment.",
                speakerDisplayLabel: "Anonymous speaker SPEAKER_01 (not a verified identity)"
            ),
        ],
        degradationReason: nil
    )
}

private func degradedTranscriptState() -> TranscriptReviewState {
    TranscriptReviewState(
        contentState: .available,
        heading: "Shell transcript",
        summary: "Transcript has 1 segment for review.",
        segments: [
            TranscriptReviewVisibleSegment(
                id: "seg-shell",
                timestampLabel: "00:01-00:03",
                text: "Shell transcript segment.",
                speakerDisplayLabel: nil
            ),
        ],
        degradationReason: "speaker labeling runtime unavailable"
    )
}

private func readyActionState() -> TranscriptReviewActionsState {
    TranscriptReviewActionsState(
        phase: .ready,
        sessionID: "session-shell",
        sessionTitle: "Shell transcript",
        statusText: "Transcript actions are ready.",
        successSummary: nil,
        failureSummary: nil,
        warnings: [],
        isDeletePromptVisible: false
    )
}
