import Foundation

public actor ProcessingCommandFakeClient: ProcessingCommandClient {
    public enum TranscriptScript: Equatable, Sendable {
        case success(
            transcriptID: String? = "transcript-fake",
            artifactID: String? = "artifact-transcript-fake",
            segmentCount: Int? = 2,
            warnings: [String] = []
        )
        case failure(
            code: String,
            message: String,
            details: [String] = [],
            warnings: [String] = []
        )
    }

    public enum SpeakerLabelsScript: Equatable, Sendable {
        case success(
            labelStatus: String = "labels_available",
            speakerLabelsArtifactID: String? = "artifact-speaker-labels-fake",
            degradationReason: String? = nil,
            warnings: [String] = []
        )
        case failure(
            code: String,
            message: String,
            details: [String] = [],
            warnings: [String] = []
        )
    }

    public private(set) var transcriptRequests: [GenerateTranscriptRequest] = []
    public private(set) var speakerLabelsRequests: [GenerateSpeakerLabelsRequest] = []

    private let transcriptScript: TranscriptScript
    private let speakerLabelsScript: SpeakerLabelsScript
    private let responseDelayNanoseconds: UInt64

    public init(
        transcriptScript: TranscriptScript = .success(),
        speakerLabelsScript: SpeakerLabelsScript = .success(),
        responseDelayNanoseconds: UInt64 = 0
    ) {
        self.transcriptScript = transcriptScript
        self.speakerLabelsScript = speakerLabelsScript
        self.responseDelayNanoseconds = responseDelayNanoseconds
    }

    public func generateTranscript(
        _ request: GenerateTranscriptRequest
    ) async throws -> GenerateTranscriptResponse {
        transcriptRequests.append(request)
        await delayIfNeeded()

        switch transcriptScript {
        case .success(let transcriptID, let artifactID, let segmentCount, let warnings):
            return GenerateTranscriptResponse(
                ok: true,
                requestID: "local-fake-generate-transcript",
                sessionID: request.sessionID,
                transcriptID: transcriptID,
                artifactID: artifactID,
                segmentCount: segmentCount,
                warnings: warnings
            )
        case .failure(let code, let message, let details, let warnings):
            return GenerateTranscriptResponse(
                ok: false,
                requestID: "local-fake-generate-transcript-failure",
                sessionID: request.sessionID,
                warnings: warnings,
                code: ProcessingCommandErrorCode(rawValue: code),
                message: message,
                details: details
            )
        }
    }

    public func generateSpeakerLabels(
        _ request: GenerateSpeakerLabelsRequest
    ) async throws -> GenerateSpeakerLabelsResponse {
        speakerLabelsRequests.append(request)
        await delayIfNeeded()

        switch speakerLabelsScript {
        case .success(let labelStatus, let artifactID, let degradationReason, let warnings):
            return GenerateSpeakerLabelsResponse(
                ok: true,
                requestID: "local-fake-generate-speaker-labels",
                sessionID: request.sessionID,
                transcriptID: request.transcriptID,
                labelStatus: labelStatus,
                speakerLabelsArtifactID: artifactID,
                degradationReason: degradationReason,
                warnings: warnings
            )
        case .failure(let code, let message, let details, let warnings):
            return GenerateSpeakerLabelsResponse(
                ok: false,
                requestID: "local-fake-generate-speaker-labels-failure",
                sessionID: request.sessionID,
                transcriptID: request.transcriptID,
                warnings: warnings,
                code: ProcessingCommandErrorCode(rawValue: code),
                message: message,
                details: details
            )
        }
    }

    public func transcriptRequestSnapshot() -> [GenerateTranscriptRequest] {
        transcriptRequests
    }

    public func speakerLabelsRequestSnapshot() -> [GenerateSpeakerLabelsRequest] {
        speakerLabelsRequests
    }

    private func delayIfNeeded() async {
        guard responseDelayNanoseconds > 0 else {
            return
        }
        try? await Task.sleep(nanoseconds: responseDelayNanoseconds)
    }
}
