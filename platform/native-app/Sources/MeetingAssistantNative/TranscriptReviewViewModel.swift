import Foundation

public struct TranscriptReviewVisibleSegment: Equatable, Identifiable, Sendable {
    public let id: String
    public let timestampLabel: String
    public let text: String
    public let speakerDisplayLabel: String?
}

public struct TranscriptReviewState: Equatable, Sendable {
    public enum ContentState: Equatable, Sendable {
        case missing
        case empty
        case available
    }

    public let contentState: ContentState
    public let heading: String
    public let summary: String
    public let segments: [TranscriptReviewVisibleSegment]
    public let degradationReason: String?

    public static let missing = TranscriptReviewState(
        contentState: .missing,
        heading: "Transcript Review",
        summary: "Transcript is missing for this session.",
        segments: [],
        degradationReason: nil
    )
}

public enum TranscriptReviewFormatter {
    public static func timestampLabel(startMS: Int, endMS: Int) -> String {
        "\(timeLabel(milliseconds: startMS))-\(timeLabel(milliseconds: endMS))"
    }

    private static func timeLabel(milliseconds: Int) -> String {
        let totalSeconds = max(0, milliseconds / 1_000)
        let hours = totalSeconds / 3_600
        let minutes = (totalSeconds % 3_600) / 60
        let seconds = totalSeconds % 60

        if hours > 0 {
            return "\(hours):\(twoDigits(minutes)):\(twoDigits(seconds))"
        }
        return "\(twoDigits(minutes)):\(twoDigits(seconds))"
    }

    private static func twoDigits(_ value: Int) -> String {
        value < 10 ? "0\(value)" : "\(value)"
    }
}

public struct TranscriptReviewViewModel: Equatable, Sendable {
    public let state: TranscriptReviewState

    public init(input: TranscriptReviewInput) {
        guard let transcript = input.transcript else {
            state = .missing
            return
        }

        let orderedSegments = transcript.segments.sorted {
            if $0.startMS == $1.startMS {
                return $0.segmentID < $1.segmentID
            }
            return $0.startMS < $1.startMS
        }

        let heading = input.sessionTitle?.isEmpty == false
            ? input.sessionTitle!
            : "Session \(transcript.sessionID)"

        guard !orderedSegments.isEmpty else {
            state = TranscriptReviewState(
                contentState: .empty,
                heading: heading,
                summary: "Transcript has no segments to review.",
                segments: [],
                degradationReason: input.speakerLabelsDegradationReason
            )
            return
        }

        let speakerLabelState = SpeakerLabelState(
            transcriptSessionID: transcript.sessionID,
            artifact: input.speakerLabels
        )
        let visibleSegments = orderedSegments.map { segment in
            let speaker = speakerLabelState.nonVerifiedLabel(forSegmentID: segment.segmentID)
            return TranscriptReviewVisibleSegment(
                id: segment.segmentID,
                timestampLabel: TranscriptReviewFormatter.timestampLabel(
                    startMS: segment.startMS,
                    endMS: segment.endMS
                ),
                text: segment.text,
                speakerDisplayLabel: speaker.map {
                    "Anonymous speaker \($0) (not a verified identity)"
                }
            )
        }
        let hasVisibleSpeakerLabels = visibleSegments.contains { $0.speakerDisplayLabel != nil }

        state = TranscriptReviewState(
            contentState: .available,
            heading: heading,
            summary: "Transcript has \(visibleSegments.count) segment\(visibleSegments.count == 1 ? "" : "s") for review.",
            segments: visibleSegments,
            degradationReason: hasVisibleSpeakerLabels ? nil : input.speakerLabelsDegradationReason
        )
    }
}

private struct SpeakerLabelState {
    private let mappedLabelsBySegmentID: [String: String]
    private let nonVerifiedLabels: Set<String>

    init(transcriptSessionID: String, artifact: SpeakerLabelsReviewArtifact?) {
        guard let artifact,
              artifact.sessionID == transcriptSessionID
        else {
            mappedLabelsBySegmentID = [:]
            nonVerifiedLabels = []
            return
        }

        mappedLabelsBySegmentID = artifact.segmentMapping.reduce(into: [String: String]()) { result, mapping in
            result[mapping.segmentID] = mapping.label
        }
        nonVerifiedLabels = Set(
            artifact.labels
                .filter {
                    $0.sessionID == transcriptSessionID && !$0.isVerifiedIdentity
                }
                .map(\.label)
        )
    }

    func nonVerifiedLabel(forSegmentID segmentID: String) -> String? {
        guard let label = mappedLabelsBySegmentID[segmentID],
              nonVerifiedLabels.contains(label)
        else {
            return nil
        }
        return label
    }
}
