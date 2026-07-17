import CryptoKit
import Darwin
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
        bindRecordedSession(viewModel, sessionID: "session-processing")

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
    func explicitBoundSessionInheritsConfiguredRuntimeAndLanguage() async {
        let client = ProcessingCommandFakeClient()
        let viewModel = ProcessingStateViewModel(
            commandClient: client,
            readinessState: readyReadinessState(),
            defaultSessionID: "session-local-runtime",
            defaultLanguage: "zh",
            defaultRuntime: .whisperCpp
        )
        bindRecordedSession(viewModel, sessionID: "session-local-runtime")

        await viewModel.start(
            sessionID: "session-local-runtime",
            sourceArtifactID: "artifact-mixed-audio"
        )

        #expect((await client.transcriptRequestSnapshot()) == [
            GenerateTranscriptRequest(
                sessionID: "session-local-runtime",
                sourceArtifactID: "artifact-mixed-audio",
                language: "zh",
                runtime: .whisperCpp
            ),
        ])
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
        bindRecordedSession(viewModel, sessionID: "session-processing", audioStatus: .degraded)

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
        bindRecordedSession(viewModel, sessionID: "session-processing")

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
        bindRecordedSession(viewModel, sessionID: "session-processing")

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
    func bindingAnotherRecordedSessionClearsOldRetryAndTargetsTheNewSession() async {
        let client = ProcessingCommandFakeClient(
            transcriptScript: .failure(
                code: "processing_failed",
                message: "Transcript adapter failed."
            )
        )
        let viewModel = ProcessingStateViewModel(
            commandClient: client,
            readinessState: readyReadinessState(),
            defaultSessionID: "session-app-ui-blocked"
        )
        bindRecordedSession(viewModel, sessionID: "session-app-ui-blocked")

        await viewModel.start()
        #expect(viewModel.state.phase == .failed)
        #expect(viewModel.state.sessionID == "session-app-ui-blocked")
        #expect(viewModel.canRetry)

        bindRecordedSession(
            viewModel,
            sessionID: "session-current-recording",
            audioStatus: .degraded
        )
        #expect(viewModel.state.phase == .idle)
        #expect(!viewModel.canRetry)

        await viewModel.start()

        let transcriptRequests = await client.transcriptRequestSnapshot()
        #expect(transcriptRequests == [
            GenerateTranscriptRequest(sessionID: "session-app-ui-blocked"),
            GenerateTranscriptRequest(sessionID: "session-current-recording"),
        ])
    }

    @Test
    func defaultSessionIdentifierAloneDoesNotGrantProcessingEligibility() async {
        let client = ProcessingCommandFakeClient()
        let viewModel = ProcessingStateViewModel(
            commandClient: client,
            readinessState: readyReadinessState(),
            defaultSessionID: "session-unbound"
        )

        #expect(viewModel.boundSessionID == nil)
        #expect(!viewModel.canStart)
        #expect(viewModel.state.phase == .blocked)
        #expect(viewModel.state.statusText == "Choose a recorded meeting before generating a transcript.")

        await viewModel.start()

        #expect((await client.transcriptRequestSnapshot()).isEmpty)
        #expect((await client.speakerLabelsRequestSnapshot()).isEmpty)
    }

    @Test
    func emptySessionBindingFailsClosedWithoutSendingCommands() async {
        let client = ProcessingCommandFakeClient()
        let viewModel = ProcessingStateViewModel(
            commandClient: client,
            readinessState: readyReadinessState()
        )

        viewModel.bindSession(
            sessionID: "  \n ",
            sessionStatus: "recorded",
            processableAudioStatus: .available
        )
        await viewModel.start(sessionID: "  ")

        #expect(viewModel.boundSessionID == nil)
        #expect(!viewModel.canStart)
        #expect(viewModel.state.phase == .blocked)
        #expect((await client.transcriptRequestSnapshot()).isEmpty)
    }

    @Test
    func sessionMustBeRecordedBeforeProcessingCanStart() async {
        let client = ProcessingCommandFakeClient()
        let viewModel = ProcessingStateViewModel(
            commandClient: client,
            readinessState: readyReadinessState()
        )

        viewModel.bindSession(
            sessionID: "session-recording",
            sessionStatus: "recording",
            processableAudioStatus: .available
        )
        await viewModel.start()

        #expect(viewModel.boundSessionID == "session-recording")
        #expect(!viewModel.canStart)
        #expect(viewModel.state.phase == .blocked)
        #expect(viewModel.state.statusText == "Finish and save this recording before generating a transcript.")
        #expect((await client.transcriptRequestSnapshot()).isEmpty)
    }

    @Test
    func recordedSessionRequiresAvailableOrDegradedProcessableAudio() async {
        let blockedStatuses: [NativeCaptureArtifactStatus?] = [nil, .missing, .failed]

        for status in blockedStatuses {
            let client = ProcessingCommandFakeClient()
            let viewModel = ProcessingStateViewModel(
                commandClient: client,
                readinessState: readyReadinessState()
            )
            viewModel.bindSession(
                sessionID: "session-no-audio",
                sessionStatus: "recorded",
                processableAudioStatus: status
            )

            await viewModel.start()

            #expect(!viewModel.canStart)
            #expect(viewModel.state.phase == .blocked)
            #expect(viewModel.state.statusText == "This meeting does not have processable audio for a transcript.")
            #expect((await client.transcriptRequestSnapshot()).isEmpty)
        }
    }

    @Test
    func availableAndDegradedProcessableAudioBothPermitRecordedSession() async {
        for (index, status) in [NativeCaptureArtifactStatus.available, .degraded].enumerated() {
            let client = ProcessingCommandFakeClient()
            let sessionID = "session-eligible-\(index)"
            let viewModel = ProcessingStateViewModel(
                commandClient: client,
                readinessState: readyReadinessState()
            )
            bindRecordedSession(viewModel, sessionID: sessionID, audioStatus: status)

            #expect(viewModel.canStart)
            #expect(viewModel.state.phase == .idle)

            await viewModel.start()

            #expect((await client.transcriptRequestSnapshot()) == [
                GenerateTranscriptRequest(sessionID: sessionID),
            ])
            #expect(viewModel.state.phase == .completed)
        }
    }

    @Test
    func transcribedSessionWithSavedAudioCanRegenerateTranscript() async {
        let client = ProcessingCommandFakeClient()
        let viewModel = ProcessingStateViewModel(
            commandClient: client,
            readinessState: readyReadinessState()
        )
        viewModel.bindSession(
            sessionID: "session-transcribed-recovery",
            sessionStatus: "transcribed",
            processableAudioStatus: .available
        )

        #expect(viewModel.canStart)
        #expect(viewModel.state.phase == .idle)

        await viewModel.start()

        #expect((await client.transcriptRequestSnapshot()) == [
            GenerateTranscriptRequest(sessionID: "session-transcribed-recovery"),
        ])
        #expect(viewModel.state.phase == .completed)
    }

    @Test
    func interruptedProcessingSessionWithSavedAudioCanRestartFromTheOriginalArtifact() async {
        let client = ProcessingCommandFakeClient()
        let viewModel = ProcessingStateViewModel(
            commandClient: client,
            readinessState: readyReadinessState()
        )
        viewModel.bindSession(
            sessionID: "session-interrupted-processing",
            sessionStatus: "processing",
            processableAudioStatus: .available
        )

        #expect(viewModel.canStart)
        #expect(viewModel.state.phase == .idle)

        await viewModel.start(
            sessionID: "session-interrupted-processing",
            sourceArtifactID: "artifact-original-audio"
        )

        #expect((await client.transcriptRequestSnapshot()) == [
            GenerateTranscriptRequest(
                sessionID: "session-interrupted-processing",
                sourceArtifactID: "artifact-original-audio"
            ),
        ])
        #expect(viewModel.state.phase == .completed)
    }

    @Test
    func transcribedSessionWithoutSavedAudioCannotRegenerateTranscript() async {
        let client = ProcessingCommandFakeClient()
        let viewModel = ProcessingStateViewModel(
            commandClient: client,
            readinessState: readyReadinessState()
        )
        viewModel.bindSession(
            sessionID: "session-transcribed-no-audio",
            sessionStatus: "transcribed",
            processableAudioStatus: nil
        )

        await viewModel.start()

        #expect(!viewModel.canStart)
        #expect(viewModel.state.phase == .blocked)
        #expect(viewModel.state.statusText == "This meeting does not have processable audio for a transcript.")
        #expect((await client.transcriptRequestSnapshot()).isEmpty)
    }

    @Test
    func explicitStartCannotTargetASessionOtherThanTheBoundSession() async {
        let client = ProcessingCommandFakeClient()
        let viewModel = ProcessingStateViewModel(
            commandClient: client,
            readinessState: readyReadinessState()
        )
        bindRecordedSession(viewModel, sessionID: "session-current")

        await viewModel.start(sessionID: "session-stale")

        #expect(viewModel.boundSessionID == "session-current")
        #expect(viewModel.state.phase == .idle)
        #expect((await client.transcriptRequestSnapshot()).isEmpty)
        #expect((await client.speakerLabelsRequestSnapshot()).isEmpty)
    }

    @Test
    func switchingSessionWhileTranscriptCommandIsRunningIgnoresTheOldResult() async {
        let client = FirstTranscriptGateProcessingCommandClient()
        let viewModel = ProcessingStateViewModel(
            commandClient: client,
            readinessState: readyReadinessState()
        )
        bindRecordedSession(viewModel, sessionID: "session-old")

        let oldRun = Task {
            await viewModel.start()
        }
        while (await client.transcriptRequestSnapshot()).isEmpty {
            await Task.yield()
        }

        bindRecordedSession(viewModel, sessionID: "session-new", audioStatus: .degraded)
        await client.releaseFirstTranscript()
        await oldRun.value

        #expect(viewModel.boundSessionID == "session-new")
        #expect(viewModel.state.phase == .idle)
        #expect(viewModel.state.sessionID == nil)
        #expect((await client.speakerLabelsRequestSnapshot()).isEmpty)

        await viewModel.start()

        #expect((await client.transcriptRequestSnapshot()) == [
            GenerateTranscriptRequest(sessionID: "session-old"),
            GenerateTranscriptRequest(sessionID: "session-new"),
        ])
        #expect((await client.speakerLabelsRequestSnapshot()) == [
            GenerateSpeakerLabelsRequest(
                sessionID: "session-new",
                transcriptID: "transcript-fake",
                allowTranscriptOnlyFallback: true
            ),
        ])
        #expect(viewModel.state.phase == .completed)
        #expect(viewModel.state.sessionID == "session-new")
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
        bindRecordedSession(viewModel, sessionID: "session-processing")

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
        bindRecordedSession(viewModel, sessionID: "session-processing")

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
        bindRecordedSession(viewModel, sessionID: "session-processing", audioStatus: .degraded)

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
        bindRecordedSession(viewModel, sessionID: "session-processing")

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
        bindRecordedSession(viewModel, sessionID: "session-processing")

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
        bindRecordedSession(viewModel, sessionID: "session-processing")

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
        bindRecordedSession(viewModel, sessionID: "session-processing")

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
    func processRunnerDrainsStderrWhileWaitingForStdoutJSON() async throws {
        let fixture = try ProcessingProcessRunnerFixture(script: .noisyStderrTranscriptSuccess)
        let transcriptResponse = try await fixture.runner.generateTranscript(
            GenerateTranscriptRequest(sessionID: "session-process")
        )

        #expect(transcriptResponse.ok)
        #expect(transcriptResponse.command == .generateTranscript)
        #expect(transcriptResponse.transcriptID == "transcript-process")
        #expect(try fixture.recordedArguments() == [
            "generate_transcript",
            "--session-id",
            "session-process",
        ])
    }

    @Test
    func processRunnerTimesOutTerminatesTheChildAndReturnsOnlySafeBridgeDetails() async throws {
        let fixture = try ProcessingProcessRunnerFixture(
            script: .hangingAfterSensitiveOutput,
            timeoutSeconds: 5
        )

        do {
            _ = try await fixture.runner.generateTranscript(
                GenerateTranscriptRequest(sessionID: "session-process")
            )
            #expect(Bool(false), "Expected the hanging processing command to time out.")
        } catch let error as ProcessingCommandBridgeError {
            #expect(error == .timedOut(command: .generateTranscript))
            #expect(error.code == .processingFailed)
            #expect(error.safeMessage == "Processing command timed out and was stopped.")
            #expect(error.errorDescription?.contains("/Users/jerry") == false)
            #expect(error.errorDescription?.contains("sk-processing-timeout-secret") == false)
        }

        #expect(try fixture.recordedProcessIsRunning() == false)
    }

    @Test
    func processRunnerBoundsDrainAndKillsBackgroundDescendantHoldingPipes() async throws {
        let fixture = try ProcessingProcessRunnerFixture(
            script: .backgroundDescendantHoldingPipes,
            timeoutSeconds: 10
        )
        let runner = fixture.runner

        do {
            _ = try await runner.generateTranscript(
                GenerateTranscriptRequest(sessionID: "session-process")
            )
            #expect(Bool(false), "Expected the direct command's nonzero exit to fail.")
        } catch let error as ProcessingCommandBridgeError {
            #expect(
                error == .processFailed(
                    command: .generateTranscript,
                    exitCode: 5,
                    code: .processingFailed
                )
            )
            #expect(error.errorDescription?.contains("/Users/jerry") == false)
            #expect(error.errorDescription?.contains("sk-processing-descendant-secret") == false)
        }

        // Measure from the fixture's PID write rather than test scheduling. The
        // descendant sleeps for 10 seconds, so an 8-second ceiling proves inherited
        // pipes are bounded without conflating that behavior with parallel test load.
        let processStartDate = try fixture.recordedProcessStartDate()
        #expect(Date().timeIntervalSince(processStartDate) < 8)
        #expect(try fixture.recordedProcessStopsWithin(timeoutSeconds: 1))
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
        bindRecordedSession(viewModel, sessionID: "session-process")

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
        bindRecordedSession(viewModel, sessionID: "session-process")

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
        bindRecordedSession(viewModel, sessionID: "session-process", audioStatus: .degraded)

        await viewModel.start()

        #expect(viewModel.state.phase == .degraded)
        #expect(viewModel.state.statusText == "Processing completed with transcript-only speaker labels.")
        #expect(viewModel.state.transcriptStatus == "Transcript transcript-process generated with 1 segments.")
        #expect(viewModel.state.degradationReason == "speaker labeling runtime unavailable")
        #expect(viewModel.state.speakerLabelStatus == "Speaker labels degraded: speaker labeling runtime unavailable")
        #expect(viewModel.state.errorMessage == nil)
    }

    @Test
    func processRunnerWithRealProcessingCLIWritesWorkspaceArtifactsLoadableByTranscriptReview() async throws {
        let fixture = try RealProcessingCLIWorkspaceFixture()
        let sessionID = try fixture.importMediaSession()
        let viewModel = ProcessingStateViewModel(
            commandClient: fixture.runner,
            readinessState: readyReadinessState(),
            defaultSessionID: sessionID
        )
        bindRecordedSession(viewModel, sessionID: sessionID)

        await viewModel.start()

        #expect(viewModel.state.phase == .degraded)
        #expect(viewModel.state.statusText == "Processing completed with transcript-only speaker labels.")
        #expect(viewModel.state.sessionID == sessionID)
        #expect(viewModel.state.transcriptID?.isEmpty == false)
        #expect(viewModel.state.transcriptArtifactID?.isEmpty == false)
        #expect(viewModel.state.segmentCount == 1)
        #expect(viewModel.state.labelStatus == "transcript_only")
        #expect(viewModel.state.degradationReason?.contains("transcript-only fallback") == true)
        #expect(viewModel.state.errorMessage == nil)

        let artifactTypes = try fixture.artifactTypes(sessionID: sessionID)
        #expect(artifactTypes == [
            "mixed_audio",
            "normalized_audio",
            "transcript_text",
            "speaker_labels",
        ])
        #expect(try fixture.sourceChecksumUnchanged())

        let input = try TranscriptReviewWorkspaceLoader.load(
            workspaceURL: fixture.workspaceURL,
            sessionID: sessionID
        )
        let transcript = try #require(input.transcript)
        #expect(transcript.id == viewModel.state.transcriptID)
        #expect(transcript.sessionID == sessionID)
        #expect(transcript.segments.map(\.segmentID) == ["segment-0001"])
        #expect(transcript.segments.first?.text.contains("Fake transcript generated from local audio.") == true)
        #expect(input.speakerLabels?.sessionID == sessionID)
        #expect(input.speakerLabels?.labels.isEmpty == true)
        #expect(input.speakerLabels?.segmentMapping.isEmpty == true)
        #expect(input.speakerLabelsDegradationReason?.contains("transcript-only fallback") == true)
    }

    @Test
    func processRunnerWithRealWhisperRuntimeWritesWorkspaceArtifactsLoadableByTranscriptReviewWhenEnabled() async throws {
        guard Self.realRuntimeBridgeSmokeEnabled() else {
            return
        }

        let fixture = try RealProcessingCLIWorkspaceFixture(mode: .realWhisperRuntime)
        let sessionID = try fixture.createNativeRecordingSession(title: "Native real runtime bridge fixture")
        let viewModel = ProcessingStateViewModel(
            commandClient: fixture.runner,
            readinessState: readyReadinessState(),
            defaultSessionID: sessionID
        )
        bindRecordedSession(viewModel, sessionID: sessionID)

        await viewModel.start(sessionID: sessionID, language: "zh", runtime: .whisperCpp)

        #expect(viewModel.state.phase == .degraded)
        #expect(viewModel.state.statusText == "Processing completed with transcript-only speaker labels.")
        #expect(viewModel.state.sessionID == sessionID)
        #expect(viewModel.state.transcriptID?.isEmpty == false)
        #expect(viewModel.state.transcriptArtifactID?.isEmpty == false)
        #expect((viewModel.state.segmentCount ?? 0) > 0)
        #expect(viewModel.state.labelStatus == "transcript_only")
        #expect(viewModel.state.degradationReason?.contains("transcript-only fallback") == true)
        #expect(viewModel.state.errorMessage == nil)

        let artifactTypes = try fixture.artifactTypes(sessionID: sessionID)
        #expect(artifactTypes == [
            "mixed_audio",
            "normalized_audio",
            "transcript_text",
            "speaker_labels",
        ])
        #expect(try fixture.sourceChecksumUnchanged())

        let transcriptText = try fixture.transcriptText(sessionID: sessionID)
        #expect(transcriptText.range(of: #"\p{Han}"#, options: .regularExpression) != nil)
        for term in ["http", "llm", "clean architecture", "eda"] {
            #expect(Self.transcriptContains(transcriptText, term: term))
        }

        let input = try TranscriptReviewWorkspaceLoader.load(
            workspaceURL: fixture.workspaceURL,
            sessionID: sessionID
        )
        let transcript = try #require(input.transcript)
        #expect(transcript.id == viewModel.state.transcriptID)
        #expect(transcript.sessionID == sessionID)
        #expect(transcript.segments.isEmpty == false)
        #expect(Self.transcriptContains(transcript.segments.map(\.text).joined(separator: " "), term: "llm"))
        #expect(input.speakerLabels?.sessionID == sessionID)
        #expect(input.speakerLabels?.labels.isEmpty == true)
        #expect(input.speakerLabels?.segmentMapping.isEmpty == true)
        #expect(input.speakerLabelsDegradationReason?.contains("transcript-only fallback") == true)

        print(
            "VS-MA-22 native-app real runtime bridge marker [non-contract]: "
                + "ProcessingCommandProcessRunner -> provider CLI -> whisper.cpp -> TranscriptReviewWorkspaceLoader verified"
        )
    }

    @Test
    func processRunnerWithVSMA21HardeningFixtureRetriesPathConflictPreservingCaptureArtifactWhenEnabled() async throws {
        guard Self.vsMA21HardeningBridgeSmokeEnabled() else {
            return
        }

        let fixture = try VSMA21ProcessingHardeningBridgeFixture()
        let sessionID = try fixture.createNativeRecordingSession()
        let originalMixedAudioChecksum = try fixture.mixedAudioChecksum(sessionID: sessionID)
        let viewModel = ProcessingStateViewModel(
            commandClient: fixture.runner,
            readinessState: readyReadinessState(),
            defaultSessionID: sessionID
        )
        bindRecordedSession(viewModel, sessionID: sessionID)

        await viewModel.start(sessionID: sessionID)

        #expect(viewModel.state.phase == .failed)
        #expect(viewModel.state.statusText == "Processing failed.")
        #expect(viewModel.state.errorCode?.rawValue == "path_conflict")
        #expect(viewModel.state.errorMessage == "Processing path conflict.")
        #expect(viewModel.canRetry)
        #expect(try fixture.mixedAudioChecksum(sessionID: sessionID) == originalMixedAudioChecksum)
        #expect(try fixture.transcriptExists(sessionID: sessionID) == false)

        await viewModel.retry()

        #expect(viewModel.state.phase == .completed)
        #expect(viewModel.state.statusText == "Processing complete.")
        #expect(viewModel.state.sessionID == sessionID)
        #expect(viewModel.state.transcriptID == "transcript-process-fixture")
        #expect(viewModel.state.transcriptArtifactID == "artifact-process-transcript")
        #expect(viewModel.state.segmentCount == 2)
        #expect(viewModel.state.labelStatus == "labeled")
        #expect(viewModel.state.errorMessage == nil)
        #expect(try fixture.mixedAudioChecksum(sessionID: sessionID) == originalMixedAudioChecksum)
        #expect(try fixture.artifactTypes(sessionID: sessionID) == [
            "mixed_audio",
            "transcript_text",
            "speaker_labels",
        ])
        #expect(try fixture.recordedInvocationLines() == [
            "generate_transcript --session-id \(sessionID)",
            "generate_transcript --session-id \(sessionID)",
            "generate_speaker_labels --session-id \(sessionID) --transcript-id transcript-process-fixture --allow-transcript-only-fallback true",
        ])

        print(
            "VS-MA-21 native-app hardening bridge marker [non-contract]: "
                + "ProcessingCommandProcessRunner path_conflict retry preserved original mixed_audio checksum"
        )
    }

    @Test
    func processRunnerDrivenViewModelShowsFailureAndRetryFromStdoutJSON() async throws {
        let fixture = try ProcessingProcessRunnerFixture(script: .structuredTranscriptFailure)
        let viewModel = ProcessingStateViewModel(
            commandClient: fixture.runner,
            readinessState: readyReadinessState(),
            defaultSessionID: "session-process"
        )
        bindRecordedSession(viewModel, sessionID: "session-process")

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

    private func bindRecordedSession(
        _ viewModel: ProcessingStateViewModel,
        sessionID: String,
        audioStatus: NativeCaptureArtifactStatus = .available
    ) {
        viewModel.bindSession(
            sessionID: sessionID,
            sessionStatus: "recorded",
            processableAudioStatus: audioStatus
        )
    }

    private static func realRuntimeBridgeSmokeEnabled() -> Bool {
        switch ProcessInfo.processInfo.environment["MA_NATIVE_REAL_RUNTIME_BRIDGE_SMOKE"]?
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .lowercased() {
        case "1", "true", "yes":
            return true
        default:
            return false
        }
    }

    private static func vsMA21HardeningBridgeSmokeEnabled() -> Bool {
        switch ProcessInfo.processInfo.environment["MA_NATIVE_VSMA21_HARDENING_BRIDGE_SMOKE"]?
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .lowercased() {
        case "1", "true", "yes":
            return true
        default:
            return false
        }
    }

    private static func normalizedTranscriptText(_ value: String) -> String {
        var normalized = value.lowercased()
        for punctuation in [".", ",", ":", ";", "!", "?", "(", ")", "[", "]", "{", "}", "\"", "'", "\n", "\t"] {
            normalized = normalized.replacingOccurrences(of: punctuation, with: " ")
        }
        return normalized.split(whereSeparator: \.isWhitespace).joined(separator: " ")
    }

    private static func transcriptContains(_ transcript: String, term: String) -> Bool {
        let normalizedTranscript = normalizedTranscriptText(transcript)
        let normalizedTerm = normalizedTranscriptText(term)
        let compactTranscript = normalizedTranscript.replacingOccurrences(of: " ", with: "")
        let compactTerm = normalizedTerm.replacingOccurrences(of: " ", with: "")
        return normalizedTranscript.contains(normalizedTerm) || compactTranscript.contains(compactTerm)
    }
}

