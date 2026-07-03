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
        guard !state.isBusy else {
            return
        }
        guard readinessState.canRunProcessing else {
            state = .blocked
            return
        }
        guard let lastRunRequest, state.phase == .failed else {
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
                    .processingSafeDisplayLines()
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
        } catch let bridgeError as ProcessingCommandBridgeError {
            fail(
                ProcessingCommandFailure(
                    command: bridgeError.command,
                    code: bridgeError.code,
                    message: bridgeError.safeMessage
                ),
                sessionID: request.sessionID,
                transcriptStatus: state.transcriptStatus
            )
        } catch {
            fail(
                ProcessingCommandFailure(
                    command: state.phase == .generatingSpeakerLabels ? .generateSpeakerLabels : .generateTranscript,
                    code: .internalError,
                    message: "Processing command failed unexpectedly."
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
        let safeDegradationReason = speakerLabels.degradationReason?
            .processingSafeDisplayText(
                fallback: "speaker labeling unavailable"
            )
        let speakerStatus: String
        if let degradationReason = safeDegradationReason, isDegraded {
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
            degradationReason: isDegraded ? safeDegradationReason : nil,
            errorCode: nil,
            errorMessage: nil,
            errorDetails: [],
            warnings: warnings.processingSafeDisplayLines()
        )
    }

    private func fail(
        _ failure: ProcessingCommandFailure,
        sessionID: String?,
        transcriptStatus: String?
    ) {
        let safeMessage = failure.message.processingSafeDisplayText(
            fallback: Self.fallbackFailureMessage(command: failure.command, code: failure.code)
        )
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
            errorMessage: safeMessage,
            errorDetails: failure.details.processingSafeDisplayLines(),
            warnings: failure.warnings.processingSafeDisplayLines()
        )
    }

    private static func fallbackFailureMessage(
        command: ProcessingCommandName,
        code: ProcessingCommandErrorCode?
    ) -> String {
        switch code?.rawValue {
        case "invalid_input":
            return "Processing request was invalid."
        case "artifact_missing":
            return "Required processing artifact is missing."
        case "dependency_missing":
            return "Required processing dependency is missing."
        case "processing_failed":
            return "Processing failed."
        case "path_conflict":
            return "Processing path conflict."
        case "internal_error":
            return "Processing failed with an internal error."
        default:
            switch command {
            case .generateTranscript:
                return "Transcript generation failed."
            case .generateSpeakerLabels:
                return "Speaker label generation failed."
            }
        }
    }
}

private extension Array where Element == String {
    func processingSafeDisplayLines(limit: Int = 5) -> [String] {
        var lines: [String] = []
        for value in self {
            let safe = value.processingSafeDisplayText(fallback: "<redacted>")
            guard !safe.isEmpty else {
                continue
            }
            lines.append(safe)
            if lines.count == limit {
                break
            }
        }
        return lines
    }
}

private extension String {
    func processingSafeDisplayText(
        fallback: String,
        maxLength: Int = 160
    ) -> String {
        var value = trimmingCharacters(in: .whitespacesAndNewlines)
            .split(whereSeparator: \.isWhitespace)
            .joined(separator: " ")
        guard !value.isEmpty else {
            return fallback
        }

        if value.processingHasTranscriptLikeKeyValue {
            return value.processingRedactedKeyValue(fallback: fallback)
        }
        if value.processingHasPathLikeKeyValue {
            return value.processingRedactedKeyValue(fallback: fallback)
        }

        value = value.processingReplacingSensitivePatterns()
        if value.processingLooksLikeTranscriptSnippet {
            return fallback
        }
        if value.isEmpty || value == "<redacted>" {
            return fallback
        }
        if value.count > maxLength {
            let endIndex = value.index(value.startIndex, offsetBy: maxLength)
            value = String(value[..<endIndex]).trimmingCharacters(in: .whitespacesAndNewlines) + "..."
        }
        return value
    }

    private var processingHasTranscriptLikeKeyValue: Bool {
        guard let key = processingKeyValueKey else {
            return false
        }
        return [
            "transcript",
            "transcript_text",
            "transcript-text",
            "text",
            "content",
            "segment",
            "segment_text",
            "segment-text",
            "utterance",
            "raw_output",
            "raw-output",
        ].contains(key)
    }

