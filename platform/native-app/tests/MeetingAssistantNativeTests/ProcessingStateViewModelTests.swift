import Foundation
import Testing
@testable import MeetingAssistantNative

@Suite("Processing state")
@MainActor
struct ProcessingStateViewModelTests {
    @Test
    func decodesFrozenTranscriptAndSpeakerResponses() throws {
        let transcriptJSON = """
        {
          "ok": true,
          "request_id": "local-transcript-1",
          "command": "generate_transcript",
          "session_id": "session-processing",
          "transcript_id": "transcript-1",
          "artifact_id": "artifact-transcript-1",
          "segment_count": 2,
          "warnings": ["transcript warning"],
          "ignored_extra": "ignored"
        }
        """.data(using: .utf8)!
        let speakerJSON = """
        {
          "ok": true,
          "request_id": "local-speaker-1",
          "command": "generate_speaker_labels",
          "session_id": "session-processing",
          "transcript_id": "transcript-1",
          "label_status": "transcript_only",
          "speaker_labels_artifact_id": "artifact-speakers-1",
          "degradation_reason": "speaker labeling runtime unavailable",
          "warnings": [],
          "ignored_extra": "ignored"
        }
        """.data(using: .utf8)!

        let transcriptResponse = try ProcessingCommandResponseDecoder.decodeTranscript(transcriptJSON)
        let speakerResponse = try ProcessingCommandResponseDecoder.decodeSpeakerLabels(speakerJSON)

        #expect(transcriptResponse.command == .generateTranscript)
        #expect(transcriptResponse.sessionID == "session-processing")
        #expect(transcriptResponse.transcriptID == "transcript-1")
        #expect(transcriptResponse.artifactID == "artifact-transcript-1")
        #expect(transcriptResponse.segmentCount == 2)
        #expect(transcriptResponse.warnings == ["transcript warning"])
        #expect(speakerResponse.command == .generateSpeakerLabels)
        #expect(speakerResponse.labelStatus == "transcript_only")
        #expect(speakerResponse.speakerLabelsArtifactID == "artifact-speakers-1")
        #expect(speakerResponse.degradationReason == "speaker labeling runtime unavailable")
    }

    @Test
    func decodesObjectShapedFailureDetailsWithoutHidingCodeOrMessage() throws {
        let transcriptJSON = """
        {
          "ok": false,
          "request_id": "local-transcript-failure",
          "command": "generate_transcript",
          "session_id": "session-processing",
          "code": "processing_failed",
          "message": "Transcript adapter failed.",
          "details": {
            "stage": "transcription",
            "attempt": 1
          },
          "warnings": []
        }
        """.data(using: .utf8)!

        let response = try ProcessingCommandResponseDecoder.decodeTranscript(transcriptJSON)
        let failure = ProcessingCommandFailure(response: response)

        #expect(failure.code?.rawValue == "processing_failed")
        #expect(failure.message == "Transcript adapter failed.")
        #expect(failure.details == ["attempt: 1", "stage: transcription"])
        #expect(failure.errorDescription == "Transcript adapter failed. (processing_failed)")
    }

