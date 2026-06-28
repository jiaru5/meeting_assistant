import Foundation
import Testing
@testable import MeetingAssistantNative

@Suite("Recording state machine")
struct RecordingStateMachineTests {
    @Test
    @MainActor
    func readinessFailureBlocksStart() async {
        let client = SpyRecordingCommandClient()
        let viewModel = RecordingControlViewModel(client: client)

        viewModel.updateReadiness(canStartRecording: false)
        await viewModel.start()

        #expect(viewModel.state.phase == .idle)
        #expect(viewModel.state.canStart == false)
        #expect(viewModel.state.canStop == false)
        #expect(await client.recordedStartRequests().isEmpty)
    }

    @Test
    @MainActor
    func startSuccessEntersRecording() async {
        let client = SpyRecordingCommandClient(
            startResponses: [
                RecordingCommandResponse(
                    ok: true,
                    requestID: "local-start-1",
                    command: .startNativeRecording,
                    sessionID: "session-started",
                    status: "recording",
                    captureTarget: .window,
                    warnings: ["system_audio degraded"]
                ),
            ]
        )
        let viewModel = RecordingControlViewModel(client: client)

        viewModel.updateReadiness(canStartRecording: true)
        await viewModel.start(
            title: "Design review",
            captureTarget: .window,
            captureSystemAudio: true,
            captureMicrophoneAudio: false
        )

        #expect(viewModel.state.phase == .recording)
        #expect(viewModel.state.sessionID == "session-started")
        #expect(viewModel.state.canStart == false)
        #expect(viewModel.state.canStop == true)
        #expect(viewModel.state.warnings == ["system_audio degraded"])

        let requests = await client.recordedStartRequests()
        #expect(requests.count == 1)
        #expect(requests.first?.title == "Design review")
        #expect(requests.first?.captureTarget == .window)
        #expect(requests.first?.captureSystemAudio == true)
        #expect(requests.first?.captureMicrophoneAudio == false)
    }

    @Test
    @MainActor
    func stopSuccessEntersRecorded() async {
        let client = SpyRecordingCommandClient(
            stopResponses: [
                RecordingCommandResponse(
                    ok: true,
                    requestID: "local-stop-1",
                    command: .stopRecording,
                    sessionID: "session-recording",
                    status: "recorded",
                    artifacts: [
                        RecordingCommandArtifact(
                            id: "artifact-screen-video",
                            sessionID: "session-recording",
                            artifactType: "screen_video",
                            captureStatus: "available"
                        ),
                    ],
                    warnings: ["microphone_audio unavailable"]
                ),
            ]
        )
        let viewModel = RecordingControlViewModel(
            client: client,
            initialState: .recording(sessionID: "session-recording", warnings: ["startup warning"])
        )

        await viewModel.stop()

        #expect(viewModel.state.phase == .recorded)
        #expect(viewModel.state.sessionID == "session-recording")
        #expect(viewModel.state.canStart == true)
        #expect(viewModel.state.canStop == false)
        #expect(viewModel.state.warnings == ["microphone_audio unavailable"])

        let requests = await client.recordedStopRequests()
        #expect(requests.map(\.sessionID) == ["session-recording"])
    }

    @Test
    @MainActor
    func startFailureEntersFailedWithoutRecording() async {
        let client = SpyRecordingCommandClient(
            startResponses: [
                .failed(
                    requestID: "local-start-failed",
                    command: .startNativeRecording,
                    code: "permission_denied",
                    message: "Screen recording permission is denied."
                ),
            ]
        )
        let viewModel = RecordingControlViewModel(client: client)

        viewModel.updateReadiness(canStartRecording: true)
        await viewModel.start()

        #expect(viewModel.state.phase == .failed)
        #expect(viewModel.state.sessionID == nil)
        #expect(viewModel.state.errorCode == .permissionDenied)
        #expect(viewModel.state.errorMessage == "Screen recording permission is denied.")
        #expect(viewModel.state.canStop == false)
    }

    @Test
    @MainActor
    func stopFailureDoesNotEnterRecorded() async {
        let client = SpyRecordingCommandClient(
            stopResponses: [
                .failed(
                    requestID: "local-stop-failed",
                    command: .stopRecording,
                    code: "capture_failed",
                    message: "Recording could not be saved."
                ),
            ]
        )
        let viewModel = RecordingControlViewModel(
            client: client,
            initialState: .recording(sessionID: "session-recording", warnings: [])
        )

        await viewModel.stop()

        #expect(viewModel.state.phase == .failed)
        #expect(viewModel.state.sessionID == "session-recording")
        #expect(viewModel.state.errorCode == .captureFailed)
        #expect(viewModel.state.errorMessage == "Recording could not be saved.")
        #expect(viewModel.state.canStop == false)
    }

    @Test
    @MainActor
    func repeatedActionsDoNotCreateIllegalStateTransitions() async {
        let client = SpyRecordingCommandClient()
        let recordingViewModel = RecordingControlViewModel(
            client: client,
            initialState: .recording(sessionID: "session-active", warnings: [])
        )

        await recordingViewModel.start()

        #expect(recordingViewModel.state.phase == .recording)
        #expect(recordingViewModel.state.sessionID == "session-active")
        #expect(await client.recordedStartRequests().isEmpty)

        let recordedViewModel = RecordingControlViewModel(
            client: client,
            initialState: .recorded(sessionID: "session-saved", warnings: [])
        )

        await recordedViewModel.stop()

        #expect(recordedViewModel.state.phase == .recorded)
        #expect(recordedViewModel.state.sessionID == "session-saved")
        #expect(await client.recordedStopRequests().isEmpty)
    }

    @Test
    func exposesStableAccessibilityIdentifiersForRecordingSurface() {
        #expect(RecordingAccessibilityID.status == "ma.recording.status")
        #expect(RecordingAccessibilityID.startButton == "ma.recording.startButton")
        #expect(RecordingAccessibilityID.stopButton == "ma.recording.stopButton")
        #expect(RecordingAccessibilityID.error == "ma.recording.error")
        #expect(RecordingAccessibilityID.savedSummary == "ma.recording.savedSummary")
    }
}

private actor SpyRecordingCommandClient: RecordingCommandClient {
    private var startResponses: [RecordingCommandResponse]
    private var stopResponses: [RecordingCommandResponse]
    private var startRequests: [StartNativeRecordingRequest] = []
    private var stopRequests: [StopRecordingRequest] = []

    init(
        startResponses: [RecordingCommandResponse] = [],
        stopResponses: [RecordingCommandResponse] = []
    ) {
        self.startResponses = startResponses
        self.stopResponses = stopResponses
    }

    func startNativeRecording(_ request: StartNativeRecordingRequest) async throws -> RecordingCommandResponse {
        startRequests.append(request)
        guard !startResponses.isEmpty else {
            throw SpyRecordingCommandClientError.missingStartResponse
        }
        return startResponses.removeFirst()
    }

    func stopRecording(_ request: StopRecordingRequest) async throws -> RecordingCommandResponse {
        stopRequests.append(request)
        guard !stopResponses.isEmpty else {
            throw SpyRecordingCommandClientError.missingStopResponse
        }
        return stopResponses.removeFirst()
    }

    func recordedStartRequests() -> [StartNativeRecordingRequest] {
        startRequests
    }

    func recordedStopRequests() -> [StopRecordingRequest] {
        stopRequests
    }
}

private enum SpyRecordingCommandClientError: Error {
    case missingStartResponse
    case missingStopResponse
}