private actor FirstTranscriptGateProcessingCommandClient: ProcessingCommandClient {
    private var transcriptRequests: [GenerateTranscriptRequest] = []
    private var speakerLabelsRequests: [GenerateSpeakerLabelsRequest] = []
    private var firstTranscriptContinuation: CheckedContinuation<Void, Never>?
    private var firstTranscriptWasReleased = false

    func generateTranscript(
        _ request: GenerateTranscriptRequest
    ) async throws -> GenerateTranscriptResponse {
        transcriptRequests.append(request)
        if transcriptRequests.count == 1 {
            await waitForFirstTranscriptRelease()
        }

        return GenerateTranscriptResponse(
            ok: true,
            requestID: "local-gated-generate-transcript",
            sessionID: request.sessionID,
            transcriptID: "transcript-fake",
            artifactID: "artifact-transcript-fake",
            segmentCount: 2,
            warnings: []
        )
    }

    func generateSpeakerLabels(
        _ request: GenerateSpeakerLabelsRequest
    ) async throws -> GenerateSpeakerLabelsResponse {
        speakerLabelsRequests.append(request)
        return GenerateSpeakerLabelsResponse(
            ok: true,
            requestID: "local-gated-generate-speaker-labels",
            sessionID: request.sessionID,
            transcriptID: request.transcriptID,
            labelStatus: "labeled",
            speakerLabelsArtifactID: "artifact-speaker-labels-fake",
            warnings: []
        )
    }

    func releaseFirstTranscript() {
        firstTranscriptWasReleased = true
        firstTranscriptContinuation?.resume()
        firstTranscriptContinuation = nil
    }

    func transcriptRequestSnapshot() -> [GenerateTranscriptRequest] {
        transcriptRequests
    }

    func speakerLabelsRequestSnapshot() -> [GenerateSpeakerLabelsRequest] {
        speakerLabelsRequests
    }

    private func waitForFirstTranscriptRelease() async {
        guard !firstTranscriptWasReleased else {
            return
        }

        await withCheckedContinuation { continuation in
            if firstTranscriptWasReleased {
                continuation.resume()
            } else {
                firstTranscriptContinuation = continuation
            }
        }
    }
}