    @Test
    func startRunsTranscriptThenSpeakerLabelsAndCompletes() async {
        let client = ProcessingCommandFakeClient(
            transcriptScript: .success(
                transcriptID: "transcript-processing",
                artifactID: "artifact-transcript-processing",
                segmentCount: 3,
                warnings: ["transcript warning"]
            ),
            speakerLabelsScript: .success(
                labelStatus: "labeled",
                speakerLabelsArtifactID: "artifact-speakers-processing",
                warnings: ["speaker warning"]
            )
        )
        let viewModel = ProcessingStateViewModel(
            commandClient: client,
            readinessState: readyReadinessState(),
            defaultSessionID: "session-processing"
        )

        await viewModel.start()

        let transcriptRequests = await client.transcriptRequestSnapshot()
        let speakerRequests = await client.speakerLabelsRequestSnapshot()

        #expect(transcriptRequests == [
            GenerateTranscriptRequest(sessionID: "session-processing"),
        ])
        #expect(speakerRequests == [
            GenerateSpeakerLabelsRequest(
                sessionID: "session-processing",
                transcriptID: "transcript-processing",
                allowTranscriptOnlyFallback: true
            ),
        ])
        #expect(viewModel.state.phase == .completed)
        #expect(viewModel.state.statusText == "Processing complete.")
        #expect(viewModel.state.transcriptStatus == "Transcript transcript-processing generated with 3 segments.")
        #expect(viewModel.state.speakerLabelStatus == "Speaker labels artifact artifact-speakers-processing is available.")
        #expect(viewModel.state.successSummary == "Generated transcript and speaker labels for session session-processing.")
        #expect(viewModel.state.warnings == ["transcript warning", "speaker warning"])
    }

    @Test
    func transcriptOnlyFallbackRequiresReasonAndShowsDegradedState() async {
        let client = ProcessingCommandFakeClient(
            transcriptScript: .success(transcriptID: "transcript-processing"),
            speakerLabelsScript: .success(
                labelStatus: "transcript_only",
                speakerLabelsArtifactID: "artifact-speakers-processing",
                degradationReason: "speaker labeling runtime unavailable"
            )
        )
        let viewModel = ProcessingStateViewModel(
            commandClient: client,
            readinessState: readyReadinessState(),
            defaultSessionID: "session-processing"
        )

        await viewModel.start()

        #expect(viewModel.state.phase == .degraded)
        #expect(viewModel.state.statusText == "Processing completed with transcript-only speaker labels.")
        #expect(viewModel.state.degradationReason == "speaker labeling runtime unavailable")
        #expect(viewModel.state.speakerLabelStatus == "Speaker labels degraded: speaker labeling runtime unavailable")
        #expect(viewModel.state.errorMessage == nil)
    }

    @Test
    func transcriptOnlyFallbackWithoutReasonFailsAsInvalidResponse() async {
        let client = ProcessingCommandFakeClient(
            transcriptScript: .success(transcriptID: "transcript-processing"),
            speakerLabelsScript: .success(
                labelStatus: "transcript_only",
                speakerLabelsArtifactID: "artifact-speakers-processing",
                degradationReason: nil
            )
        )
        let viewModel = ProcessingStateViewModel(
            commandClient: client,
            readinessState: readyReadinessState(),
            defaultSessionID: "session-processing"
        )

        await viewModel.start()

        #expect(viewModel.state.phase == .failed)
        #expect(viewModel.state.errorMessage == "generate_speaker_labels returned transcript-only without a degradation reason.")
        #expect(viewModel.canRetry)
    }

    @Test
    func failureSurfacesCodeMessageDetailsAndRetryReplaysLastRequest() async {
        let client = ProcessingCommandFakeClient(
            transcriptScript: .failure(
                code: "processing_failed",
                message: "Transcript adapter failed.",
                details: ["adapter exited with 5"]
            )
        )
        let viewModel = ProcessingStateViewModel(
            commandClient: client,
            readinessState: readyReadinessState()
        )

        await viewModel.start(
            sessionID: "session-processing",
            sourceArtifactID: "artifact-source",
            language: "zh",
            runtime: .whisperCpp
        )

        #expect(viewModel.state.phase == .failed)
        #expect(viewModel.state.errorCode?.rawValue == "processing_failed")
        #expect(viewModel.state.errorMessage == "Transcript adapter failed.")
        #expect(viewModel.state.errorDetails == ["adapter exited with 5"])
        #expect(viewModel.canRetry)

        await viewModel.retry()

        let transcriptRequests = await client.transcriptRequestSnapshot()
        #expect(transcriptRequests == [
            GenerateTranscriptRequest(
                sessionID: "session-processing",
                sourceArtifactID: "artifact-source",
                language: "zh",
                runtime: .whisperCpp
            ),
            GenerateTranscriptRequest(
                sessionID: "session-processing",
                sourceArtifactID: "artifact-source",
                language: "zh",
                runtime: .whisperCpp
            ),
        ])
    }

    @Test
    func failureDisplayRedactsUnsafeMessageDetailsAndWarningsWithoutChangingCode() async {
        let client = ProcessingCommandFakeClient(
            transcriptScript: .failure(
                code: "path_conflict",
                message: "Adapter failed at /Users/jerry/Movies/MeetingAssistant/session with access_token=sk-localrawvalue",
                details: [
                    "path: /Users/jerry/Movies/MeetingAssistant/session/transcript.txt",
                    "log_path: artifacts/logs/processing.log",
                    "runtime_path: /usr/local/bin/whisper",
                    "workspace: sessions/session-processing",
                    "transcript_text: Alice discussed the customer renewal and project roadmap",
                ],
                warnings: [
                    "content: We discussed the customer renewal transcript in detail",
                ]
            )
        )
        let viewModel = ProcessingStateViewModel(
            commandClient: client,
            readinessState: readyReadinessState(),
            defaultSessionID: "session-processing"
        )

        await viewModel.start()

        #expect(viewModel.state.phase == .failed)
        #expect(viewModel.state.errorCode?.rawValue == "path_conflict")
        #expect(viewModel.state.errorMessage == "Adapter failed at <redacted> with access_token=<redacted>")
        #expect(viewModel.state.errorDetails == [
            "path: <redacted>",
            "log_path: <redacted>",
            "runtime_path: <redacted>",
            "workspace: <redacted>",
            "transcript_text: <redacted>",
        ])
        #expect(viewModel.state.warnings == ["content: <redacted>"])
        #expect(viewModel.state.errorMessage?.contains("/Users/jerry") == false)
        #expect(viewModel.state.errorMessage?.contains("sk-localrawvalue") == false)
        #expect(viewModel.state.errorDetails.joined(separator: " ").contains("artifacts/logs") == false)
        #expect(viewModel.state.errorDetails.joined(separator: " ").contains("/usr/local") == false)
        #expect(viewModel.state.errorDetails.joined(separator: " ").contains("sessions/session-processing") == false)
        #expect(viewModel.state.errorDetails.joined(separator: " ").contains("customer renewal") == false)
        #expect(viewModel.state.warnings.joined(separator: " ").contains("customer renewal") == false)
    }

    @Test
    func failureDisplayRedactsFreeFormRelativePathsBearerTokensAndShortTranscriptSnippets() async {
        let client = ProcessingCommandFakeClient(
            transcriptScript: .failure(
                code: "processing_failed",
                message: "Adapter failed with Authorization: Bearer secretBearerToken12345",
                details: [
                    "see artifacts/logs/processing.log",
                    "reason: sessions/session-processing/transcript.json",
                    "Alice discussed customer renewal and project roadmap",
                    "stage: transcription",
                ],
                warnings: [
                    "retry with ../workspace/session/transcript.json",
                    "Bearer secretBearerToken12345",
                    "short customer roadmap note",
                ]
            )
        )
        let viewModel = ProcessingStateViewModel(
            commandClient: client,
            readinessState: readyReadinessState(),
            defaultSessionID: "session-processing"
        )

        await viewModel.start()

        #expect(viewModel.state.phase == .failed)
        #expect(viewModel.state.errorCode?.rawValue == "processing_failed")
        #expect(viewModel.state.errorMessage == "Adapter failed with Authorization=<redacted>")
        #expect(viewModel.state.errorDetails == [
            "see <redacted>",
            "reason: <redacted>",
            "<redacted>",
            "stage: transcription",
        ])
        #expect(viewModel.state.warnings == [
            "retry with <redacted>",
            "Bearer <redacted>",
            "<redacted>",
        ])

        let displayedText = (
            [viewModel.state.errorMessage ?? ""]
                + viewModel.state.errorDetails
                + viewModel.state.warnings
        ).joined(separator: " ")
        #expect(displayedText.contains("artifacts/logs") == false)
        #expect(displayedText.contains("sessions/session-processing") == false)
        #expect(displayedText.contains("../workspace") == false)
        #expect(displayedText.contains("secretBearerToken12345") == false)
        #expect(displayedText.contains("customer renewal") == false)
        #expect(displayedText.contains("customer roadmap") == false)
    }

    @Test
    func transcriptOnlyDegradationReasonIsRedactedBeforeDisplay() async {
        let client = ProcessingCommandFakeClient(
            transcriptScript: .success(transcriptID: "transcript-processing"),
            speakerLabelsScript: .success(
                labelStatus: "transcript_only",
                speakerLabelsArtifactID: "artifact-speakers-processing",
                degradationReason: "/Users/jerry/Movies/MeetingAssistant/session/transcript.json"
            )
        )
        let viewModel = ProcessingStateViewModel(
            commandClient: client,
            readinessState: readyReadinessState(),
            defaultSessionID: "session-processing"
        )

        await viewModel.start()

        #expect(viewModel.state.phase == .degraded)
        #expect(viewModel.state.degradationReason == "speaker labeling unavailable")
        #expect(viewModel.state.speakerLabelStatus == "Speaker labels degraded: speaker labeling unavailable")
        #expect(viewModel.state.speakerLabelStatus?.contains("/Users/jerry") == false)
    }

    @Test
    func dependencyBlockedStateDoesNotSendProcessingCommands() async {
        let client = ProcessingCommandFakeClient()
        let viewModel = ProcessingStateViewModel(
            commandClient: client,
            readinessState: blockedProcessingReadinessState()
        )

        await viewModel.start(sessionID: "session-processing")

        let transcriptRequests = await client.transcriptRequestSnapshot()
        let speakerRequests = await client.speakerLabelsRequestSnapshot()

        #expect(viewModel.state.phase == .blocked)
        #expect(viewModel.canStart == false)
        #expect(viewModel.canRetry == false)
        #expect(transcriptRequests.isEmpty)
        #expect(speakerRequests.isEmpty)
    }

    @Test
    func duplicateStartWhileBusyDoesNotSendSecondRequest() async {
        let client = ProcessingCommandFakeClient(responseDelayNanoseconds: 150_000_000)
        let viewModel = ProcessingStateViewModel(
            commandClient: client,
            readinessState: readyReadinessState(),
            defaultSessionID: "session-processing"
        )

        let task = Task {
            await viewModel.start()
        }
        await Task.yield()
        await viewModel.start()
        await task.value

        let transcriptRequests = await client.transcriptRequestSnapshot()
        #expect(transcriptRequests == [
            GenerateTranscriptRequest(sessionID: "session-processing"),
        ])
    }

    @Test
    func duplicateRetryWhileBusyDoesNotSendSecondRetryRequest() async {
        let client = ProcessingCommandFakeClient(
            transcriptScript: .failure(
                code: "processing_failed",
                message: "Transcript adapter failed."
            ),
            responseDelayNanoseconds: 150_000_000
        )
        let viewModel = ProcessingStateViewModel(
            commandClient: client,
            readinessState: readyReadinessState(),
            defaultSessionID: "session-processing"
        )

        await viewModel.start()
        #expect(viewModel.state.phase == .failed)

        let retryTask = Task {
            await viewModel.retry()
        }
        while !viewModel.state.isBusy {
            await Task.yield()
        }
        await viewModel.retry()
        await retryTask.value

        let transcriptRequests = await client.transcriptRequestSnapshot()
        #expect(transcriptRequests == [
            GenerateTranscriptRequest(sessionID: "session-processing"),
            GenerateTranscriptRequest(sessionID: "session-processing"),
        ])
    }

    @Test
    func retryWhenReadinessBecomesBlockedFailsClosedWithoutSendingRequest() async {
        let client = ProcessingCommandFakeClient(
            transcriptScript: .failure(
                code: "processing_failed",
                message: "Transcript adapter failed."
            )
        )
        let viewModel = ProcessingStateViewModel(
            commandClient: client,
            readinessState: readyReadinessState(),
            defaultSessionID: "session-processing"
        )

        await viewModel.start()
        #expect(viewModel.state.phase == .failed)

        viewModel.updateReadiness(blockedProcessingReadinessState())
        await viewModel.retry()

        let transcriptRequests = await client.transcriptRequestSnapshot()
        #expect(viewModel.state.phase == .blocked)
        #expect(viewModel.canRetry == false)
        #expect(transcriptRequests == [
            GenerateTranscriptRequest(sessionID: "session-processing"),
        ])
    }

    @Test
    func processRunnerUsesFrozenArgumentsWithoutFormatFlagAndDecodesJSON() async throws {
        let fixture = try ProcessingProcessRunnerFixture()
        let transcriptResponse = try await fixture.runner.generateTranscript(
            GenerateTranscriptRequest(
                sessionID: "session-process",
                sourceArtifactID: "artifact-source",
                language: "zh",
                runtime: .whisperCpp
            )
        )

        #expect(transcriptResponse.ok)
        #expect(transcriptResponse.transcriptID == "transcript-process")
        #expect(try fixture.recordedArguments() == [
            "generate_transcript",
            "--session-id",
            "session-process",
            "--source-artifact-id",
            "artifact-source",
            "--language",
            "zh",
            "--runtime",
            "whisper_cpp",
        ])

        let speakerResponse = try await fixture.runner.generateSpeakerLabels(
            GenerateSpeakerLabelsRequest(
                sessionID: "session-process",
                transcriptID: "transcript-process",
                allowTranscriptOnlyFallback: true
            )
        )

        #expect(speakerResponse.ok)
        #expect(speakerResponse.labelStatus == "transcript_only")
        #expect(try fixture.recordedArguments() == [
            "generate_speaker_labels",
            "--session-id",
            "session-process",
            "--transcript-id",
            "transcript-process",
            "--allow-transcript-only-fallback",
            "true",
        ])
    }

    @Test
    func processRunnerDecodesStructuredNonzeroTranscriptFailure() async throws {
        let fixture = try ProcessingProcessRunnerFixture(script: .structuredTranscriptFailure)
        let response = try await fixture.runner.generateTranscript(
            GenerateTranscriptRequest(sessionID: "session-process")
        )

        #expect(response.ok == false)
        #expect(response.code?.rawValue == "processing_failed")
        #expect(response.message == "Transcript adapter failed.")
        #expect(response.details == ["exit_code: 5", "stage: transcription"])
        #expect(try fixture.recordedArguments() == [
            "generate_transcript",
            "--session-id",
            "session-process",
        ])
    }

    @Test
    func processRunnerThrowsProcessFailedWhenNonzeroHasNoJSON() async throws {
        let fixture = try ProcessingProcessRunnerFixture(script: .nonJSONTranscriptFailure(exitCode: 5))

        do {
            _ = try await fixture.runner.generateTranscript(
                GenerateTranscriptRequest(sessionID: "session-process")
            )
            #expect(Bool(false), "Expected processFailed for a nonzero command without JSON stdout.")
        } catch let error as ProcessingCommandBridgeError {
            switch error {
            case .processFailed(let command, let exitCode, let code):
                #expect(command == .generateTranscript)
                #expect(exitCode == 5)
                #expect(code.rawValue == "processing_failed")
                #expect(error.errorDescription?.contains("adapter crashed") == false)
            default:
                #expect(Bool(false), "Expected processFailed, got \(error).")
            }
        } catch {
            #expect(Bool(false), "Expected ProcessingCommandBridgeError, got \(error).")
        }
    }

    @Test
    func processRunnerMapsBridgeFailureExitCodesToFrozenErrorCodes() async throws {
        let cases: [(Int32, String)] = [
            (2, "invalid_input"),
            (3, "artifact_missing"),
            (4, "dependency_missing"),
            (5, "processing_failed"),
            (9, "internal_error"),
        ]

        for (exitCode, expectedCode) in cases {
            let fixture = try ProcessingProcessRunnerFixture(
                script: .nonJSONTranscriptFailure(exitCode: exitCode)
            )
            do {
                _ = try await fixture.runner.generateTranscript(
                    GenerateTranscriptRequest(sessionID: "session-process")
                )
                #expect(Bool(false), "Expected bridge failure for exit code \(exitCode).")
            } catch let error as ProcessingCommandBridgeError {
                #expect(error.command == .generateTranscript)
                #expect(error.code.rawValue == expectedCode)
                #expect(error.errorDescription?.contains("/Users/jerry") == false)
            }
        }
    }

    @Test
    func processRunnerThrowsInvalidJSONWithoutStdoutSnippet() async throws {
        let fixture = try ProcessingProcessRunnerFixture(script: .invalidJSONTranscriptFailure)

        do {
            _ = try await fixture.runner.generateTranscript(
                GenerateTranscriptRequest(sessionID: "session-process")
            )
            #expect(Bool(false), "Expected invalidJSON for invalid stdout.")
        } catch let error as ProcessingCommandBridgeError {
            switch error {
            case .invalidJSON(let command, let code):
                #expect(command == .generateTranscript)
                #expect(code.rawValue == "processing_failed")
                #expect(error.errorDescription?.contains("not json") == false)
                #expect(error.errorDescription?.contains("/Users/jerry") == false)
            default:
                #expect(Bool(false), "Expected invalidJSON, got \(error).")
            }
        }
    }

    @Test
    func processRunnerLaunchFailureUsesSafeInternalError() async throws {
        let fixture = try ProcessingProcessRunnerFixture()
        let missingExecutable = fixture.rootURL
            .appendingPathComponent("missing", isDirectory: true)
            .appendingPathComponent("meeting-assistant-cli")
        let runner = ProcessingCommandProcessRunner(
            executablePath: missingExecutable.path,
            environment: [
                "MEETING_ASSISTANT_WORKSPACE": fixture.workspaceURL.path,
            ]
        )

        do {
            _ = try await runner.generateTranscript(
                GenerateTranscriptRequest(sessionID: "session-process")
            )
            #expect(Bool(false), "Expected launch failure.")
        } catch let error as ProcessingCommandBridgeError {
            #expect(error.command == .generateTranscript)
            #expect(error.code.rawValue == "internal_error")
            #expect(error.safeMessage == "Processing command could not be launched.")
            #expect(error.errorDescription?.contains(missingExecutable.path) == false)
        }
    }

    @Test
    func processRunnerBridgeFailuresBecomeSafeViewModelErrors() async throws {
        let fixture = try ProcessingProcessRunnerFixture(script: .nonJSONTranscriptFailure(exitCode: 5))
        let viewModel = ProcessingStateViewModel(
            commandClient: fixture.runner,
            readinessState: readyReadinessState(),
            defaultSessionID: "session-process"
        )

        await viewModel.start()

        #expect(viewModel.state.phase == .failed)
        #expect(viewModel.state.errorCode?.rawValue == "processing_failed")
        #expect(viewModel.state.errorMessage == "Processing command failed before returning a contract response.")
        #expect(viewModel.state.errorMessage?.contains("adapter crashed") == false)
        #expect(viewModel.state.errorMessage?.contains("/Users/jerry") == false)
        #expect(viewModel.canRetry)
    }

    @Test
    func processRunnerDrivenViewModelCompletesFromStdoutJSON() async throws {
        let fixture = try ProcessingProcessRunnerFixture(script: .labeledSuccess)
        let viewModel = ProcessingStateViewModel(
            commandClient: fixture.runner,
            readinessState: readyReadinessState(),
            defaultSessionID: "session-process"
        )

        await viewModel.start()

        #expect(viewModel.state.phase == .completed)
        #expect(viewModel.state.statusText == "Processing complete.")
        #expect(viewModel.state.transcriptID == "transcript-process")
        #expect(viewModel.state.transcriptArtifactID == "artifact-transcript-process")
        #expect(viewModel.state.transcriptStatus == "Transcript transcript-process generated with 1 segments.")
        #expect(viewModel.state.speakerLabelStatus == "Speaker labels artifact artifact-speakers-process is available.")
        #expect(viewModel.state.successSummary == "Generated transcript and speaker labels for session session-process.")
        #expect(viewModel.state.errorMessage == nil)
        #expect(try fixture.recordedInvocationLines() == [
            "generate_transcript --session-id session-process",
            "generate_speaker_labels --session-id session-process --transcript-id transcript-process --allow-transcript-only-fallback true",
        ])
    }

    @Test
    func processRunnerDrivenViewModelShowsDegradedStateFromStdoutJSON() async throws {
        let fixture = try ProcessingProcessRunnerFixture(script: .success)
        let viewModel = ProcessingStateViewModel(
            commandClient: fixture.runner,
            readinessState: readyReadinessState(),
            defaultSessionID: "session-process"
        )

        await viewModel.start()

        #expect(viewModel.state.phase == .degraded)
        #expect(viewModel.state.statusText == "Processing completed with transcript-only speaker labels.")
        #expect(viewModel.state.transcriptStatus == "Transcript transcript-process generated with 1 segments.")
        #expect(viewModel.state.degradationReason == "speaker labeling runtime unavailable")
        #expect(viewModel.state.speakerLabelStatus == "Speaker labels degraded: speaker labeling runtime unavailable")
        #expect(viewModel.state.errorMessage == nil)
    }

    @Test
    func processRunnerDrivenViewModelShowsFailureAndRetryFromStdoutJSON() async throws {
        let fixture = try ProcessingProcessRunnerFixture(script: .structuredTranscriptFailure)
        let viewModel = ProcessingStateViewModel(
            commandClient: fixture.runner,
            readinessState: readyReadinessState(),
            defaultSessionID: "session-process"
        )

        await viewModel.start()

        #expect(viewModel.state.phase == .failed)
        #expect(viewModel.state.statusText == "Processing failed.")
        #expect(viewModel.state.errorCode?.rawValue == "processing_failed")
        #expect(viewModel.state.errorMessage == "Transcript adapter failed.")
        #expect(viewModel.state.errorDetails == ["exit_code: 5", "stage: transcription"])
        #expect(viewModel.canRetry)

        await viewModel.retry()

        #expect(viewModel.state.phase == .failed)
        #expect(viewModel.state.errorCode?.rawValue == "processing_failed")
        #expect(try fixture.recordedInvocationLines() == [
            "generate_transcript --session-id session-process",
            "generate_transcript --session-id session-process",
        ])
    }
}

