import Foundation
import SwiftUI

public enum DesignedNativeShellSection: String, CaseIterable, Identifiable, Sendable {
    case preflight
    case recording
    case artifacts
    case processing
    case transcript
    case actions

    public var id: String {
        rawValue
    }

    public var title: String {
        switch self {
        case .preflight:
            return "Preflight"
        case .recording:
            return "Record meeting"
        case .artifacts:
            return "Session artifacts"
        case .processing:
            return "Processing"
        case .transcript:
            return "Transcript"
        case .actions:
            return "Export and delete"
        }
    }

    public var subtitle: String {
        switch self {
        case .preflight:
            return "Permissions, workspace and local dependency readiness"
        case .recording:
            return "Native recording setup, live state and stop action"
        case .artifacts:
            return "Screen video, system audio, microphone audio and mixed audio status"
        case .processing:
            return "Transcript and speaker-label pipeline state"
        case .transcript:
            return "Timestamped transcript review with anonymous speaker labels"
        case .actions:
            return "User-triggered copy, export and delete confirmation"
        }
    }
}

public enum DesignedNativeShellAccessibilityID {
    public static let root = "ma.shell.root"
    public static let heading = "ma.shell.heading"
    public static let subtitle = "ma.shell.subtitle"
    public static let navigation = "ma.shell.navigation"
    public static let selectedSection = "ma.shell.selectedSection"
    public static let statusBoard = "ma.shell.statusBoard"
    public static let commandRail = "ma.shell.commandRail"
    public static let workspaceBoundary = "ma.shell.workspaceBoundary"
    public static let recordingSetup = "ma.shell.recordingSetup"
    public static let exportDeleteUnavailable = "ma.shell.exportDelete.unavailable"

    public static func navButton(_ section: DesignedNativeShellSection) -> String {
        "ma.shell.nav.\(section.rawValue)"
    }

    public static func section(_ section: DesignedNativeShellSection) -> String {
        "ma.shell.section.\(section.rawValue)"
    }

    public static func sectionHeading(_ section: DesignedNativeShellSection) -> String {
        "ma.shell.section.\(section.rawValue).heading"
    }

    public static func status(_ id: String) -> String {
        "ma.shell.status.\(id)"
    }

    public static func artifactStatus(_ artifactType: String) -> String {
        "ma.sessionArtifact.\(artifactType).status"
    }

    public static func artifactDetail(_ artifactType: String) -> String {
        "ma.sessionArtifact.\(artifactType).detail"
    }

    public static func processingStep(_ id: String) -> String {
        "ma.shell.processingStep.\(id)"
    }
}

public struct DesignedNativeShellStatusItem: Equatable, Identifiable, Sendable {
    public let id: String
    public let title: String
    public let value: String
    public let tone: String

    public init(id: String, title: String, value: String, tone: String) {
        self.id = id
        self.title = title
        self.value = value
        self.tone = tone
    }
}

public struct DesignedNativeShellArtifactRow: Equatable, Identifiable, Sendable {
    public let artifactType: String
    public let status: String
    public let detail: String

    public var id: String {
        artifactType
    }

    public init(artifactType: String, status: String, detail: String) {
        self.artifactType = artifactType
        self.status = status
        self.detail = detail
    }
}

public struct DesignedNativeShellProcessingStep: Equatable, Identifiable, Sendable {
    public let id: String
    public let title: String
    public let status: String

    public init(id: String, title: String, status: String) {
        self.id = id
        self.title = title
        self.status = status
    }
}

@MainActor
public final class DesignedNativeShellViewModel: ObservableObject {
    @Published public private(set) var selectedSection: DesignedNativeShellSection

    public init(initialSection: DesignedNativeShellSection = .preflight) {
        selectedSection = initialSection
    }

    public var sections: [DesignedNativeShellSection] {
        DesignedNativeShellSection.allCases
    }

    public var selectedSectionLabel: String {
        "\(selectedSection.title) selected."
    }

    public func select(_ section: DesignedNativeShellSection) {
        selectedSection = section
    }

