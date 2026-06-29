import Foundation

public struct TranscriptReviewTranscript: Decodable, Equatable, Sendable {
    public let id: String
    public let sessionID: String
    public let sourceArtifactID: String
    public let status: String
    public let segments: [TranscriptReviewSegment]

    private enum CodingKeys: String, CodingKey {
        case id
        case sessionID = "session_id"
        case sourceArtifactID = "source_artifact_id"
        case status
        case segments
    }

    public init(
        id: String,
        sessionID: String,
        sourceArtifactID: String,
        status: String,
        segments: [TranscriptReviewSegment]
    ) {
        self.id = id
        self.sessionID = sessionID
        self.sourceArtifactID = sourceArtifactID
        self.status = status
        self.segments = segments
    }
}

public struct TranscriptReviewSegment: Decodable, Equatable, Identifiable, Sendable {
    public let segmentID: String
    public let startMS: Int
    public let endMS: Int
    public let text: String
    public let speakerLabel: String?

    public var id: String {
        segmentID
    }

    private enum CodingKeys: String, CodingKey {
        case segmentID = "segment_id"
        case startMS = "start_ms"
        case endMS = "end_ms"
        case text
        case speakerLabel = "speaker_label"
    }

    public init(
        segmentID: String,
        startMS: Int,
        endMS: Int,
        text: String,
        speakerLabel: String? = nil
    ) {
        self.segmentID = segmentID
        self.startMS = startMS
        self.endMS = endMS
        self.text = text
        self.speakerLabel = speakerLabel
    }
}

public struct SpeakerLabelsReviewArtifact: Decodable, Equatable, Sendable {
    public let sessionID: String
    public let labels: [SpeakerLabelReviewEntry]
    public let segmentMapping: [SpeakerLabelSegmentMapping]

    private enum CodingKeys: String, CodingKey {
        case sessionID = "session_id"
        case labels
        case segmentMapping = "segment_mapping"
    }

    public init(
        sessionID: String,
        labels: [SpeakerLabelReviewEntry],
        segmentMapping: [SpeakerLabelSegmentMapping]
    ) {
        self.sessionID = sessionID
        self.labels = labels
        self.segmentMapping = segmentMapping
    }
}

public struct SpeakerLabelReviewEntry: Decodable, Equatable, Sendable {
    public let label: String
    public let sessionID: String
    public let isVerifiedIdentity: Bool

    private enum CodingKeys: String, CodingKey {
        case label
        case sessionID = "session_id"
        case isVerifiedIdentity = "is_verified_identity"
    }

    public init(
        label: String,
        sessionID: String,
        isVerifiedIdentity: Bool
    ) {
        self.label = label
        self.sessionID = sessionID
        self.isVerifiedIdentity = isVerifiedIdentity
    }
}

public struct SpeakerLabelSegmentMapping: Decodable, Equatable, Sendable {
    public let segmentID: String
    public let label: String

    private enum CodingKeys: String, CodingKey {
        case segmentID = "segment_id"
        case label
    }

    public init(segmentID: String, label: String) {
        self.segmentID = segmentID
        self.label = label
    }
}

public struct TranscriptReviewInput: Equatable, Sendable {
    public let sessionTitle: String?
    public let transcript: TranscriptReviewTranscript?
    public let speakerLabels: SpeakerLabelsReviewArtifact?
    public let speakerLabelsDegradationReason: String?

    public init(
        sessionTitle: String? = nil,
        transcript: TranscriptReviewTranscript?,
        speakerLabels: SpeakerLabelsReviewArtifact? = nil,
        speakerLabelsDegradationReason: String? = nil
    ) {
        self.sessionTitle = sessionTitle
        self.transcript = transcript
        self.speakerLabels = speakerLabels
        self.speakerLabelsDegradationReason = speakerLabelsDegradationReason
    }
}
