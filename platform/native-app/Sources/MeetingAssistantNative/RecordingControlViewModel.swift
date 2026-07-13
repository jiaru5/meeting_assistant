import Foundation
import SwiftUI

public enum RecordingControlPhase: String, Equatable, Sendable {
    case idle
    case ready
    case starting
    case recording
    case stopping
    case recorded
    case failed
}

public enum RecordingReadiness: Equatable, Sendable {
    case notReady
    case ready
}

public typealias RecordingCaptureControlling = RecordingCommandClient
public typealias RecordingStartRequest = StartNativeRecordingRequest
public typealias RecordingStopRequest = StopRecordingRequest

public struct RecordingControlState: Equatable, Sendable {
    public let phase: RecordingControlPhase
    public let statusText: String
    public let sessionID: String?
    public let artifacts: [RecordingCommandArtifact]
    public let errorCode: RecordingCommandErrorCode?
    public let errorMessage: String?
    public let savedSummary: String?
    public let technicalDetails: [String]
    public let warnings: [String]

    public var canStart: Bool {
        phase == .ready
            || phase == .recorded
            || (phase == .failed && sessionID == nil)
    }

    public var canStop: Bool {
        phase == .recording
            || (phase == .failed && sessionID != nil)
    }

    public static let idle = RecordingControlState(
        phase: .idle,
        statusText: "Run readiness checks before recording.",
        sessionID: nil,
        artifacts: [],
        errorCode: nil,
        errorMessage: nil,
        savedSummary: nil,
        technicalDetails: [],
        warnings: []
    )

    public static let ready = RecordingControlState(
        phase: .ready,
        statusText: "Ready to start recording.",
        sessionID: nil,
        artifacts: [],
        errorCode: nil,
        errorMessage: nil,
        savedSummary: nil,
        technicalDetails: [],
        warnings: []
    )

    public static func recording(
        sessionID: String,
        warnings: [String] = []
    ) -> RecordingControlState {
        RecordingControlState(
            phase: .recording,
            statusText: "Recording in progress.",
            sessionID: sessionID,
            artifacts: [],
            errorCode: nil,
            errorMessage: nil,
            savedSummary: nil,
            technicalDetails: [],
            warnings: warnings
        )
    }

    public static func recorded(
        sessionID: String,
        artifacts: [RecordingCommandArtifact] = [],
        warnings: [String] = []
    ) -> RecordingControlState {
        RecordingControlState(
            phase: .recorded,
            statusText: "Recording saved.",
            sessionID: sessionID,
            artifacts: artifacts,
            errorCode: nil,
            errorMessage: nil,
            savedSummary: Self.savedSummary(for: artifacts),
            technicalDetails: [],
            warnings: warnings
        )
    }

    public static func savedSummary(for artifacts: [RecordingCommandArtifact]) -> String {
        let artifactCount = artifacts.filter { $0.captureStatus == "available" }.count
        return artifactCount == 1
            ? "Saved 1 recording artifact."
            : "Saved \(artifactCount) recording artifacts."
    }
}

@MainActor
public final class RecordingControlViewModel: ObservableObject {
    @Published public private(set) var state: RecordingControlState
    @Published private var startCommandIsPending = false

    public var canStart: Bool {
        canStartRecording && state.canStart && !startCommandIsPending
    }

    public var canStop: Bool {
        state.canStop
    }

    private let commandClient: any RecordingCaptureControlling
    private var canStartRecording: Bool
    private let title: String?
    private let captureTarget: RecordingCaptureTarget
    private let workspaceURL: URL?
    private let captureSystemAudio: Bool
    private let captureMicrophoneAudio: Bool
    private let permissionRepairIdentity: LocalAppPermissionIdentity
    private let startTimeoutNanoseconds: UInt64
    private let stopTimeoutNanoseconds: UInt64
    private var activeStartAttemptID: UUID?
    private var pendingStartCommandAttemptID: UUID?
    private var startCommandTask: Task<RecordingCommandResponse, Error>?
    private var startTimeoutTask: Task<Void, Never>?
    private var activeStopAttemptID: UUID?
    private var stopTimeoutTask: Task<Void, Never>?

