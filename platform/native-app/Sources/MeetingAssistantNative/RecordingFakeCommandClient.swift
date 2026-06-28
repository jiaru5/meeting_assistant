import Foundation

public actor FakeRecordingCommandClient: RecordingCommandClient {
    public enum Script: Equatable, Sendable {
        case success
        case startFailure(code: String, message: String)
        case stopFailure(code: String, message: String)
    }

    public private(set) var startRequests: [StartNativeRecordingRequest] = []
    public private(set) var stopRequests: [StopRecordingRequest] = []

    private let script: Script
    private let sessionID: String

    public init(
        script: Script = .success,
        sessionID: String = "session-fake-recording"
    ) {
        self.script = script
        self.sessionID = sessionID
    }

    public func startNativeRecording(
        _ request: StartNativeRecordingRequest
    ) async throws -> RecordingCommandResponse {
        startRequests.append(request)

        if case .startFailure(let code, let message) = script {
            return .failed(
                command: .startNativeRecording,
                code: code,
                message: message
            )
        }

        return .successfulStart(
            sessionID: sessionID,
            captureTarget: request.captureTarget ?? .screen
        )
    }

    public func stopRecording(
        _ request: StopRecordingRequest
    ) async throws -> RecordingCommandResponse {
        stopRequests.append(request)

        if case .stopFailure(let code, let message) = script {
            return .failed(
                command: .stopRecording,
                code: code,
                message: message
            )
        }

        return .successfulStop(sessionID: request.sessionID)
    }
}
