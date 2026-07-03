import Foundation

private enum ProcessingDetailsValue: Decodable {
    case string(String)
    case number(String)
    case bool(Bool)
    case array([ProcessingDetailsValue])
    case object([String: ProcessingDetailsValue])
    case null

    init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        if container.decodeNil() {
            self = .null
        } else if let object = try? container.decode([String: ProcessingDetailsValue].self) {
            self = .object(object)
        } else if let array = try? container.decode([ProcessingDetailsValue].self) {
            self = .array(array)
        } else if let string = try? container.decode(String.self) {
            self = .string(string)
        } else if let bool = try? container.decode(Bool.self) {
            self = .bool(bool)
        } else if let int = try? container.decode(Int.self) {
            self = .number(String(int))
        } else if let double = try? container.decode(Double.self) {
            self = .number(String(double))
        } else {
            throw DecodingError.dataCorruptedError(
                in: container,
                debugDescription: "Unsupported processing details shape."
            )
        }
    }

    var summaryLines: [String] {
        switch self {
        case .string(let value), .number(let value):
            return value.isEmpty ? [] : [value]
        case .bool(let value):
            return [String(value)]
        case .array(let values):
            return values.flatMap(\.summaryLines)
        case .object(let object):
            return object.keys.sorted().flatMap { key in
                guard let value = object[key] else {
                    return [String]()
                }
                let lines = value.summaryLines
                guard !lines.isEmpty else {
                    return [String]()
                }
                return lines.map { "\(key): \($0)" }
            }
        case .null:
            return []
        }
    }
}

private func decodeProcessingDetails<Key: CodingKey>(
    from container: KeyedDecodingContainer<Key>,
    forKey key: Key
) throws -> [String] {
    guard container.contains(key) else {
        return []
    }
    guard !(try container.decodeNil(forKey: key)) else {
        return []
    }
    return try container.decode(ProcessingDetailsValue.self, forKey: key).summaryLines
}

public enum ProcessingCommandName: String, Decodable, Equatable, Sendable {
    case generateTranscript = "generate_transcript"
    case generateSpeakerLabels = "generate_speaker_labels"
}

public enum ProcessingTranscriptRuntime: String, Codable, Equatable, Sendable {
    case whisperCpp = "whisper_cpp"
}

public struct ProcessingCommandErrorCode: RawRepresentable, Equatable, Sendable, ExpressibleByStringLiteral {
    public let rawValue: String

    public init(rawValue: String) {
        self.rawValue = rawValue
    }

    public init(stringLiteral value: StringLiteralType) {
        self.rawValue = value
    }

    public static let invalidInput = ProcessingCommandErrorCode(rawValue: "invalid_input")
    public static let artifactMissing = ProcessingCommandErrorCode(rawValue: "artifact_missing")
    public static let dependencyMissing = ProcessingCommandErrorCode(rawValue: "dependency_missing")
    public static let processingFailed = ProcessingCommandErrorCode(rawValue: "processing_failed")
    public static let internalError = ProcessingCommandErrorCode(rawValue: "internal_error")
}

public struct GenerateTranscriptRequest: Equatable, Sendable {
    public let sessionID: String
    public let sourceArtifactID: String?
    public let language: String?
    public let runtime: ProcessingTranscriptRuntime?

    public init(
        sessionID: String,
        sourceArtifactID: String? = nil,
        language: String? = nil,
        runtime: ProcessingTranscriptRuntime? = nil
    ) {
        self.sessionID = sessionID
        self.sourceArtifactID = sourceArtifactID
        self.language = language
        self.runtime = runtime
    }
}

public struct GenerateSpeakerLabelsRequest: Equatable, Sendable {
    public let sessionID: String
    public let transcriptID: String
    public let allowTranscriptOnlyFallback: Bool

    public init(
        sessionID: String,
        transcriptID: String,
        allowTranscriptOnlyFallback: Bool
    ) {
        self.sessionID = sessionID
        self.transcriptID = transcriptID
        self.allowTranscriptOnlyFallback = allowTranscriptOnlyFallback
    }
}

public struct GenerateTranscriptResponse: Decodable, Equatable, Sendable {
    public let ok: Bool
    public let requestID: String
    public let command: ProcessingCommandName
    public let sessionID: String?
    public let transcriptID: String?
    public let artifactID: String?
    public let segmentCount: Int?
    public let warnings: [String]
    public let code: ProcessingCommandErrorCode?
    public let message: String?
    public let details: [String]

    private enum CodingKeys: String, CodingKey {
        case ok
        case requestID = "request_id"
        case command
        case sessionID = "session_id"
        case transcriptID = "transcript_id"
        case artifactID = "artifact_id"
        case segmentCount = "segment_count"
        case warnings
        case code
        case message
        case details
    }

