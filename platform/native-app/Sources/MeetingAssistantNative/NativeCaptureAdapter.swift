import Foundation

public enum NativeCaptureArtifactType: String, CaseIterable, Equatable, Sendable {
    case screenVideo = "screen_video"
    case systemAudio = "system_audio"
    case microphoneAudio = "microphone_audio"
    case mixedAudio = "mixed_audio"

    public var defaultFormat: String {
        switch self {
        case .screenVideo:
            return "mov"
        case .systemAudio, .microphoneAudio:
            return "m4a"
        case .mixedAudio:
            return "wav"
        }
    }
}

public enum NativeCaptureArtifactStatus: String, Equatable, Sendable {
    case available
    case degraded
    case missing
    case failed
}

public struct NativeCaptureArtifactResult: Equatable, Sendable {
    public let artifactType: NativeCaptureArtifactType
    public let status: NativeCaptureArtifactStatus
    public let format: String?
    public let relativePath: String?
    public let data: Data?
    public let degradationReason: String?

    public init(
        artifactType: NativeCaptureArtifactType,
        status: NativeCaptureArtifactStatus,
        format: String? = nil,
        relativePath: String? = nil,
        data: Data? = nil,
        degradationReason: String? = nil
    ) {
        self.artifactType = artifactType
        self.status = status
        self.format = format
        self.relativePath = relativePath
        self.data = data
        self.degradationReason = degradationReason
    }

    public static func available(
        _ artifactType: NativeCaptureArtifactType,
        format: String? = nil,
        relativePath: String? = nil,
        data: Data
    ) -> NativeCaptureArtifactResult {
        NativeCaptureArtifactResult(
            artifactType: artifactType,
            status: .available,
            format: format,
            relativePath: relativePath,
            data: data
        )
    }

    public static func degraded(
        _ artifactType: NativeCaptureArtifactType,
        format: String? = nil,
        relativePath: String? = nil,
        reason: String
    ) -> NativeCaptureArtifactResult {
        NativeCaptureArtifactResult(
            artifactType: artifactType,
            status: .degraded,
            format: format,
            relativePath: relativePath,
            degradationReason: reason
        )
    }

    public static func missing(
        _ artifactType: NativeCaptureArtifactType,
        format: String? = nil,
        relativePath: String? = nil,
        reason: String
    ) -> NativeCaptureArtifactResult {
        NativeCaptureArtifactResult(
            artifactType: artifactType,
            status: .missing,
            format: format,
            relativePath: relativePath,
            degradationReason: reason
        )
    }

    public static func failed(
        _ artifactType: NativeCaptureArtifactType,
        format: String? = nil,
        relativePath: String? = nil,
        reason: String
    ) -> NativeCaptureArtifactResult {
        NativeCaptureArtifactResult(
            artifactType: artifactType,
            status: .failed,
            format: format,
            relativePath: relativePath,
            degradationReason: reason
        )
    }
}

public struct NativeCaptureStartContext: Equatable, Sendable {
    public let request: StartNativeRecordingRequest
    public let sessionID: String
    public let workspaceURL: URL
    public let sessionURL: URL
    public let artifactsURL: URL
    public let startedAt: String
}

public struct NativeCaptureStopContext: Equatable, Sendable {
    public let sessionID: String
    public let workspaceURL: URL
    public let sessionURL: URL
    public let artifactsURL: URL
    public let endedAt: String
}

public struct NativeCaptureStopResult: Equatable, Sendable {
    public let artifacts: [NativeCaptureArtifactResult]

    public init(artifacts: [NativeCaptureArtifactResult]) {
        self.artifacts = artifacts
    }
}

public enum NativeCaptureAdapterFailure: Error, Equatable, LocalizedError, Sendable {
    case startFailed(String)
    case stopFailed(message: String, partialArtifacts: [NativeCaptureArtifactResult])

    public var errorDescription: String? {
        switch self {
        case .startFailed(let message):
            return message
        case .stopFailed(let message, _):
            return message
        }
    }
}

public protocol NativeCaptureAdapter: Sendable {
    func start(_ context: NativeCaptureStartContext) async throws
    func stop(_ context: NativeCaptureStopContext) async throws -> NativeCaptureStopResult
}