    public init(
        commandClient: any RecordingCaptureControlling = FakeRecordingCommandClient(),
        readinessState: PermissionDependencyStatusState = .idle,
        title: String? = nil,
        captureTarget: RecordingCaptureTarget = .screen,
        workspaceURL: URL? = nil,
        captureSystemAudio: Bool = true,
        captureMicrophoneAudio: Bool = true,
        permissionRepairIdentity: LocalAppPermissionIdentity = .current(),
        startTimeoutNanoseconds: UInt64 = 15_000_000_000,
        stopTimeoutNanoseconds: UInt64 = 90_000_000_000
    ) {
        self.commandClient = commandClient
        self.canStartRecording = readinessState.canStartRecording
        self.title = title
        self.captureTarget = captureTarget
        self.workspaceURL = workspaceURL
        self.captureSystemAudio = captureSystemAudio
        self.captureMicrophoneAudio = captureMicrophoneAudio
        self.permissionRepairIdentity = permissionRepairIdentity
        self.startTimeoutNanoseconds = startTimeoutNanoseconds
        self.stopTimeoutNanoseconds = stopTimeoutNanoseconds
        self.state = readinessState.canStartRecording ? .ready : .idle
    }

    public convenience init(
        client: any RecordingCaptureControlling,
        initialState: RecordingControlState = .idle
    ) {
        self.init(commandClient: client, readinessState: .idle)
        self.canStartRecording = initialState.phase != .idle
        self.state = initialState
    }

    public func updateReadiness(_ readiness: RecordingReadiness) {
        updateReadiness(canStartRecording: readiness == .ready)
    }

    public func updateReadiness(canStartRecording: Bool) {
        self.canStartRecording = canStartRecording
        guard state.phase == .idle || state.phase == .ready else {
            return
        }
        state = canStartRecording ? .ready : .idle
    }

    public func updateReadiness(_ readinessState: PermissionDependencyStatusState) {
        updateReadiness(canStartRecording: readinessState.canStartRecording)
    }

    public func resetForNewTask() {
        activeStartAttemptID = nil
        startCommandTask?.cancel()
        startTimeoutTask?.cancel()
        startTimeoutTask = nil
        activeStopAttemptID = nil
        stopTimeoutTask?.cancel()
        stopTimeoutTask = nil
        state = canStartRecording ? .ready : .idle
    }

    public func start() async {
        await start(
            title: title,
            captureTarget: captureTarget,
            captureSystemAudio: captureSystemAudio,
            captureMicrophoneAudio: captureMicrophoneAudio
        )
    }

    public func start(
        title: String? = nil,
        captureTarget: RecordingCaptureTarget = .screen,
        workspaceURL: URL? = nil,
        captureSystemAudio: Bool = true,
        captureMicrophoneAudio: Bool = true
    ) async {
        guard canStart else {
            if state.phase == .ready && !canStartRecording {
                state = .idle
            }
            return
        }

        state = RecordingControlState(
            phase: .starting,
            statusText: "Starting recording...",
            sessionID: nil,
            artifacts: [],
            errorCode: nil,
            errorMessage: nil,
            savedSummary: nil,
            technicalDetails: [],
            warnings: []
        )
        let attemptID = UUID()
        activeStartAttemptID = attemptID
        pendingStartCommandAttemptID = attemptID
        startCommandIsPending = true
        armStartTimeout(for: attemptID)
        defer {
            clearStartAttemptIfCurrent(attemptID)
            finishStartCommandIfCurrent(attemptID)
        }

        do {
            let request = StartNativeRecordingRequest(
                title: title,
                captureTarget: captureTarget,
                workspaceURL: workspaceURL ?? self.workspaceURL,
                captureSystemAudio: captureSystemAudio,
                captureMicrophoneAudio: captureMicrophoneAudio
            )
            let client = commandClient
            let commandTask = Task {
                try await client.startNativeRecording(request)
            }
            startCommandTask = commandTask
            let response = try await commandTask.value
            guard activeStartAttemptID == attemptID else {
                await stopLateRecordingIfNeeded(response)
                return
            }
            try handleStartResponse(response)
        } catch let failure as RecordingCommandFailure {
            guard activeStartAttemptID == attemptID else {
                return
            }
            fail(
                code: failure.code,
                message: visibleFailureMessage(for: failure),
                sessionID: nil,
                technicalDetails: technicalFailureDetails(for: failure)
            )
        } catch {
            guard activeStartAttemptID == attemptID else {
                return
            }
            fail(
                code: nil,
                message: error.localizedDescription.processingSafeDisplayText(
                    fallback: "Recording could not start."
                ),
                sessionID: nil
            )
        }
    }

