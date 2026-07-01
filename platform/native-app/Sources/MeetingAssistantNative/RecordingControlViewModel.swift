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
    public let warnings: [String]

    public var canStart: Bool {
        phase == .ready || phase == .recorded
    }

    public var canStop: Bool {
        phase == .recording
    }

    public static let idle = RecordingControlState(
        phase: .idle,
        statusText: "Run readiness checks before recording.",
        sessionID: nil,
        artifacts: [],
        errorCode: nil,
        errorMessage: nil,
        savedSummary: nil,
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

    public var canStart: Bool {
        canStartRecording && state.canStart
    }

    public var canStop: Bool {
        state.canStop
    }

    private let commandClient: any RecordingCaptureControlling
    private var canStartRecording: Bool
    private let title: String?
    private let captureTarget: RecordingCaptureTarget
    private let workspaceURL: URL?

    public init(
        commandClient: any RecordingCaptureControlling = FakeRecordingCommandClient(),
        readinessState: PermissionDependencyStatusState = .idle,
        title: String? = nil,
        captureTarget: RecordingCaptureTarget = .screen,
        workspaceURL: URL? = nil
    ) {
        self.commandClient = commandClient
        self.canStartRecording = readinessState.canStartRecording
        self.title = title
        self.captureTarget = captureTarget
        self.workspaceURL = workspaceURL
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

    public func start() async {
        await start(
            title: title,
            captureTarget: captureTarget,
            captureSystemAudio: true,
            captureMicrophoneAudio: true
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
            warnings: []
        )

        do {
            let response = try await commandClient.startNativeRecording(
                StartNativeRecordingRequest(
                    title: title,
                    captureTarget: captureTarget,
                    workspaceURL: workspaceURL ?? self.workspaceURL,
                    captureSystemAudio: captureSystemAudio,
                    captureMicrophoneAudio: captureMicrophoneAudio
                )
            )
            try handleStartResponse(response)
        } catch let failure as RecordingCommandFailure {
            fail(code: failure.code, message: failure.message, sessionID: nil)
        } catch {
            fail(code: nil, message: error.localizedDescription, sessionID: nil)
        }
    }

    public func stop() async {
        guard state.phase == .recording, let sessionID = state.sessionID else {
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
            warnings: []
        )

        do {
            let response = try await commandClient.stopRecording(
                StopRecordingRequest(sessionID: sessionID)
            )
            try handleStopResponse(response, existingSessionID: sessionID)
        } catch let failure as RecordingCommandFailure {
            fail(code: failure.code, message: failure.message, sessionID: sessionID)
        } catch {
            fail(code: nil, message: error.localizedDescription, sessionID: sessionID)
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
            warnings: response.warnings
        )
    }

    private func fail(code: RecordingCommandErrorCode?, message: String, sessionID: String?) {
        state = RecordingControlState(
            phase: .failed,
            statusText: "Recording failed.",
            sessionID: sessionID,
            artifacts: [],
            errorCode: code,
            errorMessage: message,
            savedSummary: nil,
            warnings: []
        )
    }
}