    public init(
        ok: Bool,
        requestID: String,
        command: ProcessingCommandName = .generateTranscript,
        sessionID: String? = nil,
        transcriptID: String? = nil,
        artifactID: String? = nil,
        segmentCount: Int? = nil,
        warnings: [String] = [],
        code: ProcessingCommandErrorCode? = nil,
        message: String? = nil,
        details: [String] = []
    ) {
        self.ok = ok
        self.requestID = requestID
        self.command = command
        self.sessionID = sessionID
        self.transcriptID = transcriptID
        self.artifactID = artifactID
        self.segmentCount = segmentCount
        self.warnings = warnings
        self.code = code
        self.message = message
        self.details = details
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        ok = try container.decode(Bool.self, forKey: .ok)
        requestID = try container.decode(String.self, forKey: .requestID)
        command = try container.decode(ProcessingCommandName.self, forKey: .command)
        sessionID = try container.decodeIfPresent(String.self, forKey: .sessionID)
        transcriptID = try container.decodeIfPresent(String.self, forKey: .transcriptID)
        artifactID = try container.decodeIfPresent(String.self, forKey: .artifactID)
        segmentCount = try container.decodeIfPresent(Int.self, forKey: .segmentCount)
        warnings = try container.decodeIfPresent([String].self, forKey: .warnings) ?? []
        code = try container
            .decodeIfPresent(String.self, forKey: .code)
            .map(ProcessingCommandErrorCode.init(rawValue:))
        message = try container.decodeIfPresent(String.self, forKey: .message)
        details = try decodeProcessingDetails(from: container, forKey: .details)
    }
}

public struct GenerateSpeakerLabelsResponse: Decodable, Equatable, Sendable {
    public let ok: Bool
    public let requestID: String
    public let command: ProcessingCommandName
    public let sessionID: String?
    public let transcriptID: String?
    public let labelStatus: String?
    public let speakerLabelsArtifactID: String?
    public let degradationReason: String?
    public let warnings: [String]
    public let code: ProcessingCommandErrorCode?
    public let message: String?
    public let details: [String]

    private enum CodingKeys: String, CodingKey {
        case ok
        case requestID = "request_id"
        case command
        case sessionID = "session_id"
        case transcriptID = "transcript_id"
        case labelStatus = "label_status"
        case speakerLabelsArtifactID = "speaker_labels_artifact_id"
        case degradationReason = "degradation_reason"
        case warnings
        case code
        case message
        case details
    }

    public init(
        ok: Bool,
        requestID: String,
        command: ProcessingCommandName = .generateSpeakerLabels,
        sessionID: String? = nil,
        transcriptID: String? = nil,
        labelStatus: String? = nil,
        speakerLabelsArtifactID: String? = nil,
        degradationReason: String? = nil,
        warnings: [String] = [],
        code: ProcessingCommandErrorCode? = nil,
        message: String? = nil,
        details: [String] = []
    ) {
        self.ok = ok
        self.requestID = requestID
        self.command = command
        self.sessionID = sessionID
        self.transcriptID = transcriptID
        self.labelStatus = labelStatus
        self.speakerLabelsArtifactID = speakerLabelsArtifactID
        self.degradationReason = degradationReason
        self.warnings = warnings
        self.code = code
        self.message = message
        self.details = details
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        ok = try container.decode(Bool.self, forKey: .ok)
        requestID = try container.decode(String.self, forKey: .requestID)
        command = try container.decode(ProcessingCommandName.self, forKey: .command)
        sessionID = try container.decodeIfPresent(String.self, forKey: .sessionID)
        transcriptID = try container.decodeIfPresent(String.self, forKey: .transcriptID)
        labelStatus = try container.decodeIfPresent(String.self, forKey: .labelStatus)
        speakerLabelsArtifactID = try container.decodeIfPresent(String.self, forKey: .speakerLabelsArtifactID)
        degradationReason = try container.decodeIfPresent(String.self, forKey: .degradationReason)
        warnings = try container.decodeIfPresent([String].self, forKey: .warnings) ?? []
        code = try container
            .decodeIfPresent(String.self, forKey: .code)
            .map(ProcessingCommandErrorCode.init(rawValue:))
        message = try container.decodeIfPresent(String.self, forKey: .message)
        details = try decodeProcessingDetails(from: container, forKey: .details)
    }
}

public struct ProcessingCommandFailure: Error, Equatable, LocalizedError, Sendable {
    public let command: ProcessingCommandName
    public let code: ProcessingCommandErrorCode?
    public let message: String
    public let details: [String]
    public let warnings: [String]

    public init(
        command: ProcessingCommandName,
        code: ProcessingCommandErrorCode?,
        message: String,
        details: [String] = [],
        warnings: [String] = []
    ) {
        self.command = command
        self.code = code
        self.message = message
        self.details = details
        self.warnings = warnings
    }

    public init(response: GenerateTranscriptResponse) {
        self.init(
            command: response.command,
            code: response.code,
            message: response.message ?? "Transcript generation failed.",
            details: response.details,
            warnings: response.warnings
        )
    }

    public init(response: GenerateSpeakerLabelsResponse) {
        self.init(
            command: response.command,
            code: response.code,
            message: response.message ?? "Speaker label generation failed.",
            details: response.details,
            warnings: response.warnings
        )
    }

    public var errorDescription: String? {
        if let code {
            return "\(message) (\(code.rawValue))"
        }
        return message
    }
}

public protocol ProcessingCommandClient: Sendable {
    func generateTranscript(_ request: GenerateTranscriptRequest) async throws -> GenerateTranscriptResponse
    func generateSpeakerLabels(_ request: GenerateSpeakerLabelsRequest) async throws -> GenerateSpeakerLabelsResponse
}