    public func stop() async {
        guard state.canStop, let sessionID = state.sessionID else {
            return
        }

        state = RecordingControlState(
            phase: .stopping,
            statusText: "Stopping and saving recording...",
            sessionID: sessionID,
            artifacts: [],
            errorCode: nil,
            errorMessage: nil,
            savedSummary: nil,
            technicalDetails: [],
            warnings: []
        )

        let attemptID = UUID()
        activeStopAttemptID = attemptID
        armStopTimeout(for: attemptID, sessionID: sessionID)
        defer {
            clearStopAttemptIfCurrent(attemptID)
        }

        do {
            let response = try await commandClient.stopRecording(
                StopRecordingRequest(sessionID: sessionID)
            )
            guard activeStopAttemptID == attemptID else {
                handleLateStopResponseIfUseful(response, sessionID: sessionID)
                return
            }
            try handleStopResponse(response, existingSessionID: sessionID)
        } catch let failure as RecordingCommandFailure {
            guard activeStopAttemptID == attemptID else {
                return
            }
            fail(
                code: failure.code,
                message: visibleFailureMessage(for: failure),
                sessionID: sessionID,
                technicalDetails: technicalFailureDetails(for: failure)
            )
        } catch {
            guard activeStopAttemptID == attemptID else {
                return
            }
            fail(
                code: nil,
                message: error.localizedDescription.processingSafeDisplayText(
                    fallback: "Recording could not be saved."
                ),
                sessionID: sessionID
            )
        }
    }

    private func handleStartResponse(_ response: RecordingCommandResponse) throws {
        guard response.ok else {
            throw RecordingCommandFailure(response: response)
        }
        guard response.command == .startNativeRecording,
              response.status == "recording",
              let sessionID = response.sessionID
        else {
            throw RecordingCommandFailure(
                command: .startNativeRecording,
                code: .internalError,
                message: "start_native_recording returned an incomplete response."
            )
        }

        state = RecordingControlState(
            phase: .recording,
            statusText: "Recording in progress.",
            sessionID: sessionID,
            artifacts: [],
            errorCode: nil,
            errorMessage: nil,
            savedSummary: nil,
            technicalDetails: [],
            warnings: response.warnings
        )
    }

    private func handleStopResponse(
        _ response: RecordingCommandResponse,
        existingSessionID: String
    ) throws {
        guard response.ok else {
            throw RecordingCommandFailure(response: response)
        }
        guard response.command == .stopRecording,
              response.status == "recorded",
              response.sessionID == existingSessionID
        else {
            throw RecordingCommandFailure(
                command: .stopRecording,
                code: .internalError,
                message: "stop_recording returned an incomplete response."
            )
        }

        state = RecordingControlState(
            phase: .recorded,
            statusText: "Recording saved.",
            sessionID: existingSessionID,
            artifacts: response.artifacts,
            errorCode: nil,
            errorMessage: nil,
            savedSummary: RecordingControlState.savedSummary(for: response.artifacts),
            technicalDetails: [],
            warnings: response.warnings
        )
    }

    private func fail(
        code: RecordingCommandErrorCode?,
        message: String,
        sessionID: String?,
        technicalDetails: [String] = []
    ) {
        state = RecordingControlState(
            phase: .failed,
            statusText: "Recording failed.",
            sessionID: sessionID,
            artifacts: [],
            errorCode: code,
            errorMessage: message,
            savedSummary: nil,
            technicalDetails: technicalDetails,
            warnings: []
        )
    }