private func readyReadinessState() -> PermissionDependencyStatusState {
    PermissionDependencyStatusState.from(
        DependencyCheckResponse(
            ok: true,
            requestID: "local-test-ready",
            checks: [
                DependencyCheckItem(
                    id: "permission.screen_recording",
                    status: "granted",
                    required: false,
                    ok: true,
                    message: "Screen Recording permission is granted."
                ),
                DependencyCheckItem(
                    id: "permission.microphone",
                    status: "granted",
                    required: false,
                    ok: true,
                    message: "Microphone permission is granted."
                ),
                DependencyCheckItem(
                    id: "media_tool.ffmpeg",
                    status: "available",
                    required: true,
                    ok: true,
                    message: "FFmpeg is available."
                ),
            ]
        )
    )
}

private func blockedProcessingReadinessState() -> PermissionDependencyStatusState {
    PermissionDependencyStatusState.from(
        DependencyCheckResponse(
            ok: false,
            requestID: "local-test-blocked",
            code: "dependency_missing",
            message: "Required dependency is missing.",
            checks: [
                DependencyCheckItem(
                    id: "permission.screen_recording",
                    status: "granted",
                    required: false,
                    ok: true,
                    message: "Screen Recording permission is granted."
                ),
                DependencyCheckItem(
                    id: "permission.microphone",
                    status: "granted",
                    required: false,
                    ok: true,
                    message: "Microphone permission is granted."
                ),
                DependencyCheckItem(
                    id: "media_tool.ffmpeg",
                    status: "missing",
                    required: true,
                    ok: false,
                    message: "FFmpeg executable was not found."
                ),
            ]
        )
    )
}

