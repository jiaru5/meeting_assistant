import Foundation
import SwiftUI

public enum ProcessingStatePhase: String, Equatable, Sendable {
    case idle
    case blocked
    case generatingTranscript
    case generatingSpeakerLabels
    case completed
    case degraded
    case failed
}

public struct ProcessingState: Equatable, Sendable {
    public let phase: ProcessingStatePhase
    public let statusText: String
    public let sessionID: String?
    public let transcriptID: String?
    public let transcriptArtifactID: String?
    public let transcriptStatus: String?
    public let segmentCount: Int?
    public let labelStatus: String?
    public let speakerLabelsArtifactID: String?
    public let speakerLabelStatus: String?
    public let successSummary: String?
    public let degradationReason: String?
    public let errorCode: ProcessingCommandErrorCode?
    public let errorMessage: String?
    public let errorDetails: [String]
    public let warnings: [String]

    public var isBusy: Bool {
        phase == .generatingTranscript || phase == .generatingSpeakerLabels
    }

    public static let idle = ProcessingState(
        phase: .idle,
        statusText: "Processing is ready to run.",
        sessionID: nil,
        transcriptID: nil,
        transcriptArtifactID: nil,
        transcriptStatus: nil,
        segmentCount: nil,
        labelStatus: nil,
        speakerLabelsArtifactID: nil,
        speakerLabelStatus: nil,
        successSummary: nil,
        degradationReason: nil,
        errorCode: nil,
        errorMessage: nil,
        errorDetails: [],
        warnings: []
    )

    public static let blocked = ProcessingState(
        phase: .blocked,
        statusText: "Processing is blocked until required dependencies are available.",
        sessionID: nil,
        transcriptID: nil,
        transcriptArtifactID: nil,
        transcriptStatus: nil,
        segmentCount: nil,
        labelStatus: nil,
        speakerLabelsArtifactID: nil,
        speakerLabelStatus: nil,
        successSummary: nil,
        degradationReason: nil,
        errorCode: nil,
        errorMessage: nil,
        errorDetails: [],
        warnings: []
    )
}

private struct ProcessingRunRequest: Equatable, Sendable {
    let sessionID: String
    let sourceArtifactID: String?
    let language: String?
    let runtime: ProcessingTranscriptRuntime?
    let allowTranscriptOnlyFallback: Bool

    var transcriptRequest: GenerateTranscriptRequest {
        GenerateTranscriptRequest(
            sessionID: sessionID,
            sourceArtifactID: sourceArtifactID,
            language: language,
            runtime: runtime
        )
    }

    func speakerLabelsRequest(transcriptID: String) -> GenerateSpeakerLabelsRequest {
        GenerateSpeakerLabelsRequest(
            sessionID: sessionID,
            transcriptID: transcriptID,
            allowTranscriptOnlyFallback: allowTranscriptOnlyFallback
        )
    }
}

@MainActor
public final class ProcessingStateViewModel: ObservableObject {
    @Published public private(set) var state: ProcessingState

    public var canStart: Bool {
        readinessState.canRunProcessing && !state.isBusy
    }

    public var canRetry: Bool {
        readinessState.canRunProcessing
            && !state.isBusy
            && state.phase == .failed
            && lastRunRequest != nil
    }

    private let commandClient: any ProcessingCommandClient
    private var readinessState: PermissionDependencyStatusState
    private var lastRunRequest: ProcessingRunRequest?
    private let defaultSessionID: String

    public init(
        commandClient: any ProcessingCommandClient = ProcessingCommandFakeClient(),
        readinessState: PermissionDependencyStatusState = .idle,
        defaultSessionID: String = "session-processing-fixture"
    ) {
        self.commandClient = commandClient
        self.readinessState = readinessState
        self.defaultSessionID = defaultSessionID
        state = readinessState.canRunProcessing ? .idle : .blocked
    }

    public func updateReadiness(_ readinessState: PermissionDependencyStatusState) {
        self.readinessState = readinessState
        guard state.phase == .idle || state.phase == .blocked else {
            return
        }
        state = readinessState.canRunProcessing ? .idle : .blocked
    }