    private func visibleFailureMessage(for failure: RecordingCommandFailure) -> String {
        let safeMessage = failure.message.processingSafeDisplayText(
            fallback: failure.command == .startNativeRecording
                ? "Recording could not start."
                : "Recording could not be saved."
        )
        guard failure.code == .permissionDenied else {
            return safeMessage
        }
        let repairHint = "Open System Settings > Privacy & Security and grant the missing Screen Recording / Screen & System Audio Recording or Microphone permission, then relaunch and retry."
        return [safeMessage, repairHint].joined(separator: " ")
    }

    private func technicalFailureDetails(for failure: RecordingCommandFailure) -> [String] {
        var details = failure.details.map {
            $0.processingSafeDisplayText(fallback: "<redacted>")
        }
        if failure.code == .permissionDenied {
            details.append(permissionRepairIdentity.recordingPermissionFailureHint)
        }
        return details
    }

    private func armStartTimeout(for attemptID: UUID) {
        startTimeoutTask?.cancel()
        let timeout = startTimeoutNanoseconds
        startTimeoutTask = Task { [weak self] in
            do {
                try await Task.sleep(nanoseconds: timeout)
            } catch {
                return
            }
            self?.failStartIfStillPending(attemptID)
        }
    }

    private func clearStartAttemptIfCurrent(_ attemptID: UUID) {
        guard activeStartAttemptID == attemptID else {
            return
        }
        activeStartAttemptID = nil
        startTimeoutTask?.cancel()
        startTimeoutTask = nil
    }

    private func failStartIfStillPending(_ attemptID: UUID) {
        guard activeStartAttemptID == attemptID, state.phase == .starting else {
            return
        }
        activeStartAttemptID = nil
        startTimeoutTask = nil
        startCommandTask?.cancel()
        fail(
            code: .captureFailed,
            message: "Native recording did not start before timeout. The pending start was cancelled; wait for any macOS permission prompt to close before trying again.",
            sessionID: nil
        )
    }

    private func finishStartCommandIfCurrent(_ attemptID: UUID) {
        guard pendingStartCommandAttemptID == attemptID else {
            return
        }
        pendingStartCommandAttemptID = nil
        startCommandTask = nil
        startCommandIsPending = false
    }

    private func stopLateRecordingIfNeeded(_ response: RecordingCommandResponse) async {
        guard response.ok,
              response.command == .startNativeRecording,
              response.status == "recording",
              let sessionID = response.sessionID else {
            return
        }

        // A native start may finish after the UI timeout or after the user has
        // moved to another task. Never surface that stale session, but stop it
        // best-effort so the app cannot leave an invisible recording running.
        _ = try? await commandClient.stopRecording(
            StopRecordingRequest(sessionID: sessionID)
        )
    }

    private func armStopTimeout(for attemptID: UUID, sessionID: String) {
        stopTimeoutTask?.cancel()
        let timeout = stopTimeoutNanoseconds
        stopTimeoutTask = Task { [weak self] in
            do {
                try await Task.sleep(nanoseconds: timeout)
            } catch {
                return
            }
            self?.failStopIfStillPending(attemptID, sessionID: sessionID)
        }
    }

    private func clearStopAttemptIfCurrent(_ attemptID: UUID) {
        guard activeStopAttemptID == attemptID else {
            return
        }
        activeStopAttemptID = nil
        stopTimeoutTask?.cancel()
        stopTimeoutTask = nil
    }

    private func failStopIfStillPending(_ attemptID: UUID, sessionID: String) {
        guard activeStopAttemptID == attemptID,
              state.phase == .stopping,
              state.sessionID == sessionID else {
            return
        }
        activeStopAttemptID = nil
        stopTimeoutTask = nil
        fail(
            code: .captureFailed,
            message: "Saving did not finish before timeout. The current recording session is still selected; try saving again.",
            sessionID: sessionID
        )
    }

    private func handleLateStopResponseIfUseful(
        _ response: RecordingCommandResponse,
        sessionID: String
    ) {
        guard activeStopAttemptID == nil,
              state.phase == .failed,
              state.sessionID == sessionID else {
            return
        }
        try? handleStopResponse(response, existingSessionID: sessionID)
    }
}
