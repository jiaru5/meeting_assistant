import Foundation
import Testing
@testable import MeetingAssistantNative

@Suite("Transcript review actions")
@MainActor
struct TranscriptReviewActionsViewModelTests {
    @Test
    func decodesFrozenExportAndDeleteResponses() throws {
        let exportJSON = """
        {
          "ok": true,
          "request_id": "local-export-1",
          "command": "export_transcript",
          "session_id": "session-actions",
          "export_type": "plain_text",
          "export_package_id": "export-package-1",
          "content": "Copyable transcript text.",
          "warnings": ["copy warning"],
          "ignored_extra": "ignored"
        }
        """.data(using: .utf8)!
        let deleteJSON = """
        {
          "ok": true,
          "request_id": "local-delete-1",
          "command": "delete_session",
          "session_id": "session-actions",
          "deleted": true,
          "deleted_items": ["artifacts/transcript.json"],
          "retained_external_exports": ["/tmp/export.md"],
          "warnings": [],
          "ignored_extra": "ignored"
        }
        """.data(using: .utf8)!

        let exportResponse = try JSONDecoder().decode(ExportTranscriptResponse.self, from: exportJSON)
        let deleteResponse = try JSONDecoder().decode(DeleteSessionResponse.self, from: deleteJSON)

        #expect(exportResponse.command == .exportTranscript)
        #expect(exportResponse.sessionID == "session-actions")
        #expect(exportResponse.exportType == .plainText)
        #expect(exportResponse.content == "Copyable transcript text.")
        #expect(exportResponse.warnings == ["copy warning"])
        #expect(deleteResponse.command == .deleteSession)
        #expect(deleteResponse.sessionID == "session-actions")
        #expect(deleteResponse.deleted == true)
        #expect(deleteResponse.deletedItems == ["artifacts/transcript.json"])
        #expect(deleteResponse.retainedExternalExports == ["/tmp/export.md"])
    }

    @Test
    func decodesObjectShapedFailureDetailsWithoutHidingCodeOrMessage() throws {
        let exportJSON = """
        {
          "ok": false,
          "request_id": "local-export-failure-1",
          "command": "export_transcript",
          "session_id": "session-actions",
          "export_type": "markdown",
          "code": "path_conflict",
          "message": "Export target already exists.",
          "details": {
            "reason": "exists",
            "target_path": "/tmp/actions.md"
          },
          "warnings": []
        }
        """.data(using: .utf8)!
        let deleteJSON = """
        {
          "ok": false,
          "request_id": "local-delete-failure-1",
          "command": "delete_session",
          "session_id": "session-actions",
          "code": "workspace_mismatch",
          "message": "Session path escaped the workspace.",
          "details": {
            "session_id": "session-actions",
            "workspace_dir": "/tmp/workspace"
          },
          "warnings": []
        }
        """.data(using: .utf8)!

        let exportResponse = try JSONDecoder().decode(ExportTranscriptResponse.self, from: exportJSON)
        let deleteResponse = try JSONDecoder().decode(DeleteSessionResponse.self, from: deleteJSON)
        let exportFailure = TranscriptActionCommandFailure(response: exportResponse)
        let deleteFailure = TranscriptActionCommandFailure(response: deleteResponse)

        #expect(exportFailure.code?.rawValue == "path_conflict")
        #expect(exportFailure.message == "Export target already exists.")
        #expect(exportFailure.details == ["reason: exists", "target_path: /tmp/actions.md"])
        #expect(exportFailure.errorDescription == "Export target already exists. (path_conflict)")
        #expect(deleteFailure.code?.rawValue == "workspace_mismatch")
        #expect(deleteFailure.message == "Session path escaped the workspace.")
        #expect(deleteFailure.details == ["session_id: session-actions", "workspace_dir: /tmp/workspace"])
        #expect(deleteFailure.errorDescription == "Session path escaped the workspace. (workspace_mismatch)")
    }