    public static func statusItems(
        readiness: PermissionDependencyStatusState,
        recording: RecordingControlState,
        processing: ProcessingState,
        transcript: TranscriptReviewState,
        actions: TranscriptReviewActionsState
    ) -> [DesignedNativeShellStatusItem] {
        [
            DesignedNativeShellStatusItem(
                id: "preflight",
                title: "Preflight",
                value: readinessStatus(readiness),
                tone: readinessTone(readiness)
            ),
            DesignedNativeShellStatusItem(
                id: "recording",
                title: "Recording",
                value: recordingStatus(recording),
                tone: recordingTone(recording)
            ),
            DesignedNativeShellStatusItem(
                id: "processing",
                title: "Processing",
                value: processingStatus(processing),
                tone: processingTone(processing)
            ),
            DesignedNativeShellStatusItem(
                id: "transcript",
                title: "Transcript",
                value: transcriptStatus(transcript),
                tone: transcriptTone(transcript)
            ),
            DesignedNativeShellStatusItem(
                id: "actions",
                title: "Export/Delete",
                value: actionStatus(actions),
                tone: actionTone(actions)
            ),
        ]
    }

    public static func artifactRows(from artifacts: [RecordingCommandArtifact]) -> [DesignedNativeShellArtifactRow] {
        let artifactsByType = Dictionary(uniqueKeysWithValues: artifacts.map { ($0.artifactType, $0) })
        return artifactTypes.map { artifactType in
            guard let artifact = artifactsByType[artifactType] else {
                return DesignedNativeShellArtifactRow(
                    artifactType: artifactType,
                    status: "pending",
                    detail: "Pending until recording stops."
                )
            }

            let detail = artifact.degradationReason
                ?? artifact.path
                ?? "Registered by stop_recording."
            return DesignedNativeShellArtifactRow(
                artifactType: artifactType,
                status: artifact.captureStatus,
                detail: detail
            )
        }
    }

    public static func processingSteps(from state: ProcessingState) -> [DesignedNativeShellProcessingStep] {
        [
            DesignedNativeShellProcessingStep(
                id: "normalizedAudio",
                title: "Normalized audio",
                status: normalizedAudioStatus(from: state)
            ),
            DesignedNativeShellProcessingStep(
                id: "transcript",
                title: "Transcript",
                status: state.transcriptStatus ?? "Waiting for processing."
            ),
            DesignedNativeShellProcessingStep(
                id: "speakerLabels",
                title: "Speaker labels",
                status: state.speakerLabelStatus ?? speakerLabelFallbackStatus(from: state)
            ),
            DesignedNativeShellProcessingStep(
                id: "exportReady",
                title: "Export readiness",
                status: exportReadinessStatus(from: state)
            ),
        ]
    }

    public static func recordingSetupText(
        captureSystemAudio: Bool,
        captureMicrophoneAudio: Bool
    ) -> String {
        switch (captureSystemAudio, captureMicrophoneAudio) {
        case (true, true):
            return "Capture target: screen. System audio and microphone capture are requested through the recording command client."
        case (true, false):
            return "Capture target: screen. System audio capture is requested; microphone capture is not requested for this run."
        case (false, true):
            return "Capture target: screen. Microphone capture is requested; system audio capture is not requested for this run."
        case (false, false):
            return "Capture target: screen. Audio capture is not requested for this run; unavailable audio artifacts must stay missing with reasons."
        }
    }

    public static let artifactTypes = [
        "screen_video",
        "system_audio",
        "microphone_audio",
        "mixed_audio",
    ]

    private static func readinessStatus(_ state: PermissionDependencyStatusState) -> String {
        switch state.phase {
        case .idle:
            return "Needs check"
        case .checking:
            return "Checking"
        case .ready:
            return "Ready"
        case .blocked:
            return "Blocked"
        case .failed:
            return "Failed"
        }
    }

    private static func readinessTone(_ state: PermissionDependencyStatusState) -> String {
        switch state.phase {
        case .ready:
            return "success"
        case .blocked, .failed:
            return "error"
        case .checking:
            return "warning"
        case .idle:
            return "neutral"
        }
    }

