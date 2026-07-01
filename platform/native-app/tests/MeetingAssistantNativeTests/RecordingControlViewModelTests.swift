import Foundation
import Testing
@testable import MeetingAssistantNative

@Suite("Recording control")
struct RecordingControlViewModelTests {
    @Test
    @MainActor
    func readinessFailureDoesNotStartRecording() async {
        let client = FakeRecordingCommandClient()
        let viewModel = RecordingControlViewModel(
            commandClient: client,
            readinessState: blockedReadinessState()
        )

        await viewModel.start()

        #expect(viewModel.state.phase == .idle)
        #expect(viewModel.state.canStart == false)
        #expect(await client.startRequests.isEmpty)
    }

    @Test
    @MainActor
    func startSuccessMovesIntoRecording() async {
        let client = FakeRecordingCommandClient(sessionID: "session-start-success")
        let viewModel = RecordingControlViewModel(
            commandClient: client,
            readinessState: readyReadinessState(),
            title: "Design Review",
            captureTarget: .window
        )

        await viewModel.start()

        #expect(viewModel.state.phase == .recording)
        #expect(viewModel.state.sessionID == "session-start-success")
        #expect(viewModel.state.statusText == "Recording in progress.")
        let requests = await client.startRequests
        #expect(requests.count == 1)
        #expect(requests.first?.title == "Design Review")
        #expect(requests.first?.captureTarget == .window)
        #expect(requests.first?.captureSystemAudio == true)
        #expect(requests.first?.captureMicrophoneAudio == true)
    }

    @Test
    @MainActor
    func stopSuccessMovesIntoRecorded() async {
        let client = FakeRecordingCommandClient(sessionID: "session-stop-success")
        let viewModel = RecordingControlViewModel(
            commandClient: client,
            readinessState: readyReadinessState()
        )

        await viewModel.start()
        await viewModel.stop()

        #expect(viewModel.state.phase == .recorded)
        #expect(viewModel.state.sessionID == "session-stop-success")
        #expect(viewModel.state.savedSummary == "Saved 2 recording artifacts.")
        #expect(viewModel.state.artifacts.map(\.artifactType) == ["screen_video", "mixed_audio"])
        let requests = await client.stopRequests
        #expect(requests == [StopRecordingRequest(sessionID: "session-stop-success")])
    }

    @Test
    @MainActor
    func startFailureMovesIntoFailed() async {
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

        await viewModel.start()

        #expect(viewModel.state.phase == .failed)
        #expect(viewModel.state.sessionID == nil)
        #expect(viewModel.state.errorCode == .permissionDenied)
        #expect(viewModel.state.errorMessage == "Screen Recording permission is missing.")
        #expect(await client.startRequests.count == 1)
    }

    @Test
    @MainActor
    func stopFailureMovesIntoFailedAndKeepsSession() async {
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

        await viewModel.start()
        await viewModel.stop()

        #expect(viewModel.state.phase == .failed)
        #expect(viewModel.state.sessionID == "session-stop-failure")
        #expect(viewModel.state.errorCode == .captureFailed)
        #expect(viewModel.state.errorMessage == "Recording could not be saved.")
        #expect(await client.stopRequests.count == 1)
    }

    @Test
    @MainActor
    func repeatedTriggersDoNotCreateIllegalTransitions() async {
        let client = FakeRecordingCommandClient(sessionID: "session-repeat")
        let viewModel = RecordingControlViewModel(
            commandClient: client,
            readinessState: readyReadinessState()
        )

        await viewModel.start()
        await viewModel.start()
        await viewModel.stop()
        await viewModel.stop()

        #expect(viewModel.state.phase == .recorded)
        #expect(await client.startRequests.count == 1)
        #expect(await client.stopRequests.count == 1)
    }

    @Test
    @MainActor
    func readinessUpdatesOnlyAffectIdleOrReadyStates() async {
        let client = FakeRecordingCommandClient()
        let viewModel = RecordingControlViewModel(
            commandClient: client,
            readinessState: blockedReadinessState()
        )

        viewModel.updateReadiness(readyReadinessState())
        #expect(viewModel.state.phase == .ready)

        await viewModel.start()
        viewModel.updateReadiness(blockedReadinessState())

        #expect(viewModel.state.phase == .recording)
        #expect(viewModel.state.canStop == true)
        #expect(viewModel.canStart == false)
    }

    @Test
    @MainActor
    func recordedStateDoesNotExposeStartWhenReadinessIsRevoked() async {
        let client = FakeRecordingCommandClient(sessionID: "session-readiness-revoked")
        let viewModel = RecordingControlViewModel(
            commandClient: client,
            readinessState: readyReadinessState()
        )

        await viewModel.start()
        await viewModel.stop()
        viewModel.updateReadiness(blockedReadinessState())
        await viewModel.start()

        #expect(viewModel.state.phase == .recorded)
        #expect(viewModel.state.canStart == true)
        #expect(viewModel.canStart == false)
        #expect(await client.startRequests.count == 1)
    }

    @Test
    func exposesStableRecordingAccessibilityIdentifiers() {
        #expect(RecordingAccessibilityID.status == "ma.recording.status")
        #expect(RecordingAccessibilityID.startButton == "ma.recording.startButton")
        #expect(RecordingAccessibilityID.stopButton == "ma.recording.stopButton")
        #expect(RecordingAccessibilityID.error == "ma.recording.error")
        #expect(RecordingAccessibilityID.savedSummary == "ma.recording.savedSummary")
        #expect(
            RecordingAccessibilityID.artifactStatus("screen_video")
                == "ma.recording.artifact.screen_video.status"
        )
        #expect(
            RecordingAccessibilityID.artifactDegradation("mixed_audio")
                == "ma.recording.artifact.mixed_audio.degradation"
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
                dependencyCheck("media_tool.ffmpeg", status: "available", required: true, ok: true),
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
