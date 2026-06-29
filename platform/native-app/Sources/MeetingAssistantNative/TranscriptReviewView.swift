import SwiftUI

public enum TranscriptReviewAccessibilityID {
    public static let heading = "ma.transcript.heading"
    public static let summary = "ma.transcript.summary"
    public static let segmentRowPrefix = "ma.transcript.segmentRow"
    public static let timestampPrefix = "ma.transcript.timestamp"
    public static let textPrefix = "ma.transcript.text"
    public static let speakerLabelPrefix = "ma.transcript.speakerLabel"
    public static let degradation = "ma.transcript.degradation"
    public static let empty = "ma.transcript.empty"
    public static let missing = "ma.transcript.missing"

    public static func segmentRow(_ segmentID: String) -> String {
        "\(segmentRowPrefix).\(segmentID)"
    }

    public static func timestamp(_ segmentID: String) -> String {
        "\(timestampPrefix).\(segmentID)"
    }

    public static func text(_ segmentID: String) -> String {
        "\(textPrefix).\(segmentID)"
    }

    public static func speakerLabel(_ segmentID: String) -> String {
        "\(speakerLabelPrefix).\(segmentID)"
    }
}

public struct TranscriptReviewView: View {
    private let state: TranscriptReviewState

    public init(viewModel: TranscriptReviewViewModel) {
        self.state = viewModel.state
    }

    public var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(state.heading)
                .font(.headline)
                .accessibilityAddTraits(.isHeader)
                .accessibilityLabel(state.heading)
                .accessibilityIdentifier(TranscriptReviewAccessibilityID.heading)

            Text(state.summary)
                .font(.body)
                .accessibilityLabel(state.summary)
                .accessibilityIdentifier(TranscriptReviewAccessibilityID.summary)

            switch state.contentState {
            case .missing:
                Text(state.summary)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .accessibilityLabel(state.summary)
                    .accessibilityIdentifier(TranscriptReviewAccessibilityID.missing)
            case .empty:
                Text(state.summary)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .accessibilityLabel(state.summary)
                    .accessibilityIdentifier(TranscriptReviewAccessibilityID.empty)
            case .available:
                ForEach(state.segments) { segment in
                    segmentRow(segment)
                }
            }

            if let degradationReason = state.degradationReason {
                Text("Speaker labels unavailable: \(degradationReason)")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .accessibilityLabel("Speaker labels unavailable: \(degradationReason)")
                    .accessibilityIdentifier(TranscriptReviewAccessibilityID.degradation)
            }
        }
        .padding()
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func segmentRow(_ segment: TranscriptReviewVisibleSegment) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                Text(segment.timestampLabel)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .accessibilityLabel(segment.timestampLabel)
                    .accessibilityIdentifier(TranscriptReviewAccessibilityID.timestamp(segment.id))

                if let speakerDisplayLabel = segment.speakerDisplayLabel {
                    Text(speakerDisplayLabel)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .accessibilityLabel(speakerDisplayLabel)
                        .accessibilityIdentifier(TranscriptReviewAccessibilityID.speakerLabel(segment.id))
                }
            }

            Text(segment.text)
                .font(.body)
                .accessibilityLabel(segment.text)
                .accessibilityIdentifier(TranscriptReviewAccessibilityID.text(segment.id))
        }
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier(TranscriptReviewAccessibilityID.segmentRow(segment.id))
    }
}

