import Foundation
import SwiftUI

public enum TranscriptReviewActionPhase: String, Equatable, Sendable {
    case unavailable
    case ready
    case copying
    case exporting
    case awaitingDeleteConfirmation
    case deleting
}

public struct TranscriptReviewActionsState: Equatable, Sendable {
    public let phase: TranscriptReviewActionPhase
    public let sessionID: String?
    public let sessionTitle: String?
    public let statusText: String
    public let successSummary: String?
    public let failureSummary: String?
    public let technicalDetails: [String]
    public let warnings: [String]
    public let isDeletePromptVisible: Bool
    public let hasTranscript: Bool

    public init(
        phase: TranscriptReviewActionPhase,
        sessionID: String?,
        sessionTitle: String?,
        statusText: String,
        successSummary: String?,
        failureSummary: String?,
        technicalDetails: [String] = [],
        warnings: [String],
        isDeletePromptVisible: Bool,
        hasTranscript: Bool = true
    ) {
        self.phase = phase
        self.sessionID = sessionID
        self.sessionTitle = sessionTitle
        self.statusText = statusText
        self.successSummary = successSummary
        self.failureSummary = failureSummary
        self.technicalDetails = technicalDetails
        self.warnings = warnings
        self.isDeletePromptVisible = isDeletePromptVisible
        self.hasTranscript = hasTranscript
    }

    public var isAvailable: Bool {
        sessionID != nil && phase != .unavailable
    }

    public var isBusy: Bool {
        phase == .copying || phase == .exporting || phase == .deleting
    }

    public var canCopy: Bool {
        isAvailable && hasTranscript && !isBusy && !isDeletePromptVisible
    }

    public var canExport: Bool {
        isAvailable && hasTranscript && !isBusy && !isDeletePromptVisible
    }

    public var canRequestDelete: Bool {
        isAvailable && !isBusy && !isDeletePromptVisible
    }

    public var canConfirmDelete: Bool {
        isDeletePromptVisible && !isBusy
    }

    public var canCancelDelete: Bool {
        isDeletePromptVisible && !isBusy
    }

    public var deletePromptText: String? {
        guard isDeletePromptVisible, let sessionID else {
            return nil
        }

        let titleText = sessionTitle.map { "\($0) (\(sessionID))" } ?? sessionID
        return "Delete session \(titleText)? This removes application-managed files in the session workspace. External exports are retained."
    }

    public static let unavailable = TranscriptReviewActionsState(
        phase: .unavailable,
        sessionID: nil,
        sessionTitle: nil,
        statusText: "Transcript actions are unavailable until a transcript is loaded.",
        successSummary: nil,
        failureSummary: nil,
        warnings: [],
        isDeletePromptVisible: false,
        hasTranscript: false
    )
}

private enum TranscriptExportResponseExpectation: Equatable, Sendable {
    case copyContent
    case fileExport(targetPath: String)
}

@MainActor
public final class TranscriptReviewActionsViewModel: ObservableObject {
    @Published public private(set) var state: TranscriptReviewActionsState

    private let commandClient: any TranscriptActionCommandClient
    private let clipboard: any TranscriptClipboardWriting
    private let destinationSelector: any TranscriptExportDestinationSelecting
    private let workspaceDir: String?
    private var sessionRevision: UInt = 0

    public init(
        input: TranscriptReviewInput,
        commandClient: any TranscriptActionCommandClient = TranscriptActionFakeCommandClient(),
        clipboard: any TranscriptClipboardWriting = TranscriptActionMemoryClipboard(),
        destinationSelector: any TranscriptExportDestinationSelecting = TranscriptActionStaticDestinationSelector(),
        workspaceDir: String? = nil
    ) {
        self.commandClient = commandClient
        self.clipboard = clipboard
        self.destinationSelector = destinationSelector
        self.workspaceDir = workspaceDir

        state = Self.initialState(input: input)
    }

    public func updateInput(_ input: TranscriptReviewInput) {
        guard let transcript = input.transcript else {
            clearSession()
            return
        }

        updateSession(
            sessionID: transcript.sessionID,
            sessionTitle: input.sessionTitle,
            transcript: transcript
        )
    }

