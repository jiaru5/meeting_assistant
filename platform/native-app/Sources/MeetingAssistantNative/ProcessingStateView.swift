import SwiftUI

public enum ProcessingAccessibilityID {
    public static let heading = "ma.processing.heading"
    public static let status = "ma.processing.status"
    public static let startButton = "ma.processing.startButton"
    public static let retryButton = "ma.processing.retryButton"
    public static let transcriptStatus = "ma.processing.transcriptStatus"
    public static let speakerLabelStatus = "ma.processing.speakerLabelStatus"
    public static let success = "ma.processing.success"
    public static let error = "ma.processing.error"
    public static let degradation = "ma.processing.degradation"
    public static let warnings = "ma.processing.warnings"
}

public struct ProcessingStateView: View {
    @ObservedObject private var viewModel: ProcessingStateViewModel

    public init(viewModel: ProcessingStateViewModel) {
        self.viewModel = viewModel
    }

    public var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Processing")
                .font(.headline)
                .accessibilityAddTraits(.isHeader)
                .accessibilityLabel("Processing")
                .accessibilityIdentifier(ProcessingAccessibilityID.heading)

            Text(viewModel.state.statusText)
                .font(.body)
                .accessibilityLabel(viewModel.state.statusText)
                .accessibilityIdentifier(ProcessingAccessibilityID.status)

            HStack(spacing: 8) {
                Button("Start Processing") {
                    Task {
                        await viewModel.start()
                    }
                }
                .disabled(!viewModel.canStart)
                .accessibilityIdentifier(ProcessingAccessibilityID.startButton)

                Button("Retry Processing") {
                    Task {
                        await viewModel.retry()
                    }
                }
                .disabled(!viewModel.canRetry)
                .accessibilityIdentifier(ProcessingAccessibilityID.retryButton)
            }

            if let transcriptStatus = viewModel.state.transcriptStatus {
                Text(transcriptStatus)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .accessibilityLabel(transcriptStatus)
                    .accessibilityIdentifier(ProcessingAccessibilityID.transcriptStatus)
            }

            if let speakerLabelStatus = viewModel.state.speakerLabelStatus {
                Text(speakerLabelStatus)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .accessibilityLabel(speakerLabelStatus)
                    .accessibilityIdentifier(ProcessingAccessibilityID.speakerLabelStatus)
            }

            if let successSummary = viewModel.state.successSummary {
                Text(successSummary)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .accessibilityLabel(successSummary)
                    .accessibilityIdentifier(ProcessingAccessibilityID.success)
            }

            if let degradationReason = viewModel.state.degradationReason {
                Text("Transcript-only speaker labeling: \(degradationReason)")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .accessibilityLabel("Transcript-only speaker labeling: \(degradationReason)")
                    .accessibilityIdentifier(ProcessingAccessibilityID.degradation)
            }

            if let errorMessage = viewModel.state.errorMessage {
                VStack(alignment: .leading, spacing: 4) {
                    Text(errorMessage)
                    if let errorCode = viewModel.state.errorCode {
                        Text("Error code: \(errorCode.rawValue)")
                    }
                    ForEach(viewModel.state.errorDetails, id: \.self) { detail in
                        Text(detail)
                    }
                }
                .font(.caption)
                .foregroundStyle(.red)
                .accessibilityElement(children: .combine)
                .accessibilityLabel(errorAccessibilityLabel)
                .accessibilityIdentifier(ProcessingAccessibilityID.error)
            }

            if !viewModel.state.warnings.isEmpty {
                VStack(alignment: .leading, spacing: 4) {
                    ForEach(viewModel.state.warnings, id: \.self) { warning in
                        Text(warning)
                    }
                }
                .font(.caption)
                .foregroundStyle(.secondary)
                .accessibilityElement(children: .combine)
                .accessibilityLabel(viewModel.state.warnings.joined(separator: " "))
                .accessibilityIdentifier(ProcessingAccessibilityID.warnings)
            }
        }
        .padding()
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var errorAccessibilityLabel: String {
        guard let errorMessage = viewModel.state.errorMessage else {
            return ""
        }
        var parts = [errorMessage]
        if let errorCode = viewModel.state.errorCode {
            parts.append("Error code: \(errorCode.rawValue)")
        }
        parts.append(contentsOf: viewModel.state.errorDetails)
        return parts.joined(separator: " ")
    }
}