private final class RealProcessingCLIWorkspaceFixture {
    enum Mode {
        case defaultFakeRuntime
        case realWhisperRuntime
    }

    let rootURL: URL
    let workspaceURL: URL
    let mediaURL: URL
    let runner: ProcessingCommandProcessRunner

    private let cliURL: URL
    private let mediaChecksum: String
    private let realRuntimeConfiguration: RealRuntimeConfiguration?

    init(mode: Mode = .defaultFakeRuntime) throws {
        rootURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("meeting-assistant-real-processing-\(UUID().uuidString)", isDirectory: true)
        workspaceURL = rootURL.appendingPathComponent("workspace", isDirectory: true)
        mediaURL = rootURL.appendingPathComponent("fixtures/native-processing.wav")
        cliURL = rootURL.appendingPathComponent("meeting-assistant-cli")
        switch mode {
        case .defaultFakeRuntime:
            realRuntimeConfiguration = nil
        case .realWhisperRuntime:
            realRuntimeConfiguration = try Self.realRuntimeConfiguration()
        }

        try FileManager.default.createDirectory(at: workspaceURL, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(
            at: mediaURL.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        if let realRuntimeConfiguration {
            try FileManager.default.copyItem(at: realRuntimeConfiguration.smokeAudioURL, to: mediaURL)
        } else {
            try Self.writeFixtureWAV(to: mediaURL)
        }
        mediaChecksum = try Self.sha256(mediaURL)

        let repoRoot = try Self.repositoryRootURL()
        let processingSource = repoRoot.appendingPathComponent(
            "platform/processing-cli/src",
            isDirectory: true
        )
        let script = """
        #!/bin/sh
        set -eu
        export PYTHONPATH="\(processingSource.path)${PYTHONPATH:+:$PYTHONPATH}"
        exec /usr/bin/env python3 -m meeting_assistant_cli "$@"
        """
        try script.write(to: cliURL, atomically: true, encoding: .utf8)
        try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: cliURL.path)

        runner = ProcessingCommandProcessRunner(
            executablePath: cliURL.path,
            environment: Self.cliEnvironment(
                workspaceURL: workspaceURL,
                realRuntimeConfiguration: realRuntimeConfiguration
            )
        )
    }

    deinit {
        try? FileManager.default.removeItem(at: rootURL)
    }

    func importMediaSession() throws -> String {
        let payload = try runCLI([
            "import_media",
            "--path",
            mediaURL.path,
            "--title",
            "Native processing real CLI fixture",
        ])
        return try #require(payload["session_id"] as? String)
    }

    func createNativeRecordingSession(title: String) throws -> String {
        let sessionID = "session-native-real-runtime"
        let sessionRootURL = self.sessionRootURL(sessionID: sessionID)
        let artifactsURL = sessionRootURL.appendingPathComponent("artifacts", isDirectory: true)
        try FileManager.default.createDirectory(at: artifactsURL, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(
            at: sessionRootURL.appendingPathComponent("logs", isDirectory: true),
            withIntermediateDirectories: true
        )

        let audioURL = artifactsURL.appendingPathComponent("mixed_audio.wav", isDirectory: false)
        try FileManager.default.copyItem(at: mediaURL, to: audioURL)
        let checksum = try Self.sha256(audioURL)
        let now = "2026-07-05T00:00:00Z"
        try writeJSON(
            [
                "id": sessionID,
                "title": title,
                "source_type": "native_recording",
                "status": "recorded",
                "started_at": now,
                "workspace_dir": sessionRootURL.path,
                "created_at": now,
                "updated_at": now,
                "artifacts": [
                    [
                        "id": "artifact-native-real-runtime-mixed",
                        "session_id": sessionID,
                        "artifact_type": "mixed_audio",
                        "path": "artifacts/mixed_audio.wav",
                        "format": "wav",
                        "capture_status": "available",
                        "checksum": checksum,
                        "created_at": now,
                    ],
                ],
            ],
            to: sessionRootURL.appendingPathComponent("session.json", isDirectory: false)
        )
        return sessionID
    }

    func artifactTypes(sessionID: String) throws -> [String] {
        let session = try sessionMetadata(sessionID: sessionID)
        let artifacts = try #require(session["artifacts"] as? [[String: Any]])
        return artifacts.compactMap { $0["artifact_type"] as? String }
    }

    func sourceChecksumUnchanged() throws -> Bool {
        try Self.sha256(mediaURL) == mediaChecksum
    }

    func transcriptText(sessionID: String) throws -> String {
        let session = try sessionMetadata(sessionID: sessionID)
        let artifacts = try #require(session["artifacts"] as? [[String: Any]])
        let transcriptArtifact = try #require(artifacts.first { $0["artifact_type"] as? String == "transcript_text" })
        let transcriptURL = try artifactURL(transcriptArtifact, sessionID: sessionID)
        let data = try Data(contentsOf: transcriptURL)
        let payload = try JSONSerialization.jsonObject(with: data) as? [String: Any]
        let segments = try #require(payload?["segments"] as? [[String: Any]])
        let text = segments.compactMap { $0["text"] as? String }.joined(separator: " ")
        #expect(text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty == false)
        return text
    }

    private func runCLI(_ arguments: [String]) throws -> [String: Any] {
        let process = Process()
        let stdout = Pipe()
        let stderr = Pipe()
        process.executableURL = cliURL
        process.arguments = arguments
        process.environment = Self.cliEnvironment(
            workspaceURL: workspaceURL,
            realRuntimeConfiguration: realRuntimeConfiguration
        )
        process.standardOutput = stdout
        process.standardError = stderr

        try process.run()
        process.waitUntilExit()

        let stdoutData = stdout.fileHandleForReading.readDataToEndOfFile()
        let stderrData = stderr.fileHandleForReading.readDataToEndOfFile()
        let stdoutText = String(data: stdoutData, encoding: .utf8) ?? ""
        let stderrText = String(data: stderrData, encoding: .utf8) ?? ""
        #expect(stdoutText.contains("Traceback") == false)
        #expect(stderrText.contains("Traceback") == false)
        #expect(process.terminationStatus == 0)
        if process.terminationStatus != 0 {
            throw RealProcessingCLIFixtureError.commandFailed(stdout: stdoutText, stderr: stderrText)
        }

        let lines = stdoutText.split(separator: "\n").filter { !$0.trimmingCharacters(in: .whitespaces).isEmpty }
        guard lines.count == 1,
              let data = lines[0].data(using: .utf8),
              let payload = try JSONSerialization.jsonObject(with: data) as? [String: Any]
        else {
            throw RealProcessingCLIFixtureError.invalidJSON(stdout: stdoutText)
        }
        #expect(payload["ok"] as? Bool == true)
        return payload
    }

    private func sessionMetadata(sessionID: String) throws -> [String: Any] {
        let sessionURL = sessionRootURL(sessionID: sessionID)
            .appendingPathComponent("session.json", isDirectory: false)
        let data = try Data(contentsOf: sessionURL)
        guard let payload = try JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            throw RealProcessingCLIFixtureError.invalidJSON(stdout: sessionURL.path)
        }
        return payload
    }

    private func sessionRootURL(sessionID: String) -> URL {
        workspaceURL
            .appendingPathComponent("sessions", isDirectory: true)
            .appendingPathComponent(sessionID, isDirectory: true)
    }

    private func artifactURL(_ artifact: [String: Any], sessionID: String) throws -> URL {
        let path = try #require(artifact["path"] as? String)
        if path.hasPrefix("/") {
            return URL(fileURLWithPath: path, isDirectory: false)
        }
        return sessionRootURL(sessionID: sessionID)
            .appendingPathComponent(path, isDirectory: false)
    }

    private func writeJSON(_ payload: Any, to url: URL) throws {
        let data = try JSONSerialization.data(withJSONObject: payload, options: [.prettyPrinted, .sortedKeys])
        try data.write(to: url)
    }

    private static func repositoryRootURL(filePath: String = #filePath) throws -> URL {
        if let configured = ProcessInfo.processInfo.environment["MEETING_ASSISTANT_REPO_ROOT"],
           !configured.isEmpty {
            return URL(fileURLWithPath: configured, isDirectory: true)
                .standardizedFileURL
                .resolvingSymlinksInPath()
        }

        var candidate = URL(fileURLWithPath: filePath, isDirectory: false)
            .deletingLastPathComponent()
            .standardizedFileURL
        while candidate.path != "/" {
            let marker = candidate.appendingPathComponent(
                "platform/processing-cli/src/meeting_assistant_cli/cli.py",
                isDirectory: false
            )
            if FileManager.default.fileExists(atPath: marker.path) {
                return candidate
            }
            candidate.deleteLastPathComponent()
        }
        throw RealProcessingCLIFixtureError.repositoryRootNotFound
    }

    private static func cliEnvironment(
        workspaceURL: URL,
        realRuntimeConfiguration: RealRuntimeConfiguration?
    ) -> [String: String] {
        var environment = ProcessInfo.processInfo.environment
        environment["MEETING_ASSISTANT_WORKSPACE"] = workspaceURL.path
        if let realRuntimeConfiguration {
            environment["MEETING_ASSISTANT_TRANSCRIPTION_RUNTIME"] = realRuntimeConfiguration.runtimePath
            environment["MEETING_ASSISTANT_TRANSCRIPTION_MODEL"] = realRuntimeConfiguration.modelPath
            environment["MEETING_ASSISTANT_WHISPER_SMOKE_AUDIO"] = realRuntimeConfiguration.smokeAudioURL.path
        } else {
            environment.removeValue(forKey: "MEETING_ASSISTANT_TRANSCRIPTION_RUNTIME")
            environment.removeValue(forKey: "MEETING_ASSISTANT_TRANSCRIPTION_MODEL")
            environment.removeValue(forKey: "MEETING_ASSISTANT_WHISPER_SMOKE_AUDIO")
        }
        return environment
    }

    private static func realRuntimeConfiguration() throws -> RealRuntimeConfiguration {
        let environment = ProcessInfo.processInfo.environment
        let runtimePath = try nonEmptyEnvironmentValue(
            named: "MEETING_ASSISTANT_TRANSCRIPTION_RUNTIME",
            message: "real runtime bridge smoke requires MEETING_ASSISTANT_TRANSCRIPTION_RUNTIME"
        )
        let modelPath = try nonEmptyEnvironmentValue(
            named: "MEETING_ASSISTANT_TRANSCRIPTION_MODEL",
            message: "real runtime bridge smoke requires MEETING_ASSISTANT_TRANSCRIPTION_MODEL"
        )
        let smokeAudioPath = try nonEmptyEnvironmentValue(
            named: "MEETING_ASSISTANT_WHISPER_SMOKE_AUDIO",
            message: "real runtime bridge smoke requires MEETING_ASSISTANT_WHISPER_SMOKE_AUDIO"
        )
        let smokeAudioURL = URL(fileURLWithPath: smokeAudioPath)
        guard FileManager.default.isReadableFile(atPath: smokeAudioURL.path) else {
            throw RealProcessingCLIFixtureError.missingFixture(path: smokeAudioURL.path)
        }
        guard FileManager.default.isReadableFile(atPath: modelPath) else {
            throw RealProcessingCLIFixtureError.missingFixture(path: modelPath)
        }
        if !FileManager.default.isExecutableFile(atPath: runtimePath) {
            let resolvedRuntime = environment["PATH"]?
                .split(separator: ":")
                .map { URL(fileURLWithPath: String($0)).appendingPathComponent(runtimePath).path }
                .first { FileManager.default.isExecutableFile(atPath: $0) }
            if resolvedRuntime == nil {
                throw RealProcessingCLIFixtureError.missingFixture(path: runtimePath)
            }
        }
        return RealRuntimeConfiguration(
            runtimePath: runtimePath,
            modelPath: modelPath,
            smokeAudioURL: smokeAudioURL
        )
    }

    private static func nonEmptyEnvironmentValue(named name: String, message: String) throws -> String {
        guard let value = ProcessInfo.processInfo.environment[name]?
            .trimmingCharacters(in: .whitespacesAndNewlines),
            !value.isEmpty
        else {
            throw RealProcessingCLIFixtureError.missingConfiguration(message)
        }
        return value
    }

    private static func writeFixtureWAV(to url: URL) throws {
        var pcm = Data()
        for index in 0..<1_600 {
            let sample = Int16(((index % 64) - 32) * 128)
            pcm.appendLittleEndian(sample)
        }

        var wav = Data()
        wav.appendASCII("RIFF")
        wav.appendLittleEndian(UInt32(36 + pcm.count))
        wav.appendASCII("WAVE")
        wav.appendASCII("fmt ")
        wav.appendLittleEndian(UInt32(16))
        wav.appendLittleEndian(UInt16(1))
        wav.appendLittleEndian(UInt16(1))
        wav.appendLittleEndian(UInt32(8_000))
        wav.appendLittleEndian(UInt32(8_000 * 2))
        wav.appendLittleEndian(UInt16(2))
        wav.appendLittleEndian(UInt16(16))
        wav.appendASCII("data")
        wav.appendLittleEndian(UInt32(pcm.count))
        wav.append(pcm)
        try wav.write(to: url)
    }

    private static func sha256(_ url: URL) throws -> String {
        let digest = SHA256.hash(data: try Data(contentsOf: url))
        let hex = digest.map { String(format: "%02x", $0) }.joined()
        return "sha256:\(hex)"
    }

    private struct RealRuntimeConfiguration {
        let runtimePath: String
        let modelPath: String
        let smokeAudioURL: URL
    }
}

private final class VSMA21ProcessingHardeningBridgeFixture {
    let rootURL: URL
    let workspaceURL: URL
    let runner: ProcessingCommandProcessRunner