    private var processingHasPathLikeKeyValue: Bool {
        guard let key = processingKeyValueKey else {
            return false
        }
        return key == "path"
            || key.hasPrefix("path_")
            || key.hasPrefix("path-")
            || key.hasSuffix("_path")
            || key.hasSuffix("-path")
            || [
                "dir",
                "directory",
                "file",
                "file_name",
                "file-name",
                "filename",
                "log",
                "log_file",
                "log-file",
                "source_file",
                "source-file",
                "target_file",
                "target-file",
                "workspace",
                "workspace_dir",
                "workspace-dir",
                "working_directory",
                "working-directory",
            ].contains(key)
    }

    private var processingKeyValueKey: String? {
        guard let separator = firstIndex(of: ":") ?? firstIndex(of: "=") else {
            return nil
        }
        let key = self[..<separator].lowercased()
        let compactKey = key.filter { $0.isLetter || $0.isNumber || $0 == "_" || $0 == "-" }
        let normalizedKey = String(compactKey)
        return normalizedKey.isEmpty ? nil : normalizedKey
    }

    private var processingLooksLikeTranscriptSnippet: Bool {
        let wordCount = split(whereSeparator: \.isWhitespace).count
        let lowercasedValue = lowercased()
        let contentMarkers = [
            "action item",
            "budget",
            "confidential",
            "customer",
            "deadline",
            "discuss",
            "follow up",
            "roadmap",
            "renewal",
            "said",
        ]
        if wordCount >= 4, contentMarkers.contains(where: { lowercasedValue.contains($0) }) {
            return true
        }
        guard wordCount >= 18 else {
            return false
        }
        return lowercasedValue.contains("meeting")
            || lowercasedValue.contains("speaker")
            || lowercasedValue.contains("transcript")
            || lowercasedValue.contains("project")
    }

    private func processingRedactedKeyValue(fallback: String) -> String {
        guard let separator = firstIndex(of: ":") ?? firstIndex(of: "=") else {
            return fallback
        }
        let key = String(self[..<separator]).trimmingCharacters(in: .whitespacesAndNewlines)
        return key.isEmpty ? fallback : "\(key): <redacted>"
    }

    private func processingReplacingSensitivePatterns() -> String {
        var value = self
        let replacements: [(String, String)] = [
            (#"(?i)\b(authorization)\s*[:=]\s*(?:bearer|basic)\s+[^,\s;]+"#, "$1=<redacted>"),
            (#"(?i)\b(bearer)\s+[A-Za-z0-9._~+/=-]{8,}"#, "$1 <redacted>"),
            (#"(?i)(authorization|bearer|api[_-]?key|access[_-]?token|refresh[_-]?token|password|secret)\s*[:=]\s*[^,\s;]+"#, "$1=<redacted>"),
            (#"\bsk-[A-Za-z0-9_-]{8,}\b"#, "<redacted>"),
            (#"\bgh[pousr]_[A-Za-z0-9_]{8,}\b"#, "<redacted>"),
            (#"\bxox[baprs]-[A-Za-z0-9-]{8,}\b"#, "<redacted>"),
            (#"file:///[^\s,;)]+"#, "<redacted>"),
            (#"(?<![A-Za-z0-9_~:/.-])(?:\.\./|\./)(?:[A-Za-z0-9._-]+/){1,}[A-Za-z0-9._-]+(?:\.[A-Za-z0-9._-]+)?"#, "<redacted>"),
            (#"(?<![A-Za-z0-9_~-])~/(?:[^\s,;)]*)"#, "<redacted>"),
            (#"(?<![A-Za-z0-9_~-])/(?:Users|Volumes|private|tmp|var|etc|opt|Applications|Library|System)/[^\s,;)]*"#, "<redacted>"),
            (#"(?<![A-Za-z0-9_~.-])/(?:[A-Za-z0-9._-]+/){1,}[^\s,;)]*"#, "<redacted>"),
            (#"(?<![A-Za-z0-9_~:/.-])(?:[A-Za-z0-9._-]+/){1,}[A-Za-z0-9._-]+(?:\.[A-Za-z0-9._-]+)?"#, "<redacted>"),
        ]
        for (pattern, replacement) in replacements {
            value = value.replacingOccurrences(
                of: pattern,
                with: replacement,
                options: .regularExpression
            )
        }
        return value
    }
}
