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
            readinessState: readyReadinessState(),
            permissionRepairIdentity: installedAppIdentity()
        )

        await viewModel.start()

        #expect(viewModel.state.phase == .failed)
        #expect(viewModel.state.sessionID == nil)
        #expect(viewModel.state.errorCode == .permissionDenied)
        #expect(viewModel.state.errorMessage?.contains("Screen Recording permission is missing.") == true)
        #expect(viewModel.state.errorMessage?.contains("System Settings > Privacy & Security") == true)
        #expect(await client.startRequests.count == 1)
    }

    @Test
    @MainActor
    func permissionFailureShowsDetailsAndRepairHint() async {
        let client = PermissionDeniedRecordingCommandClient(
            details: ["Screen Recording permission is denied."]
        )
        let viewModel = RecordingControlViewModel(
            commandClient: client,
            readinessState: readyReadinessState(),
            permissionRepairIdentity: installedAppIdentity()
        )

        await viewModel.start()

        #expect(viewModel.state.phase == .failed)
        #expect(viewModel.state.errorCode == .permissionDenied)
        #expect(viewModel.state.errorMessage?.contains("Native capture permissions are denied or unknown.") == true)
        #expect(viewModel.state.errorMessage?.contains("Screen Recording permission is denied.") == true)
        #expect(viewModel.state.errorMessage?.contains("System Settings > Privacy & Security") == true)
        #expect(viewModel.state.errorMessage?.contains("/Users/jerry/Applications/MeetingAssistantNativeLocal.app") == true)
        #expect(viewModel.state.errorMessage?.contains("local.meeting-assistant.native.localdirect") == true)
        #expect(viewModel.state.errorMessage?.contains("designated requirement: identifier") == true)
        #expect(viewModel.state.errorMessage?.contains("Meeting Assistant Local Code Signing") == true)
        #expect(viewModel.state.errorMessage?.contains("ca3e033b67f6b4b8cabb9245cc9c7d9f0b7290db") == true)
        #expect(viewModel.state.errorMessage?.contains("remove stale ad-hoc") == true)
    }

    @Test
    @MainActor
    func startTimeoutMovesIntoFailedWhenCommandDoesNotReturn() async {
        let client = HangingRecordingCommandClient()
        let viewModel = RecordingControlViewModel(
            commandClient: client,
            readinessState: readyReadinessState(),
            startTimeoutNanoseconds: 20_000_000
        )

        let startTask = Task {
            await viewModel.start()
        }

        #expect(await waitForRecordingPhase(.failed, in: viewModel))
        #expect(viewModel.state.phase == .failed)
        #expect(viewModel.state.statusText == "Recording failed.")
        #expect(viewModel.state.errorCode == .captureFailed)
        #expect(viewModel.state.errorMessage?.contains("did not start before timeout") == true)
        #expect(await client.startRequests.count == 1)

        startTask.cancel()
        _ = await startTask.result
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

private func installedAppIdentity() -> LocalAppPermissionIdentity {
    LocalAppPermissionIdentity(
        bundlePath: "/Users/jerry/Applications/MeetingAssistantNativeLocal.app",
        bundleIdentifier: "local.meeting-assistant.native.localdirect",
        codeSignatureHash: "ca3e033b67f6b4b8cabb9245cc9c7d9f0b7290db",
        designatedRequirement: "identifier \"local.meeting-assistant.native.localdirect\" and certificate root = H\"d2ebc4b501da40173af71fd03a33c9581d13b5dd\"",
        signingAuthority: "Meeting Assistant Local Code Signing"
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

@MainActor
private func waitForRecordingPhase(
    _ phase: RecordingControlPhase,
    in viewModel: RecordingControlViewModel,
    attempts: Int = 100,
    intervalNanoseconds: UInt64 = 10_000_000
) async -> Bool {
    for _ in 0..<attempts {
        if viewModel.state.phase == phase {
            return true
        }
        try? await Task.sleep(nanoseconds: intervalNanoseconds)
    }
    return viewModel.state.phase == phase
}

private actor HangingRecordingCommandClient: RecordingCommandClient {
    private(set) var startRequests: [StartNativeRecordingRequest] = []

    func startNativeRecording(_ request: StartNativeRecordingRequest) async throws -> RecordingCommandResponse {
        startRequests.append(request)
        try await Task.sleep(nanoseconds: 10_000_000_000)
        return .successfulStart(sessionID: "session-hanging-recording")
    }

    func stopRecording(_ request: StopRecordingRequest) async throws -> RecordingCommandResponse {
        .successfulStop(sessionID: request.sessionID)
    }
}

private actor PermissionDeniedRecordingCommandClient: RecordingCommandClient {
    private let details: [String]

    init(details: [String]) {
        self.details = details
    }

    func startNativeRecording(_ request: StartNativeRecordingRequest) async throws -> RecordingCommandResponse {
        .failure(
            command: .startNativeRecording,
            code: .permissionDenied,
            message: "Native capture permissions are denied or unknown.",
            details: details
        )
    }

    func stopRecording(_ request: StopRecordingRequest) async throws -> RecordingCommandResponse {
        .failure(
            command: .stopRecording,
            sessionID: request.sessionID,
            code: .permissionDenied,
            message: "Native capture permissions are denied or unknown.",
            details: details
        )
    }
}
