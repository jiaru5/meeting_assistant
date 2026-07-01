import SwiftUI

public enum RecordingAccessibilityID {
    public static let heading = "ma.recording.heading"
    public static let readinessStatus = "ma.recording.readinessStatus"
    public static let status = "ma.recording.status"
    public static let startButton = "ma.recording.startButton"
    public static let stopButton = "ma.recording.stopButton"
    public static let errorSummary = "ma.recording.error"
    public static let savedSummary = "ma.recording.savedSummary"
    public static let success = savedSummary

    public static let error = errorSummary

    public static func artifactStatus(_ artifactType: String) -> String {
        "ma.recording.artifact.\(artifactType).status"
    }

    public static func artifactDegradation(_ artifactType: String) -> String {
        "ma.recording.artifact.\(artifactType).degradation"
    }
}

public enum RecordingControlAccessibilityID {
    public static let heading = RecordingAccessibilityID.heading
    public static let stateLabel = RecordingAccessibilityID.status
    public static let readinessStatus = RecordingAccessibilityID.readinessStatus
    public static let status = RecordingAccessibilityID.status
    public static let summary = RecordingAccessibilityID.status
    public static let sessionID = "ma.recording.sessionID"
    public static let startButton = RecordingAccessibilityID.startButton
    public static let stopButton = RecordingAccessibilityID.stopButton
    public static let success = RecordingAccessibilityID.savedSummary
    public static let failure = RecordingAccessibilityID.error
    public static let warnings = "ma.recording.warnings"

    public static func artifactStatus(_ artifactType: String) -> String {
        RecordingAccessibilityID.artifactStatus(artifactType)
    }

    public static func artifactDegradation(_ artifactType: String) -> String {
        RecordingAccessibilityID.artifactDegradation(artifactType)
    }
}

public struct RecordingControlView: View {
    @ObservedObject private var viewModel: RecordingControlViewModel

    public init(viewModel: RecordingControlViewModel) {
        self.viewModel = viewModel
    }

    public var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Recording")
                .font(.headline)
                .accessibilityAddTraits(.isHeader)
                .accessibilityLabel("Recording")
                .accessibilityIdentifier(RecordingControlAccessibilityID.heading)

            Text(readinessStatusText)
                .font(.caption)
                .foregroundStyle(.secondary)
                .accessibilityLabel(readinessStatusText)
                .accessibilityIdentifier(RecordingControlAccessibilityID.readinessStatus)

            Text(viewModel.state.statusText)
                .font(.body)
                .accessibilityLabel(viewModel.state.statusText)
                .accessibilityIdentifier(RecordingControlAccessibilityID.status)

            HStack(spacing: 8) {
                Button("Start Recording") {
                    Task {
                        await viewModel.start()
                    }
                }
                .disabled(!viewModel.canStart)
                .accessibilityIdentifier(RecordingControlAccessibilityID.startButton)

                Button("Stop Recording") {
                    Task {
                        await viewModel.stop()
                    }
                }
                .disabled(!viewModel.canStop)
                .accessibilityIdentifier(RecordingControlAccessibilityID.stopButton)
            }

            if let sessionID = viewModel.state.sessionID {
                Text("Session: \(sessionID)")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .accessibilityLabel("Session: \(sessionID)")
                    .accessibilityIdentifier(RecordingControlAccessibilityID.sessionID)
            }

            if let savedSummary = viewModel.state.savedSummary {
                Text(savedSummary)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .accessibilityLabel(savedSummary)
                    .accessibilityIdentifier(RecordingControlAccessibilityID.success)
            }

            if !viewModel.state.artifacts.isEmpty {
                VStack(alignment: .leading, spacing: 4) {
                    ForEach(viewModel.state.artifacts) { artifact in
                        VStack(alignment: .leading, spacing: 2) {
                            Text("\(artifact.artifactType): \(artifact.captureStatus)")
                                .accessibilityLabel("\(artifact.artifactType): \(artifact.captureStatus)")
                                .accessibilityIdentifier(
                                    RecordingControlAccessibilityID.artifactStatus(artifact.artifactType)
                                )
                            if let degradationReason = artifact.degradationReason {
                                Text(degradationReason)
                                    .foregroundStyle(.secondary)
                                    .accessibilityLabel(degradationReason)
                                    .accessibilityIdentifier(
                                        RecordingControlAccessibilityID.artifactDegradation(artifact.artifactType)
                                    )
                            }
                        }
                    }
                }
                .font(.caption)
            }

            if let errorMessage = viewModel.state.errorMessage {
                VStack(alignment: .leading, spacing: 4) {
                    Text(errorMessage)
                    if let errorCode = viewModel.state.errorCode {
                        Text("Error code: \(errorCode.rawValue)")
                    }
                }
                .font(.caption)
                .foregroundStyle(.red)
                .accessibilityElement(children: .combine)
                .accessibilityLabel(errorAccessibilityLabel)
                .accessibilityIdentifier(RecordingControlAccessibilityID.failure)
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
                .accessibilityIdentifier(RecordingControlAccessibilityID.warnings)
            }
        }
        .padding()
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var readinessStatusText: String {
        switch viewModel.state.phase {
        case .idle:
            return "Recording readiness is pending."
        case .ready:
            return "Recording readiness is ready."
        case .starting, .recording, .stopping, .recorded:
            return "Recording command is active."
        case .failed:
            return "Recording command failed."
        }
    }

    private var errorAccessibilityLabel: String {
        guard let errorMessage = viewModel.state.errorMessage else {
            return ""
        }
        if let errorCode = viewModel.state.errorCode {
            return "\(errorMessage) Error code: \(errorCode.rawValue)"
        }
        return errorMessage
    }
}