    private let invocationsURL: URL

    init() throws {
        rootURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("meeting-assistant-vsma21-bridge-\(UUID().uuidString)", isDirectory: true)
        workspaceURL = rootURL.appendingPathComponent("workspace", isDirectory: true)
        invocationsURL = rootURL.appendingPathComponent("invocations.txt")

        try FileManager.default.createDirectory(at: workspaceURL, withIntermediateDirectories: true)
        let scriptURL = try Self.repositoryRootURL()
            .appendingPathComponent("platform/native-app/test-fixtures/processing-command-fixture.sh")
        guard FileManager.default.isExecutableFile(atPath: scriptURL.path) else {
            throw VSMA21ProcessingHardeningBridgeFixtureError.fixtureScriptMissing(scriptURL.path)
        }

        runner = ProcessingCommandProcessRunner(
            executablePath: scriptURL.path,
            environment: [
                "MEETING_ASSISTANT_WORKSPACE": workspaceURL.path,
                "MA_NATIVE_PROCESSING_FIXTURE_MODE": "path-conflict-then-success",
                "MA_NATIVE_PROCESSING_FIXTURE_INVOCATIONS": invocationsURL.path,
            ]
        )
    }

    deinit {
        try? FileManager.default.removeItem(at: rootURL)
    }