private final class ProcessingProcessRunnerFixture {
    enum Script {
        case success
        case labeledSuccess
        case structuredTranscriptFailure
        case nonJSONTranscriptFailure(exitCode: Int32)
        case invalidJSONTranscriptFailure
    }

    let rootURL: URL
    let workspaceURL: URL
    let scriptURL: URL
    let argsURL: URL
    let invocationsURL: URL
    let runner: ProcessingCommandProcessRunner

    init(script: Script = .success) throws {
        rootURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("meeting-assistant-processing-tests-\(UUID().uuidString)", isDirectory: true)
        workspaceURL = rootURL.appendingPathComponent("workspace", isDirectory: true)
        scriptURL = rootURL.appendingPathComponent("meeting-assistant-cli")
        argsURL = rootURL.appendingPathComponent("args.txt")
        invocationsURL = rootURL.appendingPathComponent("invocations.txt")

        try FileManager.default.createDirectory(at: workspaceURL, withIntermediateDirectories: true)
        try Self.script(script).write(to: scriptURL, atomically: true, encoding: .utf8)
        try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: scriptURL.path)

        runner = ProcessingCommandProcessRunner(
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
        let transcriptCase: String
        switch script {
        case .success, .labeledSuccess:
            transcriptCase = """
                cat <<JSON
            {
              "ok": true,
              "request_id": "local-process-transcript",
              "command": "generate_transcript",
              "session_id": "$3",
              "transcript_id": "transcript-process",
              "artifact_id": "artifact-transcript-process",
              "segment_count": 1,
              "warnings": []
            }
            JSON
            """
        case .structuredTranscriptFailure:
            transcriptCase = """
                cat <<JSON
            {
              "ok": false,
              "request_id": "local-process-transcript-failure",
              "command": "generate_transcript",
              "session_id": "$3",
              "code": "processing_failed",
              "message": "Transcript adapter failed.",
              "details": {
                "stage": "transcription",
                "exit_code": 5
              },
              "warnings": []
            }
            JSON
                exit 5
            """
        case .nonJSONTranscriptFailure(let exitCode):
            transcriptCase = """
                printf '%s\\n' "adapter crashed at /Users/jerry/Movies/MeetingAssistant/session with sk-localrawvalue" >&2
                exit \(exitCode)
            """
        case .invalidJSONTranscriptFailure:
            transcriptCase = """
                printf '%s\\n' "not json from /Users/jerry/Movies/MeetingAssistant/session sk-localrawvalue"
                exit 5
            """
        }
        let speakerStatus: String
        switch script {
        case .labeledSuccess, .structuredTranscriptFailure, .nonJSONTranscriptFailure(_), .invalidJSONTranscriptFailure:
            speakerStatus = """
                "label_status": "labeled",
                "speaker_labels_artifact_id": "artifact-speakers-process",
            """
        case .success:
            speakerStatus = """
                "label_status": "transcript_only",
                "speaker_labels_artifact_id": "artifact-speakers-process",
                "degradation_reason": "speaker labeling runtime unavailable",
            """
        }

        return """
        #!/bin/sh
        : "${MEETING_ASSISTANT_WORKSPACE:?missing workspace}"
        printf '%s\\n' "$@" > "$MEETING_ASSISTANT_TEST_ARGS_FILE"
        printf '%s\\n' "$*" >> "$MEETING_ASSISTANT_TEST_INVOCATIONS_FILE"
        case "$1" in
          generate_transcript)
        \(transcriptCase)
            ;;
          generate_speaker_labels)
            cat <<JSON
        {
          "ok": true,
          "request_id": "local-process-speakers",
          "command": "generate_speaker_labels",
          "session_id": "$3",
          "transcript_id": "$5",
        \(speakerStatus)
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