    private static func recordingStatus(_ state: RecordingControlState) -> String {
        switch state.phase {
        case .idle:
            return "Not ready"
        case .ready:
            return "Ready"
        case .starting:
            return "Starting"
        case .recording:
            return "Recording"
        case .stopping:
            return "Saving"
        case .recorded:
            return "Saved"
        case .failed:
            return "Failed"
        }
    }

    private static func recordingTone(_ state: RecordingControlState) -> String {
        switch state.phase {
        case .recording:
            return "recording"
        case .recorded:
            return "success"
        case .failed:
            return "error"
        case .starting, .stopping:
            return "warning"
        case .ready:
            return "success"
        case .idle:
            return "neutral"
        }
    }

    private static func processingStatus(_ state: ProcessingState) -> String {
        switch state.phase {
        case .idle:
            return "Ready"
        case .blocked:
            return "Blocked"
        case .generatingTranscript:
            return "Transcribing"
        case .generatingSpeakerLabels:
            return "Labeling"
        case .completed:
            return "Complete"
        case .degraded:
            return "Transcript-only"
        case .failed:
            return "Failed"
        }
    }

    private static func processingTone(_ state: ProcessingState) -> String {
        switch state.phase {
        case .completed:
            return "success"
        case .degraded:
            return "fallback"
        case .failed, .blocked:
            return "error"
        case .generatingTranscript, .generatingSpeakerLabels:
            return "warning"
        case .idle:
            return "neutral"
        }
    }

    private static func transcriptStatus(_ state: TranscriptReviewState) -> String {
        switch state.contentState {
        case .missing:
            return "Missing"
        case .empty:
            return "Empty"
        case .available:
            return "Available"
        }
    }

    private static func transcriptTone(_ state: TranscriptReviewState) -> String {
        switch state.contentState {
        case .available:
            return state.degradationReason == nil ? "success" : "fallback"
        case .empty:
            return "warning"
        case .missing:
            return "neutral"
        }
    }

    private static func actionStatus(_ state: TranscriptReviewActionsState) -> String {
        if !state.isAvailable {
            return "Unavailable"
        }
        switch state.phase {
        case .ready:
            return "Ready"
        case .copying:
            return "Copying"
        case .exporting:
            return "Exporting"
        case .awaitingDeleteConfirmation:
            return "Confirming"
        case .deleting:
            return "Deleting"
        case .unavailable:
            return "Unavailable"
        }
    }

    private static func actionTone(_ state: TranscriptReviewActionsState) -> String {
        if state.failureSummary != nil {
            return "error"
        }
        switch state.phase {
        case .ready where state.successSummary != nil:
            return "success"
        case .ready:
            return "neutral"
        case .copying, .exporting, .awaitingDeleteConfirmation, .deleting:
            return "warning"
        case .unavailable:
            return "neutral"
        }
    }

    private static func normalizedAudioStatus(from state: ProcessingState) -> String {
        switch state.phase {
        case .idle:
            return "Waiting for a recorded session."
        case .blocked:
            return "Blocked until dependencies are ready."
        case .generatingTranscript, .generatingSpeakerLabels, .completed, .degraded:
            return "Processing input selected through command contract."
        case .failed:
            return "Retained for retry; original media remains protected."
        }
    }

    private static func speakerLabelFallbackStatus(from state: ProcessingState) -> String {
        if let degradationReason = state.degradationReason {
            return "Transcript-only fallback: \(degradationReason)"
        }
        switch state.phase {
        case .blocked:
            return "Blocked until dependencies are ready."
        case .failed:
            return "Waiting for retry."
        default:
            return "Waiting for transcript."
        }
    }

    private static func exportReadinessStatus(from state: ProcessingState) -> String {
        switch state.phase {
        case .completed, .degraded:
            return "Transcript can be reviewed before user-triggered export."
        case .failed:
            return "Export blocked until processing succeeds or transcript is loaded."
        default:
            return "Waiting for transcript."
        }
    }
}