    func createNativeRecordingSession() throws -> String {
        let sessionID = "session-vs-ma-21-hardening-bridge"
        let sessionRootURL = self.sessionRootURL(sessionID: sessionID)
        let artifactsURL = sessionRootURL.appendingPathComponent("artifacts", isDirectory: true)
        try FileManager.default.createDirectory(at: artifactsURL, withIntermediateDirectories: true)

        let mixedAudioURL = artifactsURL.appendingPathComponent("mixed_audio.wav")
        try Self.writeFixtureWAV(to: mixedAudioURL)
        let checksum = try Self.sha256(mixedAudioURL)
        let now = "2026-07-06T00:00:00Z"
        try writeJSON(
            [
                "id": sessionID,
                "title": "VS-MA-21 native hardening bridge fixture",
                "source_type": "native_recording",
                "status": "recorded",
                "started_at": now,
                "workspace_dir": sessionRootURL.path,
                "created_at": now,
                "updated_at": now,
                "artifacts": [
                    [
                        "id": "artifact-vsma21-hardening-mixed",
                        "session_id": sessionID,
                        "artifact_type": "mixed_audio",
                        "path": "artifacts/mixed_audio.wav",
                        "format": "wav",
                        "capture_status": "available",
                        "checksum": checksum,
                        "created_at": now,
                    ],
                ],
            ],
            to: sessionRootURL.appendingPathComponent("session.json")
        )
        return sessionID
    }