    @Test
    func copySuccessUsesExportWithNilTargetAndWritesInjectedClipboard() async {
        let client = TranscriptActionFakeCommandClient(
            exportScript: .success(content: "Copyable transcript text.")
        )
        let clipboard = TranscriptActionMemoryClipboard()
        let viewModel = TranscriptReviewActionsViewModel(
            input: actionInput(),
            commandClient: client,
            clipboard: clipboard,
            destinationSelector: TranscriptActionStaticDestinationSelector()
        )

        await viewModel.copyTranscript()

        let exportRequests = await client.exportRequestSnapshot()
        let latestContent = await clipboard.latestContentSnapshot()

        #expect(exportRequests == [
            ExportTranscriptRequest(
                sessionID: "session-actions",
                exportType: .plainText,
                targetPath: nil
            ),
        ])
        #expect(latestContent == "Copyable transcript text.")
        #expect(viewModel.state.statusText == "Copy complete.")
        #expect(viewModel.state.successSummary == "Copied plain text transcript for session session-actions.")
        #expect(viewModel.state.failureSummary == nil)
    }

    @Test
    func copyFailureDoesNotWriteInjectedClipboard() async {
        let client = TranscriptActionFakeCommandClient(
            exportScript: .failure(
                code: "artifact_missing",
                message: "Transcript artifact is missing."
            )
        )
        let clipboard = TranscriptActionMemoryClipboard()
        let viewModel = TranscriptReviewActionsViewModel(
            input: actionInput(),
            commandClient: client,
            clipboard: clipboard,
            destinationSelector: TranscriptActionStaticDestinationSelector()
        )

        await viewModel.copyTranscript()

        let exportRequests = await client.exportRequestSnapshot()
        let latestContent = await clipboard.latestContentSnapshot()

        #expect(exportRequests.count == 1)
        #expect(latestContent == nil)
        #expect(viewModel.state.statusText == "Copy failed.")
        #expect(viewModel.state.failureSummary == "Copy failed: Transcript artifact is missing. (artifact_missing)")
    }

    @Test
    func copySuccessWithoutContentFailsAndDoesNotWriteInjectedClipboard() async {
        let client = TranscriptActionFakeCommandClient(
            exportScript: .success(content: nil)
        )
        let clipboard = TranscriptActionMemoryClipboard()
        let viewModel = TranscriptReviewActionsViewModel(
            input: actionInput(),
            commandClient: client,
            clipboard: clipboard,
            destinationSelector: TranscriptActionStaticDestinationSelector()
        )

        await viewModel.copyTranscript()

        let exportRequests = await client.exportRequestSnapshot()
        let latestContent = await clipboard.latestContentSnapshot()

        #expect(exportRequests.count == 1)
        #expect(latestContent == nil)
        #expect(viewModel.state.statusText == "Copy failed.")
        #expect(viewModel.state.failureSummary == "Copy failed: Transcript copy did not return content.")
    }

    @Test
    func copyShowsUserTriggeredOperationStateWhileCommandIsRunning() async {
        let client = TranscriptActionFakeCommandClient(
            exportScript: .success(content: "Delayed content."),
            responseDelayNanoseconds: 150_000_000
        )
        let viewModel = TranscriptReviewActionsViewModel(
            input: actionInput(),
            commandClient: client,
            clipboard: TranscriptActionMemoryClipboard(),
            destinationSelector: TranscriptActionStaticDestinationSelector()
        )

        let task = Task {
            await viewModel.copyTranscript()
        }
        await Task.yield()

        #expect(viewModel.state.phase == .copying)
        #expect(viewModel.state.statusText == "Copying transcript...")

        await task.value
    }

    @Test
    func exportSuccessUsesInjectedDestination() async {
        let client = TranscriptActionFakeCommandClient(
            exportScript: .success(exportPackageID: "export-package-actions")
        )
        let selector = TranscriptActionStaticDestinationSelector(targetPath: "/tmp/actions.md")
        let viewModel = TranscriptReviewActionsViewModel(
            input: actionInput(),
            commandClient: client,
            clipboard: TranscriptActionMemoryClipboard(),
            destinationSelector: selector
        )

        await viewModel.exportTranscript()

        let destinationRequests = await selector.requestSnapshot()
        let exportRequests = await client.exportRequestSnapshot()

        #expect(destinationRequests == [
            TranscriptExportDestinationRequest(
                sessionID: "session-actions",
                exportType: .markdown
            ),
        ])
        #expect(exportRequests == [
            ExportTranscriptRequest(
                sessionID: "session-actions",
                exportType: .markdown,
                targetPath: "/tmp/actions.md"
            ),
        ])
        #expect(viewModel.state.statusText == "Export complete.")
        #expect(viewModel.state.successSummary == "Exported markdown transcript to /tmp/actions.md.")
    }

    @Test
    func exportSuccessMissingPackageIDFails() async {
        let client = TranscriptActionFakeCommandClient(
            exportScript: .success(exportPackageID: nil)
        )
        let viewModel = TranscriptReviewActionsViewModel(
            input: actionInput(),
            commandClient: client,
            clipboard: TranscriptActionMemoryClipboard(),
            destinationSelector: TranscriptActionStaticDestinationSelector(targetPath: "/tmp/actions.md")
        )

        await viewModel.exportTranscript()

        let exportRequests = await client.exportRequestSnapshot()

        #expect(exportRequests.count == 1)
        #expect(viewModel.state.statusText == "Export failed.")
        #expect(viewModel.state.successSummary == nil)
        #expect(viewModel.state.failureSummary == "Export failed: Transcript export returned an incomplete response.")
    }

    @Test
    func exportSuccessMissingTargetPathAndContentFails() async {
        let client = TranscriptActionStaticCommandClient(
            exportResponse: ExportTranscriptResponse(
                ok: true,
                requestID: "local-export-missing-target-and-content",
                sessionID: "session-actions",
                exportType: .markdown,
                exportPackageID: "export-package-actions",
                targetPath: nil,
                content: nil
            )
        )
        let viewModel = TranscriptReviewActionsViewModel(
            input: actionInput(),
            commandClient: client,
            clipboard: TranscriptActionMemoryClipboard(),
            destinationSelector: TranscriptActionStaticDestinationSelector(targetPath: "/tmp/actions.md")
        )

        await viewModel.exportTranscript()

        let exportRequests = await client.exportRequestSnapshot()

        #expect(exportRequests == [
            ExportTranscriptRequest(
                sessionID: "session-actions",
                exportType: .markdown,
                targetPath: "/tmp/actions.md"
            ),
        ])
        #expect(viewModel.state.statusText == "Export failed.")
        #expect(viewModel.state.successSummary == nil)
        #expect(viewModel.state.failureSummary == "Export failed: Transcript export returned an incomplete response.")
    }

    @Test
    func exportCancelDoesNotCallExportCommand() async {
        let client = TranscriptActionFakeCommandClient()
        let selector = TranscriptActionStaticDestinationSelector(targetPath: nil)
        let viewModel = TranscriptReviewActionsViewModel(
            input: actionInput(),
            commandClient: client,
            clipboard: TranscriptActionMemoryClipboard(),
            destinationSelector: selector
        )

        await viewModel.exportTranscript()

        let destinationRequests = await selector.requestSnapshot()
        let exportRequests = await client.exportRequestSnapshot()

        #expect(destinationRequests.count == 1)
        #expect(exportRequests.isEmpty)
        #expect(viewModel.state.statusText == "Export cancelled. No command was sent.")
    }

    @Test
    func exportFailureShowsPersistentFailureSummary() async {
        let client = TranscriptActionFakeCommandClient(
            exportScript: .failure(
                code: "path_conflict",
                message: "Export target already exists."
            )
        )
        let viewModel = TranscriptReviewActionsViewModel(
            input: actionInput(),
            commandClient: client,
            clipboard: TranscriptActionMemoryClipboard(),
            destinationSelector: TranscriptActionStaticDestinationSelector(targetPath: "/tmp/actions.md")
        )

        await viewModel.exportTranscript()

        let exportRequests = await client.exportRequestSnapshot()

        #expect(exportRequests.count == 1)
        #expect(viewModel.state.statusText == "Export failed.")
        #expect(viewModel.state.failureSummary == "Export failed: Export target already exists. (path_conflict)")
    }

    @Test
    func deleteCancelDoesNotCallDeleteCommand() async {
        let client = TranscriptActionFakeCommandClient()
        let viewModel = TranscriptReviewActionsViewModel(
            input: actionInput(sessionTitle: "Action Transcript"),
            commandClient: client,
            clipboard: TranscriptActionMemoryClipboard(),
            destinationSelector: TranscriptActionStaticDestinationSelector()
        )

        viewModel.requestDeleteConfirmation()
        #expect(viewModel.state.isDeletePromptVisible)
        #expect(viewModel.state.deletePromptText?.contains("Action Transcript (session-actions)") == true)

        viewModel.cancelDelete()

        let deleteRequests = await client.deleteRequestSnapshot()

        #expect(deleteRequests.isEmpty)
        #expect(viewModel.state.isDeletePromptVisible == false)
        #expect(viewModel.state.statusText == "Delete cancelled. No command was sent.")
    }

    @Test
    func deleteConfirmSendsConfirmTrueAndShowsSuccessSummary() async {
        let client = TranscriptActionFakeCommandClient(
            deleteScript: .success(
                deletedItems: [
                    "artifacts/transcript.json",
                    "logs/processing.log",
                ],
                retainedExternalExports: ["/tmp/export.md"]
            )
        )
        let viewModel = TranscriptReviewActionsViewModel(
            input: actionInput(),
            commandClient: client,
            clipboard: TranscriptActionMemoryClipboard(),
            destinationSelector: TranscriptActionStaticDestinationSelector(),
            workspaceDir: "/tmp/workspace"
        )

        viewModel.requestDeleteConfirmation()
        await viewModel.confirmDelete()

        let deleteRequests = await client.deleteRequestSnapshot()

        #expect(deleteRequests == [
            DeleteSessionRequest(
                sessionID: "session-actions",
                workspaceDir: "/tmp/workspace",
                confirm: true
            ),
        ])
        #expect(viewModel.state.statusText == "Delete complete.")
        #expect(viewModel.state.successSummary == "Deleted session session-actions. Removed 2 items. Retained 1 external export.")
    }

    @Test
    func deleteSuccessMissingDeletedItemsFails() async {
        let client = TranscriptActionStaticCommandClient(
            deleteResponse: DeleteSessionResponse(
                ok: true,
                requestID: "local-delete-missing-deleted-items",
                sessionID: "session-actions",
                deleted: true,
                deletedItems: [],
                retainedExternalExports: [],
                hasDeletedItemsField: false,
                hasRetainedExternalExportsField: true
            )
        )
        let viewModel = TranscriptReviewActionsViewModel(
            input: actionInput(),
            commandClient: client,
            clipboard: TranscriptActionMemoryClipboard(),
            destinationSelector: TranscriptActionStaticDestinationSelector()
        )

        viewModel.requestDeleteConfirmation()
        await viewModel.confirmDelete()

        let deleteRequests = await client.deleteRequestSnapshot()

        #expect(deleteRequests.count == 1)
        #expect(viewModel.state.statusText == "Delete failed.")
        #expect(viewModel.state.successSummary == nil)
        #expect(viewModel.state.failureSummary == "Delete failed: Delete session returned an incomplete response.")
    }

    @Test
    func deleteSuccessMissingRetainedExternalExportsFails() async {
        let client = TranscriptActionStaticCommandClient(
            deleteResponse: DeleteSessionResponse(
                ok: true,
                requestID: "local-delete-missing-retained-exports",
                sessionID: "session-actions",
                deleted: true,
                deletedItems: [],
                retainedExternalExports: [],
                hasDeletedItemsField: true,
                hasRetainedExternalExportsField: false
            )
        )
        let viewModel = TranscriptReviewActionsViewModel(
            input: actionInput(),
            commandClient: client,
            clipboard: TranscriptActionMemoryClipboard(),
            destinationSelector: TranscriptActionStaticDestinationSelector()
        )

        viewModel.requestDeleteConfirmation()
        await viewModel.confirmDelete()

        let deleteRequests = await client.deleteRequestSnapshot()

        #expect(deleteRequests.count == 1)
        #expect(viewModel.state.statusText == "Delete failed.")
        #expect(viewModel.state.successSummary == nil)
        #expect(viewModel.state.failureSummary == "Delete failed: Delete session returned an incomplete response.")
    }

    @Test
    func deleteFailureSummaryPersistsAcrossPromptAndCancel() async {
        let client = TranscriptActionFakeCommandClient(
            deleteScript: .failure(
                code: "path_conflict",
                message: "Session path escaped the workspace."
            )
        )
        let viewModel = TranscriptReviewActionsViewModel(
            input: actionInput(),
            commandClient: client,
            clipboard: TranscriptActionMemoryClipboard(),
            destinationSelector: TranscriptActionStaticDestinationSelector()
        )

        viewModel.requestDeleteConfirmation()
        await viewModel.confirmDelete()

        let deleteRequests = await client.deleteRequestSnapshot()

        #expect(deleteRequests == [
            DeleteSessionRequest(
                sessionID: "session-actions",
                workspaceDir: nil,
                confirm: true
            ),
        ])
        #expect(viewModel.state.statusText == "Delete failed.")
        #expect(viewModel.state.failureSummary == "Delete failed: Session path escaped the workspace. (path_conflict)")

        viewModel.requestDeleteConfirmation()
        viewModel.cancelDelete()

        #expect(viewModel.state.failureSummary == "Delete failed: Session path escaped the workspace. (path_conflict)")
    }

    @Test
    func exposesStableAccessibilityIdentifiers() {
        #expect(TranscriptActionAccessibilityID.heading == "ma.transcriptAction.heading")
        #expect(TranscriptActionAccessibilityID.status == "ma.transcriptAction.status")
        #expect(TranscriptActionAccessibilityID.copyButton == "ma.transcriptAction.copyButton")
        #expect(TranscriptActionAccessibilityID.exportButton == "ma.transcriptAction.exportButton")
        #expect(TranscriptActionAccessibilityID.deleteButton == "ma.transcriptAction.deleteButton")
        #expect(TranscriptActionAccessibilityID.successSummary == "ma.transcriptAction.success")
        #expect(TranscriptActionAccessibilityID.errorSummary == "ma.transcriptAction.error")
        #expect(TranscriptActionAccessibilityID.deletePrompt == "ma.transcriptAction.deletePrompt")
        #expect(TranscriptActionAccessibilityID.deletePromptText == "ma.transcriptAction.deletePromptText")
        #expect(TranscriptActionAccessibilityID.deleteConfirmButton == "ma.transcriptAction.deleteConfirmButton")
        #expect(TranscriptActionAccessibilityID.deleteCancelButton == "ma.transcriptAction.deleteCancelButton")
    }

    @Test
    func unavailableWithoutTranscriptContextDoesNotSendCommands() async {
        let client = TranscriptActionFakeCommandClient()
        let viewModel = TranscriptReviewActionsViewModel(
            input: TranscriptReviewInput(sessionTitle: "Missing", transcript: nil),
            commandClient: client,
            clipboard: TranscriptActionMemoryClipboard(),
            destinationSelector: TranscriptActionStaticDestinationSelector()
        )

        await viewModel.copyTranscript()
        await viewModel.exportTranscript()
        viewModel.requestDeleteConfirmation()

        #expect(viewModel.state.isAvailable == false)
        let exportRequests = await client.exportRequestSnapshot()
        let deleteRequests = await client.deleteRequestSnapshot()

        #expect(exportRequests.isEmpty)
        #expect(deleteRequests.isEmpty)
    }

    private func actionInput(sessionTitle: String? = "Action Transcript") -> TranscriptReviewInput {
        TranscriptReviewInput(
            sessionTitle: sessionTitle,
            transcript: TranscriptReviewTranscript(
                id: "transcript-actions",
                sessionID: "session-actions",
                sourceArtifactID: "artifact-normalized-audio",
                status: "succeeded",
                segments: [
                    TranscriptReviewSegment(
                        segmentID: "seg-action",
                        startMS: 0,
                        endMS: 2_000,
                        text: "Transcript action text."
                    ),
                ]
            )
        )
    }
}