    public func updateSession(
        sessionID: String?,
        sessionTitle: String?,
        transcript: TranscriptReviewTranscript?,
        preservingFailureFeedback: Bool = false
    ) {
        let previousState = state
        sessionRevision &+= 1

        guard let sessionID = sessionID?.trimmingCharacters(in: .whitespacesAndNewlines),
              !sessionID.isEmpty
        else {
            state = .unavailable
            return
        }

        let hasMatchingTranscript = transcript?.sessionID == sessionID
        let preservesFailure = preservingFailureFeedback
            && previousState.sessionID == sessionID
            && previousState.failureSummary != nil
        state = TranscriptReviewActionsState(
            phase: .ready,
            sessionID: sessionID,
            sessionTitle: sessionTitle,
            statusText: preservesFailure
                ? previousState.statusText
                : (hasMatchingTranscript
                    ? "Transcript actions are ready."
                    : "Session actions are ready. Load a transcript to copy or export it."),
            successSummary: nil,
            failureSummary: preservesFailure ? previousState.failureSummary : nil,
            technicalDetails: preservesFailure ? previousState.technicalDetails : [],
            warnings: [],
            isDeletePromptVisible: false,
            hasTranscript: hasMatchingTranscript
        )
    }

    public func reportDeleteReconciliationFailure() {
        guard state.sessionID != nil else {
            return
        }
        setState(
            phase: .ready,
            statusText: "Delete failed.",
            successSummary: nil,
            failureSummary: "Delete failed: The meeting is still present in the refreshed workspace.",
            warnings: [],
            isDeletePromptVisible: false
        )
    }

    public func clearSession() {
        sessionRevision &+= 1
        state = .unavailable
    }

    private static func initialState(input: TranscriptReviewInput) -> TranscriptReviewActionsState {
        guard let sessionID = input.transcript?.sessionID else {
            return .unavailable
        }

        return TranscriptReviewActionsState(
            phase: .ready,
            sessionID: sessionID,
            sessionTitle: input.sessionTitle,
            statusText: "Transcript actions are ready.",
            successSummary: nil,
            failureSummary: nil,
            warnings: [],
            isDeletePromptVisible: false,
            hasTranscript: true
        )
    }

    public func copyTranscript() async {
        guard let sessionID = state.sessionID, state.canCopy else {
            return
        }
        let revision = sessionRevision

        setState(
            phase: .copying,
            statusText: "Copying transcript...",
            successSummary: nil,
            failureSummary: nil,
            warnings: [],
            isDeletePromptVisible: false
        )

        do {
            let response = try await commandClient.exportTranscript(
                ExportTranscriptRequest(
                    sessionID: sessionID,
                    exportType: .plainText,
                    targetPath: nil
                )
            )
            try validateExportResponse(
                response,
                expectedSessionID: sessionID,
                expectedExportType: .plainText,
                expectation: .copyContent
            )
            guard isCurrentSession(sessionID, revision: revision) else {
                return
            }
            guard let content = response.content, !content.isEmpty else {
                throw TranscriptActionCommandFailure(
                    command: .exportTranscript,
                    code: nil,
                    message: "Transcript copy did not return content."
                )
            }

            await clipboard.writeTranscript(content)
            guard isCurrentSession(sessionID, revision: revision) else {
                return
            }
            setState(
                phase: .ready,
                statusText: "Copy complete.",
                successSummary: "Transcript copied.",
                failureSummary: nil,
                warnings: response.warnings,
                technicalDetails: ["Session ID: \(sessionID)"],
                isDeletePromptVisible: false
            )
        } catch {
            fail(
                operation: "Copy",
                error: error,
                expectedSessionID: sessionID,
                expectedRevision: revision
            )
        }
    }