    func mixedAudioChecksum(sessionID: String) throws -> String {
        try Self.sha256(
            sessionRootURL(sessionID: sessionID)
                .appendingPathComponent("artifacts/mixed_audio.wav")
        )
    }

    func transcriptExists(sessionID: String) throws -> Bool {
        FileManager.default.fileExists(
            atPath: sessionRootURL(sessionID: sessionID)
                .appendingPathComponent("artifacts/transcript.json")
                .path
        )
    }

    func artifactTypes(sessionID: String) throws -> [String] {
        let data = try Data(contentsOf: sessionRootURL(sessionID: sessionID).appendingPathComponent("session.json"))
        let payload = try JSONSerialization.jsonObject(with: data) as? [String: Any]
        let artifacts = try #require(payload?["artifacts"] as? [[String: Any]])
        return artifacts.compactMap { $0["artifact_type"] as? String }
    }

    func recordedInvocationLines() throws -> [String] {
        try String(contentsOf: invocationsURL, encoding: .utf8)
            .split(separator: "\n")
            .map(String.init)
    }

    private func sessionRootURL(sessionID: String) -> URL {
        workspaceURL
            .appendingPathComponent("sessions", isDirectory: true)
            .appendingPathComponent(sessionID, isDirectory: true)
    }

    private func writeJSON(_ payload: Any, to url: URL) throws {
        let data = try JSONSerialization.data(withJSONObject: payload, options: [.prettyPrinted, .sortedKeys])
        try data.write(to: url)
    }

