import Foundation

public enum RecordingCommandName: String, Equatable, Sendable {
    case startNativeRecording = "start_native_recording"
    case stopRecording = "stop_recording"
}

public enum RecordingCaptureTarget: String, Equatable, Sendable {
    case screen
    case window
    case area
}

public struct RecordingCommandErrorCode: RawRepresentable, Equatable, Sendable, ExpressibleByStringLiteral {
    public let rawValue: String

    public init(rawValue: String) {
        self.rawValue = rawValue
    }

    public init(stringLiteral value: StringLiteralType) {
        self.rawValue = value
    }

    public static let permissionDenied = RecordingCommandErrorCode(rawValue: "permission_denied")
    public static let dependencyMissing = RecordingCommandErrorCode(rawValue: "dependency_missing")
    public static let invalidInput = RecordingCommandErrorCode(rawValue: "invalid_input")
    public static let captureFailed = RecordingCommandErrorCode(rawValue: "capture_failed")
    public static let pathConflict = RecordingCommandErrorCode(rawValue: "path_conflict")
    public static let notFound = RecordingCommandErrorCode(rawValue: "not_found")
    public static let internalError = RecordingCommandErrorCode(rawValue: "internal_error")
}

public struct StartNativeRecordingRequest: Equatable, Sendable {
    public let title: String?
    public let captureTarget: RecordingCaptureTarget?
    public let workspaceURL: URL?
    public let captureSystemAudio: Bool
    public let captureMicrophoneAudio: Bool

    public init(
        title: String? = nil,
        captureTarget: RecordingCaptureTarget? = .screen,
        workspaceURL: URL? = nil,
        captureSystemAudio: Bool = true,
        captureMicrophoneAudio: Bool = true
    ) {
        self.title = title
        self.captureTarget = captureTarget
        self.workspaceURL = workspaceURL
        self.captureSystemAudio = captureSystemAudio
        self.captureMicrophoneAudio = captureMicrophoneAudio
    }
}

public struct StopRecordingRequest: Equatable, Sendable {
    public let sessionID: String

    public init(sessionID: String) {
        self.sessionID = sessionID
    }
}

public struct RecordingCommandArtifact: Equatable, Identifiable, Sendable {
    public let id: String
    public let sessionID: String
    public let artifactType: String
    public let format: String?
    public let path: String?
    public let captureStatus: String
    public let degradationReason: String?
    public let createdAt: String?
    public let checksum: String?

    public init(
        id: String,
        sessionID: String = "",
        artifactType: String,
        format: String? = nil,
        path: String? = nil,
        captureStatus: String = "available",
        degradationReason: String? = nil,
        createdAt: String? = nil,
        checksum: String? = nil
    ) {
        self.id = id
        self.sessionID = sessionID
        self.artifactType = artifactType
        self.format = format
        self.path = path
        self.captureStatus = captureStatus
        self.degradationReason = degradationReason
        self.createdAt = createdAt
        self.checksum = checksum
    }
}

public struct RecordingCommandResponse: Equatable, Sendable {
    public let ok: Bool
    public let requestID: String
    public let command: RecordingCommandName
    public let sessionID: String?
    public let status: String?
    public let captureTarget: RecordingCaptureTarget?
    public let artifacts: [RecordingCommandArtifact]
    public let warnings: [String]
    public let code: RecordingCommandErrorCode?
    public let message: String?
    public let details: [String]

    public init(
        ok: Bool,
        requestID: String,
        command: RecordingCommandName,
        sessionID: String? = nil,
        status: String? = nil,
        captureTarget: RecordingCaptureTarget? = nil,
        artifacts: [RecordingCommandArtifact] = [],
        warnings: [String] = [],
        code: RecordingCommandErrorCode? = nil,
        message: String? = nil,
        details: [String] = []
    ) {
        self.ok = ok
        self.requestID = requestID
        self.command = command
        self.sessionID = sessionID
        self.status = status
        self.captureTarget = captureTarget
        self.artifacts = artifacts
        self.warnings = warnings
        self.code = code
        self.message = message
        self.details = details
    }

    public static func successfulStart(
        requestID: String = "local-fake-start",
        sessionID: String = "session-fake-recording",
        captureTarget: RecordingCaptureTarget = .screen,
        warnings: [String] = []
    ) -> RecordingCommandResponse {
        RecordingCommandResponse(
            ok: true,
            requestID: requestID,
            command: .startNativeRecording,
            sessionID: sessionID,
            status: "recording",
            captureTarget: captureTarget,
            warnings: warnings
        )
    }

    public static func successfulStop(
        requestID: String = "local-fake-stop",
        sessionID: String = "session-fake-recording",
        artifacts: [RecordingCommandArtifact]? = nil,
        warnings: [String] = []
    ) -> RecordingCommandResponse {
        let savedArtifacts = artifacts ?? [
            RecordingCommandArtifact(
                id: "artifact-fake-screen-video",
                sessionID: sessionID,
                artifactType: "screen_video",
                format: "mov",
                path: "sessions/\(sessionID)/artifacts/screen_video.mov",
                checksum: "sha256:1111111111111111111111111111111111111111111111111111111111111111"
            ),
            RecordingCommandArtifact(
                id: "artifact-fake-mixed-audio",
                sessionID: sessionID,
                artifactType: "mixed_audio",
                format: "wav",
                path: "sessions/\(sessionID)/artifacts/mixed_audio.wav",
                checksum: "sha256:2222222222222222222222222222222222222222222222222222222222222222"
            ),
        ]

        return RecordingCommandResponse(
            ok: true,
            requestID: requestID,
            command: .stopRecording,
            sessionID: sessionID,
            status: "recorded",
            artifacts: savedArtifacts,
            warnings: warnings
        )
    }

    public static func failed(
        requestID: String = "local-fake-failure",
        command: RecordingCommandName,
        code: String,
        message: String,
        details: [String] = []
    ) -> RecordingCommandResponse {
        let errorCode = RecordingCommandErrorCode(rawValue: code)
        return failure(
            requestID: requestID,
            command: command,
            code: errorCode,
            message: message,
            details: details
        )
    }

    public static func failure(
        requestID: String = "local-fake-failure",
        command: RecordingCommandName,
        sessionID: String? = nil,
        code: RecordingCommandErrorCode,
        message: String,
        details: [String] = [],
        warnings: [String] = []
    ) -> RecordingCommandResponse {
        RecordingCommandResponse(
            ok: false,
            requestID: requestID,
            command: command,
            sessionID: sessionID,
            warnings: warnings,
            code: code,
            message: message,
            details: details
        )
    }
}

public struct RecordingCommandFailure: Error, Equatable, LocalizedError, Sendable {
    public let command: RecordingCommandName
    public let code: RecordingCommandErrorCode
    public let message: String
    public let details: [String]

    public init(
        command: RecordingCommandName,
        code: RecordingCommandErrorCode,
        message: String,
        details: [String] = []
    ) {
        self.command = command
        self.code = code
        self.message = message
        self.details = details
    }

    public init(response: RecordingCommandResponse) {
        self.init(
            command: response.command,
            code: response.code ?? .internalError,
            message: response.message ?? "Recording command failed.",
            details: response.details
        )
    }

    public var errorDescription: String? {
        "\(message) (\(code.rawValue))"
    }
}

public protocol RecordingCommandClient: Sendable {
    func startNativeRecording(_ request: StartNativeRecordingRequest) async throws -> RecordingCommandResponse
    func stopRecording(_ request: StopRecordingRequest) async throws -> RecordingCommandResponse
}