    public func exportTranscript() async {
        guard let sessionID = state.sessionID, state.canExport else {
            return
        }
        let revision = sessionRevision

        let exportType = TranscriptExportType.markdown
        let destination = await destinationSelector.destination(
            for: TranscriptExportDestinationRequest(
                sessionID: sessionID,
                exportType: exportType
            )
        )

        guard isCurrentSession(sessionID, revision: revision) else {
            return
        }

        guard let targetPath = destination, !targetPath.isEmpty else {
            setState(
                phase: .ready,
                statusText: "Export cancelled. No command was sent.",
                successSummary: nil,
                failureSummary: state.failureSummary,
                warnings: [],
                technicalDetails: state.technicalDetails,
                isDeletePromptVisible: false
            )
            return
        }

        setState(
            phase: .exporting,
            statusText: "Exporting transcript...",
            successSummary: nil,
            failureSummary: nil,
            warnings: [],
            isDeletePromptVisible: false
        )

        do {
            let response = try await commandClient.exportTranscript(
                ExportTranscriptRequest(
                    sessionID: sessionID,
                    exportType: exportType,
                    targetPath: targetPath
                )
            )
            try validateExportResponse(
                response,
                expectedSessionID: sessionID,
                expectedExportType: exportType,
                expectation: .fileExport(targetPath: targetPath)
            )
            guard isCurrentSession(sessionID, revision: revision) else {
                return
            }

            let resolvedTargetPath = response.targetPath ?? targetPath
            setState(
                phase: .ready,
                statusText: "Export complete.",
                successSummary: "Transcript exported.",
                failureSummary: nil,
                warnings: response.warnings,
                technicalDetails: [
                    "Session ID: \(sessionID)",
                    "Export path: \(resolvedTargetPath)",
                ],
                isDeletePromptVisible: false
            )
        } catch {
            fail(
                operation: "Export",
                error: error,
                expectedSessionID: sessionID,
                expectedRevision: revision
            )
        }
    }

    public func requestDeleteConfirmation() {
        guard state.canRequestDelete else {
            return
        }

        setState(
            phase: .awaitingDeleteConfirmation,
            statusText: "Confirm delete before removing the session.",
            successSummary: nil,
            failureSummary: state.failureSummary,
            warnings: [],
            technicalDetails: state.technicalDetails,
            isDeletePromptVisible: true
        )
    }

    public func cancelDelete() {
        guard state.canCancelDelete else {
            return
        }

        setState(
            phase: .ready,
            statusText: "Delete cancelled. No command was sent.",
            successSummary: nil,
            failureSummary: state.failureSummary,
            warnings: [],
            technicalDetails: state.technicalDetails,
            isDeletePromptVisible: false
        )
    }

    public func dismissFeedback() {
        guard state.isAvailable, !state.isBusy, !state.isDeletePromptVisible else {
            return
        }
        setState(
            phase: .ready,
            statusText: state.hasTranscript
                ? "Transcript actions are ready."
                : "Session actions are ready. Load a transcript to copy or export it.",
            successSummary: nil,
            failureSummary: nil,
            warnings: [],
            isDeletePromptVisible: false
        )
    }

    @discardableResult
    public func confirmDelete() async -> String? {
        guard let sessionID = state.sessionID, state.canConfirmDelete else {
            return nil
        }
        let revision = sessionRevision

        setState(
            phase: .deleting,
            statusText: "Deleting session...",
            successSummary: nil,
            failureSummary: nil,
            warnings: [],
            isDeletePromptVisible: true
        )

        do {
            let response = try await commandClient.deleteSession(
                DeleteSessionRequest(
                    sessionID: sessionID,
                    workspaceDir: workspaceDir,
                    confirm: true
                )
            )
            try validateDeleteResponse(response, expectedSessionID: sessionID)

            guard isCurrentSession(sessionID, revision: revision) else {
                return nil
            }
            clearSession()
            return sessionID
        } catch {
            fail(
                operation: "Delete",
                error: error,
                keepPromptVisible: false,
                expectedSessionID: sessionID,
                expectedRevision: revision
            )
            return nil
        }
    }

