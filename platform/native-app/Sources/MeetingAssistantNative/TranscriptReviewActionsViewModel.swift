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
    public let warnings: [String]
    public let isDeletePromptVisible: Bool

    public var isAvailable: Bool {
        sessionID != nil && phase != .unavailable
    }

    public var isBusy: Bool {
        phase == .copying || phase == .exporting || phase == .deleting
    }

    public var canCopy: Bool {
        isAvailable && !isBusy && !isDeletePromptVisible
    }

    public var canExport: Bool {
        isAvailable && !isBusy && !isDeletePromptVisible
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
        isDeletePromptVisible: false
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

        guard let sessionID = input.transcript?.sessionID else {
            state = .unavailable
            return
        }

        state = TranscriptReviewActionsState(
            phase: .ready,
            sessionID: sessionID,
            sessionTitle: input.sessionTitle,
            statusText: "Transcript actions are ready.",
            successSummary: nil,
            failureSummary: nil,
            warnings: [],
            isDeletePromptVisible: false
        )
    }

    public func copyTranscript() async {
        guard let sessionID = state.sessionID, state.canCopy else {
            return
        }

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
            guard let content = response.content, !content.isEmpty else {
                throw TranscriptActionCommandFailure(
                    command: .exportTranscript,
                    code: nil,
                    message: "Transcript copy did not return content."
                )
            }

            await clipboard.writeTranscript(content)
            setState(
                phase: .ready,
                statusText: "Copy complete.",
                successSummary: "Copied plain text transcript for session \(sessionID).",
                failureSummary: nil,
                warnings: response.warnings,
                isDeletePromptVisible: false
            )
        } catch {
            fail(operation: "Copy", error: error)
        }
    }

    public func exportTranscript() async {
        guard let sessionID = state.sessionID, state.canExport else {
            return
        }

        let exportType = TranscriptExportType.markdown
        let destination = await destinationSelector.destination(
            for: TranscriptExportDestinationRequest(
                sessionID: sessionID,
                exportType: exportType
            )
        )

        guard let targetPath = destination, !targetPath.isEmpty else {
            setState(
                phase: .ready,
                statusText: "Export cancelled. No command was sent.",
                successSummary: nil,
                failureSummary: state.failureSummary,
                warnings: [],
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

            let resolvedTargetPath = response.targetPath ?? targetPath
            setState(
                phase: .ready,
                statusText: "Export complete.",
                successSummary: "Exported markdown transcript to \(resolvedTargetPath).",
                failureSummary: nil,
                warnings: response.warnings,
                isDeletePromptVisible: false
            )
        } catch {
            fail(operation: "Export", error: error)
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
            isDeletePromptVisible: false
        )
    }

    public func confirmDelete() async {
        guard let sessionID = state.sessionID, state.canConfirmDelete else {
            return
        }

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

            let deletedCount = response.deletedItems.count
            let retainedCount = response.retainedExternalExports.count
            let itemLabel = deletedCount == 1 ? "item" : "items"
            let exportLabel = retainedCount == 1 ? "external export" : "external exports"
            setState(
                phase: .ready,
                statusText: "Delete complete.",
                successSummary: "Deleted session \(sessionID). Removed \(deletedCount) \(itemLabel). Retained \(retainedCount) \(exportLabel).",
                failureSummary: nil,
                warnings: response.warnings,
                isDeletePromptVisible: false
            )
        } catch {
            fail(operation: "Delete", error: error, keepPromptVisible: false)
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
        keepPromptVisible: Bool = false
    ) {
        let summary: String
        if let failure = error as? TranscriptActionCommandFailure {
            if let code = failure.code {
                summary = "\(operation) failed: \(failure.message) (\(code.rawValue))"
            } else {
                summary = "\(operation) failed: \(failure.message)"
            }
        } else {
            summary = "\(operation) failed: \(error.localizedDescription)"
        }

        setState(
            phase: .ready,
            statusText: "\(operation) failed.",
            successSummary: nil,
            failureSummary: summary,
            warnings: [],
            isDeletePromptVisible: keepPromptVisible
        )
    }

    private func setState(
        phase: TranscriptReviewActionPhase,
        statusText: String,
        successSummary: String?,
        failureSummary: String?,
        warnings: [String],
        isDeletePromptVisible: Bool
    ) {
        state = TranscriptReviewActionsState(
            phase: phase,
            sessionID: state.sessionID,
            sessionTitle: state.sessionTitle,
            statusText: statusText,
            successSummary: successSummary,
            failureSummary: failureSummary,
            warnings: warnings,
            isDeletePromptVisible: isDeletePromptVisible
        )
    }
}