    public func start() async {
        await start(sessionID: defaultSessionID)
    }

    public func start(
        sessionID: String,
        sourceArtifactID: String? = nil,
        language: String? = nil,
        runtime: ProcessingTranscriptRuntime? = nil,
        allowTranscriptOnlyFallback: Bool = true
    ) async {
        let request = ProcessingRunRequest(
            sessionID: sessionID,
            sourceArtifactID: sourceArtifactID,
            language: language,
            runtime: runtime,
            allowTranscriptOnlyFallback: allowTranscriptOnlyFallback
        )
        await run(request, rememberRequest: true)
    }

    public func retry() async {
        guard let lastRunRequest, canRetry else {
            return
        }
        await run(lastRunRequest, rememberRequest: false)
    }

    private func run(_ request: ProcessingRunRequest, rememberRequest: Bool) async {
        guard !state.isBusy else {
            return
        }
        guard readinessState.canRunProcessing else {
            state = .blocked
            return
        }
        guard !request.sessionID.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            fail(
                ProcessingCommandFailure(
                    command: .generateTranscript,
                    code: nil,
                    message: "Processing session id is required."
                ),
                sessionID: nil,
                transcriptStatus: nil
            )
            return
        }

        if rememberRequest {
            lastRunRequest = request
        }

        state = ProcessingState(
            phase: .generatingTranscript,
            statusText: "Generating transcript...",
            sessionID: request.sessionID,
            transcriptID: nil,
            transcriptArtifactID: nil,
            transcriptStatus: "Transcript generation is running.",
            segmentCount: nil,
            labelStatus: nil,
            speakerLabelsArtifactID: nil,
            speakerLabelStatus: nil,
            successSummary: nil,
            degradationReason: nil,
            errorCode: nil,
            errorMessage: nil,
            errorDetails: [],
            warnings: []
        )

