import SwiftUI

public enum TranscriptActionAccessibilityID {
    public static let heading = "ma.transcriptAction.heading"
    public static let status = "ma.transcriptAction.status"
    public static let copyButton = "ma.transcriptAction.copyButton"
    public static let exportButton = "ma.transcriptAction.exportButton"
    public static let deleteButton = "ma.transcriptAction.deleteButton"
    public static let successSummary = "ma.transcriptAction.success"
    public static let errorSummary = "ma.transcriptAction.error"
    public static let warnings = "ma.transcriptAction.warnings"
    public static let deletePrompt = "ma.transcriptAction.deletePrompt"
    public static let deletePromptText = "ma.transcriptAction.deletePromptText"
    public static let deleteConfirmButton = "ma.transcriptAction.deleteConfirmButton"
    public static let deleteCancelButton = "ma.transcriptAction.deleteCancelButton"
}

public struct TranscriptReviewActionsView: View {
    @ObservedObject private var viewModel: TranscriptReviewActionsViewModel

    public init(viewModel: TranscriptReviewActionsViewModel) {
        self.viewModel = viewModel
    }

    public var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Transcript Actions")
                .font(.headline)
                .accessibilityAddTraits(.isHeader)
                .accessibilityLabel("Transcript Actions")
                .accessibilityIdentifier(TranscriptActionAccessibilityID.heading)

            Text(viewModel.state.statusText)
                .font(.body)
                .accessibilityLabel(viewModel.state.statusText)
                .accessibilityIdentifier(TranscriptActionAccessibilityID.status)

            HStack(spacing: 8) {
                Button("Copy Transcript") {
                    Task {
                        await viewModel.copyTranscript()
                    }
                }
                .disabled(!viewModel.state.canCopy)
                .accessibilityIdentifier(TranscriptActionAccessibilityID.copyButton)

                Button("Export Markdown") {
                    Task {
                        await viewModel.exportTranscript()
                    }
                }
                .disabled(!viewModel.state.canExport)
                .accessibilityIdentifier(TranscriptActionAccessibilityID.exportButton)

                Button("Delete Session") {
                    viewModel.requestDeleteConfirmation()
                }
                .disabled(!viewModel.state.canRequestDelete)
                .accessibilityIdentifier(TranscriptActionAccessibilityID.deleteButton)
            }

            if let successSummary = viewModel.state.successSummary {
                Text(successSummary)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .accessibilityLabel(successSummary)
                    .accessibilityIdentifier(TranscriptActionAccessibilityID.successSummary)
            }

            if let failureSummary = viewModel.state.failureSummary {
                Text(failureSummary)
                    .font(.caption)
                    .foregroundStyle(.red)
                    .accessibilityLabel(failureSummary)
                    .accessibilityIdentifier(TranscriptActionAccessibilityID.errorSummary)
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
                .accessibilityIdentifier(TranscriptActionAccessibilityID.warnings)
            }

            if viewModel.state.isDeletePromptVisible {
                VStack(alignment: .leading, spacing: 8) {
                    Text(viewModel.state.deletePromptText ?? "Confirm delete before removing the session.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .accessibilityLabel(viewModel.state.deletePromptText ?? "Confirm delete before removing the session.")
                        .accessibilityIdentifier(TranscriptActionAccessibilityID.deletePromptText)

                    HStack(spacing: 8) {
                        Button("Confirm Delete") {
                            Task {
                                await viewModel.confirmDelete()
                            }
                        }
                        .disabled(!viewModel.state.canConfirmDelete)
                        .accessibilityIdentifier(TranscriptActionAccessibilityID.deleteConfirmButton)

                        Button("Cancel Delete") {
                            viewModel.cancelDelete()
                        }
                        .disabled(!viewModel.state.canCancelDelete)
                        .accessibilityIdentifier(TranscriptActionAccessibilityID.deleteCancelButton)
                    }
                }
                .padding(.top, 4)
                .accessibilityElement(children: .contain)
                .accessibilityIdentifier(TranscriptActionAccessibilityID.deletePrompt)
            }
        }
        .padding()
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}