    private static func repositoryRootURL(filePath: String = #filePath) throws -> URL {
        if let configured = ProcessInfo.processInfo.environment["MEETING_ASSISTANT_REPO_ROOT"],
           !configured.isEmpty {
            return URL(fileURLWithPath: configured, isDirectory: true)
                .standardizedFileURL
                .resolvingSymlinksInPath()
        }

        var candidate = URL(fileURLWithPath: filePath, isDirectory: false)
            .deletingLastPathComponent()
            .standardizedFileURL
        while candidate.path != "/" {
            let marker = candidate.appendingPathComponent(
                "platform/native-app/test-fixtures/processing-command-fixture.sh",
                isDirectory: false
            )
            if FileManager.default.fileExists(atPath: marker.path) {
                return candidate
            }
            candidate.deleteLastPathComponent()
        }
        throw VSMA21ProcessingHardeningBridgeFixtureError.repositoryRootNotFound
    }

    private static func writeFixtureWAV(to url: URL) throws {
        var pcm = Data()
        for index in 0..<1_600 {
            let sample = Int16(((index % 64) - 32) * 128)
            pcm.appendLittleEndian(sample)
        }

        var wav = Data()
        wav.appendASCII("RIFF")
        wav.appendLittleEndian(UInt32(36 + pcm.count))
        wav.appendASCII("WAVE")
        wav.appendASCII("fmt ")
        wav.appendLittleEndian(UInt32(16))
        wav.appendLittleEndian(UInt16(1))
        wav.appendLittleEndian(UInt16(1))
        wav.appendLittleEndian(UInt32(8_000))
        wav.appendLittleEndian(UInt32(8_000 * 2))
        wav.appendLittleEndian(UInt16(2))
        wav.appendLittleEndian(UInt16(16))
        wav.appendASCII("data")
        wav.appendLittleEndian(UInt32(pcm.count))
        wav.append(pcm)
        try wav.write(to: url)
    }

