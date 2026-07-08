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
    func processRunnerUsesFrozenArgumentsWithoutFormatFlagAndDecodesJSON() async throws {
        let fixture = try TranscriptActionProcessRunnerFixture()
        let copyResponse = try await fixture.runner.exportTranscript(
            ExportTranscriptRequest(
                sessionID: "session-actions",
                exportType: .plainText,
                targetPath: nil
            )
        )

        #expect(copyResponse.ok)
        #expect(copyResponse.content == "Process runner copy content.")
        #expect(try fixture.recordedArguments() == [
            "export_transcript",
            "--session-id",
            "session-actions",
            "--export-type",
            "plain_text",
        ])

        let exportResponse = try await fixture.runner.exportTranscript(
            ExportTranscriptRequest(
                sessionID: "session-actions",
                exportType: .markdown,
                targetPath: "/tmp/actions.md"
            )
        )

        #expect(exportResponse.ok)
        #expect(exportResponse.exportPackageID == "export-package-process")
        #expect(exportResponse.targetPath == "/tmp/actions.md")
        #expect(try fixture.recordedArguments() == [
            "export_transcript",
            "--session-id",
            "session-actions",
            "--export-type",
            "markdown",
            "--target-path",
            "/tmp/actions.md",
        ])

        let deleteResponse = try await fixture.runner.deleteSession(
            DeleteSessionRequest(
                sessionID: "session-actions",
                workspaceDir: "/tmp/workspace",
                confirm: true
            )
        )

        #expect(deleteResponse.ok)
        #expect(deleteResponse.deleted == true)
        #expect(deleteResponse.deletedItems == ["artifacts/transcript.json", "logs/processing.log"])
        #expect(deleteResponse.retainedExternalExports == ["/tmp/actions.md"])
        #expect(try fixture.recordedArguments() == [
            "delete_session",
            "--session-id",
            "session-actions",
            "--workspace-dir",
            "/tmp/workspace",
            "--confirm",
            "true",
        ])
        #expect(try fixture.recordedInvocationLines() == [
            "export_transcript --session-id session-actions --export-type plain_text",
            "export_transcript --session-id session-actions --export-type markdown --target-path /tmp/actions.md",
            "delete_session --session-id session-actions --workspace-dir /tmp/workspace --confirm true",
        ])
    }

    @Test
    func processRunnerDecodesStructuredNonzeroExportFailure() async throws {
        let fixture = try TranscriptActionProcessRunnerFixture(script: .structuredExportFailure)
        let response = try await fixture.runner.exportTranscript(
            ExportTranscriptRequest(
                sessionID: "session-actions",
                exportType: .markdown,
                targetPath: "/tmp/actions.md"
            )
        )

        #expect(response.ok == false)
        #expect(response.code?.rawValue == "path_conflict")
        #expect(response.message == "Export target already exists.")
        #expect(response.details == ["stage: export", "target_path: /tmp/actions.md"])
        #expect(try fixture.recordedArguments() == [
            "export_transcript",
            "--session-id",
            "session-actions",
            "--export-type",
            "markdown",
            "--target-path",
            "/tmp/actions.md",
        ])
    }

    @Test
    func processRunnerThrowsSafeBridgeErrorsWithoutStdoutOrStderrSnippets() async throws {
        let nonJSONFixture = try TranscriptActionProcessRunnerFixture(script: .nonJSONExportFailure(exitCode: 3))

        do {
            _ = try await nonJSONFixture.runner.exportTranscript(
                ExportTranscriptRequest(
                    sessionID: "session-actions",
                    exportType: .plainText
                )
            )
            #expect(Bool(false), "Expected processFailed for non-JSON failure.")
        } catch let error as TranscriptActionBridgeError {
            #expect(error.command == .exportTranscript)
            #expect(error.code.rawValue == "path_conflict")
            #expect(error.safeMessage == "Transcript action command failed before returning a contract response.")
            #expect(error.errorDescription?.contains("/Users/jerry") == false)
            #expect(error.errorDescription?.contains("sk-actionrawvalue") == false)
        }

        let invalidJSONFixture = try TranscriptActionProcessRunnerFixture(script: .invalidJSONExportFailure)

        do {
            _ = try await invalidJSONFixture.runner.exportTranscript(
                ExportTranscriptRequest(
                    sessionID: "session-actions",
                    exportType: .plainText
                )
            )
            #expect(Bool(false), "Expected invalidJSON for invalid stdout.")
        } catch let error as TranscriptActionBridgeError {
            #expect(error.command == .exportTranscript)
            #expect(error.code.rawValue == "path_conflict")
            #expect(error.safeMessage == "Transcript action command returned an invalid response.")
            #expect(error.errorDescription?.contains("not json") == false)
            #expect(error.errorDescription?.contains("/Users/jerry") == false)
        }
    }

    @Test
    func processRunnerBridgeFailuresBecomeSafeViewModelErrors() async throws {
        let fixture = try TranscriptActionProcessRunnerFixture(script: .nonJSONExportFailure(exitCode: 3))
        let viewModel = TranscriptReviewActionsViewModel(
            input: actionInput(),
            commandClient: fixture.runner,
            clipboard: TranscriptActionMemoryClipboard(),
            destinationSelector: TranscriptActionStaticDestinationSelector()
        )

        await viewModel.copyTranscript()

        #expect(viewModel.state.statusText == "Copy failed.")
        #expect(viewModel.state.failureSummary?.contains("Transcript action command failed before returning a contract response.") == true)
        #expect(viewModel.state.failureSummary?.contains("path_conflict") == true)
        #expect(viewModel.state.failureSummary?.contains("/Users/jerry") == false)
        #expect(viewModel.state.failureSummary?.contains("sk-actionrawvalue") == false)
    }

    @Test
    func processRunnerDrivenViewModelUsesInjectedClipboardDestinationAndCommandDelete() async throws {
        let fixture = try TranscriptActionProcessRunnerFixture()
        let clipboard = TranscriptActionMemoryClipboard()
        let selector = TranscriptActionStaticDestinationSelector(targetPath: "/tmp/actions.md")
        let viewModel = TranscriptReviewActionsViewModel(
            input: actionInput(),
            commandClient: fixture.runner,
            clipboard: clipboard,
            destinationSelector: selector,
            workspaceDir: "/tmp/workspace"
        )

        await viewModel.copyTranscript()

        #expect(await clipboard.latestContentSnapshot() == "Process runner copy content.")
        #expect(viewModel.state.statusText == "Copy complete.")

        await viewModel.exportTranscript()

        #expect(viewModel.state.statusText == "Export complete.")
        #expect(viewModel.state.successSummary == "Exported markdown transcript to /tmp/actions.md.")

        viewModel.requestDeleteConfirmation()
        await viewModel.confirmDelete()

        #expect(viewModel.state.statusText == "Delete complete.")
        #expect(viewModel.state.successSummary == "Deleted session session-actions. Removed 2 items. Retained 1 external export.")
        #expect(try fixture.recordedInvocationLines() == [
            "export_transcript --session-id session-actions --export-type plain_text",
            "export_transcript --session-id session-actions --export-type markdown --target-path /tmp/actions.md",
            "delete_session --session-id session-actions --workspace-dir /tmp/workspace --confirm true",
        ])
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
    func savePanelDestinationSelectorSuggestsSafeFileNames() {
        #expect(
            TranscriptActionSavePanelDestinationSelector.suggestedFilename(
                for: TranscriptExportDestinationRequest(
                    sessionID: "meeting/actions 2026.07.04",
                    exportType: .markdown
                )
            ) == "meeting-actions-2026.07.04.md"
        )
        #expect(
            TranscriptActionSavePanelDestinationSelector.suggestedFilename(
                for: TranscriptExportDestinationRequest(
                    sessionID: "../",
                    exportType: .plainText
                )
            ) == "meeting-transcript.txt"
        )
        #expect(
            TranscriptActionSavePanelDestinationSelector.suggestedFilename(
                for: TranscriptExportDestinationRequest(
                    sessionID: "session-actions",
                    exportType: .json
                )
            ) == "session-actions.json"
        )
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

    @Test
    func updateInputEnablesActionsAfterProcessingLoadsTranscript() {
        let viewModel = TranscriptReviewActionsViewModel(
            input: TranscriptReviewInput(sessionTitle: "Missing", transcript: nil),
            commandClient: TranscriptActionFakeCommandClient(),
            clipboard: TranscriptActionMemoryClipboard(),
            destinationSelector: TranscriptActionStaticDestinationSelector()
        )

        #expect(viewModel.state.isAvailable == false)

        viewModel.updateInput(actionInput(sessionTitle: "Loaded Transcript"))

        #expect(viewModel.state.isAvailable == true)
        #expect(viewModel.state.phase == .ready)
        #expect(viewModel.state.sessionID == "session-actions")
        #expect(viewModel.state.sessionTitle == "Loaded Transcript")
        #expect(viewModel.state.canCopy == true)
        #expect(viewModel.state.canExport == true)
        #expect(viewModel.state.canRequestDelete == true)
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

private final class TranscriptActionProcessRunnerFixture {
    enum Script {
        case success
        case structuredExportFailure
        case nonJSONExportFailure(exitCode: Int32)
        case invalidJSONExportFailure
    }

    let rootURL: URL
    let workspaceURL: URL
    let scriptURL: URL
    let argsURL: URL
    let invocationsURL: URL
    let runner: TranscriptActionProcessRunner

    init(script: Script = .success) throws {
        rootURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("meeting-assistant-transcript-action-tests-\(UUID().uuidString)", isDirectory: true)
        workspaceURL = rootURL.appendingPathComponent("workspace", isDirectory: true)
        scriptURL = rootURL.appendingPathComponent("meeting-assistant-cli")
        argsURL = rootURL.appendingPathComponent("args.txt")
        invocationsURL = rootURL.appendingPathComponent("invocations.txt")

        try FileManager.default.createDirectory(at: workspaceURL, withIntermediateDirectories: true)
        try Self.script(script).write(to: scriptURL, atomically: true, encoding: .utf8)
        try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: scriptURL.path)

        runner = TranscriptActionProcessRunner(
            executablePath: scriptURL.path,
            environment: [
                "MEETING_ASSISTANT_TEST_ARGS_FILE": argsURL.path,
                "MEETING_ASSISTANT_TEST_INVOCATIONS_FILE": invocationsURL.path,
                "MEETING_ASSISTANT_WORKSPACE": workspaceURL.path,
            ]
        )
    }

    deinit {
        try? FileManager.default.removeItem(at: rootURL)
    }

    func recordedArguments() throws -> [String] {
        try String(contentsOf: argsURL, encoding: .utf8)
            .split(separator: "\n")
            .map(String.init)
    }

    func recordedInvocationLines() throws -> [String] {
        try String(contentsOf: invocationsURL, encoding: .utf8)
            .split(separator: "\n")
            .map(String.init)
    }

    private static func script(_ script: Script) -> String {
        let exportCase: String
        switch script {
        case .success:
            exportCase = """
                if [ "${6:-}" = "--target-path" ]; then
                  cat <<JSON
            {
              "ok": true,
              "request_id": "local-action-export",
              "command": "export_transcript",
              "session_id": "$3",
              "export_type": "$5",
              "export_package_id": "export-package-process",
              "target_path": "$7",
              "warnings": []
            }
            JSON
                else
                  cat <<JSON
            {
              "ok": true,
              "request_id": "local-action-copy",
              "command": "export_transcript",
              "session_id": "$3",
              "export_type": "$5",
              "export_package_id": "export-package-process",
              "content": "Process runner copy content.",
              "warnings": []
            }
            JSON
                fi
            """
        case .structuredExportFailure:
            exportCase = """
                cat <<JSON
            {
              "ok": false,
              "request_id": "local-action-export-failure",
              "command": "export_transcript",
              "session_id": "$3",
              "export_type": "$5",
              "code": "path_conflict",
              "message": "Export target already exists.",
              "details": {
                "stage": "export",
                "target_path": "/tmp/actions.md"
              },
              "warnings": []
            }
            JSON
                exit 3
            """
        case .nonJSONExportFailure(let exitCode):
            exportCase = """
                printf '%s\\n' "export crashed at /Users/jerry/Movies/MeetingAssistant/session with sk-actionrawvalue" >&2
                exit \(exitCode)
            """
        case .invalidJSONExportFailure:
            exportCase = """
                printf '%s\\n' "not json from /Users/jerry/Movies/MeetingAssistant/session sk-actionrawvalue"
                exit 3
            """
        }

        return """
        #!/bin/sh
        : "${MEETING_ASSISTANT_WORKSPACE:?missing workspace}"
        printf '%s\\n' "$@" > "$MEETING_ASSISTANT_TEST_ARGS_FILE"
        printf '%s\\n' "$*" >> "$MEETING_ASSISTANT_TEST_INVOCATIONS_FILE"
        case "$1" in
          export_transcript)
        \(exportCase)
            ;;
          delete_session)
            cat <<JSON
        {
          "ok": true,
          "request_id": "local-action-delete",
          "command": "delete_session",
          "session_id": "$3",
          "deleted": true,
          "deleted_items": ["artifacts/transcript.json", "logs/processing.log"],
          "retained_external_exports": ["/tmp/actions.md"],
          "warnings": []
        }
        JSON
            ;;
          *)
            exit 2
            ;;
        esac
        """
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