    private func validateExportResponse(
        _ response: ExportTranscriptResponse,
        expectedSessionID: String,
        expectedExportType: TranscriptExportType,
        expectation: TranscriptExportResponseExpectation
    ) throws {
        guard response.ok else {
            throw TranscriptActionCommandFailure(response: response)
        }
        guard response.command == .exportTranscript,
              response.sessionID == expectedSessionID,
              response.exportType == expectedExportType
        else {
            throw TranscriptActionCommandFailure(
                command: .exportTranscript,
                code: nil,
                message: "Transcript export returned an incomplete response."
            )
        }

        switch expectation {
        case .copyContent:
            guard let content = response.content, !content.isEmpty else {
                throw TranscriptActionCommandFailure(
                    command: .exportTranscript,
                    code: nil,
                    message: "Transcript copy did not return content."
                )
            }
        case .fileExport(let targetPath):
            guard let exportPackageID = response.exportPackageID, !exportPackageID.isEmpty else {
                throw TranscriptActionCommandFailure(
                    command: .exportTranscript,
                    code: nil,
                    message: "Transcript export returned an incomplete response."
                )
            }
            let hasReturnedTargetPath = response.targetPath.map { !$0.isEmpty } ?? false
            let hasReturnedContent = response.content.map { !$0.isEmpty } ?? false
            guard hasReturnedTargetPath || hasReturnedContent else {
                throw TranscriptActionCommandFailure(
                    command: .exportTranscript,
                    code: nil,
                    message: "Transcript export returned an incomplete response."
                )
            }
            if let responseTargetPath = response.targetPath {
                guard responseTargetPath == targetPath else {
                    throw TranscriptActionCommandFailure(
                        command: .exportTranscript,
                        code: nil,
                        message: "Transcript export returned an incomplete response."
                    )
                }
            }
        }
    }

    private func validateDeleteResponse(
        _ response: DeleteSessionResponse,
        expectedSessionID: String
    ) throws {
        guard response.ok else {
            throw TranscriptActionCommandFailure(response: response)
        }
        guard response.command == .deleteSession,
              response.sessionID == expectedSessionID,
              response.deleted == true,
              response.hasDeletedItemsField,
              response.hasRetainedExternalExportsField
        else {
            throw TranscriptActionCommandFailure(
                command: .deleteSession,
                code: nil,
                message: "Delete session returned an incomplete response."
            )
        }
    }

    private func fail(
        operation: String,
        error: Error,
        keepPromptVisible: Bool = false,
        expectedSessionID: String,
        expectedRevision: UInt
    ) {
        guard isCurrentSession(expectedSessionID, revision: expectedRevision) else {
            return
        }

        let summary: String
        let technicalDetails: [String]
        if let failure = error as? TranscriptActionCommandFailure {
            summary = "\(operation) failed: \(failure.message.processingSafeDisplayText(fallback: "The requested action could not be completed."))"
            technicalDetails = failure.code.map { ["Error code: \($0.rawValue)"] } ?? []
        } else {
            summary = "\(operation) failed: \(error.localizedDescription.processingSafeDisplayText(fallback: "The requested action could not be completed."))"
            technicalDetails = []
        }

        setState(
            phase: .ready,
            statusText: "\(operation) failed.",
            successSummary: nil,
            failureSummary: summary,
            warnings: [],
            technicalDetails: technicalDetails,
            isDeletePromptVisible: keepPromptVisible
        )
    }

    private func setState(
        phase: TranscriptReviewActionPhase,
        statusText: String,
        successSummary: String?,
        failureSummary: String?,
        warnings: [String],
        technicalDetails: [String] = [],
        isDeletePromptVisible: Bool
    ) {
        state = TranscriptReviewActionsState(
            phase: phase,
            sessionID: state.sessionID,
            sessionTitle: state.sessionTitle,
            statusText: statusText,
            successSummary: successSummary,
            failureSummary: failureSummary,
            technicalDetails: technicalDetails,
            warnings: warnings,
            isDeletePromptVisible: isDeletePromptVisible,
            hasTranscript: state.hasTranscript
        )
    }

    private func isCurrentSession(_ sessionID: String, revision: UInt) -> Bool {
        sessionRevision == revision && state.sessionID == sessionID
    }
}