    private static func sha256(_ url: URL) throws -> String {
        let digest = SHA256.hash(data: try Data(contentsOf: url))
        let hex = digest.map { String(format: "%02x", $0) }.joined()
        return "sha256:\(hex)"
    }
}

private enum VSMA21ProcessingHardeningBridgeFixtureError: Error, CustomStringConvertible {
    case fixtureScriptMissing(String)
    case repositoryRootNotFound

    var description: String {
        switch self {
        case .fixtureScriptMissing(let path):
            return "VS-MA-21 hardening fixture script is missing or not executable: \(path)"
        case .repositoryRootNotFound:
            return "repository root containing platform/native-app/test-fixtures was not found"
        }
    }
}

private enum RealProcessingCLIFixtureError: Error, CustomStringConvertible {
    case commandFailed(stdout: String, stderr: String)
    case invalidJSON(stdout: String)
    case missingConfiguration(String)
    case missingFixture(path: String)
    case repositoryRootNotFound

    var description: String {
        switch self {
        case .commandFailed(let stdout, let stderr):
            return "real processing CLI command failed; stdout=\(stdout), stderr=\(stderr)"
        case .invalidJSON(let stdout):
            return "real processing CLI returned invalid JSON: \(stdout)"
        case .missingConfiguration(let message):
            return message
        case .missingFixture(let path):
            return "real processing CLI fixture is missing or unreadable: \(path)"
        case .repositoryRootNotFound:
            return "repository root containing platform/processing-cli/src was not found"
        }
    }
}

private extension Data {
    mutating func appendASCII(_ value: String) {
        append(value.data(using: .ascii)!)
    }

    mutating func appendLittleEndian(_ value: UInt16) {
        append(UInt8(value & 0xff))
        append(UInt8((value >> 8) & 0xff))
    }

    mutating func appendLittleEndian(_ value: UInt32) {
        append(UInt8(value & 0xff))
        append(UInt8((value >> 8) & 0xff))
        append(UInt8((value >> 16) & 0xff))
        append(UInt8((value >> 24) & 0xff))
    }

    mutating func appendLittleEndian(_ value: Int16) {
        appendLittleEndian(UInt16(bitPattern: value))
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
        case noisyStderrTranscriptSuccess
        case structuredTranscriptFailure
        case nonJSONTranscriptFailure(exitCode: Int32)
        case invalidJSONTranscriptFailure
        case hangingAfterSensitiveOutput
        case backgroundDescendantHoldingPipes
    }

    let rootURL: URL
    let workspaceURL: URL
    let scriptURL: URL
    let argsURL: URL
    let invocationsURL: URL
    let pidURL: URL
    let runner: ProcessingCommandProcessRunner

    init(
        script: Script = .success,
        timeoutSeconds: TimeInterval = ProcessingCommandProcessRunner.defaultTimeoutSeconds
    ) throws {
        rootURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("meeting-assistant-processing-tests-\(UUID().uuidString)", isDirectory: true)
        workspaceURL = rootURL.appendingPathComponent("workspace", isDirectory: true)
        scriptURL = rootURL.appendingPathComponent("meeting-assistant-cli")
        argsURL = rootURL.appendingPathComponent("args.txt")
        invocationsURL = rootURL.appendingPathComponent("invocations.txt")
        pidURL = rootURL.appendingPathComponent("pid.txt")

        try FileManager.default.createDirectory(at: workspaceURL, withIntermediateDirectories: true)
        try Self.script(script).write(to: scriptURL, atomically: true, encoding: .utf8)
        try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: scriptURL.path)

        runner = ProcessingCommandProcessRunner(
            executablePath: scriptURL.path,
            environment: [
                "MEETING_ASSISTANT_TEST_ARGS_FILE": argsURL.path,
                "MEETING_ASSISTANT_TEST_INVOCATIONS_FILE": invocationsURL.path,
                "MEETING_ASSISTANT_TEST_PID_FILE": pidURL.path,
                "MEETING_ASSISTANT_WORKSPACE": workspaceURL.path,
            ],
            timeoutSeconds: timeoutSeconds
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

    func recordedProcessIsRunning() throws -> Bool {
        let rawPID = try String(contentsOf: pidURL, encoding: .utf8)
            .trimmingCharacters(in: .whitespacesAndNewlines)
        guard let pid = Int32(rawPID) else {
            throw NSError(
                domain: "ProcessingProcessRunnerFixture",
                code: 1,
                userInfo: [NSLocalizedDescriptionKey: "The hanging fixture did not record a valid process ID."]
            )
        }
        return Darwin.kill(pid, 0) == 0
    }

    func recordedProcessStartDate() throws -> Date {
        let attributes = try FileManager.default.attributesOfItem(atPath: pidURL.path)
        guard let date = attributes[.modificationDate] as? Date else {
            throw NSError(
                domain: "ProcessingProcessRunnerFixture",
                code: 2,
                userInfo: [NSLocalizedDescriptionKey: "The background descendant did not record a start time."]
            )
        }
        return date
    }

    func recordedProcessStopsWithin(timeoutSeconds: TimeInterval) throws -> Bool {
        let deadline = Date().addingTimeInterval(timeoutSeconds)
        while try recordedProcessIsRunning() {
            guard Date() < deadline else {
                return false
            }
            usleep(10_000)
        }
        return true
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
        case .noisyStderrTranscriptSuccess:
            transcriptCase = """
                i=0
                while [ "$i" -lt 4096 ]; do
                  printf '%s\\n' "whisper.cpp progress line with local runtime diagnostics and token timing noise" >&2
                  i=$((i + 1))
                done
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
        case .hangingAfterSensitiveOutput:
            transcriptCase = """
                printf '%s\\n' "$$" > "$MEETING_ASSISTANT_TEST_PID_FILE"
                printf '%s\\n' "processing stalled at /Users/jerry/Movies/MeetingAssistant/session with sk-processing-timeout-secret" >&2
                trap '' TERM
                fifo="$MEETING_ASSISTANT_TEST_PID_FILE.fifo"
                /usr/bin/mkfifo "$fifo"
                read blocked < "$fifo"
            """
        case .backgroundDescendantHoldingPipes:
            transcriptCase = """
                (
                  trap '' TERM
                  printf '%s\\n' "processing descendant retained /Users/jerry/Movies/MeetingAssistant/session with sk-processing-descendant-secret" >&2
                  /bin/sleep 10
                ) &
                printf '%s\\n' "$!" > "$MEETING_ASSISTANT_TEST_PID_FILE"
                exit 5
            """
        }
        let speakerStatus: String
        switch script {
        case .labeledSuccess, .noisyStderrTranscriptSuccess, .structuredTranscriptFailure,
                .nonJSONTranscriptFailure(_), .invalidJSONTranscriptFailure, .hangingAfterSensitiveOutput,
                .backgroundDescendantHoldingPipes:
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