        do {
            let transcriptResponse = try await commandClient.generateTranscript(request.transcriptRequest)
            let transcript = try validateTranscriptResponse(
                transcriptResponse,
                expectedSessionID: request.sessionID
            )
            let transcriptStatus = "Transcript \(transcript.id) generated with \(transcript.segmentCount) segments."

            state = ProcessingState(
                phase: .generatingSpeakerLabels,
                statusText: "Generating speaker labels...",
                sessionID: request.sessionID,
                transcriptID: transcript.id,
                transcriptArtifactID: transcript.artifactID,
                transcriptStatus: transcriptStatus,
                segmentCount: transcript.segmentCount,
                labelStatus: nil,
                speakerLabelsArtifactID: nil,
                speakerLabelStatus: "Speaker label generation is running.",
                successSummary: nil,
                degradationReason: nil,
                errorCode: nil,
                errorMessage: nil,
                errorDetails: [],
                warnings: transcriptResponse.warnings
            )

            let speakerResponse = try await commandClient.generateSpeakerLabels(
                request.speakerLabelsRequest(transcriptID: transcript.id)
            )
            let speakerLabels = try validateSpeakerLabelsResponse(
                speakerResponse,
                expectedSessionID: request.sessionID,
                expectedTranscriptID: transcript.id
            )
            complete(
                transcript: transcript,
                speakerLabels: speakerLabels,
                transcriptStatus: transcriptStatus,
                warnings: transcriptResponse.warnings + speakerResponse.warnings
            )
        } catch let failure as ProcessingCommandFailure {
            fail(failure, sessionID: request.sessionID, transcriptStatus: state.transcriptStatus)
        } catch {
            fail(
                ProcessingCommandFailure(
                    command: state.phase == .generatingSpeakerLabels ? .generateSpeakerLabels : .generateTranscript,
                    code: nil,
                    message: error.localizedDescription
                ),
                sessionID: request.sessionID,
                transcriptStatus: state.transcriptStatus
            )
        }
    }

    private func validateTranscriptResponse(
        _ response: GenerateTranscriptResponse,
        expectedSessionID: String
    ) throws -> (id: String, artifactID: String, segmentCount: Int) {
        guard response.ok else {
            throw ProcessingCommandFailure(response: response)
        }
        guard response.command == .generateTranscript,
              response.sessionID == expectedSessionID,
              let transcriptID = response.transcriptID,
              !transcriptID.isEmpty,
              let artifactID = response.artifactID,
              !artifactID.isEmpty,
              let segmentCount = response.segmentCount,
              segmentCount >= 0
        else {
            throw ProcessingCommandFailure(
                command: .generateTranscript,
                code: nil,
                message: "generate_transcript returned an incomplete response."
            )
        }
        return (transcriptID, artifactID, segmentCount)
    }

    private func validateSpeakerLabelsResponse(
        _ response: GenerateSpeakerLabelsResponse,
        expectedSessionID: String,
        expectedTranscriptID: String
    ) throws -> (labelStatus: String, artifactID: String, degradationReason: String?) {
        guard response.ok else {
            throw ProcessingCommandFailure(response: response)
        }
        guard response.command == .generateSpeakerLabels,
              response.sessionID == expectedSessionID,
              response.transcriptID == expectedTranscriptID,
              let labelStatus = response.labelStatus,
              !labelStatus.isEmpty,
              let artifactID = response.speakerLabelsArtifactID,
              !artifactID.isEmpty
        else {
            throw ProcessingCommandFailure(
                command: .generateSpeakerLabels,
                code: nil,
                message: "generate_speaker_labels returned an incomplete response."
            )
        }

        if labelStatus == "transcript_only" {
            guard let degradationReason = response.degradationReason,
                  !degradationReason.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            else {
                throw ProcessingCommandFailure(
                    command: .generateSpeakerLabels,
                    code: nil,
                    message: "generate_speaker_labels returned transcript-only without a degradation reason."
                )
            }
            return (labelStatus, artifactID, degradationReason)
        }

        return (labelStatus, artifactID, response.degradationReason)
    }

    private func complete(
        transcript: (id: String, artifactID: String, segmentCount: Int),
        speakerLabels: (labelStatus: String, artifactID: String, degradationReason: String?),
        transcriptStatus: String,
        warnings: [String]
    ) {
        let isDegraded = speakerLabels.labelStatus == "transcript_only"
        let speakerStatus: String
        if let degradationReason = speakerLabels.degradationReason, isDegraded {
            speakerStatus = "Speaker labels degraded: \(degradationReason)"
        } else {
            speakerStatus = "Speaker labels artifact \(speakerLabels.artifactID) is available."
        }

        state = ProcessingState(
            phase: isDegraded ? .degraded : .completed,
            statusText: isDegraded ? "Processing completed with transcript-only speaker labels." : "Processing complete.",
            sessionID: state.sessionID,
            transcriptID: transcript.id,
            transcriptArtifactID: transcript.artifactID,
            transcriptStatus: transcriptStatus,
            segmentCount: transcript.segmentCount,
            labelStatus: speakerLabels.labelStatus,
            speakerLabelsArtifactID: speakerLabels.artifactID,
            speakerLabelStatus: speakerStatus,
            successSummary: isDegraded ? nil : "Generated transcript and speaker labels for session \(state.sessionID ?? "").",
            degradationReason: isDegraded ? speakerLabels.degradationReason : nil,
            errorCode: nil,
            errorMessage: nil,
            errorDetails: [],
            warnings: warnings
        )
    }

    private func fail(
        _ failure: ProcessingCommandFailure,
        sessionID: String?,
        transcriptStatus: String?
    ) {
        state = ProcessingState(
            phase: .failed,
            statusText: "Processing failed.",
            sessionID: sessionID,
            transcriptID: state.transcriptID,
            transcriptArtifactID: state.transcriptArtifactID,
            transcriptStatus: transcriptStatus,
            segmentCount: state.segmentCount,
            labelStatus: nil,
            speakerLabelsArtifactID: nil,
            speakerLabelStatus: nil,
            successSummary: nil,
            degradationReason: nil,
            errorCode: failure.code,
            errorMessage: failure.message,
            errorDetails: failure.details,
            warnings: []
        )
    }
}