private actor TranscriptActionStaticCommandClient: TranscriptActionCommandClient {
    private let exportResponse: ExportTranscriptResponse
    private let deleteResponse: DeleteSessionResponse
    private var exportRequests: [ExportTranscriptRequest] = []
    private var deleteRequests: [DeleteSessionRequest] = []

    init(
        exportResponse: ExportTranscriptResponse = ExportTranscriptResponse(
            ok: false,
            requestID: "unexpected-export-command",
            message: "Unexpected export command."
        ),
        deleteResponse: DeleteSessionResponse = DeleteSessionResponse(
            ok: false,
            requestID: "unexpected-delete-command",
            message: "Unexpected delete command."
        )
    ) {
        self.exportResponse = exportResponse
        self.deleteResponse = deleteResponse
    }

    func exportTranscript(_ request: ExportTranscriptRequest) async throws -> ExportTranscriptResponse {
        exportRequests.append(request)
        return exportResponse
    }

    func deleteSession(_ request: DeleteSessionRequest) async throws -> DeleteSessionResponse {
        deleteRequests.append(request)
        return deleteResponse
    }

    func exportRequestSnapshot() -> [ExportTranscriptRequest] {
        exportRequests
    }

    func deleteRequestSnapshot() -> [DeleteSessionRequest] {
        deleteRequests
    }
}
