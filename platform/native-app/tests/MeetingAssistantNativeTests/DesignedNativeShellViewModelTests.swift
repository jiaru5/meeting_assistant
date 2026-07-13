import Testing
@testable import MeetingAssistantNative

@Suite("Task-based native shell")
struct DesignedNativeShellViewModelTests {
    @Test
    func exposesStableTaskRoutesInsteadOfPipelineSections() {
        #expect(MeetingWorkspaceRoute.allCases == [
            .meetings,
            .newRecording,
            .meetingDetail,
            .diagnostics,
        ])
        #expect(MeetingWorkspaceRoute.meetings.title == "Meetings")
        #expect(MeetingWorkspaceRoute.newRecording.title == "New recording")
        #expect(MeetingWorkspaceRoute.meetingDetail.title == "Meeting detail")
        #expect(MeetingWorkspaceRoute.diagnostics.title == "Settings & diagnostics")
    }

    @Test
    func taskLocatorsUseUserJourneyPrefixes() {
        #expect(MeetingTaskAccessibilityID.navigation == "ma.shell.navigation")
        #expect(MeetingTaskAccessibilityID.meetingsHeading == "ma.meetings.heading")
        #expect(MeetingTaskAccessibilityID.newRecordingButton == "ma.meetings.newRecordingButton")
        #expect(MeetingTaskAccessibilityID.newRecordingHeading == "ma.newRecording.heading")
        #expect(MeetingTaskAccessibilityID.titleField == "ma.newRecording.titleField")
        #expect(MeetingTaskAccessibilityID.detailHeading == "ma.meetingDetail.heading")
        #expect(MeetingTaskAccessibilityID.recoveryStatus == "ma.meetingDetail.recoveryStatus")
        #expect(MeetingTaskAccessibilityID.startNewRecording == "ma.meetingDetail.startNewRecording")
        #expect(MeetingTaskAccessibilityID.diagnosticsHeading == "ma.diagnostics.heading")
        #expect(
            MeetingTaskAccessibilityID.meetingRow("session-1")
                == "ma.meetings.row.session-1"
        )
    }

    @Test
    func recordingDraftUsesUserInputAndDoesNotInventATitle() {
        var draft = MeetingRecordingDraft(
            title: "   ",
            captureSystemAudio: true,
            captureMicrophoneAudio: false
        )

        #expect(draft.normalizedTitle == nil)
        #expect(draft.captureSystemAudio)
        #expect(draft.captureMicrophoneAudio == false)

        draft.title = "  Design review  "
        #expect(draft.normalizedTitle == "Design review")
    }

    @Test
    func onlyInProgressActivitiesLockNavigation() {
        #expect(MeetingWorkspaceActivity.idle.locksNavigation == false)
        #expect(MeetingWorkspaceActivity.startingRecording.locksNavigation)
        #expect(MeetingWorkspaceActivity.recording.locksNavigation)
        #expect(MeetingWorkspaceActivity.saving.locksNavigation)
        #expect(MeetingWorkspaceActivity.processing.locksNavigation)
    }

    @Test
    func meetingTimestampAcceptsISO8601WithAndWithoutFractionalSeconds() throws {
        let wholeSeconds = try #require(
            meetingTimestampDate("2026-07-13T08:09:10Z")
        )
        let fractionalSeconds = try #require(
            meetingTimestampDate("2026-07-13T08:09:10.000Z")
        )

        #expect(wholeSeconds == fractionalSeconds)
        #expect(meetingTimestampDate("not-a-timestamp") == nil)
        #expect(meetingFriendlyDate("not-a-timestamp") == "Meeting date unavailable")
    }

    @Test
    func savedArtifactSummaryTreatsUnrequestedAudioAsNeutral() {
        let artifacts = [
            readyArtifact(id: "screen", type: "screen_video"),
            notRequestedArtifact(id: "microphone", type: "microphone_audio"),
        ]

        #expect(
            recordingSavedArtifactSummary(artifacts: artifacts, fallbackCount: 0)
                == "1 meeting file is ready. Optional audio was left out as requested."
        )
    }

    @Test
    func savedArtifactSummaryCountsOnlyRequestedUnavailableSourcesAsFailures() {
        let artifacts = [
            readyArtifact(id: "screen", type: "screen_video"),
            RecordingCommandArtifact(
                id: "system",
                artifactType: "system_audio",
                captureStatus: "missing",
                degradationReason: "System audio permission was unavailable."
            ),
            notRequestedArtifact(id: "microphone", type: "microphone_audio"),
        ]

        #expect(
            recordingSavedArtifactSummary(artifacts: artifacts, fallbackCount: 0)
                == "1 meeting file is ready; 1 requested source was unavailable. Successful files were kept. Optional audio was left out as requested."
        )
    }

    @Test
    func savedArtifactAccessibilityUsesUserLanguageInsteadOfRawTypeAndStatus() {
        let degradedAudio = RecordingCommandArtifact(
            id: "meeting-audio",
            artifactType: "mixed_audio",
            path: "sessions/session/artifacts/meeting-audio.wav",
            captureStatus: "degraded",
            degradationReason: "Meeting audio was recovered with limited quality.",
            checksum: "sha256:1111111111111111111111111111111111111111111111111111111111111111"
        )
        let missingMicrophone = RecordingCommandArtifact(
            id: "microphone",
            artifactType: "microphone_audio",
            captureStatus: "missing",
            degradationReason: "Microphone access was unavailable."
        )

        let degradedLabel = recordingArtifactAccessibilityLabel(degradedAudio)
        let missingLabel = recordingArtifactAccessibilityLabel(missingMicrophone)

        #expect(degradedLabel == "Meeting audio, Saved with limited quality.")
        #expect(missingLabel == "Microphone, Not captured. Microphone access was unavailable.")
        #expect(!degradedLabel.contains("mixed_audio"))
        #expect(!degradedLabel.contains("degraded"))
        #expect(!missingLabel.contains("microphone_audio"))
        #expect(!missingLabel.contains("missing"))
    }

    @Test
    func savedArtifactUserStatusHidesRawContractFieldsFromProviderReason() {
        let missingMicrophone = RecordingCommandArtifact(
            id: "microphone",
            artifactType: "microphone_audio",
            captureStatus: "missing",
            degradationReason: "capture_status=missing"
        )

        let status = recordingArtifactUserStatus(missingMicrophone)

        #expect(status == "Not captured. This source was not saved.")
        #expect(!status.contains("microphone_audio"))
        #expect(!status.contains("capture_status"))
    }

    @Test
    func historicalIncompleteStatusesUseRecoveryLanguageInsteadOfSaved() {
        let expected = [
            "created": "Recording not started",
            "recording": "Recording interrupted",
            "processing": "Transcript interrupted",
            "failed": "Needs attention",
        ]

        for (status, userStatus) in expected {
            #expect(historicalMeetingRecoveryStatus(status) == userStatus)
            #expect(meetingUserStatus(status, hasTranscript: false) == userStatus)
            #expect(meetingUserStatus(status, hasTranscript: true) == userStatus)
            #expect(!meetingUserStatus(status, hasTranscript: false).contains("Saved"))
        }

        #expect(historicalMeetingRecoveryStatus("recorded") == nil)
        #expect(historicalMeetingRecoveryStatus("transcribed") == nil)
        #expect(historicalMeetingRecoveryStatus("unexpected") == "Needs attention")
        #expect(meetingUserStatus("recorded", hasTranscript: false) == "Ready to transcribe")
        #expect(meetingUserStatus("transcribed", hasTranscript: true) == "Transcript ready")
        #expect(meetingUserStatus("unexpected", hasTranscript: false) == "Needs attention")
        #expect(meetingUserStatus("unexpected", hasTranscript: true) == "Needs attention")
    }

    private func readyArtifact(id: String, type: String) -> RecordingCommandArtifact {
        RecordingCommandArtifact(
            id: id,
            artifactType: type,
            path: "sessions/session/artifacts/\(id)",
            captureStatus: "available",
            checksum: "sha256:1111111111111111111111111111111111111111111111111111111111111111"
        )
    }

    private func notRequestedArtifact(id: String, type: String) -> RecordingCommandArtifact {
        RecordingCommandArtifact(
            id: id,
            artifactType: type,
            captureStatus: "missing",
            degradationReason: "\(type) was not requested for this native capture session."
        )
    }
}
