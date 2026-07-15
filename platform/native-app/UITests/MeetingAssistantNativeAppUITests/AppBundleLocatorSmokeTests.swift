import CryptoKit
import AppKit
import XCTest

final class AppBundleLocatorSmokeTests: XCTestCase {
    private var launchedApp: XCUIApplication?

    override func setUp() {
        continueAfterFailure = false
    }

    override func tearDown() {
        launchedApp?.terminate()
        if let launchedApp {
            _ = launchedApp.wait(for: .notRunning, timeout: 5)
        }
        launchedApp = nil
    }

    func testDefaultBlockedFixtureLaunchesAppBundleAndExposesReadinessLocators() {
        let app = launchApp()

        assertElement("ma.meetings.heading", in: app, contains: "Meetings")
        assertExists("ma.meetings.newRecordingButton", in: app)

        tapButton("ma.navigation.diagnostics", in: app)
        assertElement("ma.permissionDependency.heading", in: app, contains: "Meeting Assistant Readiness")
        assertElement(
            "ma.permissionDependency.summary",
            in: app,
            contains: "Recording and processing are blocked by missing permissions and dependencies."
        )
        assertElement(
            "ma.permission.permission.screen_recording.status",
            in: app,
            contains: "Screen Recording"
        )
        assertElement(
            "ma.permission.permission.screen_recording.status",
            in: app,
            contains: "denied"
        )
        assertElement("ma.dependency.media_tool.ffmpeg.status", in: app, contains: "FFmpeg executable was not found.")

        tapButton("ma.navigation.newRecording", in: app)
        assertElement("ma.newRecording.heading", in: app, contains: "Set up your recording")
        assertElement("ma.newRecording.readiness", in: app, contains: "Setup needs attention")
        XCTAssertTrue(button("ma.recording.startButton", in: app).exists)
        XCTAssertFalse(button("ma.recording.startButton", in: app).isEnabled)
        assertDoesNotExist("ma.recording.stopButton", in: app)
        assertDoesNotExist("ma.processing.startButton", in: app)
    }

    func testReadyFixtureStartsAndStopsFakeRecordingFromLaunchedAppBundle() {
        let app = launchApp(fixture: "ready")

        assertElement("ma.meetings.heading", in: app, contains: "Meetings")
        ensureNewRecordingRoute(in: app)
        assertElement("ma.newRecording.readiness", in: app, contains: "Ready to record")
        tapButton("ma.recording.startButton", in: app)

        assertElement("ma.recording.status", in: app, contains: "Recording in progress.")
        assertElement("ma.recording.sessionID", in: app, contains: "session-app-ui-smoke")
        tapRecordingButton(
            "ma.recording.stopButton",
            in: app,
            expectingStatus: "Recording saved."
        )

        assertElement("ma.recording.status", in: app, contains: "Recording saved.")
        assertElement("ma.recording.savedSummary", in: app, contains: "Saved 2 recording artifacts.")
    }

    func testControlledNativeRecordingClientWritesSessionArtifactsFromLaunchedAppBundle() throws {
        let recordingFixture = try AppControlledRecordingFixture()
        defer { recordingFixture.cleanup() }
        let app = launchApp(fixture: "ready", recordingFixture: recordingFixture)

        tapButton("ma.recording.startButton", in: app)

        assertRecordingStarted(in: app)
        assertElement("ma.recording.sessionID", in: app, contains: recordingFixture.sessionID)
        tapRecordingButton(
            "ma.recording.stopButton",
            in: app,
            expectingStatus: "Recording saved."
        )

        assertElement("ma.recording.status", in: app, contains: "Recording saved.")
        assertElement("ma.recording.savedSummary", in: app, contains: "Saved 1 recording artifact.")
        assertElement("ma.recording.artifact.screen_video.status", in: app, contains: "screen_video: available")
        assertElement("ma.recording.artifact.system_audio.status", in: app, contains: "system_audio: missing")
        assertElement(
            "ma.recording.artifact.system_audio.degradation",
            in: app,
            contains: "system audio unavailable in controlled app fixture"
        )
        assertElement("ma.recording.artifact.microphone_audio.status", in: app, contains: "microphone_audio: degraded")
        assertElement(
            "ma.recording.artifact.microphone_audio.degradation",
            in: app,
            contains: "microphone audio degraded in controlled app fixture"
        )
        assertElement("ma.recording.artifact.mixed_audio.status", in: app, contains: "mixed_audio: missing")

        let session = try recordingFixture.sessionMetadata()
        XCTAssertEqual(session["id"] as? String, recordingFixture.sessionID)
        XCTAssertEqual(session["source_type"] as? String, "native_recording")
        XCTAssertEqual(session["status"] as? String, "recorded")
        XCTAssertEqual(session["workspace_dir"] as? String, recordingFixture.sessionRootURL.path)
        let artifacts = try XCTUnwrap(session["artifacts"] as? [[String: Any]])
        XCTAssertEqual(artifacts.count, 4)
        XCTAssertEqual(artifacts.filter { $0["capture_status"] as? String == "available" }.count, 1)
        XCTAssertEqual(artifacts.compactMap { $0["checksum"] as? String }.count, 1)
        XCTAssertEqual(artifacts.compactMap { $0["degradation_reason"] as? String }.count, 3)
        XCTAssertTrue(FileManager.default.fileExists(atPath: recordingFixture.artifactURL("screen_video.mov").path))

        assertDoesNotExist("ma.processing.startButton", in: app)
    }

    func testOptInAppleScreenCaptureKitRecordsFromDesignedShellWhenExplicitlyEnabled() throws {
        guard ProcessInfo.processInfo.environment["MA_NATIVE_APP_REAL_CAPTURE_SMOKE"] == "1" else {
            throw XCTSkip("Set MA_NATIVE_APP_REAL_CAPTURE_SMOKE=1 to run the opt-in app-bundle ScreenCaptureKit smoke.")
        }

        let recordingFixture = try AppAppleScreenCaptureKitRecordingFixture()
        defer { recordingFixture.cleanup() }
        let app = launchApp(fixture: "ready", realCaptureFixture: recordingFixture)

        tapButton("ma.recording.startButton", in: app)

        assertRecordingStarted(in: app)
        assertElement("ma.recording.sessionID", in: app, contains: recordingFixture.sessionID)
        Thread.sleep(forTimeInterval: 2.2)
        tapRecordingButton(
            "ma.recording.stopButton",
            in: app,
            expectingStatus: "Recording saved."
        )

        assertElement("ma.recording.status", in: app, contains: "Recording saved.")
        assertElement("ma.recording.savedSummary", in: app, contains: "Saved 1 recording artifact.")
        assertElement("ma.recording.artifact.screen_video.status", in: app, contains: "screen_video: available")
        assertElement("ma.recording.artifact.system_audio.status", in: app, contains: "system_audio: missing")
        assertElement("ma.recording.artifact.microphone_audio.status", in: app, contains: "microphone_audio: missing")
        assertElement("ma.recording.artifact.mixed_audio.status", in: app, contains: "mixed_audio: missing")

        let session = try recordingFixture.sessionMetadata()
        XCTAssertEqual(session["id"] as? String, recordingFixture.sessionID)
        XCTAssertEqual(session["source_type"] as? String, "native_recording")
        XCTAssertEqual(session["status"] as? String, "recorded")
        let artifacts = try XCTUnwrap(session["artifacts"] as? [[String: Any]])
        let screenVideo = try XCTUnwrap(artifacts.first { $0["artifact_type"] as? String == "screen_video" })
        XCTAssertEqual(screenVideo["capture_status"] as? String, "available")
        let screenVideoPath = try XCTUnwrap(screenVideo["path"] as? String)
        XCTAssertTrue(screenVideoPath.hasPrefix("artifacts/"))
        XCTAssertFalse(screenVideoPath.contains(".."))
        let checksum = try XCTUnwrap(screenVideo["checksum"] as? String)
        XCTAssertTrue(checksum.hasPrefix("sha256:"))
        let screenVideoURL = recordingFixture.sessionRootURL.appendingPathComponent(screenVideoPath)
        let fileSize = try XCTUnwrap(screenVideoURL.resourceValues(forKeys: [.fileSizeKey]).fileSize)
        XCTAssertGreaterThan(fileSize, 0)
        XCTAssertEqual(artifacts.first { $0["artifact_type"] as? String == "system_audio" }?["capture_status"] as? String, "missing")
        XCTAssertEqual(artifacts.first { $0["artifact_type"] as? String == "microphone_audio" }?["capture_status"] as? String, "missing")
        XCTAssertEqual(artifacts.first { $0["artifact_type"] as? String == "mixed_audio" }?["capture_status"] as? String, "missing")
    }

    func testVSMA21RealScreenCaptureKitProcessingTranscriptActionsSameChainWhenExplicitlyEnabled() throws {
        try XCTSkipUnless(
            Self.realCaptureSameChainCLISmokeEnabled(),
            "Set MA_NATIVE_APP_REAL_CAPTURE_SAME_CHAIN_SMOKE=1 to run the VS-MA-21 real capture same-chain app-bundle smoke."
        )

        let fixture = try AppRealCaptureSameChainCLIFixture()
        defer { fixture.cleanup() }
        let app = launchApp(fixture: "ready", realCaptureSameChainFixture: fixture)

        tapButton("ma.recording.startButton", in: app)

        assertRecordingStarted(in: app)
        assertElement("ma.recording.sessionID", in: app, contains: fixture.sessionID)
        Thread.sleep(forTimeInterval: 3.0)
        tapRecordingButton(
            "ma.recording.stopButton",
            in: app,
            expectingStatus: "Recording saved."
        )

        assertElement("ma.recording.status", in: app, contains: "Recording saved.")
        assertElement("ma.recording.artifact.screen_video.status", in: app, contains: "screen_video: available")
        assertElement("ma.recording.artifact.microphone_audio.status", in: app, contains: "microphone_audio: missing")

        let recordedSession = try fixture.sessionMetadata()
        let recordedArtifacts = try XCTUnwrap(recordedSession["artifacts"] as? [[String: Any]])
        let mixedAudio = try XCTUnwrap(
            recordedArtifacts.first { $0["artifact_type"] as? String == "mixed_audio" },
            "Real capture same-chain smoke requires ScreenCaptureKit to register mixed_audio."
        )
        XCTAssertEqual(
            mixedAudio["capture_status"] as? String,
            "available",
            "Real capture same-chain smoke requires mixed_audio available; current capture is \(mixedAudio["capture_status"] ?? "<missing>")."
        )
        let originalMixedAudioChecksum = try fixture.mixedAudioChecksum()

        tapProcessingButton(
            "ma.processing.startButton",
            in: app,
            expectingStatus: "Processing completed with transcript-only speaker labels."
        )

        assertElement(
            "ma.processing.status",
            in: app,
            contains: "Processing completed with transcript-only speaker labels."
        )
        assertElement("ma.processing.transcriptStatus", in: app, contains: "generated with 1 segment")
        assertElement("ma.processing.degradation", in: app, contains: "transcript-only fallback")
        assertDoesNotExist("ma.processing.error", in: app)
        XCTAssertEqual(try fixture.mixedAudioChecksum(), originalMixedAudioChecksum)

        let processedSession = try fixture.sessionMetadata()
        let processedArtifacts = try XCTUnwrap(processedSession["artifacts"] as? [[String: Any]])
        let processedArtifactTypes = Set(processedArtifacts.compactMap { $0["artifact_type"] as? String })
        XCTAssertTrue(
            processedArtifactTypes.isSuperset(of: ["screen_video", "mixed_audio", "normalized_audio", "transcript_text", "speaker_labels"])
        )

        let reviewApp = launchApp(
            workspaceURL: fixture.workspaceURL,
            sessionID: fixture.sessionID,
            realCaptureSameChainFixture: fixture
        )

        assertElement("ma.transcript.heading", in: reviewApp, contains: "UI smoke recording")
        assertElement("ma.transcript.summary", in: reviewApp, contains: "Transcript has 1 segment for review.")
        assertElement(
            "ma.transcript.text.segment-0001",
            in: reviewApp,
            contains: "Fake transcript generated from local audio."
        )
        assertElement("ma.transcript.degradation", in: reviewApp, contains: "transcript-only fallback")
        assertElement("ma.transcriptAction.status", in: reviewApp, contains: "Transcript actions are ready.")

        tapTranscriptActionButton("ma.transcriptAction.copyButton", in: reviewApp)
        assertElement("ma.transcriptAction.status", in: reviewApp, contains: "Copy complete.")

        tapTranscriptActionButton("ma.transcriptAction.exportButton", in: reviewApp)
        assertElement("ma.transcriptAction.status", in: reviewApp, contains: "Export complete.")
        assertElement("ma.transcriptAction.success", in: reviewApp, contains: fixture.exportURL.path)
        XCTAssertTrue(FileManager.default.fileExists(atPath: fixture.exportURL.path))
        XCTAssertTrue(try fixture.exportContent().contains("Fake transcript generated from local audio."))

        tapTranscriptActionButton("ma.transcriptAction.deleteButton", in: reviewApp)
        assertElement("ma.transcriptAction.deletePromptText", in: reviewApp, contains: fixture.sessionID)
        assertElement("ma.transcriptAction.deletePromptText", in: reviewApp, contains: "External exports are retained.")
        tapTranscriptActionButton("ma.transcriptAction.deleteConfirmButton", in: reviewApp)

        assertElement("ma.transcriptAction.status", in: reviewApp, contains: "Delete complete.")
        assertElement("ma.transcriptAction.success", in: reviewApp, contains: "Deleted session \(fixture.sessionID).")
        assertElement("ma.transcriptAction.success", in: reviewApp, contains: "Retained 1 external export.")
        XCTAssertFalse(FileManager.default.fileExists(atPath: fixture.sessionRootURL.path))
        XCTAssertTrue(FileManager.default.fileExists(atPath: fixture.exportURL.path))
        let deleteEvent = try fixture.deleteEventContent()
        XCTAssertTrue(deleteEvent.contains("meeting_session.deleted.v1"))
        XCTAssertTrue(deleteEvent.contains(fixture.sessionID))
        XCTAssertFalse(deleteEvent.contains("Fake transcript generated from local audio."))
    }

    func testVSMA23RealScreenCaptureKitWhisperRuntimeTranscriptActionsSameChainWhenExplicitlyEnabled() throws {
        try XCTSkipUnless(
            Self.realCaptureRealRuntimeSameChainCLISmokeEnabled(),
            "Set MA_NATIVE_APP_REAL_CAPTURE_REAL_RUNTIME_SAME_CHAIN_SMOKE=1 to run the VS-MA-23 real capture + real runtime app-bundle smoke."
        )

        let fixture = try AppRealCaptureSameChainCLIFixture(realRuntime: true)
        defer { fixture.cleanup() }
        let app = launchApp(fixture: "ready", realCaptureSameChainFixture: fixture)

        tapButton("ma.recording.startButton", in: app)

        assertRecordingStarted(in: app)
        assertElement("ma.recording.sessionID", in: app, contains: fixture.sessionID)
        Thread.sleep(forTimeInterval: 1.0)
        let playback = try fixture.startSmokeAudioPlayback()
        defer { fixture.terminateSmokeAudioPlayback(playback) }
        try fixture.waitForSmokeAudioPlayback(playback, timeout: 15)
        Thread.sleep(forTimeInterval: 1.0)
        tapRecordingButton(
            "ma.recording.stopButton",
            in: app,
            expectingStatus: "Recording saved."
        )

        assertElement("ma.recording.status", in: app, contains: "Recording saved.")
        assertElement("ma.recording.artifact.screen_video.status", in: app, contains: "screen_video: available")
        assertElement("ma.recording.artifact.microphone_audio.status", in: app, contains: "microphone_audio: missing")

        let recordedSession = try fixture.sessionMetadata()
        let recordedArtifacts = try XCTUnwrap(recordedSession["artifacts"] as? [[String: Any]])
        let mixedAudio = try XCTUnwrap(
            recordedArtifacts.first { $0["artifact_type"] as? String == "mixed_audio" },
            "Real capture + real runtime same-chain smoke requires ScreenCaptureKit to register mixed_audio."
        )
        XCTAssertEqual(
            mixedAudio["capture_status"] as? String,
            "available",
            "Real capture + real runtime same-chain smoke requires mixed_audio available; current capture is \(mixedAudio["capture_status"] ?? "<missing>")."
        )
        let originalMixedAudioChecksum = try fixture.mixedAudioChecksum()

        tapProcessingButton(
            "ma.processing.startButton",
            in: app,
            expectingStatus: "Processing completed with transcript-only speaker labels."
        )

        assertElement(
            "ma.processing.status",
            in: app,
            contains: "Processing completed with transcript-only speaker labels."
        )
        assertElement("ma.processing.transcriptStatus", in: app, contains: "generated with")
        assertElement("ma.processing.degradation", in: app, contains: "transcript-only fallback")
        assertDoesNotExist("ma.processing.error", in: app)
        XCTAssertEqual(try fixture.mixedAudioChecksum(), originalMixedAudioChecksum)

        let transcript = try fixture.transcriptPayload()
        let transcriptText = try Self.transcriptText(from: transcript)
        XCTAssertFalse(
            transcriptText.contains("Fake transcript generated from local audio."),
            "Expected real runtime transcript, not the fake transcript fixture."
        )
        XCTAssertTrue(
            transcriptText.range(of: #"\p{Han}"#, options: .regularExpression) != nil,
            "Expected real runtime transcript to contain Chinese text. Transcript: \(transcriptText)"
        )
        for term in ["http", "llm", "clean architecture", "eda"] {
            XCTAssertTrue(
                Self.transcriptContains(transcriptText, term: term),
                "Expected real runtime transcript to contain \(term). Transcript: \(transcriptText)"
            )
        }

        let reviewApp = launchApp(
            workspaceURL: fixture.workspaceURL,
            sessionID: fixture.sessionID,
            realCaptureSameChainFixture: fixture
        )

        assertElement("ma.transcript.heading", in: reviewApp, contains: "UI smoke recording")
        assertElement("ma.transcript.summary", in: reviewApp, contains: "Transcript has")
        assertElement("ma.transcript.degradation", in: reviewApp, contains: "transcript-only fallback")
        assertElement("ma.transcriptAction.status", in: reviewApp, contains: "Transcript actions are ready.")

        tapTranscriptActionButton("ma.transcriptAction.copyButton", in: reviewApp)
        assertElement("ma.transcriptAction.status", in: reviewApp, contains: "Copy complete.")

        tapTranscriptActionButton("ma.transcriptAction.exportButton", in: reviewApp)
        assertElement("ma.transcriptAction.status", in: reviewApp, contains: "Export complete.")
        assertElement("ma.transcriptAction.success", in: reviewApp, contains: fixture.exportURL.path)
        XCTAssertTrue(FileManager.default.fileExists(atPath: fixture.exportURL.path))
        let exportContent = try fixture.exportContent()
        XCTAssertFalse(exportContent.contains("Fake transcript generated from local audio."))
        XCTAssertTrue(Self.transcriptContains(exportContent, term: "llm"))

        tapTranscriptActionButton("ma.transcriptAction.deleteButton", in: reviewApp)
        assertElement("ma.transcriptAction.deletePromptText", in: reviewApp, contains: fixture.sessionID)
        assertElement("ma.transcriptAction.deletePromptText", in: reviewApp, contains: "External exports are retained.")
        tapTranscriptActionButton("ma.transcriptAction.deleteConfirmButton", in: reviewApp)

        assertElement("ma.transcriptAction.status", in: reviewApp, contains: "Delete complete.")
        assertElement("ma.transcriptAction.success", in: reviewApp, contains: "Deleted session \(fixture.sessionID).")
        assertElement("ma.transcriptAction.success", in: reviewApp, contains: "Retained 1 external export.")
        XCTAssertFalse(FileManager.default.fileExists(atPath: fixture.sessionRootURL.path))
        XCTAssertTrue(FileManager.default.fileExists(atPath: fixture.exportURL.path))
        let deleteEvent = try fixture.deleteEventContent()
        XCTAssertTrue(deleteEvent.contains("meeting_session.deleted.v1"))
        XCTAssertTrue(deleteEvent.contains(fixture.sessionID))
        XCTAssertFalse(deleteEvent.contains(transcriptText))
    }

    func testStartFailureFixtureShowsStableErrorLocatorFromLaunchedAppBundle() {
        let app = launchApp(fixture: "start-failure")

        tapButton("ma.recording.startButton", in: app)

        assertElement("ma.recording.status", in: app, contains: "Recording failed.")
        assertElement("ma.recording.error", in: app, contains: "Screen Recording permission is missing.")
        assertElement("ma.recording.error", in: app, contains: "permission_denied")
    }

    func testTranscriptReviewFixtureExposesReadOnlyTranscriptLocatorsFromLaunchedAppBundle() {
        let app = launchApp(fixture: "transcript-review")

        assertElement("ma.transcript.heading", in: app, contains: "Transcript Review Fixture")
        assertElement("ma.transcript.summary", in: app, contains: "Transcript has 2 segments for review.")
        assertExists("ma.transcript.segmentRow.seg-1", in: app)
        assertElement("ma.transcript.timestamp.seg-1", in: app, contains: "00:00-00:05")
        assertElement("ma.transcript.text.seg-1", in: app, contains: "First transcript segment for review.")
        assertElement("ma.transcript.speakerLabel.seg-1", in: app, contains: "Anonymous speaker SPEAKER_01")
        assertElement("ma.transcript.speakerLabel.seg-1", in: app, contains: "not a verified identity")
        assertDoesNotExist("ma.transcript.degradation", in: app)
    }

    func testTranscriptOnlyFixtureShowsDegradationWhenNoSpeakerLabelsAreVisible() {
        let app = launchApp(fixture: "transcript-only")

        assertElement("ma.transcript.heading", in: app, contains: "Transcript-only fixture")
        assertElement("ma.transcript.summary", in: app, contains: "Transcript has 1 segment for review.")
        assertElement("ma.transcript.text.seg-plain", in: app, contains: "Transcript remains available without speaker labels.")
        assertDoesNotExist("ma.transcript.speakerLabel.seg-plain", in: app)
        assertElement("ma.transcript.degradation", in: app, contains: "speaker labeling runtime unavailable")
    }

    func testWorkspaceArtifactLaunchEnvironmentLoadsTranscriptOnlyReviewFromLaunchedAppBundle() throws {
        let fixture = try createWorkspaceTranscriptOnlyFixture()
        defer { try? FileManager.default.removeItem(at: fixture.workspaceURL) }
        let app = launchApp(workspaceURL: fixture.workspaceURL, sessionID: fixture.sessionID)

        assertElement("ma.transcript.heading", in: app, contains: "Workspace injected transcript")
        assertElement("ma.transcript.summary", in: app, contains: "Transcript has 1 segment for review.")
        assertElement("ma.transcript.timestamp.seg-workspace", in: app, contains: "00:02-00:04")
        assertElement("ma.transcript.text.seg-workspace", in: app, contains: "Workspace transcript loaded through launch environment.")
        assertDoesNotExist("ma.transcript.speakerLabel.seg-workspace", in: app)
        assertElement("ma.transcript.degradation", in: app, contains: "speaker labels degraded from session metadata")
    }

    func testEmptyTranscriptFixtureExposesStableEmptyStateFromLaunchedAppBundle() {
        let app = launchApp(fixture: "transcript-empty")

        assertElement("ma.transcript.heading", in: app, contains: "Empty transcript fixture")
        assertElement("ma.transcript.empty", in: app, contains: "Transcript has no segments to review.")
        assertElement("ma.transcript.degradation", in: app, contains: "speaker labeling skipped")
    }

    func testTranscriptActionCopySuccessAndFailureAreUserTriggeredFromLaunchedAppBundle() {
        let successApp = launchApp(fixture: "transcript-action-copy-success")

        assertElement("ma.transcriptAction.heading", in: successApp, contains: "Transcript Actions")
        assertElement("ma.transcriptAction.status", in: successApp, contains: "Transcript actions are ready.")
        tapTranscriptActionButton("ma.transcriptAction.copyButton", in: successApp)

        assertElement("ma.transcriptAction.status", in: successApp, contains: "Copy complete.")
        assertElement(
            "ma.transcriptAction.success",
            in: successApp,
            contains: "Transcript copied."
        )
        assertDoesNotExist("ma.transcriptAction.error", in: successApp)

        let failureApp = launchApp(fixture: "transcript-action-copy-failure")

        tapTranscriptActionButton("ma.transcriptAction.copyButton", in: failureApp)

        assertElement("ma.transcriptAction.status", in: failureApp, contains: "Copy failed.")
        assertElement("ma.transcriptAction.error", in: failureApp, contains: "Transcript artifact is missing.")
        assertElement("ma.transcriptAction.error", in: failureApp, doesNotContain: "artifact_missing")
    }

    func testTranscriptActionExportSuccessCancelAndFailureAreUserTriggeredFromLaunchedAppBundle() {
        let successApp = launchApp(fixture: "transcript-action-export-success")

        tapTranscriptActionButton("ma.transcriptAction.exportButton", in: successApp)

        assertElement("ma.transcriptAction.status", in: successApp, contains: "Export complete.")
        assertElement(
            "ma.transcriptAction.success",
            in: successApp,
            contains: "Transcript exported."
        )

        let cancelApp = launchApp(fixture: "transcript-action-export-cancel")

        tapTranscriptActionButton("ma.transcriptAction.exportButton", in: cancelApp)

        assertElement(
            "ma.transcriptAction.status",
            in: cancelApp,
            contains: "Export cancelled. No command was sent."
        )
        assertDoesNotExist("ma.transcriptAction.success", in: cancelApp)
        assertDoesNotExist("ma.transcriptAction.error", in: cancelApp)

        let failureApp = launchApp(fixture: "transcript-action-export-failure")

        tapTranscriptActionButton("ma.transcriptAction.exportButton", in: failureApp)

        assertElement("ma.transcriptAction.status", in: failureApp, contains: "Export failed.")
        assertElement("ma.transcriptAction.error", in: failureApp, contains: "Export target already exists.")
        assertElement("ma.transcriptAction.error", in: failureApp, doesNotContain: "path_conflict")
    }

    func testTranscriptActionDeleteConfirmCancelSuccessAndFailureFromLaunchedAppBundle() throws {
        let successApp = launchApp(fixture: "transcript-action-delete-success")

        tapTranscriptActionButton("ma.transcriptAction.deleteButton", in: successApp)

        assertExists("ma.transcriptAction.deletePrompt", in: successApp)
        assertElement("ma.transcriptAction.deletePromptText", in: successApp, contains: "session-app-ui-transcript")
        assertElement("ma.transcriptAction.deletePromptText", in: successApp, contains: "External exports are retained.")
        tapTranscriptActionButton("ma.transcriptAction.deleteCancelButton", in: successApp)

        assertElement(
            "ma.transcriptAction.status",
            in: successApp,
            contains: "Delete cancelled. No command was sent."
        )
        assertDoesNotExist("ma.transcriptAction.deletePrompt", in: successApp)

        tapTranscriptActionButton("ma.transcriptAction.deleteButton", in: successApp)
        tapTranscriptActionButton("ma.transcriptAction.deleteConfirmButton", in: successApp)

        assertElement("ma.transcriptAction.status", in: successApp, contains: "Delete complete.")
        assertElement(
            "ma.transcriptAction.success",
            in: successApp,
            contains: "Deleted session session-app-ui-transcript. Removed 3 items. Retained 1 external export."
        )

        let failureFixture = try AppTranscriptActionProcessFixture(mode: "delete-failure")
        defer { failureFixture.cleanup() }
        let failureApp = launchApp(
            workspaceURL: failureFixture.workspaceURL,
            sessionID: failureFixture.sessionID,
            transcriptActionFixture: failureFixture
        )

        tapTranscriptActionButton("ma.transcriptAction.deleteButton", in: failureApp)
        assertExists("ma.transcriptAction.deletePrompt", in: failureApp)
        assertElement("ma.transcriptAction.deletePromptText", in: failureApp, contains: "External exports are retained.")
        tapTranscriptActionButton("ma.transcriptAction.deleteConfirmButton", in: failureApp)

        assertElement("ma.transcriptAction.status", in: failureApp, contains: "Delete failed.")
        assertElement("ma.transcriptAction.error", in: failureApp, contains: "The meeting is still available.")
        assertElement("ma.transcriptAction.error", in: failureApp, doesNotContain: "path_conflict")
        XCTAssertTrue(FileManager.default.fileExists(atPath: failureFixture.sessionRootURL.path))
        XCTAssertEqual(
            try failureFixture.invocationLines(),
            failedDeleteTranscriptActionInvocationLines(
                sessionID: failureFixture.sessionID,
                workspaceURL: failureFixture.workspaceURL
            )
        )
    }

    func testTranscriptActionProcessRunnerLaunchEnvironmentExportsAndDeletesWorkspaceArtifactsFromLaunchedAppBundle() throws {
        let actionFixture = try AppTranscriptActionProcessFixture()
        defer { actionFixture.cleanup() }
        let app = launchApp(
            workspaceURL: actionFixture.workspaceURL,
            sessionID: actionFixture.sessionID,
            transcriptActionFixture: actionFixture
        )

        assertElement("ma.transcript.heading", in: app, contains: "Native action process workspace fixture")
        assertElement("ma.transcriptAction.status", in: app, contains: "Transcript actions are ready.")

        tapTranscriptActionButton("ma.transcriptAction.copyButton", in: app)

        assertElement("ma.transcriptAction.status", in: app, contains: "Copy complete.")
        assertElement(
            "ma.transcriptAction.success",
            in: app,
            contains: "Transcript copied."
        )

        tapTranscriptActionButton("ma.transcriptAction.exportButton", in: app)

        assertElement("ma.transcriptAction.status", in: app, contains: "Export complete.")
        assertElement("ma.transcriptAction.success", in: app, contains: "Transcript exported.")
        assertElement("ma.transcriptAction.success", in: app, doesNotContain: actionFixture.exportURL.path)
        XCTAssertTrue(FileManager.default.fileExists(atPath: actionFixture.exportURL.path))
        XCTAssertTrue(try actionFixture.exportContent().contains("Native action process fixture transcript content."))

        tapTranscriptActionButton("ma.transcriptAction.deleteButton", in: app)
        assertElement("ma.transcriptAction.deletePromptText", in: app, contains: actionFixture.sessionID)
        assertElement("ma.transcriptAction.deletePromptText", in: app, contains: "External exports are retained.")
        tapTranscriptActionButton("ma.transcriptAction.deleteConfirmButton", in: app)

        assertElement("ma.transcriptAction.status", in: app, contains: "Delete complete.")
        assertElement(
            "ma.transcriptAction.success",
            in: app,
            contains: "Deleted session \(actionFixture.sessionID). Removed 3 items. Retained 1 external export."
        )
        XCTAssertFalse(FileManager.default.fileExists(atPath: actionFixture.sessionRootURL.path))
        XCTAssertTrue(FileManager.default.fileExists(atPath: actionFixture.exportURL.path))
        XCTAssertEqual(
            try actionFixture.invocationLines(),
            successfulTranscriptActionInvocationLines(
                sessionID: actionFixture.sessionID,
                workspaceURL: actionFixture.workspaceURL,
                exportURL: actionFixture.exportURL
            )
        )
    }

    func testTranscriptActionProcessRunnerBridgeFailureShowsSafeAppBundleError() throws {
        let actionFixture = try AppTranscriptActionProcessFixture(mode: "non-json-stderr")
        defer { actionFixture.cleanup() }
        let app = launchApp(
            workspaceURL: actionFixture.workspaceURL,
            sessionID: actionFixture.sessionID,
            transcriptActionFixture: actionFixture
        )

        tapTranscriptActionButton("ma.transcriptAction.copyButton", in: app)

        assertElement("ma.transcriptAction.status", in: app, contains: "Copy failed.")
        assertElement(
            "ma.transcriptAction.error",
            in: app,
            contains: "Transcript action command failed before returning a contract response."
        )
        assertElement("ma.transcriptAction.error", in: app, doesNotContain: "internal_error")
        assertElement("ma.transcriptAction.error", in: app, doesNotContain: "customer roadmap")
        assertElement("ma.transcriptAction.error", in: app, doesNotContain: "/Users/jerry")
        assertElement("ma.transcriptAction.error", in: app, doesNotContain: "sk-nativefixturevalue")
        XCTAssertEqual(
            try actionFixture.invocationLines(),
            failedTranscriptActionInvocationLines(sessionID: actionFixture.sessionID)
        )
    }

    func testProcessingSuccessAndTranscriptOnlyDegradationFromLaunchedAppBundle() {
        let successApp = launchApp(fixture: "processing-success")

        tapProcessingButton(
            "ma.processing.startButton",
            in: successApp,
            expectingStatus: "Processing complete."
        )

        assertElement("ma.processing.status", in: successApp, contains: "Processing complete.")
        assertElement(
            "ma.processing.transcriptStatus",
            in: successApp,
            contains: "Transcript transcript-app-processing generated with 2 segments."
        )
        assertElement(
            "ma.processing.speakerLabelStatus",
            in: successApp,
            contains: "Speaker labels artifact artifact-app-speakers is available."
        )
        assertElement(
            "ma.processing.success",
            in: successApp,
            contains: "Generated transcript and speaker labels for session session-app-ui-processing."
        )
        assertDoesNotExist("ma.processing.error", in: successApp)

        let degradedApp = launchApp(fixture: "processing-transcript-only")

        tapProcessingButton(
            "ma.processing.startButton",
            in: degradedApp,
            expectingStatus: "Processing completed with transcript-only speaker labels."
        )

        assertElement(
            "ma.processing.status",
            in: degradedApp,
            contains: "Processing completed with transcript-only speaker labels."
        )
        assertElement(
            "ma.processing.degradation",
            in: degradedApp,
            contains: "speaker labeling runtime unavailable"
        )
        assertDoesNotExist("ma.processing.error", in: degradedApp)
    }

    func testProcessingFailureKeepsRetryAvailableFromLaunchedAppBundle() {
        let app = launchApp(fixture: "processing-failure")

        tapProcessingButton("ma.processing.startButton", in: app)

        assertElement("ma.processing.status", in: app, contains: "Processing failed.")
        assertElement("ma.processing.error", in: app, contains: "Transcript adapter failed.")
        assertElement("ma.processing.error", in: app, contains: "processing_failed")
        XCTAssertTrue(button("ma.processing.retryButton", in: app).isEnabled)

        tapProcessingButton("ma.processing.retryButton", in: app)

        assertElement("ma.processing.status", in: app, contains: "Processing failed.")
        assertElement("ma.processing.error", in: app, contains: "Transcript adapter failed.")
    }

    func testProcessingProcessRunnerLaunchEnvironmentDrivesAppBundleProcessingStates() throws {
        let successFixture = try AppProcessingProcessFixture(mode: "success")
        let successApp = launchApp(fixture: "processing-success", processingFixture: successFixture)

        tapProcessingButton("ma.processing.startButton", in: successApp)

        assertElement("ma.processing.status", in: successApp, contains: "Processing complete.")
        assertElement(
            "ma.processing.transcriptStatus",
            in: successApp,
            contains: "Transcript transcript-process-fixture generated with 2 segments."
        )
        assertElement(
            "ma.processing.speakerLabelStatus",
            in: successApp,
            contains: "Speaker labels artifact artifact-process-speakers is available."
        )
        assertElement(
            "ma.processing.success",
            in: successApp,
            contains: "Generated transcript and speaker labels for session session-app-ui-processing."
        )
        assertDoesNotExist("ma.processing.error", in: successApp)
        XCTAssertEqual(
            try successFixture.invocationLines(),
            successfulProcessingInvocationLines(sessionID: "session-app-ui-processing")
        )

        let degradedFixture = try AppProcessingProcessFixture(mode: "degraded")
        let degradedApp = launchApp(fixture: "processing-transcript-only", processingFixture: degradedFixture)

        tapProcessingButton("ma.processing.startButton", in: degradedApp)

        assertElement(
            "ma.processing.status",
            in: degradedApp,
            contains: "Processing completed with transcript-only speaker labels."
        )
        assertElement("ma.processing.degradation", in: degradedApp, contains: "speaker labeling runtime unavailable")
        assertDoesNotExist("ma.processing.error", in: degradedApp)
        XCTAssertEqual(
            try degradedFixture.invocationLines(),
            successfulProcessingInvocationLines(sessionID: "session-app-ui-processing")
        )

        let failureFixture = try AppProcessingProcessFixture(mode: "transcript-failure")
        let failureApp = launchApp(fixture: "processing-failure", processingFixture: failureFixture)

        tapProcessingButton(
            "ma.processing.startButton",
            in: failureApp,
            expectingStatus: "Processing failed."
        )

        assertElement("ma.processing.status", in: failureApp, contains: "Processing failed.")
        assertElement("ma.processing.error", in: failureApp, contains: "Transcript adapter failed from process fixture.")
        assertElement("ma.processing.error", in: failureApp, contains: "processing_failed")
        XCTAssertTrue(button("ma.processing.retryButton", in: failureApp).isEnabled)

        tapProcessingButton("ma.processing.retryButton", in: failureApp)

        assertElement("ma.processing.status", in: failureApp, contains: "Processing failed.")
        assertElement("ma.processing.error", in: failureApp, contains: "Transcript adapter failed from process fixture.")
        XCTAssertEqual(
            try failureFixture.invocationLines(),
            failedRetryProcessingInvocationLines(sessionID: "session-app-ui-processing")
        )
    }

    func testProcessingProcessRunnerBridgeFailureShowsSafeAppBundleError() throws {
        let failureFixture = try AppProcessingProcessFixture(mode: "non-json-stderr")
        let app = launchApp(fixture: "processing-failure", processingFixture: failureFixture)

        tapProcessingButton(
            "ma.processing.startButton",
            in: app,
            expectingStatus: "Processing failed."
        )

        assertElement("ma.processing.status", in: app, contains: "Processing failed.")
        assertElement(
            "ma.processing.error",
            in: app,
            contains: "Processing command failed before returning a contract response."
        )
        assertElement("ma.processing.error", in: app, contains: "processing_failed")
        assertElement("ma.processing.error", in: app, doesNotContain: "adapter crashed")
        assertElement("ma.processing.error", in: app, doesNotContain: "/Users/jerry")
        assertElement("ma.processing.error", in: app, doesNotContain: "sk-nativefixturevalue")
        XCTAssertTrue(button("ma.processing.retryButton", in: app).isEnabled)

        tapProcessingButton("ma.processing.retryButton", in: app)

        assertElement("ma.processing.status", in: app, contains: "Processing failed.")
        assertElement(
            "ma.processing.error",
            in: app,
            contains: "Processing command failed before returning a contract response."
        )
        XCTAssertEqual(
            try failureFixture.invocationLines(),
            failedRetryProcessingInvocationLines(sessionID: "session-app-ui-processing")
        )
    }

    func testVSMA21AppBundleProcessingPathConflictRetryPreservesOriginalCaptureArtifactWhenExplicitlyEnabled() throws {
        try XCTSkipUnless(
            Self.vsMA21HardeningCLISmokeEnabled(),
            "Set MA_NATIVE_APP_VSMA21_HARDENING_SMOKE=1 to run the VS-MA-21 app-bundle hardening smoke."
        )

        let sessionID = "session-app-ui-processing"
        let processingFixture = try AppProcessingProcessFixture(mode: "path-conflict-then-success")
        defer { processingFixture.cleanup() }
        try processingFixture.createNativeRecordingWorkspace(sessionID: sessionID)
        let originalMixedAudioChecksum = try processingFixture.mixedAudioChecksum(sessionID: sessionID)

        let app = launchApp(fixture: "processing-failure", processingFixture: processingFixture)

        tapProcessingButton(
            "ma.processing.startButton",
            in: app,
            expectingStatus: "Processing failed."
        )

        assertElement("ma.processing.status", in: app, contains: "Processing failed.")
        assertElement("ma.processing.error", in: app, contains: "Processing path conflict.")
        assertElement("ma.processing.error", in: app, contains: "path_conflict")
        XCTAssertTrue(button("ma.processing.retryButton", in: app).isEnabled)
        XCTAssertEqual(try processingFixture.mixedAudioChecksum(sessionID: sessionID), originalMixedAudioChecksum)
        XCTAssertFalse(
            FileManager.default.fileExists(
                atPath: processingFixture.artifactURL(sessionID: sessionID, filename: "transcript.json").path
            )
        )

        tapProcessingButton(
            "ma.processing.retryButton",
            in: app,
            expectingStatus: "Processing complete."
        )

        assertElement("ma.processing.status", in: app, contains: "Processing complete.")
        assertElement("ma.processing.transcriptStatus", in: app, contains: "generated with")
        assertElement(
            "ma.processing.success",
            in: app,
            contains: "Generated transcript and speaker labels for session \(sessionID)."
        )
        assertDoesNotExist("ma.processing.error", in: app)
        XCTAssertEqual(try processingFixture.mixedAudioChecksum(sessionID: sessionID), originalMixedAudioChecksum)
        XCTAssertEqual(
            try processingFixture.invocationLines(),
            pathConflictRetryProcessingInvocationLines(sessionID: sessionID)
        )

        let session = try processingFixture.sessionMetadata(sessionID: sessionID)
        let artifacts = try XCTUnwrap(session["artifacts"] as? [[String: Any]])
        let artifactTypes = Set(artifacts.compactMap { $0["artifact_type"] as? String })
        XCTAssertTrue(artifactTypes.isSuperset(of: ["mixed_audio", "transcript_text", "speaker_labels"]))
        XCTAssertEqual(
            artifacts.first { $0["artifact_type"] as? String == "mixed_audio" }?["checksum"] as? String,
            originalMixedAudioChecksum
        )
    }

    func testProcessingProcessRunnerWorkspaceArtifactsLoadThroughTranscriptReview() throws {
        let processingFixture = try AppProcessingProcessFixture(mode: "workspace-success")
        let processingApp = launchApp(fixture: "processing-success", processingFixture: processingFixture)

        tapProcessingButton(
            "ma.processing.startButton",
            in: processingApp,
            expectingStatus: "Processing complete."
        )

        assertElement("ma.processing.status", in: processingApp, contains: "Processing complete.")
        assertElement(
            "ma.processing.transcriptStatus",
            in: processingApp,
            contains: "Transcript transcript-process-fixture generated with 2 segments."
        )
        assertElement(
            "ma.processing.speakerLabelStatus",
            in: processingApp,
            contains: "Speaker labels artifact artifact-process-speakers is available."
        )
        XCTAssertEqual(
            try processingFixture.invocationLines(),
            successfulProcessingInvocationLines(sessionID: "session-app-ui-processing")
        )

        let session = try processingFixture.sessionMetadata(sessionID: "session-app-ui-processing")
        XCTAssertEqual(session["id"] as? String, "session-app-ui-processing")
        XCTAssertEqual(session["source_type"] as? String, "native_recording")
        XCTAssertEqual(session["status"] as? String, "transcribed")
        let artifacts = try XCTUnwrap(session["artifacts"] as? [[String: Any]])
        XCTAssertEqual(artifacts.count, 2)
        XCTAssertEqual(artifacts.compactMap { $0["artifact_type"] as? String }, ["transcript_text", "speaker_labels"])
        XCTAssertEqual(artifacts.compactMap { $0["capture_status"] as? String }, ["available", "available"])
        XCTAssertEqual(artifacts.compactMap { $0["checksum"] as? String }.count, 2)

        let reviewApp = launchApp(
            workspaceURL: processingFixture.workspaceURL,
            sessionID: "session-app-ui-processing"
        )

        assertElement("ma.transcript.heading", in: reviewApp, contains: "Native process bridge workspace fixture")
        assertElement("ma.transcript.summary", in: reviewApp, contains: "Transcript has 1 segment for review.")
        assertElement("ma.transcript.timestamp.seg-process-1", in: reviewApp, contains: "00:01-00:03")
        assertElement(
            "ma.transcript.text.seg-process-1",
            in: reviewApp,
            contains: "Native process bridge wrote transcript artifact."
        )
        assertElement(
            "ma.transcript.speakerLabel.seg-process-1",
            in: reviewApp,
            contains: "Anonymous speaker SPEAKER_01"
        )
        assertElement(
            "ma.transcript.speakerLabel.seg-process-1",
            in: reviewApp,
            contains: "not a verified identity"
        )
        assertDoesNotExist("ma.transcript.degradation", in: reviewApp)
    }

    func testRealProcessingCLIProcessesNativeRecordingFromLaunchedAppBundleWhenExplicitlyEnabled() throws {
        try XCTSkipUnless(
            Self.realProcessingCLISmokeEnabled(),
            "Set MA_NATIVE_APP_REAL_PROCESSING_SMOKE=1 to run the real processing-cli app-bundle smoke."
        )

        let processingFixture = try AppRealProcessingCLIFixture()
        defer { processingFixture.cleanup() }
        let app = launchApp(fixture: "ready", realProcessingFixture: processingFixture)

        tapProcessingButton(
            "ma.processing.startButton",
            in: app,
            expectingStatus: "Processing completed with transcript-only speaker labels."
        )

        assertElement(
            "ma.processing.status",
            in: app,
            contains: "Processing completed with transcript-only speaker labels."
        )
        assertElement("ma.processing.transcriptStatus", in: app, contains: "generated with 1 segment")
        assertElement("ma.processing.speakerLabelStatus", in: app, contains: "Speaker labels degraded:")
        assertElement("ma.processing.degradation", in: app, contains: "transcript-only fallback")
        assertDoesNotExist("ma.processing.error", in: app)

        let session = try processingFixture.sessionMetadata()
        let artifacts = try XCTUnwrap(session["artifacts"] as? [[String: Any]])
        let artifactTypes = Set(artifacts.compactMap { $0["artifact_type"] as? String })
        XCTAssertTrue(artifactTypes.isSuperset(of: ["mixed_audio", "normalized_audio", "transcript_text", "speaker_labels"]))
        XCTAssertEqual(
            artifacts.first { $0["artifact_type"] as? String == "speaker_labels" }?["capture_status"] as? String,
            "degraded"
        )

        let transcript = try processingFixture.transcriptPayload()
        let segments = try XCTUnwrap(transcript["segments"] as? [[String: Any]])
        XCTAssertEqual(segments.count, 1)
        XCTAssertEqual(segments.first?["text"] as? String, "Fake transcript generated from local audio.")
    }

    func testRealProcessingCLITranscriptReviewExportAndDeleteFromLaunchedAppBundleWhenExplicitlyEnabled() throws {
        try XCTSkipUnless(
            Self.realActionCLISmokeEnabled(),
            "Set MA_NATIVE_APP_REAL_ACTION_SMOKE=1 to run the real processing-cli transcript action app-bundle smoke."
        )

        let processingFixture = try AppRealProcessingCLIFixture()
        defer { processingFixture.cleanup() }
        let processingApp = launchApp(fixture: "ready", realProcessingFixture: processingFixture)

        tapProcessingButton(
            "ma.processing.startButton",
            in: processingApp,
            expectingStatus: "Processing completed with transcript-only speaker labels."
        )

        let reviewApp = launchApp(
            workspaceURL: processingFixture.workspaceURL,
            sessionID: processingFixture.sessionID,
            realProcessingFixture: processingFixture
        )

        assertElement(
            "ma.transcript.heading",
            in: reviewApp,
            contains: "Real processing CLI app-bundle fixture"
        )
        assertElement("ma.transcript.summary", in: reviewApp, contains: "Transcript has 1 segment for review.")
        assertElement(
            "ma.transcript.text.segment-0001",
            in: reviewApp,
            contains: "Fake transcript generated from local audio."
        )
        assertElement("ma.transcript.degradation", in: reviewApp, contains: "transcript-only fallback")
        assertElement("ma.transcriptAction.status", in: reviewApp, contains: "Transcript actions are ready.")

        tapTranscriptActionButton("ma.transcriptAction.copyButton", in: reviewApp)

        assertElement("ma.transcriptAction.status", in: reviewApp, contains: "Copy complete.")
        assertElement(
            "ma.transcriptAction.success",
            in: reviewApp,
            contains: "Transcript copied."
        )

        tapTranscriptActionButton("ma.transcriptAction.exportButton", in: reviewApp)

        assertElement("ma.transcriptAction.status", in: reviewApp, contains: "Export complete.")
        assertElement("ma.transcriptAction.success", in: reviewApp, contains: processingFixture.exportURL.path)
        XCTAssertTrue(FileManager.default.fileExists(atPath: processingFixture.exportURL.path))
        XCTAssertTrue(try processingFixture.exportContent().contains("Fake transcript generated from local audio."))

        tapTranscriptActionButton("ma.transcriptAction.deleteButton", in: reviewApp)
        assertElement("ma.transcriptAction.deletePromptText", in: reviewApp, contains: processingFixture.sessionID)
        assertElement("ma.transcriptAction.deletePromptText", in: reviewApp, contains: "External exports are retained.")
        tapTranscriptActionButton("ma.transcriptAction.deleteConfirmButton", in: reviewApp)

        assertElement("ma.transcriptAction.status", in: reviewApp, contains: "Delete complete.")
        assertElement(
            "ma.transcriptAction.success",
            in: reviewApp,
            contains: "Deleted session \(processingFixture.sessionID)."
        )
        assertElement("ma.transcriptAction.success", in: reviewApp, contains: "Retained 1 external export.")
        XCTAssertFalse(FileManager.default.fileExists(atPath: processingFixture.sessionRootURL.path))
        XCTAssertTrue(FileManager.default.fileExists(atPath: processingFixture.exportURL.path))
        let deleteEvent = try processingFixture.deleteEventContent()
        XCTAssertTrue(deleteEvent.contains("meeting_session.deleted.v1"))
        XCTAssertTrue(deleteEvent.contains(processingFixture.sessionID))
        XCTAssertFalse(deleteEvent.contains("Fake transcript generated from local audio."))
    }

    func testRealProcessingCLISystemClipboardSavePanelExportAndDeleteFromLaunchedAppBundleWhenExplicitlyEnabled() throws {
        try XCTSkipUnless(
            Self.realActionOSCLISmokeEnabled(),
            "Set MA_NATIVE_APP_REAL_ACTION_OS_SMOKE=1 to run the real OS transcript action app-bundle smoke."
        )

        let processingFixture = try AppRealProcessingCLIFixture()
        defer { processingFixture.cleanup() }
        let processingApp = launchApp(fixture: "ready", realProcessingFixture: processingFixture)

        tapProcessingButton(
            "ma.processing.startButton",
            in: processingApp,
            expectingStatus: "Processing completed with transcript-only speaker labels."
        )

        let reviewApp = launchApp(
            workspaceURL: processingFixture.workspaceURL,
            sessionID: processingFixture.sessionID,
            realProcessingFixture: processingFixture,
            transcriptActionOSClientMode: "system",
            transcriptActionSavePanelDefaultDirectoryURL: processingFixture.exportURL.deletingLastPathComponent()
        )

        assertElement("ma.transcriptAction.status", in: reviewApp, contains: "Transcript actions are ready.")

        NSPasteboard.general.clearContents()
        tapTranscriptActionButton("ma.transcriptAction.copyButton", in: reviewApp)

        assertElement("ma.transcriptAction.status", in: reviewApp, contains: "Copy complete.")
        let pasteboardContent = NSPasteboard.general.string(forType: .string)
        XCTAssertTrue(
            pasteboardContent?.contains("Fake transcript generated from local audio.") == true,
            "Expected real NSPasteboard copy to contain transcript content."
        )

        tapTranscriptActionButton("ma.transcriptAction.exportButton", in: reviewApp)
        confirmSavePanelExport(in: reviewApp, expectedFilename: "\(processingFixture.sessionID).md")

        assertElement("ma.transcriptAction.status", in: reviewApp, contains: "Export complete.")
        assertElement("ma.transcriptAction.success", in: reviewApp, contains: processingFixture.exportURL.path)
        XCTAssertTrue(FileManager.default.fileExists(atPath: processingFixture.exportURL.path))
        XCTAssertTrue(try processingFixture.exportContent().contains("Fake transcript generated from local audio."))

        tapTranscriptActionButton("ma.transcriptAction.deleteButton", in: reviewApp)
        assertElement("ma.transcriptAction.deletePromptText", in: reviewApp, contains: processingFixture.sessionID)
        assertElement("ma.transcriptAction.deletePromptText", in: reviewApp, contains: "External exports are retained.")
        tapTranscriptActionButton("ma.transcriptAction.deleteConfirmButton", in: reviewApp)

        assertElement("ma.transcriptAction.status", in: reviewApp, contains: "Delete complete.")
        assertElement("ma.transcriptAction.success", in: reviewApp, contains: "Deleted session \(processingFixture.sessionID).")
        assertElement("ma.transcriptAction.success", in: reviewApp, contains: "Retained 1 external export.")
        XCTAssertFalse(FileManager.default.fileExists(atPath: processingFixture.sessionRootURL.path))
        XCTAssertTrue(FileManager.default.fileExists(atPath: processingFixture.exportURL.path))
        let deleteEvent = try processingFixture.deleteEventContent()
        XCTAssertTrue(deleteEvent.contains("meeting_session.deleted.v1"))
        XCTAssertTrue(deleteEvent.contains(processingFixture.sessionID))
        XCTAssertFalse(deleteEvent.contains("Fake transcript generated from local audio."))
    }

    func testRealWhisperRuntimeTranscriptReviewFromLaunchedAppBundleWhenExplicitlyEnabled() throws {
        try XCTSkipUnless(
            Self.realRuntimeCLISmokeEnabled(),
            "Set MA_NATIVE_APP_REAL_RUNTIME_SMOKE=1 to run the real whisper.cpp app-bundle smoke."
        )

        let processingFixture = try AppRealRuntimeProcessingCLIFixture()
        defer { processingFixture.cleanup() }
        let processingApp = launchApp(
            fixture: "ready",
            workspaceURL: processingFixture.workspaceURL,
            sessionID: processingFixture.sessionID,
            realRuntimeProcessingFixture: processingFixture
        )

        tapProcessingButton("ma.processing.startButton", in: processingApp)
        let completed = waitForElement(
            "ma.processing.status",
            in: processingApp,
            contains: "Processing completed with transcript-only speaker labels.",
            timeout: 120
        )
        if !completed {
            let reportPath = processingFixture.writeTimeoutDiagnostics(
                statusDescription: elementDescription("ma.processing.status", in: processingApp),
                errorDescription: elementDescription("ma.processing.error", in: processingApp)
            )
            XCTFail(
                "Expected real runtime processing to complete from the launched app bundle. "
                    + "Diagnostics: \(reportPath)."
            )
            return
        }

        assertElement(
            "ma.processing.status",
            in: processingApp,
            contains: "Processing completed with transcript-only speaker labels."
        )
        assertElement("ma.processing.transcriptStatus", in: processingApp, contains: "generated with")
        assertElement("ma.processing.degradation", in: processingApp, contains: "transcript-only fallback")
        assertDoesNotExist("ma.processing.error", in: processingApp)

        let transcript = try processingFixture.transcriptPayload()
        let transcriptText = try Self.transcriptText(from: transcript)
        XCTAssertTrue(
            transcriptText.range(of: #"\p{Han}"#, options: .regularExpression) != nil,
            "Expected real runtime transcript to contain Chinese text. Transcript: \(transcriptText)"
        )
        for term in ["http", "llm", "clean architecture", "eda"] {
            XCTAssertTrue(
                Self.transcriptContains(transcriptText, term: term),
                "Expected real runtime transcript to contain \(term). Transcript: \(transcriptText)"
            )
        }

        let reviewApp = launchApp(
            workspaceURL: processingFixture.workspaceURL,
            sessionID: processingFixture.sessionID,
            realRuntimeProcessingFixture: processingFixture
        )

        assertElement(
            "ma.transcript.heading",
            in: reviewApp,
            contains: "Real whisper runtime app-bundle fixture"
        )
        assertElement("ma.transcript.summary", in: reviewApp, contains: "Transcript has")
        assertElement("ma.transcript.degradation", in: reviewApp, contains: "transcript-only fallback")
    }

    func testMVPFullStackDesignedShellRecordingProcessingTranscriptActionsWhenExplicitlyEnabled() throws {
        try XCTSkipUnless(
            Self.mvpFullStackCLISmokeEnabled(),
            "Set MA_NATIVE_APP_MVP_FULL_STACK_SMOKE=1 to run the VS-MA-20 app-bundle MVP full-stack smoke."
        )

        let fixture = try AppMVPFullStackCLIFixture()
        defer { fixture.cleanup() }
        let app = launchApp(fixture: "ready", mvpFullStackFixture: fixture)

        assertElement("ma.meetings.heading", in: app, contains: "Meetings")
        assertExists("ma.meetings.newRecordingButton", in: app)

        tapButton("ma.recording.startButton", in: app)

        assertRecordingStarted(in: app)
        assertElement("ma.recording.sessionID", in: app, contains: fixture.sessionID)
        assertElement("ma.meetingDetail.status", in: app, contains: "Recording")

        tapRecordingButton(
            "ma.recording.stopButton",
            in: app,
            expectingStatus: "Recording saved."
        )

        assertElement("ma.recording.status", in: app, contains: "Recording saved.")
        assertElement("ma.recording.savedSummary", in: app, contains: "Saved 2 recording artifacts.")
        assertElement("ma.recording.artifact.screen_video.status", in: app, contains: "screen_video: available")
        assertElement("ma.recording.artifact.system_audio.status", in: app, contains: "system_audio: missing")
        assertElement("ma.recording.artifact.microphone_audio.status", in: app, contains: "microphone_audio: degraded")
        assertElement("ma.recording.artifact.mixed_audio.status", in: app, contains: "mixed_audio: available")
        assertExists("ma.meetingDetail.savedSummary", in: app)

        let recordedSession = try fixture.sessionMetadata()
        XCTAssertEqual(recordedSession["id"] as? String, fixture.sessionID)
        XCTAssertEqual(recordedSession["source_type"] as? String, "native_recording")
        XCTAssertEqual(recordedSession["status"] as? String, "recorded")
        let recordedArtifacts = try XCTUnwrap(recordedSession["artifacts"] as? [[String: Any]])
        XCTAssertEqual(recordedArtifacts.filter { $0["capture_status"] as? String == "available" }.count, 2)
        XCTAssertEqual(
            recordedArtifacts.first { $0["artifact_type"] as? String == "mixed_audio" }?["format"] as? String,
            "wav"
        )

        tapProcessingButton(
            "ma.processing.startButton",
            in: app,
            expectingStatus: "Processing completed with transcript-only speaker labels."
        )

        assertElement("ma.processing.status", in: app, contains: "Processing completed with transcript-only speaker labels.")
        assertElement("ma.processing.transcriptStatus", in: app, contains: "generated with 1 segment")
        assertElement("ma.processing.degradation", in: app, contains: "transcript-only fallback")
        assertDoesNotExist("ma.processing.error", in: app)

        let processedSession = try fixture.sessionMetadata()
        let processedArtifacts = try XCTUnwrap(processedSession["artifacts"] as? [[String: Any]])
        let processedArtifactTypes = Set(processedArtifacts.compactMap { $0["artifact_type"] as? String })
        XCTAssertTrue(
            processedArtifactTypes.isSuperset(of: ["screen_video", "mixed_audio", "normalized_audio", "transcript_text", "speaker_labels"])
        )

        let reviewApp = launchApp(
            workspaceURL: fixture.workspaceURL,
            sessionID: fixture.sessionID,
            mvpFullStackFixture: fixture
        )

        assertElement("ma.meetingDetail.heading", in: reviewApp, contains: "UI smoke recording")
        assertExists("ma.transcriptAction.copyButton", in: reviewApp)
        assertExists("ma.transcriptAction.deleteButton", in: reviewApp)
        assertElement("ma.transcript.heading", in: reviewApp, contains: "UI smoke recording")
        assertElement("ma.transcript.summary", in: reviewApp, contains: "Transcript has 1 segment for review.")
        assertElement(
            "ma.transcript.text.segment-0001",
            in: reviewApp,
            contains: "Fake transcript generated from local audio."
        )
        assertElement("ma.transcript.degradation", in: reviewApp, contains: "transcript-only fallback")
        assertElement("ma.transcriptAction.status", in: reviewApp, contains: "Transcript actions are ready.")

        tapTranscriptActionButton("ma.transcriptAction.copyButton", in: reviewApp)

        assertElement("ma.transcriptAction.status", in: reviewApp, contains: "Copy complete.")
        assertElement(
            "ma.transcriptAction.success",
            in: reviewApp,
            contains: "Transcript copied."
        )

        tapTranscriptActionButton("ma.transcriptAction.exportButton", in: reviewApp)

        assertElement("ma.transcriptAction.status", in: reviewApp, contains: "Export complete.")
        assertElement("ma.transcriptAction.success", in: reviewApp, contains: fixture.exportURL.path)
        XCTAssertTrue(FileManager.default.fileExists(atPath: fixture.exportURL.path))
        XCTAssertTrue(try fixture.exportContent().contains("Fake transcript generated from local audio."))

        tapTranscriptActionButton("ma.transcriptAction.deleteButton", in: reviewApp)
        assertElement("ma.transcriptAction.deletePromptText", in: reviewApp, contains: fixture.sessionID)
        assertElement("ma.transcriptAction.deletePromptText", in: reviewApp, contains: "External exports are retained.")
        tapTranscriptActionButton("ma.transcriptAction.deleteConfirmButton", in: reviewApp)

        assertElement("ma.transcriptAction.status", in: reviewApp, contains: "Delete complete.")
        assertElement("ma.transcriptAction.success", in: reviewApp, contains: "Deleted session \(fixture.sessionID).")
        assertElement("ma.transcriptAction.success", in: reviewApp, contains: "Retained 1 external export.")
        XCTAssertFalse(FileManager.default.fileExists(atPath: fixture.sessionRootURL.path))
        XCTAssertTrue(FileManager.default.fileExists(atPath: fixture.exportURL.path))
        let deleteEvent = try fixture.deleteEventContent()
        XCTAssertTrue(deleteEvent.contains("meeting_session.deleted.v1"))
        XCTAssertTrue(deleteEvent.contains(fixture.sessionID))
        XCTAssertFalse(deleteEvent.contains("Fake transcript generated from local audio."))
    }

    private func launchApp(
        fixture: String? = nil,
        workspaceURL: URL? = nil,
        sessionID: String? = nil,
        recordingFixture: AppControlledRecordingFixture? = nil,
        realCaptureFixture: AppAppleScreenCaptureKitRecordingFixture? = nil,
        realCaptureSameChainFixture: AppRealCaptureSameChainCLIFixture? = nil,
        processingFixture: AppProcessingProcessFixture? = nil,
        realProcessingFixture: AppRealProcessingCLIFixture? = nil,
        realRuntimeProcessingFixture: AppRealRuntimeProcessingCLIFixture? = nil,
        transcriptActionFixture: AppTranscriptActionProcessFixture? = nil,
        mvpFullStackFixture: AppMVPFullStackCLIFixture? = nil,
        transcriptActionOSClientMode: String? = nil,
        transcriptActionSavePanelDefaultDirectoryURL: URL? = nil
    ) -> XCUIApplication {
        dismissSpotlightIfPresent()
        launchedApp?.terminate()
        if let launchedApp {
            _ = launchedApp.wait(for: .notRunning, timeout: 5)
        }
        launchedApp = nil

        let app = XCUIApplication()
        app.launchArguments += ["-ApplePersistenceIgnoreState", "YES"]
        app.launchEnvironment["MA_NATIVE_APP_XCTEST"] = "1"
        if builtInScreen() != nil {
            app.launchEnvironment["MA_NATIVE_APP_TEST_DISPLAY"] = "built-in"
        }
        if let fixture {
            app.launchEnvironment["MA_NATIVE_APP_SMOKE_FIXTURE"] = fixture
        }
        if let workspaceURL, let sessionID {
            app.launchEnvironment["MA_NATIVE_TRANSCRIPT_WORKSPACE"] = workspaceURL.path
            app.launchEnvironment["MA_NATIVE_TRANSCRIPT_SESSION_ID"] = sessionID
        }
        if let recordingFixture {
            recordingFixture.applyLaunchEnvironment(to: app)
        }
        if let realCaptureFixture {
            realCaptureFixture.applyLaunchEnvironment(to: app)
        }
        if let realCaptureSameChainFixture {
            realCaptureSameChainFixture.applyLaunchEnvironment(to: app)
        }
        if let processingFixture {
            processingFixture.applyLaunchEnvironment(to: app)
        }
        if let realProcessingFixture {
            realProcessingFixture.applyLaunchEnvironment(to: app)
        }
        if let realRuntimeProcessingFixture {
            realRuntimeProcessingFixture.applyLaunchEnvironment(to: app)
        }
        if let transcriptActionFixture {
            transcriptActionFixture.applyLaunchEnvironment(to: app)
        }
        if let mvpFullStackFixture {
            mvpFullStackFixture.applyLaunchEnvironment(to: app)
        }
        if let transcriptActionOSClientMode {
            app.launchEnvironment["MA_NATIVE_TRANSCRIPT_ACTION_OS_CLIENT"] = transcriptActionOSClientMode
        }
        if let transcriptActionSavePanelDefaultDirectoryURL {
            app.launchEnvironment["MA_NATIVE_TRANSCRIPT_ACTION_SAVE_PANEL_DEFAULT_DIR"] =
                transcriptActionSavePanelDefaultDirectoryURL.path
        }
        app.terminate()
        _ = app.wait(for: .notRunning, timeout: 5)
        app.launch()
        if !app.wait(for: .runningForeground, timeout: 5) {
            app.activate()
        }
        XCTAssertTrue(app.wait(for: .runningForeground, timeout: 10), "Expected app bundle to run foreground.")
        _ = waitForAppWindow(in: app, context: "after launch")
        assertWindowIsOnBuiltInScreen(app)
        launchedApp = app
        if shouldOpenRecentMeetingAfterLaunch(
            fixture: fixture,
            workspaceURL: workspaceURL,
            sessionID: sessionID,
            realProcessingFixture: realProcessingFixture,
            realRuntimeProcessingFixture: realRuntimeProcessingFixture,
            transcriptActionFixture: transcriptActionFixture
        ) {
            openRecentMeeting(in: app, preferredSessionID: sessionID)
        }
        return app
    }

    private func shouldOpenRecentMeetingAfterLaunch(
        fixture: String?,
        workspaceURL: URL?,
        sessionID: String?,
        realProcessingFixture: AppRealProcessingCLIFixture?,
        realRuntimeProcessingFixture: AppRealRuntimeProcessingCLIFixture?,
        transcriptActionFixture: AppTranscriptActionProcessFixture?
    ) -> Bool {
        if workspaceURL != nil && sessionID != nil {
            return true
        }
        if realProcessingFixture != nil || realRuntimeProcessingFixture != nil || transcriptActionFixture != nil {
            return true
        }
        guard let fixture else {
            return false
        }
        return fixture.hasPrefix("processing-") || fixture.hasPrefix("transcript-")
    }

    private func dismissSpotlightIfPresent() {
        let spotlight = XCUIApplication(bundleIdentifier: "com.apple.Spotlight")
        guard spotlight.windows.firstMatch.exists else {
            return
        }
        spotlight.typeKey(.escape, modifierFlags: [])
    }

    private func ensureNewRecordingRoute(
        in app: XCUIApplication,
        file: StaticString = #filePath,
        line: UInt = #line
    ) {
        if rawElement("ma.recording.startButton", in: app).waitForExistence(timeout: 0.5) {
            return
        }

        let navigation = rawButton("ma.navigation.newRecording", in: app)
        XCTAssertTrue(
            navigation.waitForExistence(timeout: 5),
            "Expected New recording navigation to exist.",
            file: file,
            line: line
        )
        clickButton(navigation, in: app, file: file, line: line)
        XCTAssertTrue(
            rawElement("ma.newRecording.heading", in: app).waitForExistence(timeout: 5),
            "Expected task flow to enter New recording.",
            file: file,
            line: line
        )
    }

    private func ensureMeetingDetail(
        in app: XCUIApplication,
        targetIdentifier: String,
        file: StaticString = #filePath,
        line: UInt = #line
    ) {
        if rawElement(targetIdentifier, in: app).waitForExistence(timeout: 0.5) {
            return
        }
        openRecentMeeting(in: app, preferredSessionID: nil, file: file, line: line)
    }

    private func openRecentMeeting(
        in app: XCUIApplication,
        preferredSessionID: String?,
        file: StaticString = #filePath,
        line: UInt = #line
    ) {
        if rawElement("ma.meetingDetail.heading", in: app).exists,
           preferredSessionID == nil {
            return
        }

        if preferredSessionID != nil || !rawElement("ma.meetings.heading", in: app).waitForExistence(timeout: 1) {
            let meetingsNavigation = rawButton("ma.navigation.meetings", in: app)
            XCTAssertTrue(
                meetingsNavigation.waitForExistence(timeout: 5),
                "Expected Meetings navigation to exist.",
                file: file,
                line: line
            )
            clickButton(meetingsNavigation, in: app, file: file, line: line)
        }

        let anyRow = app
            .descendants(matching: .any)
            .matching(NSPredicate(format: "identifier BEGINSWITH %@", "ma.meetings.row."))
            .firstMatch
        let row: XCUIElement
        if let preferredSessionID {
            let preferredRow = rawElement("ma.meetings.row.\(preferredSessionID)", in: app)
            guard preferredRow.waitForExistence(timeout: 5) else {
                XCTFail(
                    "Expected recent meeting row for session \(preferredSessionID); refusing to open another session.",
                    file: file,
                    line: line
                )
                return
            }
            row = preferredRow
        } else {
            row = anyRow
            XCTAssertTrue(
                row.waitForExistence(timeout: 10),
                "Expected at least one recent meeting row to open.",
                file: file,
                line: line
            )
        }
        clickButton(row, in: app, file: file, line: line)
        XCTAssertTrue(
            rawElement("ma.meetingDetail.heading", in: app).waitForExistence(timeout: 10),
            "Expected task flow to enter Meeting detail.",
            file: file,
            line: line
        )
    }

    private func rawButton(_ identifier: String, in app: XCUIApplication) -> XCUIElement {
        app.descendants(matching: .button).matching(identifier: identifier).firstMatch
    }

    private func rawElement(_ identifier: String, in app: XCUIApplication) -> XCUIElement {
        app.descendants(matching: .any).matching(identifier: identifier).firstMatch
    }

    private func button(_ identifier: String, in app: XCUIApplication) -> XCUIElement {
        let matches = app.descendants(matching: .button).matching(identifier: identifier)
        let element = matches.firstMatch
        XCTAssertTrue(element.waitForExistence(timeout: 5), "Expected button \(identifier) to exist.")
        return matches.allElementsBoundByIndex.first { $0.exists && $0.isHittable } ?? element
    }

    private func element(_ identifier: String, in app: XCUIApplication) -> XCUIElement {
        var element = app
            .descendants(matching: .any)
            .matching(identifier: identifier)
            .firstMatch
        if !element.waitForExistence(timeout: 2) {
            scrollTowardElement(in: app, targetIdentifier: identifier)
            element = app
                .descendants(matching: .any)
                .matching(identifier: identifier)
                .firstMatch
        }
        XCTAssertTrue(element.waitForExistence(timeout: 5), "Expected element \(identifier) to exist.")
        return element
    }

    private func appWindow(in app: XCUIApplication) -> XCUIElement {
        materializedAppWindow(in: app) ?? app.windows.firstMatch
    }

    private func materializedAppWindow(in app: XCUIApplication) -> XCUIElement? {
        app.windows.allElementsBoundByIndex.first { window in
            window.exists && hasUsableFrame(window.frame)
        }
    }

    private func waitForAppWindow(
        in app: XCUIApplication,
        context: String,
        timeout: TimeInterval = 15,
        file: StaticString = #filePath,
        line: UInt = #line
    ) -> XCUIElement {
        let deadline = Date().addingTimeInterval(timeout)
        var attempts = 0

        while Date() < deadline {
            attempts += 1
            if app.state != .runningForeground {
                app.activate()
                _ = app.wait(for: .runningForeground, timeout: 2)
            }

            if let window = materializedAppWindow(in: app) {
                return window
            }

            let firstWindow = app.windows.firstMatch
            if firstWindow.waitForExistence(timeout: 1), hasUsableFrame(firstWindow.frame) {
                return firstWindow
            }

            RunLoop.current.run(until: Date().addingTimeInterval(0.2))
        }

        XCTFail(
            "Expected app window \(context). \(appWindowDiagnostics(app, attempts: attempts))",
            file: file,
            line: line
        )
        return app.windows.firstMatch
    }

    private func appWindowDiagnostics(_ app: XCUIApplication, attempts: Int) -> String {
        let windows = app.windows.allElementsBoundByIndex
        let windowSummary = windows.prefix(5).enumerated().map { index, window in
            "window[\(index)] exists=\(window.exists) hittable=\(window.isHittable) frame=\(window.frame) label=\(window.label) value=\(String(describing: window.value))"
        }.joined(separator: "; ")
        return "attempts=\(attempts); appState=\(app.state.rawValue); windows=\(windows.count); \(windowSummary.isEmpty ? "no materialized windows" : windowSummary)"
    }

    private func assertWindowIsOnBuiltInScreen(
        _ app: XCUIApplication,
        file: StaticString = #filePath,
        line: UInt = #line
    ) {
        guard let screen = builtInScreen() else {
            return
        }

        let window = appWindow(in: app)
        let predicate = NSPredicate { object, _ in
            guard let window = object as? XCUIElement else {
                return false
            }
            let frame = window.frame
            let center = CGPoint(x: frame.midX, y: frame.midY)
            return screen.frame.contains(center)
        }
        let expectation = XCTNSPredicateExpectation(predicate: predicate, object: window)
        let result = XCTWaiter.wait(for: [expectation], timeout: 8)
        let windowFrame = window.frame
        let windowCenter = CGPoint(x: windowFrame.midX, y: windowFrame.midY)
        XCTAssertEqual(
            result,
            .completed,
            "Expected app bundle window center \(windowCenter) to be on built-in screen \(screen.localizedName) frame \(screen.frame), actual window frame \(windowFrame).",
            file: file,
            line: line
        )
    }

    private func builtInScreen() -> NSScreen? {
        NSScreen.screens.first { screen in
            guard let screenNumber = screen.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? NSNumber else {
                return false
            }
            return CGDisplayIsBuiltin(CGDirectDisplayID(screenNumber.uint32Value)) != 0
        }
    }

    private func assertElement(
        _ identifier: String,
        in app: XCUIApplication,
        contains expectedText: String,
        file: StaticString = #filePath,
        line: UInt = #line
    ) {
        if assertTaskFlowReplacement(
            for: identifier,
            expectedText: expectedText,
            in: app,
            file: file,
            line: line
        ) {
            return
        }
        let element = element(identifier, in: app)
        let predicate = NSPredicate(
            format: "label CONTAINS %@ OR value CONTAINS %@",
            expectedText,
            expectedText
        )
        let expectation = XCTNSPredicateExpectation(predicate: predicate, object: element)
        let result = XCTWaiter.wait(for: [expectation], timeout: 5)
        XCTAssertEqual(
            result,
            .completed,
            "Expected \(identifier) label or value to contain \(expectedText). Actual label: \(element.label), value: \(String(describing: element.value))",
            file: file,
            line: line
        )
    }

    private func waitForElement(
        _ identifier: String,
        in app: XCUIApplication,
        contains expectedText: String,
        timeout: TimeInterval
    ) -> Bool {
        if let replacement = waitForTaskFlowReplacement(
            for: identifier,
            expectedText: expectedText,
            in: app,
            timeout: timeout
        ) {
            return replacement
        }
        let element = element(identifier, in: app)
        let predicate = NSPredicate(
            format: "label CONTAINS %@ OR value CONTAINS %@",
            expectedText,
            expectedText
        )
        let expectation = XCTNSPredicateExpectation(predicate: predicate, object: element)
        return XCTWaiter.wait(for: [expectation], timeout: timeout) == .completed
    }

    private func assertTaskFlowReplacement(
        for identifier: String,
        expectedText: String,
        in app: XCUIApplication,
        file: StaticString,
        line: UInt
    ) -> Bool {
        let replacementResult = waitForTaskFlowReplacement(
            for: identifier,
            expectedText: expectedText,
            in: app,
            timeout: 8
        )
        guard let replacementResult else {
            return false
        }
        XCTAssertTrue(
            replacementResult,
            "Expected task-routed replacement for \(identifier) to represent \(expectedText).",
            file: file,
            line: line
        )
        return true
    }

    private func waitForTaskFlowReplacement(
        for identifier: String,
        expectedText: String,
        in app: XCUIApplication,
        timeout: TimeInterval
    ) -> Bool? {
        switch identifier {
        case "ma.transcript.heading":
            return waitForRawElement(
                "ma.meetingDetail.heading",
                in: app,
                containing: expectedText,
                timeout: timeout
            )
        case "ma.transcript.summary", "ma.transcript.empty":
            return waitForRawElement(
                "ma.shell.subtitle",
                in: app,
                containing: expectedText,
                timeout: timeout
            )
        case "ma.transcript.degradation":
            return waitForVisibleText(expectedText, in: app, timeout: timeout)
                || waitForVisibleText("Speaker labels are unavailable", in: app, timeout: timeout)
        case _ where identifier.hasPrefix("ma.transcript.speakerLabel."):
            if expectedText.contains("not a verified identity") {
                return waitForVisibleText("not verified identities", in: app, timeout: timeout)
            }
            return rawElement(identifier, in: app).waitForExistence(timeout: timeout)
        case "ma.transcriptAction.heading":
            return rawElement("ma.transcriptAction.copyButton", in: app).waitForExistence(timeout: timeout)
        case "ma.transcriptAction.status":
            if expectedText == "Transcript actions are ready." {
                return rawElement("ma.transcriptAction.copyButton", in: app).waitForExistence(timeout: timeout)
                    && rawElement("ma.transcriptAction.deleteButton", in: app).exists
            }
            if expectedText == "Delete complete." {
                return waitForRawElement(
                    "ma.meetings.notice",
                    in: app,
                    containing: "Meeting deleted",
                    timeout: timeout
                )
            }
            if expectedText == "Delete cancelled. No command was sent." {
                return rawElement("ma.transcriptAction.deleteButton", in: app).waitForExistence(timeout: timeout)
                    && !rawElement("ma.transcriptAction.deletePrompt", in: app).exists
            }
            if expectedText == "Export cancelled. No command was sent." {
                return rawElement("ma.transcriptAction.exportButton", in: app).waitForExistence(timeout: timeout)
                    && !rawElement("ma.transcriptAction.success", in: app).exists
                    && !rawElement("ma.transcriptAction.error", in: app).exists
            }
            if expectedText.hasSuffix("failed.") {
                return rawElement("ma.transcriptAction.error", in: app).waitForExistence(timeout: timeout)
            }
            return rawElement("ma.transcriptAction.success", in: app).waitForExistence(timeout: timeout)
        case "ma.transcriptAction.error":
            return waitForVisibleText(expectedText, in: app, timeout: timeout)
        case "ma.transcriptAction.success"
            where expectedText.contains("Deleted session") || expectedText.contains("Retained"):
            return waitForRawElement(
                "ma.meetings.notice",
                in: app,
                containing: "Exports saved outside the workspace were kept",
                timeout: timeout
            )
        case "ma.transcriptAction.deletePromptText":
            if expectedText.contains("External exports") {
                return waitForRawElement(
                    identifier,
                    in: app,
                    containing: "Exports saved elsewhere on this Mac will be kept",
                    timeout: timeout
                )
            }
            return rawElement(identifier, in: app).waitForExistence(timeout: timeout)
        case "ma.processing.status":
            if expectedText.contains("complete") || expectedText.contains("completed") {
                return rawElement("ma.transcriptAction.copyButton", in: app).waitForExistence(timeout: timeout)
            }
            if expectedText.contains("failed") {
                return retryTranscriptButton(in: app).waitForExistence(timeout: timeout)
            }
            return rawElement(identifier, in: app).waitForExistence(timeout: timeout)
        case "ma.processing.transcriptStatus", "ma.processing.speakerLabelStatus", "ma.processing.success":
            return anyTranscriptRow(in: app).waitForExistence(timeout: timeout)
        case "ma.processing.degradation":
            return waitForVisibleText(expectedText, in: app, timeout: timeout)
                || waitForVisibleText("Speaker labels are unavailable", in: app, timeout: timeout)
        case "ma.processing.error":
            if expectedText.contains("_") {
                revealTechnicalDetails(in: app)
            }
            return waitForVisibleText(expectedText, in: app, timeout: timeout)
                || (expectedText.contains("_") && retryTranscriptButton(in: app).exists)
        case "ma.recording.status":
            if expectedText == "Recording in progress." {
                return waitForRawElement(
                    "ma.meetingDetail.status",
                    in: app,
                    containing: "Recording",
                    timeout: timeout
                )
            }
            if expectedText == "Recording saved." {
                return rawElement("ma.meetingDetail.savedSummary", in: app).waitForExistence(timeout: timeout)
            }
            if expectedText == "Recording failed." {
                return waitForVisibleText("Recording did not start", in: app, timeout: timeout)
            }
            return rawElement("ma.newRecording.readiness", in: app).waitForExistence(timeout: timeout)
        case "ma.recording.sessionID":
            return rawElement("ma.meetingDetail.heading", in: app).waitForExistence(timeout: timeout)
        case "ma.recording.savedSummary":
            return rawElement("ma.meetingDetail.savedSummary", in: app).waitForExistence(timeout: timeout)
        case _ where identifier.hasPrefix("ma.recording.artifact."):
            return rawElement("ma.meetingDetail.savedSummary", in: app).waitForExistence(timeout: timeout)
        case "ma.recording.error":
            if expectedText.contains("_") {
                return waitForVisibleText("Recording did not start", in: app, timeout: timeout)
            }
            return waitForVisibleText(expectedText, in: app, timeout: timeout)
        default:
            return nil
        }
    }

    private func waitForRawElement(
        _ identifier: String,
        in app: XCUIApplication,
        containing expectedText: String,
        timeout: TimeInterval
    ) -> Bool {
        let element = rawElement(identifier, in: app)
        let predicate = NSPredicate(
            format: "exists == true AND (label CONTAINS %@ OR value CONTAINS %@)",
            expectedText,
            expectedText
        )
        return XCTWaiter.wait(
            for: [XCTNSPredicateExpectation(predicate: predicate, object: element)],
            timeout: timeout
        ) == .completed
    }

    private func waitForVisibleText(
        _ text: String,
        in app: XCUIApplication,
        timeout: TimeInterval
    ) -> Bool {
        let predicate = NSPredicate(
            format: "label CONTAINS %@ OR value CONTAINS %@",
            text,
            text
        )
        return app.staticTexts.matching(predicate).firstMatch.waitForExistence(timeout: timeout)
    }

    private func anyTranscriptRow(in app: XCUIApplication) -> XCUIElement {
        app.descendants(matching: .any)
            .matching(NSPredicate(format: "identifier BEGINSWITH %@", "ma.transcript.segmentRow."))
            .firstMatch
    }

    private func retryTranscriptButton(in app: XCUIApplication) -> XCUIElement {
        app.buttons.matching(NSPredicate(format: "label == %@", "Retry transcript")).firstMatch
    }

    private func revealTechnicalDetails(in app: XCUIApplication) {
        let disclosure = rawButton("ma.meetingDetail.technicalDetails", in: app)
        if disclosure.waitForExistence(timeout: 0.5) {
            disclosure.click()
        }
    }

    private func assertRecordingStarted(
        in app: XCUIApplication,
        file: StaticString = #filePath,
        line: UInt = #line
    ) {
        if waitForElement("ma.recording.status", in: app, contains: "Recording in progress.", timeout: 18) {
            return
        }

        let status = elementDescription("ma.recording.status", in: app)
        let error = elementDescription("ma.recording.error", in: app)
        XCTFail(
            "Expected ma.recording.status to contain Recording in progress. Actual status: \(status). Error: \(error)",
            file: file,
            line: line
        )
    }

    private func elementDescription(_ identifier: String, in app: XCUIApplication) -> String {
        let element = app
            .descendants(matching: .any)
            .matching(identifier: identifier)
            .firstMatch
        guard element.waitForExistence(timeout: 1) else {
            return "<missing>"
        }
        return "label=\(element.label), value=\(String(describing: element.value))"
    }

    private func assertElement(
        _ identifier: String,
        in app: XCUIApplication,
        doesNotContain unexpectedText: String,
        file: StaticString = #filePath,
        line: UInt = #line
    ) {
        if identifier == "ma.processing.error" || identifier == "ma.transcriptAction.error" {
            XCTAssertFalse(
                waitForVisibleText(unexpectedText, in: app, timeout: 0.5),
                "Expected the task-routed failure not to expose \(unexpectedText).",
                file: file,
                line: line
            )
            return
        }
        let element = element(identifier, in: app)
        let value = String(describing: element.value)
        XCTAssertFalse(
            element.label.contains(unexpectedText) || value.contains(unexpectedText),
            "Expected \(identifier) label and value not to contain \(unexpectedText). Actual label: \(element.label), value: \(value)",
            file: file,
            line: line
        )
    }

    private func assertExists(
        _ identifier: String,
        in app: XCUIApplication,
        file: StaticString = #filePath,
        line: UInt = #line
    ) {
        _ = element(identifier, in: app)
    }

    private func assertDoesNotExist(
        _ identifier: String,
        in app: XCUIApplication,
        file: StaticString = #filePath,
        line: UInt = #line
    ) {
        if identifier == "ma.transcript.degradation" {
            XCTAssertFalse(
                waitForVisibleText("Speaker labels are unavailable", in: app, timeout: 0.5),
                "Expected transcript result not to show a speaker-label degradation.",
                file: file,
                line: line
            )
            return
        }
        if identifier == "ma.processing.error" {
            XCTAssertFalse(
                retryTranscriptButton(in: app).waitForExistence(timeout: 0.5),
                "Expected transcript generation not to show its retry failure state.",
                file: file,
                line: line
            )
            return
        }
        let element = app
            .descendants(matching: .any)
            .matching(identifier: identifier)
            .firstMatch
        XCTAssertFalse(element.waitForExistence(timeout: 1), "Expected element \(identifier) not to exist.", file: file, line: line)
    }

    private func tapButton(
        _ identifier: String,
        in app: XCUIApplication,
        file: StaticString = #filePath,
        line: UInt = #line
    ) {
        if identifier == "ma.recording.startButton" {
            ensureNewRecordingRoute(in: app, file: file, line: line)
        }
        bringAppToForeground(app, beforeTapping: identifier, file: file, line: line)
        let control = hittableButton(identifier, in: app, file: file, line: line)
        clickButton(control, in: app, file: file, line: line)
    }

    private func tapRecordingButton(
        _ identifier: String,
        in app: XCUIApplication,
        expectingStatus expectedStatus: String,
        file: StaticString = #filePath,
        line: UInt = #line
    ) {
        for _ in 0..<2 {
            tapButton(identifier, in: app, file: file, line: line)
            if dismissUserNotificationCenterWarningIfPresent() {
                bringAppToForeground(app, beforeTapping: identifier, file: file, line: line)
            }
            if waitForElement("ma.recording.status", in: app, contains: expectedStatus, timeout: 12) {
                return
            }
            if !waitForElement("ma.recording.status", in: app, contains: "Recording in progress.", timeout: 0.5) {
                break
            }
        }
        assertElement("ma.recording.status", in: app, contains: expectedStatus, file: file, line: line)
    }

    private func dismissUserNotificationCenterWarningIfPresent() -> Bool {
        let notificationCenter = XCUIApplication(bundleIdentifier: "com.apple.UserNotificationCenter")
        let dialog = notificationCenter.dialogs.firstMatch
        guard dialog.waitForExistence(timeout: 0.5) else {
            return false
        }

        notificationCenter.activate()
        notificationCenter.typeKey(.escape, modifierFlags: [])
        return true
    }

    private func waitForEnabled(
        _ element: XCUIElement,
        file: StaticString = #filePath,
        line: UInt = #line
    ) {
        let predicate = NSPredicate(format: "enabled == true")
        let expectation = XCTNSPredicateExpectation(predicate: predicate, object: element)
        let result = XCTWaiter.wait(for: [expectation], timeout: 5)
        XCTAssertEqual(result, .completed, "Expected \(element) to become enabled.", file: file, line: line)
    }

    private func waitForHittable(
        _ element: XCUIElement,
        file: StaticString = #filePath,
        line: UInt = #line
    ) {
        let predicate = NSPredicate(format: "exists == true AND enabled == true AND hittable == true")
        let expectation = XCTNSPredicateExpectation(predicate: predicate, object: element)
        let result = XCTWaiter.wait(for: [expectation], timeout: 10)
        XCTAssertEqual(result, .completed, "Expected \(element) to become hittable.", file: file, line: line)
    }

    private func tapTranscriptActionButton(
        _ identifier: String,
        in app: XCUIApplication,
        file: StaticString = #filePath,
        line: UInt = #line
    ) {
        ensureMeetingDetail(in: app, targetIdentifier: identifier, file: file, line: line)
        bringAppToForeground(app, beforeTapping: identifier, file: file, line: line)
        let control = hittableButton(
            identifier,
            in: app,
            scroll: { self.scrollTowardTranscriptActions(in: app, targetIdentifier: identifier, attempt: $0) },
            file: file,
            line: line
        )
        clickButton(control, in: app, file: file, line: line)
    }

    private func confirmSavePanelExport(
        in app: XCUIApplication,
        expectedFilename: String,
        file: StaticString = #filePath,
        line: UInt = #line
    ) {
        let deadline = Date().addingTimeInterval(10)
        var filenameField: XCUIElement?
        var primaryButton: XCUIElement?
        while Date() < deadline {
            if filenameField == nil {
                filenameField = app.textFields.allElementsBoundByIndex.first { field in
                    guard field.exists else {
                        return false
                    }
                    let value = String(describing: field.value)
                    return value.contains(expectedFilename)
                }
            }
            if primaryButton == nil {
                primaryButton = app.buttons.allElementsBoundByIndex.first { button in
                    guard button.exists && button.isEnabled else {
                        return false
                    }
                    return ["Export", "Save", "导出", "保存", "存储"].contains(button.label)
                }
            }
            if filenameField != nil || primaryButton != nil {
                break
            }
            RunLoop.current.run(until: Date().addingTimeInterval(0.2))
        }

        guard filenameField != nil || primaryButton != nil else {
            XCTFail(
                "Expected NSSavePanel to appear for \(expectedFilename). "
                    + "App hierarchy: \(app.debugDescription).",
                file: file,
                line: line
            )
            return
        }

        if let filenameField {
            filenameField.click()
            filenameField.typeKey(.return, modifierFlags: [])
            return
        }

        if let primaryButton, primaryButton.isHittable {
            primaryButton.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5)).click()
            return
        }

        app.typeKey(.return, modifierFlags: [])
    }

    private func tapProcessingButton(
        _ identifier: String,
        in app: XCUIApplication,
        file: StaticString = #filePath,
        line: UInt = #line
    ) {
        ensureMeetingDetail(in: app, targetIdentifier: identifier, file: file, line: line)
        bringAppToForeground(app, beforeTapping: identifier, file: file, line: line)
        let control = hittableButton(identifier, in: app, file: file, line: line)
        clickButton(control, in: app, file: file, line: line)
    }

    private func tapProcessingButton(
        _ identifier: String,
        in app: XCUIApplication,
        expectingStatus expectedStatus: String,
        file: StaticString = #filePath,
        line: UInt = #line
    ) {
        if processingExpectedStatusNeedsLongWait(expectedStatus) {
            tapProcessingButton(identifier, in: app, file: file, line: line)
            if waitForElement(
                "ma.processing.status",
                in: app,
                contains: expectedStatus,
                timeout: processingCompletionTimeout(for: expectedStatus)
            ) {
                return
            }

            XCTFail(
                "Expected ma.processing.status to contain \(expectedStatus). "
                    + "Actual status: \(elementDescription("ma.processing.status", in: app)). "
                    + "Error: \(elementDescription("ma.processing.error", in: app))",
                file: file,
                line: line
            )
            return
        }

        for attempt in 0..<2 {
            tapProcessingButton(identifier, in: app, file: file, line: line)
            let timeout: TimeInterval = attempt == 0 ? 3 : 7
            if waitForElement("ma.processing.status", in: app, contains: expectedStatus, timeout: timeout) {
                return
            }
        }

        XCTFail(
            "Expected ma.processing.status to contain \(expectedStatus). "
                + "Actual status: \(elementDescription("ma.processing.status", in: app)). "
                + "Error: \(elementDescription("ma.processing.error", in: app))",
            file: file,
            line: line
        )
    }

    private func processingExpectedStatusNeedsLongWait(_ expectedStatus: String) -> Bool {
        expectedStatus == "Processing complete."
            || expectedStatus == "Processing completed with transcript-only speaker labels."
    }

    private func processingCompletionTimeout(for expectedStatus: String) -> TimeInterval {
        if expectedStatus == "Processing completed with transcript-only speaker labels." {
            return 120
        }
        return 60
    }

    private func hittableButton(
        _ identifier: String,
        in app: XCUIApplication,
        scroll: ((Int) -> Void)? = nil,
        file: StaticString = #filePath,
        line: UInt = #line
    ) -> XCUIElement {
        var control = button(identifier, in: app)
        for attempt in 0..<8 {
            if waitUntilHittable(control, timeout: 1) || isVisibleEnabled(control, in: app) {
                return control
            }
            (scroll ?? { self.scrollTowardButton(in: app, targetIdentifier: identifier, attempt: $0) })(attempt)
            control = button(identifier, in: app)
        }
        waitForHittable(control, file: file, line: line)
        return control
    }

    private func clickButton(
        _ control: XCUIElement,
        in app: XCUIApplication,
        file: StaticString,
        line: UInt
    ) {
        if isVisibleEnabled(control, in: app) {
            // Coordinate clicks avoid XCTest treating unrelated notification dialogs as blockers.
            control.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5)).click()
            return
        }
        if waitUntilHittable(control, timeout: 1) {
            control.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5)).click()
            return
        }
        waitForHittable(control, file: file, line: line)
        control.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5)).click()
    }

    private func waitUntilHittable(_ element: XCUIElement, timeout: TimeInterval) -> Bool {
        let predicate = NSPredicate(format: "exists == true AND enabled == true AND hittable == true")
        let expectation = XCTNSPredicateExpectation(predicate: predicate, object: element)
        return XCTWaiter.wait(for: [expectation], timeout: timeout) == .completed
    }

    private func isVisibleEnabled(_ element: XCUIElement, in app: XCUIApplication) -> Bool {
        guard element.exists && element.isEnabled && hasUsableFrame(element.frame) else {
            return false
        }
        let window = appWindow(in: app)
        guard window.exists && hasUsableFrame(window.frame) else {
            return false
        }
        let center = CGPoint(x: element.frame.midX, y: element.frame.midY)
        return window.frame.insetBy(dx: 4, dy: 4).contains(center)
    }

    private func successfulProcessingInvocationLines(sessionID: String) -> [String] {
        [
            transcriptInvocationLine(sessionID: sessionID),
            speakerLabelsInvocationLine(sessionID: sessionID),
        ]
    }

    private func failedRetryProcessingInvocationLines(sessionID: String) -> [String] {
        [
            transcriptInvocationLine(sessionID: sessionID),
            transcriptInvocationLine(sessionID: sessionID),
        ]
    }

    private func pathConflictRetryProcessingInvocationLines(sessionID: String) -> [String] {
        [
            transcriptInvocationLine(sessionID: sessionID),
            transcriptInvocationLine(sessionID: sessionID),
            speakerLabelsInvocationLine(sessionID: sessionID),
        ]
    }

    private func transcriptInvocationLine(sessionID: String) -> String {
        [
            processingCommandName("generate", "transcript"),
            "--session-id",
            sessionID,
        ].joined(separator: " ")
    }

    private func speakerLabelsInvocationLine(sessionID: String) -> String {
        [
            processingCommandName("generate", "speaker", "labels"),
            "--session-id",
            sessionID,
            "--transcript-id",
            "transcript-process-fixture",
            "--allow-transcript-only-fallback",
            "true",
        ].joined(separator: " ")
    }

    private func processingCommandName(_ parts: String...) -> String {
        parts.joined(separator: "_")
    }

    private func successfulTranscriptActionInvocationLines(
        sessionID: String,
        workspaceURL: URL,
        exportURL: URL
    ) -> [String] {
        [
            transcriptActionInvocationLine(
                parts: ["export", "transcript"],
                arguments: [
                    "--session-id",
                    sessionID,
                    "--export-type",
                    "plain_text",
                ]
            ),
            transcriptActionInvocationLine(
                parts: ["export", "transcript"],
                arguments: [
                    "--session-id",
                    sessionID,
                    "--export-type",
                    "markdown",
                    "--target-path",
                    exportURL.path,
                ]
            ),
            transcriptActionInvocationLine(
                parts: ["delete", "session"],
                arguments: [
                    "--session-id",
                    sessionID,
                    "--workspace-dir",
                    workspaceURL.path,
                    "--confirm",
                    "true",
                ]
            ),
        ]
    }

    private func failedTranscriptActionInvocationLines(sessionID: String) -> [String] {
        [
            transcriptActionInvocationLine(
                parts: ["export", "transcript"],
                arguments: [
                    "--session-id",
                    sessionID,
                    "--export-type",
                    "plain_text",
                ]
            ),
        ]
    }

    private func failedDeleteTranscriptActionInvocationLines(
        sessionID: String,
        workspaceURL: URL
    ) -> [String] {
        [
            transcriptActionInvocationLine(
                parts: ["delete", "session"],
                arguments: [
                    "--session-id",
                    sessionID,
                    "--workspace-dir",
                    workspaceURL.path,
                    "--confirm",
                    "true",
                ]
            ),
        ]
    }

    private func transcriptActionInvocationLine(parts: [String], arguments: [String]) -> String {
        ([parts.joined(separator: "_")] + arguments).joined(separator: " ")
    }

    private static func realProcessingCLISmokeEnabled() -> Bool {
        switch ProcessInfo.processInfo.environment["MA_NATIVE_APP_REAL_PROCESSING_SMOKE"]?
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .lowercased() {
        case "1", "true", "yes":
            return true
        default:
            return false
        }
    }

    private static func realActionCLISmokeEnabled() -> Bool {
        switch ProcessInfo.processInfo.environment["MA_NATIVE_APP_REAL_ACTION_SMOKE"]?
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .lowercased() {
        case "1", "true", "yes":
            return true
        default:
            return false
        }
    }

    private static func realActionOSCLISmokeEnabled() -> Bool {
        switch ProcessInfo.processInfo.environment["MA_NATIVE_APP_REAL_ACTION_OS_SMOKE"]?
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .lowercased() {
        case "1", "true", "yes":
            return true
        default:
            return false
        }
    }

    private static func realRuntimeCLISmokeEnabled() -> Bool {
        switch ProcessInfo.processInfo.environment["MA_NATIVE_APP_REAL_RUNTIME_SMOKE"]?
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .lowercased() {
        case "1", "true", "yes":
            return true
        default:
            return false
        }
    }

    private static func vsMA21HardeningCLISmokeEnabled() -> Bool {
        switch ProcessInfo.processInfo.environment["MA_NATIVE_APP_VSMA21_HARDENING_SMOKE"]?
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .lowercased() {
        case "1", "true", "yes":
            return true
        default:
            return false
        }
    }

    private static func realCaptureSameChainCLISmokeEnabled() -> Bool {
        switch ProcessInfo.processInfo.environment["MA_NATIVE_APP_REAL_CAPTURE_SAME_CHAIN_SMOKE"]?
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .lowercased() {
        case "1", "true", "yes":
            return true
        default:
            return false
        }
    }

    private static func realCaptureRealRuntimeSameChainCLISmokeEnabled() -> Bool {
        switch ProcessInfo.processInfo.environment["MA_NATIVE_APP_REAL_CAPTURE_REAL_RUNTIME_SAME_CHAIN_SMOKE"]?
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .lowercased() {
        case "1", "true", "yes":
            return true
        default:
            return false
        }
    }

    private static func mvpFullStackCLISmokeEnabled() -> Bool {
        switch ProcessInfo.processInfo.environment["MA_NATIVE_APP_MVP_FULL_STACK_SMOKE"]?
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .lowercased() {
        case "1", "true", "yes":
            return true
        default:
            return false
        }
    }

    private func bringAppToForeground(
        _ app: XCUIApplication,
        beforeTapping identifier: String,
        file: StaticString = #filePath,
        line: UInt = #line
    ) {
        if app.state != .runningForeground {
            app.activate()
        }
        XCTAssertTrue(
            app.wait(for: .runningForeground, timeout: 10),
            "Expected app to be foreground before tapping \(identifier).",
            file: file,
            line: line
        )
        _ = waitForAppWindow(in: app, context: "before tapping \(identifier)", file: file, line: line)
    }

    private func scrollTowardTranscriptActions(
        in app: XCUIApplication,
        targetIdentifier: String,
        attempt: Int = 0
    ) {
        scrollTowardButton(in: app, targetIdentifier: targetIdentifier, attempt: attempt)
    }

    private func scrollTowardButton(
        in app: XCUIApplication,
        targetIdentifier: String,
        attempt: Int = 0
    ) {
        var scrollView = app.scrollViews
            .containing(.button, identifier: targetIdentifier)
            .firstMatch
        if !scrollView.waitForExistence(timeout: 1) {
            scrollView = app.scrollViews.firstMatch
        }
        guard scrollView.waitForExistence(timeout: 2) else {
            return
        }

        let element = app
            .descendants(matching: .button)
            .matching(identifier: targetIdentifier)
            .firstMatch
        if app.state != .runningForeground {
            app.activate()
            _ = app.wait(for: .runningForeground, timeout: 5)
        }
        if element.exists, hasUsableFrame(element.frame) {
            let edgePadding: CGFloat = 80
            if element.frame.minY < scrollView.frame.minY + edgePadding {
                scrollView.swipeDown()
            } else if element.frame.maxY > scrollView.frame.maxY - edgePadding {
                scrollView.swipeUp()
            } else if attempt.isMultiple(of: 2) {
                scrollView.swipeDown()
            } else if attempt < 6 {
                scrollView.swipeUp()
            } else {
                scrollView.swipeDown()
            }
        } else if attempt < 4 {
            scrollView.swipeUp()
        } else {
            scrollView.swipeDown()
        }
    }

    private func hasUsableFrame(_ frame: CGRect) -> Bool {
        !frame.isNull && !frame.isInfinite && frame.width > 0 && frame.height > 0
    }

    private func scrollTowardElement(
        in app: XCUIApplication,
        targetIdentifier: String
    ) {
        let scrollView = app.scrollViews.firstMatch
        guard scrollView.exists else {
            return
        }

        for attempt in 0..<8 {
            let element = app
                .descendants(matching: .any)
                .matching(identifier: targetIdentifier)
                .firstMatch
            if element.exists {
                if hasUsableFrame(element.frame), hasUsableFrame(scrollView.frame) {
                    if element.frame.minY < scrollView.frame.minY {
                        scrollView.swipeDown()
                    } else if element.frame.maxY > scrollView.frame.maxY {
                        scrollView.swipeUp()
                    }
                }
                return
            }
            if app.state != .runningForeground {
                app.activate()
                _ = app.wait(for: .runningForeground, timeout: 5)
            }
            if attempt.isMultiple(of: 2) {
                scrollView.swipeUp()
            } else {
                scrollView.swipeDown()
            }
        }
    }

    private func createWorkspaceTranscriptOnlyFixture() throws -> (workspaceURL: URL, sessionID: String) {
        let sessionID = "session-app-workspace-transcript"
        let workspaceURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("ma-native-app-workspace-\(UUID().uuidString)", isDirectory: true)
        let sessionRoot = workspaceURL
            .appendingPathComponent("sessions", isDirectory: true)
            .appendingPathComponent(sessionID, isDirectory: true)
        let artifactsRoot = sessionRoot.appendingPathComponent("artifacts", isDirectory: true)
        try FileManager.default.createDirectory(at: artifactsRoot, withIntermediateDirectories: true)

        let transcriptURL = artifactsRoot.appendingPathComponent("transcript.json")
        let speakerURL = artifactsRoot.appendingPathComponent("speaker_labels.json")
        let transcriptChecksum = try writeJSON(
            [
                "id": "transcript-app-workspace",
                "session_id": sessionID,
                "source_artifact_id": "artifact-normalized-audio",
                "status": "succeeded",
                "segments": [
                    [
                        "segment_id": "seg-workspace",
                        "start_ms": 2_000,
                        "end_ms": 4_000,
                        "text": "Workspace transcript loaded through launch environment.",
                    ],
                ],
                "created_at": "2026-06-29T00:00:00Z",
            ],
            to: transcriptURL
        )
        let speakerChecksum = try writeJSON(
            [
                "session_id": sessionID,
                "transcript_id": "transcript-app-workspace",
                "label_status": "transcript_only",
                "degradation_reason": "json reason should not be used by native loader",
                "labels": [],
                "segment_mapping": [],
                "created_at": "2026-06-29T00:00:00Z",
            ],
            to: speakerURL
        )
        _ = try writeJSON(
            [
                "id": sessionID,
                "title": "Workspace injected transcript",
                "source_type": "imported_media",
                "status": "transcribed",
                "started_at": "2026-06-29T00:00:00Z",
                "workspace_dir": sessionRoot.path,
                "created_at": "2026-06-29T00:00:00Z",
                "updated_at": "2026-06-29T00:00:00Z",
                "artifacts": [
                    [
                        "id": "artifact-workspace-transcript",
                        "session_id": sessionID,
                        "artifact_type": "transcript_text",
                        "path": "artifacts/transcript.json",
                        "format": "json",
                        "capture_status": "available",
                        "checksum": transcriptChecksum,
                        "created_at": "2026-06-29T00:00:00Z",
                    ],
                    [
                        "id": "artifact-workspace-speakers",
                        "session_id": sessionID,
                        "artifact_type": "speaker_labels",
                        "path": "artifacts/speaker_labels.json",
                        "format": "json",
                        "capture_status": "degraded",
                        "degradation_reason": "speaker labels degraded from session metadata",
                        "checksum": speakerChecksum,
                        "created_at": "2026-06-29T00:00:00Z",
                    ],
                ],
            ],
            to: sessionRoot.appendingPathComponent("session.json")
        )
        return (workspaceURL, sessionID)
    }

    private static func transcriptText(from payload: [String: Any]) throws -> String {
        let segments = try XCTUnwrap(payload["segments"] as? [[String: Any]])
        let text = segments
            .compactMap { $0["text"] as? String }
            .joined(separator: " ")
        XCTAssertFalse(text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
        return text
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

    @discardableResult
    private func writeJSON(_ payload: Any, to url: URL) throws -> String {
        let data = try JSONSerialization.data(withJSONObject: payload, options: [.prettyPrinted, .sortedKeys])
        try data.write(to: url)
        let digest = SHA256.hash(data: data)
        let hex = digest.map { String(format: "%02x", $0) }.joined()
        return "sha256:\(hex)"
    }
}

private final class AppControlledRecordingFixture {
    let rootURL: URL
    let workspaceURL: URL
    let sessionID = "session-app-ui-smoke"

    var sessionRootURL: URL {
        workspaceURL
            .appendingPathComponent("sessions", isDirectory: true)
            .appendingPathComponent(sessionID, isDirectory: true)
    }

    init() throws {
        rootURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("ma-native-recording-app-\(UUID().uuidString)", isDirectory: true)
        workspaceURL = rootURL.appendingPathComponent("workspace", isDirectory: true)
        try FileManager.default.createDirectory(at: workspaceURL, withIntermediateDirectories: true)
    }

    deinit {
        cleanup()
    }

    func applyLaunchEnvironment(to app: XCUIApplication) {
        app.launchEnvironment["MA_NATIVE_RECORDING_CLIENT"] = "controlled"
        app.launchEnvironment["MA_NATIVE_APP_XCTEST"] = "1"
        app.launchEnvironment["MA_NATIVE_RECORDING_WORKSPACE"] = workspaceURL.path
    }

    func sessionMetadata() throws -> [String: Any] {
        let data = try Data(contentsOf: sessionRootURL.appendingPathComponent("session.json"))
        let payload = try JSONSerialization.jsonObject(with: data)
        return try XCTUnwrap(payload as? [String: Any])
    }

    func artifactURL(_ filename: String) -> URL {
        sessionRootURL
            .appendingPathComponent("artifacts", isDirectory: true)
            .appendingPathComponent(filename, isDirectory: false)
    }

    func cleanup() {
        try? FileManager.default.removeItem(at: rootURL)
    }
}

private final class AppAppleScreenCaptureKitRecordingFixture {
    let rootURL: URL
    let workspaceURL: URL
    let sessionID = "session-app-ui-smoke"
    private let captureSystemAudio: Bool
    private let captureMicrophoneAudio: Bool

    var sessionRootURL: URL {
        workspaceURL
            .appendingPathComponent("sessions", isDirectory: true)
            .appendingPathComponent(sessionID, isDirectory: true)
    }

    init(
        captureSystemAudio: Bool = false,
        captureMicrophoneAudio: Bool = false
    ) throws {
        self.captureSystemAudio = captureSystemAudio
        self.captureMicrophoneAudio = captureMicrophoneAudio
        rootURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("ma-native-real-capture-app-\(UUID().uuidString)", isDirectory: true)
        workspaceURL = rootURL.appendingPathComponent("workspace", isDirectory: true)
        try FileManager.default.createDirectory(at: workspaceURL, withIntermediateDirectories: true)
    }

    deinit {
        cleanup()
    }

    func applyLaunchEnvironment(to app: XCUIApplication) {
        app.launchEnvironment["MA_NATIVE_RECORDING_CLIENT"] = "apple_screencapturekit"
        app.launchEnvironment["MA_NATIVE_CAPTURE_SMOKE"] = "1"
        app.launchEnvironment["MA_NATIVE_CAPTURE_SMOKE_SYSTEM_AUDIO"] = captureSystemAudio ? "true" : "false"
        app.launchEnvironment["MA_NATIVE_CAPTURE_SMOKE_MICROPHONE_AUDIO"] = captureMicrophoneAudio ? "true" : "false"
        app.launchEnvironment["MA_NATIVE_APP_XCTEST"] = "1"
        app.launchEnvironment["MA_NATIVE_RECORDING_WORKSPACE"] = workspaceURL.path
        app.launchEnvironment["MA_NATIVE_RECORDING_SESSION_ID"] = sessionID
    }

    func sessionMetadata() throws -> [String: Any] {
        let data = try Data(contentsOf: sessionRootURL.appendingPathComponent("session.json"))
        let payload = try JSONSerialization.jsonObject(with: data)
        return try XCTUnwrap(payload as? [String: Any])
    }

    func cleanup() {
        try? FileManager.default.removeItem(at: rootURL)
    }
}

private final class AppRealCaptureSameChainCLIFixture {
    private let captureFixture: AppAppleScreenCaptureKitRecordingFixture
    let cliURL: URL
    private let realRuntime: Bool
    private let runtimePath: String?
    private let modelPath: String?
    private let smokeAudioURL: URL?

    var rootURL: URL {
        captureFixture.rootURL
    }

    var workspaceURL: URL {
        captureFixture.workspaceURL
    }

    var sessionID: String {
        captureFixture.sessionID
    }

    var sessionRootURL: URL {
        captureFixture.sessionRootURL
    }

    var exportURL: URL {
        workspaceURL
            .appendingPathComponent("exports", isDirectory: true)
            .appendingPathComponent("\(sessionID).md", isDirectory: false)
    }

    var deleteEventURL: URL {
        workspaceURL
            .appendingPathComponent("events", isDirectory: true)
            .appendingPathComponent("meeting_session.deleted.v1.jsonl", isDirectory: false)
    }

    init(realRuntime: Bool = false, sourceFile: StaticString = #filePath) throws {
        let environment = ProcessInfo.processInfo.environment
        let resolvedRuntimePath: String?
        let resolvedModelPath: String?
        let resolvedSmokeAudioURL: URL?
        if realRuntime {
            guard let runtimePath = environment["MEETING_ASSISTANT_TRANSCRIPTION_RUNTIME"],
                  !runtimePath.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
                throw XCTSkip("MEETING_ASSISTANT_TRANSCRIPTION_RUNTIME is required for the real capture + real runtime app-bundle smoke.")
            }
            guard let modelPath = environment["MEETING_ASSISTANT_TRANSCRIPTION_MODEL"],
                  !modelPath.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
                throw XCTSkip("MEETING_ASSISTANT_TRANSCRIPTION_MODEL is required for the real capture + real runtime app-bundle smoke.")
            }

            let defaultSmokeAudio = FileManager.default.homeDirectoryForCurrentUser
                .appendingPathComponent(".local/share/ai-fixtures/asr/zh-en-tech/mixed-zh-en-tech.wav")
            let smokeAudioPath = environment["MEETING_ASSISTANT_WHISPER_SMOKE_AUDIO"]?
                .trimmingCharacters(in: .whitespacesAndNewlines)
            let smokeAudioURL = URL(fileURLWithPath: smokeAudioPath?.isEmpty == false ? smokeAudioPath! : defaultSmokeAudio.path)
            guard FileManager.default.isReadableFile(atPath: smokeAudioURL.path) else {
                throw XCTSkip("MEETING_ASSISTANT_WHISPER_SMOKE_AUDIO must point to the mixed-language WAV fixture.")
            }

            resolvedRuntimePath = runtimePath
            resolvedModelPath = modelPath
            resolvedSmokeAudioURL = smokeAudioURL
        } else {
            resolvedRuntimePath = nil
            resolvedModelPath = nil
            resolvedSmokeAudioURL = nil
        }

        self.realRuntime = realRuntime
        runtimePath = resolvedRuntimePath
        modelPath = resolvedModelPath
        smokeAudioURL = resolvedSmokeAudioURL
        captureFixture = try AppAppleScreenCaptureKitRecordingFixture(
            captureSystemAudio: true,
            captureMicrophoneAudio: false
        )

        let nativeAppRootURL = URL(fileURLWithPath: String(describing: sourceFile))
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
        cliURL = nativeAppRootURL
            .deletingLastPathComponent()
            .appendingPathComponent("e2e", isDirectory: true)
            .appendingPathComponent("ma-cli-local.sh", isDirectory: false)

        guard FileManager.default.isExecutableFile(atPath: cliURL.path) else {
            throw CocoaError(.fileNoSuchFile, userInfo: [NSFilePathErrorKey: cliURL.path])
        }
        try FileManager.default.createDirectory(
            at: exportURL.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
    }

    deinit {
        cleanup()
    }

    func applyLaunchEnvironment(to app: XCUIApplication) {
        captureFixture.applyLaunchEnvironment(to: app)
        app.launchEnvironment["MA_NATIVE_PROCESSING_CLIENT"] = "process"
        app.launchEnvironment["MA_NATIVE_TRANSCRIPT_ACTION_CLIENT"] = "process"
        app.launchEnvironment["MA_NATIVE_APP_XCTEST"] = "1"
        app.launchEnvironment["MEETING_ASSISTANT_CLI_PATH"] = cliURL.path
        app.launchEnvironment["MEETING_ASSISTANT_WORKSPACE"] = workspaceURL.path
        if let ffmpegPath = Self.hostFFmpegPath() {
            app.launchEnvironment["MEETING_ASSISTANT_FFMPEG_PATH"] = ffmpegPath
        }
        if realRuntime {
            app.launchEnvironment["MA_NATIVE_APP_REAL_RUNTIME_SMOKE"] = "1"
            app.launchEnvironment["MA_NATIVE_APP_REAL_CAPTURE_REAL_RUNTIME_SAME_CHAIN_SMOKE"] = "1"
            app.launchEnvironment["MA_NATIVE_PROCESSING_RUNTIME"] = "whisper_cpp"
            app.launchEnvironment["MA_NATIVE_PROCESSING_LANGUAGE"] = "zh"
            app.launchEnvironment["MEETING_ASSISTANT_TRANSCRIPTION_RUNTIME"] = runtimePath
            app.launchEnvironment["MEETING_ASSISTANT_TRANSCRIPTION_MODEL"] = modelPath
            app.launchEnvironment["MEETING_ASSISTANT_WHISPER_SMOKE_AUDIO"] = smokeAudioURL?.path
        }
    }

    private static func hostFFmpegPath() -> String? {
        let environment = ProcessInfo.processInfo.environment
        let configured = environment["MEETING_ASSISTANT_FFMPEG_PATH"]?
            .trimmingCharacters(in: .whitespacesAndNewlines)
        if let configured, !configured.isEmpty {
            return configured
        }

        let pathCandidates = (environment["PATH"] ?? "")
            .split(separator: ":")
            .map { URL(fileURLWithPath: String($0)).appendingPathComponent("ffmpeg").path }
        let standardCandidates = [
            "/opt/homebrew/bin/ffmpeg",
            "/usr/local/bin/ffmpeg",
            "/usr/bin/ffmpeg",
        ]
        return (pathCandidates + standardCandidates)
            .first { FileManager.default.isExecutableFile(atPath: $0) }
    }

    func sessionMetadata() throws -> [String: Any] {
        try captureFixture.sessionMetadata()
    }

    func mixedAudioChecksum() throws -> String {
        let session = try sessionMetadata()
        let artifacts = try XCTUnwrap(session["artifacts"] as? [[String: Any]])
        let mixedAudio = try XCTUnwrap(artifacts.first { $0["artifact_type"] as? String == "mixed_audio" })
        let relativePath = try XCTUnwrap(mixedAudio["path"] as? String)
        let data = try Data(contentsOf: sessionRootURL.appendingPathComponent(relativePath))
        let digest = SHA256.hash(data: data)
        let hex = digest.map { String(format: "%02x", $0) }.joined()
        return "sha256:\(hex)"
    }

    func transcriptPayload() throws -> [String: Any] {
        let session = try sessionMetadata()
        let artifacts = try XCTUnwrap(session["artifacts"] as? [[String: Any]])
        let transcript = try XCTUnwrap(artifacts.first { $0["artifact_type"] as? String == "transcript_text" })
        let path = try XCTUnwrap(transcript["path"] as? String)
        let transcriptURL = URL(fileURLWithPath: path, relativeTo: sessionRootURL)
        let data = try Data(contentsOf: transcriptURL)
        let payload = try JSONSerialization.jsonObject(with: data)
        return try XCTUnwrap(payload as? [String: Any])
    }

    func startSmokeAudioPlayback() throws -> Process {
        guard let smokeAudioURL else {
            throw XCTSkip("Real runtime smoke audio is only configured for the real capture + real runtime smoke.")
        }
        let afplayURL = URL(fileURLWithPath: "/usr/bin/afplay")
        guard FileManager.default.isExecutableFile(atPath: afplayURL.path) else {
            throw XCTSkip("The real capture + real runtime smoke requires /usr/bin/afplay to play fixture audio through system audio.")
        }
        let process = Process()
        process.executableURL = afplayURL
        process.arguments = [smokeAudioURL.path]
        process.standardOutput = Pipe()
        process.standardError = Pipe()
        try process.run()
        return process
    }

    func waitForSmokeAudioPlayback(_ process: Process, timeout: TimeInterval) throws {
        let deadline = Date().addingTimeInterval(timeout)
        while process.isRunning && Date() < deadline {
            Thread.sleep(forTimeInterval: 0.2)
        }
        if process.isRunning {
            process.terminate()
            throw XCTSkip("Timed out waiting for fixture audio playback before stopping real capture.")
        }
        guard process.terminationStatus == 0 else {
            throw CocoaError(.executableLoad, userInfo: [NSFilePathErrorKey: "/usr/bin/afplay"])
        }
    }

    func terminateSmokeAudioPlayback(_ process: Process) {
        guard process.isRunning else {
            return
        }
        process.terminate()
        process.waitUntilExit()
    }

    func exportContent() throws -> String {
        try String(contentsOf: exportURL, encoding: .utf8)
    }

    func deleteEventContent() throws -> String {
        try String(contentsOf: deleteEventURL, encoding: .utf8)
    }

    func cleanup() {
        captureFixture.cleanup()
    }
}

private final class AppTranscriptActionProcessFixture {
    let mode: String
    let rootURL: URL
    let workspaceURL: URL
    let cliURL: URL
    let invocationsURL: URL
    let sessionID = "session-app-ui-action-process"

    var sessionRootURL: URL {
        workspaceURL
            .appendingPathComponent("sessions", isDirectory: true)
            .appendingPathComponent(sessionID, isDirectory: true)
    }

    var exportURL: URL {
        workspaceURL
            .appendingPathComponent("exports", isDirectory: true)
            .appendingPathComponent("\(sessionID).md", isDirectory: false)
    }

    init(mode: String = "success", sourceFile: StaticString = #filePath) throws {
        self.mode = mode
        let nativeAppRootURL = URL(fileURLWithPath: String(describing: sourceFile))
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
        cliURL = nativeAppRootURL
            .appendingPathComponent("test-fixtures", isDirectory: true)
            .appendingPathComponent("transcript-action-command-fixture.sh")
        guard FileManager.default.isExecutableFile(atPath: cliURL.path) else {
            throw CocoaError(.fileNoSuchFile, userInfo: [NSFilePathErrorKey: cliURL.path])
        }

        rootURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("ma-native-transcript-action-app-\(UUID().uuidString)", isDirectory: true)
        workspaceURL = rootURL.appendingPathComponent("workspace", isDirectory: true)
        invocationsURL = rootURL.appendingPathComponent("invocations.txt")
        try FileManager.default.createDirectory(at: rootURL, withIntermediateDirectories: true)
        try createWorkspaceTranscriptFixture()
    }

    deinit {
        cleanup()
    }

    func applyLaunchEnvironment(to app: XCUIApplication) {
        app.launchEnvironment["MA_NATIVE_TRANSCRIPT_ACTION_CLIENT"] = "process"
        app.launchEnvironment["MA_NATIVE_APP_XCTEST"] = "1"
        app.launchEnvironment["MEETING_ASSISTANT_CLI_PATH"] = cliURL.path
        app.launchEnvironment["MEETING_ASSISTANT_WORKSPACE"] = workspaceURL.path
        app.launchEnvironment["MA_NATIVE_TRANSCRIPT_ACTION_FIXTURE_MODE"] = mode
        app.launchEnvironment["MA_NATIVE_TRANSCRIPT_ACTION_FIXTURE_INVOCATIONS"] = invocationsURL.path
        app.launchEnvironment["MA_NATIVE_TRANSCRIPT_ACTION_RETAINED_EXPORT"] = exportURL.path
    }

    func cleanup() {
        try? FileManager.default.removeItem(at: rootURL)
    }

    func invocationLines() throws -> [String] {
        guard FileManager.default.fileExists(atPath: invocationsURL.path) else {
            return []
        }
        let content = try String(contentsOf: invocationsURL, encoding: .utf8)
        return content.split(whereSeparator: \.isNewline).map(String.init)
    }

    func exportContent() throws -> String {
        try String(contentsOf: exportURL, encoding: .utf8)
    }

    private func createWorkspaceTranscriptFixture() throws {
        let artifactsURL = sessionRootURL.appendingPathComponent("artifacts", isDirectory: true)
        try FileManager.default.createDirectory(at: artifactsURL, withIntermediateDirectories: true)

        let transcriptURL = artifactsURL.appendingPathComponent("transcript.json", isDirectory: false)
        let speakerURL = artifactsURL.appendingPathComponent("speaker_labels.json", isDirectory: false)
        let transcriptChecksum = try writeJSON(
            [
                "id": "transcript-action-process-fixture",
                "session_id": sessionID,
                "source_artifact_id": "artifact-action-normalized-audio",
                "status": "succeeded",
                "segments": [
                    [
                        "segment_id": "seg-action-1",
                        "start_ms": 1_000,
                        "end_ms": 3_000,
                        "text": "Native action process fixture transcript content.",
                        "speaker_label": "SPEAKER_01",
                    ],
                ],
                "created_at": "2026-07-03T00:00:00Z",
            ],
            to: transcriptURL
        )
        let speakerChecksum = try writeJSON(
            [
                "session_id": sessionID,
                "transcript_id": "transcript-action-process-fixture",
                "labels": [
                    [
                        "label": "SPEAKER_01",
                        "session_id": sessionID,
                        "is_verified_identity": false,
                    ],
                ],
                "segment_mapping": [
                    [
                        "segment_id": "seg-action-1",
                        "label": "SPEAKER_01",
                    ],
                ],
                "created_at": "2026-07-03T00:00:00Z",
            ],
            to: speakerURL
        )
        _ = try writeJSON(
            [
                "id": sessionID,
                "title": "Native action process workspace fixture",
                "source_type": "native_recording",
                "status": "transcribed",
                "started_at": "2026-07-03T00:00:00Z",
                "workspace_dir": sessionRootURL.path,
                "created_at": "2026-07-03T00:00:00Z",
                "updated_at": "2026-07-03T00:00:00Z",
                "artifacts": [
                    [
                        "id": "artifact-action-transcript",
                        "session_id": sessionID,
                        "artifact_type": "transcript_text",
                        "path": "artifacts/transcript.json",
                        "format": "json",
                        "capture_status": "available",
                        "checksum": transcriptChecksum,
                        "created_at": "2026-07-03T00:00:00Z",
                    ],
                    [
                        "id": "artifact-action-speakers",
                        "session_id": sessionID,
                        "artifact_type": "speaker_labels",
                        "path": "artifacts/speaker_labels.json",
                        "format": "json",
                        "capture_status": "available",
                        "checksum": speakerChecksum,
                        "created_at": "2026-07-03T00:00:00Z",
                    ],
                ],
            ],
            to: sessionRootURL.appendingPathComponent("session.json", isDirectory: false)
        )
    }

    @discardableResult
    private func writeJSON(_ payload: Any, to url: URL) throws -> String {
        let data = try JSONSerialization.data(withJSONObject: payload, options: [.prettyPrinted, .sortedKeys])
        try data.write(to: url)
        let digest = SHA256.hash(data: data)
        let hex = digest.map { String(format: "%02x", $0) }.joined()
        return "sha256:\(hex)"
    }
}

final class AppProcessingProcessFixture {
    let mode: String
    let rootURL: URL
    let workspaceURL: URL
    let cliURL: URL
    let invocationsURL: URL

    init(mode: String, workspaceURL externalWorkspaceURL: URL? = nil, sourceFile: StaticString = #filePath) throws {
        self.mode = mode
        let nativeAppRootURL = URL(fileURLWithPath: String(describing: sourceFile))
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
        cliURL = nativeAppRootURL
            .appendingPathComponent("test-fixtures", isDirectory: true)
            .appendingPathComponent("processing-command-fixture.sh")
        guard FileManager.default.isExecutableFile(atPath: cliURL.path) else {
            throw CocoaError(.fileNoSuchFile, userInfo: [NSFilePathErrorKey: cliURL.path])
        }

        rootURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("ma-native-processing-app-\(UUID().uuidString)", isDirectory: true)
        workspaceURL = externalWorkspaceURL ?? rootURL.appendingPathComponent("workspace", isDirectory: true)
        invocationsURL = rootURL.appendingPathComponent("invocations.txt")
        try FileManager.default.createDirectory(at: rootURL, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: workspaceURL, withIntermediateDirectories: true)
    }

    deinit {
        cleanup()
    }

    func applyLaunchEnvironment(to app: XCUIApplication) {
        app.launchEnvironment["MA_NATIVE_PROCESSING_CLIENT"] = "process"
        app.launchEnvironment["MA_NATIVE_APP_XCTEST"] = "1"
        app.launchEnvironment["MEETING_ASSISTANT_CLI_PATH"] = cliURL.path
        app.launchEnvironment["MEETING_ASSISTANT_WORKSPACE"] = workspaceURL.path
        app.launchEnvironment["MA_NATIVE_PROCESSING_FIXTURE_MODE"] = mode
        app.launchEnvironment["MA_NATIVE_PROCESSING_FIXTURE_INVOCATIONS"] = invocationsURL.path
    }

    func cleanup() {
        try? FileManager.default.removeItem(at: rootURL)
    }

    func invocationLines() throws -> [String] {
        guard FileManager.default.fileExists(atPath: invocationsURL.path) else {
            return []
        }
        let content = try String(contentsOf: invocationsURL, encoding: .utf8)
        return content.split(whereSeparator: \.isNewline).map(String.init)
    }

    func createNativeRecordingWorkspace(sessionID: String) throws {
        let sessionRootURL = workspaceURL
            .appendingPathComponent("sessions", isDirectory: true)
            .appendingPathComponent(sessionID, isDirectory: true)
        let artifactsURL = sessionRootURL.appendingPathComponent("artifacts", isDirectory: true)
        try FileManager.default.createDirectory(at: artifactsURL, withIntermediateDirectories: true)

        let audioURL = artifactsURL.appendingPathComponent("mixed_audio.wav", isDirectory: false)
        let audioData = Self.fixtureWAVData()
        try audioData.write(to: audioURL)
        let audioChecksum = Self.sha256(audioData)
        let now = "2026-07-05T00:00:00Z"

        _ = try writeJSON(
            [
                "id": sessionID,
                "title": "VS-MA-21 app-bundle hardening fixture",
                "source_type": "native_recording",
                "status": "recorded",
                "started_at": now,
                "workspace_dir": sessionRootURL.path,
                "created_at": now,
                "updated_at": now,
                "artifacts": [
                    [
                        "id": "artifact-process-mixed",
                        "session_id": sessionID,
                        "artifact_type": "mixed_audio",
                        "path": "artifacts/mixed_audio.wav",
                        "format": "wav",
                        "capture_status": "available",
                        "checksum": audioChecksum,
                        "created_at": now,
                    ],
                ],
            ],
            to: sessionRootURL.appendingPathComponent("session.json", isDirectory: false)
        )
    }

    func artifactURL(sessionID: String, filename: String) -> URL {
        workspaceURL
            .appendingPathComponent("sessions", isDirectory: true)
            .appendingPathComponent(sessionID, isDirectory: true)
            .appendingPathComponent("artifacts", isDirectory: true)
            .appendingPathComponent(filename, isDirectory: false)
    }

    func mixedAudioChecksum(sessionID: String) throws -> String {
        let data = try Data(contentsOf: artifactURL(sessionID: sessionID, filename: "mixed_audio.wav"))
        return Self.sha256(data)
    }

    func sessionMetadata(sessionID: String) throws -> [String: Any] {
        let sessionURL = workspaceURL
            .appendingPathComponent("sessions", isDirectory: true)
            .appendingPathComponent(sessionID, isDirectory: true)
            .appendingPathComponent("session.json", isDirectory: false)
        let data = try Data(contentsOf: sessionURL)
        let payload = try JSONSerialization.jsonObject(with: data)
        return try XCTUnwrap(payload as? [String: Any])
    }

    @discardableResult
    private func writeJSON(_ payload: Any, to url: URL) throws -> String {
        let data = try JSONSerialization.data(withJSONObject: payload, options: [.prettyPrinted, .sortedKeys])
        try data.write(to: url)
        return Self.sha256(data)
    }

    private static func fixtureWAVData() -> Data {
        var samples = Data()
        for index in 0..<1_600 {
            let value = Int16((((index + 17) % 80) - 40) * 80)
            appendLittleEndian(value, to: &samples)
        }

        var data = Data()
        data.append(Data("RIFF".utf8))
        appendLittleEndian(UInt32(36 + samples.count), to: &data)
        data.append(Data("WAVE".utf8))
        data.append(Data("fmt ".utf8))
        appendLittleEndian(UInt32(16), to: &data)
        appendLittleEndian(UInt16(1), to: &data)
        appendLittleEndian(UInt16(1), to: &data)
        appendLittleEndian(UInt32(8_000), to: &data)
        appendLittleEndian(UInt32(16_000), to: &data)
        appendLittleEndian(UInt16(2), to: &data)
        appendLittleEndian(UInt16(16), to: &data)
        data.append(Data("data".utf8))
        appendLittleEndian(UInt32(samples.count), to: &data)
        data.append(samples)
        return data
    }

    private static func appendLittleEndian<T: FixedWidthInteger>(_ value: T, to data: inout Data) {
        var littleEndian = value.littleEndian
        withUnsafeBytes(of: &littleEndian) { data.append(contentsOf: $0) }
    }

    private static func sha256(_ data: Data) -> String {
        let digest = SHA256.hash(data: data)
        let hex = digest.map { String(format: "%02x", $0) }.joined()
        return "sha256:\(hex)"
    }
}

private final class AppRealProcessingCLIFixture {
    let rootURL: URL
    let workspaceURL: URL
    let cliURL: URL
    let sessionID = "session-app-ui-smoke"

    var sessionRootURL: URL {
        workspaceURL
            .appendingPathComponent("sessions", isDirectory: true)
            .appendingPathComponent(sessionID, isDirectory: true)
    }

    var exportURL: URL {
        workspaceURL
            .appendingPathComponent("exports", isDirectory: true)
            .appendingPathComponent("\(sessionID).md", isDirectory: false)
    }

    var deleteEventURL: URL {
        workspaceURL
            .appendingPathComponent("events", isDirectory: true)
            .appendingPathComponent("meeting_session.deleted.v1.jsonl", isDirectory: false)
    }

    init(sourceFile: StaticString = #filePath) throws {
        let nativeAppRootURL = URL(fileURLWithPath: String(describing: sourceFile))
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
        cliURL = nativeAppRootURL
            .deletingLastPathComponent()
            .appendingPathComponent("e2e", isDirectory: true)
            .appendingPathComponent("ma-cli-local.sh", isDirectory: false)

        guard FileManager.default.isExecutableFile(atPath: cliURL.path) else {
            throw CocoaError(.fileNoSuchFile, userInfo: [NSFilePathErrorKey: cliURL.path])
        }

        rootURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("ma-native-real-processing-app-\(UUID().uuidString)", isDirectory: true)
        workspaceURL = rootURL.appendingPathComponent("workspace", isDirectory: true)

        try FileManager.default.createDirectory(
            at: sessionRootURL.appendingPathComponent("artifacts", isDirectory: true),
            withIntermediateDirectories: true
        )
        try FileManager.default.createDirectory(
            at: sessionRootURL.appendingPathComponent("logs", isDirectory: true),
            withIntermediateDirectories: true
        )
        try FileManager.default.createDirectory(
            at: exportURL.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        try createNativeRecordingWorkspace()
    }

    deinit {
        cleanup()
    }

    func applyLaunchEnvironment(to app: XCUIApplication) {
        app.launchEnvironment["MA_NATIVE_PROCESSING_CLIENT"] = "process"
        app.launchEnvironment["MA_NATIVE_TRANSCRIPT_ACTION_CLIENT"] = "process"
        app.launchEnvironment["MA_NATIVE_APP_XCTEST"] = "1"
        app.launchEnvironment["MEETING_ASSISTANT_CLI_PATH"] = cliURL.path
        app.launchEnvironment["MEETING_ASSISTANT_WORKSPACE"] = workspaceURL.path
    }

    func cleanup() {
        try? FileManager.default.removeItem(at: rootURL)
    }

    func sessionMetadata() throws -> [String: Any] {
        let data = try Data(contentsOf: sessionRootURL.appendingPathComponent("session.json"))
        let payload = try JSONSerialization.jsonObject(with: data)
        return try XCTUnwrap(payload as? [String: Any])
    }

    func transcriptPayload() throws -> [String: Any] {
        let session = try sessionMetadata()
        let artifacts = try XCTUnwrap(session["artifacts"] as? [[String: Any]])
        let transcript = try XCTUnwrap(artifacts.first { $0["artifact_type"] as? String == "transcript_text" })
        let path = try XCTUnwrap(transcript["path"] as? String)
        let transcriptURL = URL(fileURLWithPath: path, relativeTo: sessionRootURL)
        let data = try Data(contentsOf: transcriptURL)
        let payload = try JSONSerialization.jsonObject(with: data)
        return try XCTUnwrap(payload as? [String: Any])
    }

    func exportContent() throws -> String {
        try String(contentsOf: exportURL, encoding: .utf8)
    }

    func deleteEventContent() throws -> String {
        try String(contentsOf: deleteEventURL, encoding: .utf8)
    }

    private func createNativeRecordingWorkspace() throws {
        let artifactsURL = sessionRootURL.appendingPathComponent("artifacts", isDirectory: true)
        let audioURL = artifactsURL.appendingPathComponent("mixed_audio.wav", isDirectory: false)
        let audioData = Self.fixtureWAVData()
        try audioData.write(to: audioURL)
        let audioChecksum = Self.sha256(audioData)
        let now = "2026-07-05T00:00:00Z"

        _ = try writeJSON(
            [
                "id": sessionID,
                "title": "Real processing CLI app-bundle fixture",
                "source_type": "native_recording",
                "status": "recorded",
                "started_at": now,
                "workspace_dir": sessionRootURL.path,
                "created_at": now,
                "updated_at": now,
                "artifacts": [
                    [
                        "id": "artifact-real-processing-mixed",
                        "session_id": sessionID,
                        "artifact_type": "mixed_audio",
                        "path": "artifacts/mixed_audio.wav",
                        "format": "wav",
                        "capture_status": "available",
                        "checksum": audioChecksum,
                        "created_at": now,
                    ],
                ],
            ],
            to: sessionRootURL.appendingPathComponent("session.json", isDirectory: false)
        )
    }

    @discardableResult
    private func writeJSON(_ payload: Any, to url: URL) throws -> String {
        let data = try JSONSerialization.data(withJSONObject: payload, options: [.prettyPrinted, .sortedKeys])
        try data.write(to: url)
        return Self.sha256(data)
    }

    private static func fixtureWAVData() -> Data {
        var samples = Data()
        for index in 0..<2_400 {
            let value = Int16((((index + 31) % 96) - 48) * 96)
            appendLittleEndian(value, to: &samples)
        }

        var data = Data()
        data.append(Data("RIFF".utf8))
        appendLittleEndian(UInt32(36 + samples.count), to: &data)
        data.append(Data("WAVE".utf8))
        data.append(Data("fmt ".utf8))
        appendLittleEndian(UInt32(16), to: &data)
        appendLittleEndian(UInt16(1), to: &data)
        appendLittleEndian(UInt16(1), to: &data)
        appendLittleEndian(UInt32(8_000), to: &data)
        appendLittleEndian(UInt32(16_000), to: &data)
        appendLittleEndian(UInt16(2), to: &data)
        appendLittleEndian(UInt16(16), to: &data)
        data.append(Data("data".utf8))
        appendLittleEndian(UInt32(samples.count), to: &data)
        data.append(samples)
        return data
    }

    private static func appendLittleEndian<T: FixedWidthInteger>(_ value: T, to data: inout Data) {
        var littleEndian = value.littleEndian
        withUnsafeBytes(of: &littleEndian) { data.append(contentsOf: $0) }
    }

    private static func sha256(_ data: Data) -> String {
        let digest = SHA256.hash(data: data)
        let hex = digest.map { String(format: "%02x", $0) }.joined()
        return "sha256:\(hex)"
    }
}

private final class AppRealRuntimeProcessingCLIFixture {
    let rootURL: URL
    let workspaceURL: URL
    let cliURL: URL
    let runtimePath: String
    let modelPath: String
    let smokeAudioURL: URL
    let sessionID = "session-app-ui-runtime"
    private let diagnosticDirectoryURL: URL?

    var sessionRootURL: URL {
        workspaceURL
            .appendingPathComponent("sessions", isDirectory: true)
            .appendingPathComponent(sessionID, isDirectory: true)
    }

    init(sourceFile: StaticString = #filePath) throws {
        let environment = ProcessInfo.processInfo.environment
        guard let runtimePath = environment["MEETING_ASSISTANT_TRANSCRIPTION_RUNTIME"],
              !runtimePath.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            throw XCTSkip("MEETING_ASSISTANT_TRANSCRIPTION_RUNTIME is required for the real runtime app-bundle smoke.")
        }
        guard let modelPath = environment["MEETING_ASSISTANT_TRANSCRIPTION_MODEL"],
              !modelPath.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            throw XCTSkip("MEETING_ASSISTANT_TRANSCRIPTION_MODEL is required for the real runtime app-bundle smoke.")
        }

        let defaultSmokeAudio = FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent(".local/share/ai-fixtures/asr/zh-en-tech/mixed-zh-en-tech.wav")
        let smokeAudioPath = environment["MEETING_ASSISTANT_WHISPER_SMOKE_AUDIO"]?
            .trimmingCharacters(in: .whitespacesAndNewlines)
        smokeAudioURL = URL(fileURLWithPath: smokeAudioPath?.isEmpty == false ? smokeAudioPath! : defaultSmokeAudio.path)
        guard FileManager.default.isReadableFile(atPath: smokeAudioURL.path) else {
            throw XCTSkip("MEETING_ASSISTANT_WHISPER_SMOKE_AUDIO must point to the mixed-language WAV fixture.")
        }

        self.runtimePath = runtimePath
        self.modelPath = modelPath
        let diagnosticPath = environment["MA_NATIVE_REAL_RUNTIME_DIAGNOSTIC_DIR"]?
            .trimmingCharacters(in: .whitespacesAndNewlines)
        diagnosticDirectoryURL = diagnosticPath?.isEmpty == false
            ? URL(fileURLWithPath: diagnosticPath!, isDirectory: true)
            : nil

        let nativeAppRootURL = URL(fileURLWithPath: String(describing: sourceFile))
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
        cliURL = nativeAppRootURL
            .deletingLastPathComponent()
            .appendingPathComponent("e2e", isDirectory: true)
            .appendingPathComponent("ma-cli-local.sh", isDirectory: false)

        guard FileManager.default.isExecutableFile(atPath: cliURL.path) else {
            throw CocoaError(.fileNoSuchFile, userInfo: [NSFilePathErrorKey: cliURL.path])
        }

        rootURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("ma-native-real-runtime-app-\(UUID().uuidString)", isDirectory: true)
        workspaceURL = rootURL.appendingPathComponent("workspace", isDirectory: true)
        try FileManager.default.createDirectory(
            at: sessionRootURL.appendingPathComponent("artifacts", isDirectory: true),
            withIntermediateDirectories: true
        )
        try FileManager.default.createDirectory(
            at: sessionRootURL.appendingPathComponent("logs", isDirectory: true),
            withIntermediateDirectories: true
        )
        try createNativeRecordingWorkspace()
    }

    deinit {
        cleanup()
    }

    func applyLaunchEnvironment(to app: XCUIApplication) {
        app.launchEnvironment["MA_NATIVE_PROCESSING_CLIENT"] = "process"
        app.launchEnvironment["MA_NATIVE_APP_XCTEST"] = "1"
        app.launchEnvironment["MA_NATIVE_APP_REAL_RUNTIME_SMOKE"] = "1"
        app.launchEnvironment["MA_NATIVE_PROCESSING_RUNTIME"] = "whisper_cpp"
        app.launchEnvironment["MA_NATIVE_PROCESSING_LANGUAGE"] = "zh"
        app.launchEnvironment["MEETING_ASSISTANT_CLI_PATH"] = cliURL.path
        app.launchEnvironment["MEETING_ASSISTANT_WORKSPACE"] = workspaceURL.path
        app.launchEnvironment["MEETING_ASSISTANT_TRANSCRIPTION_RUNTIME"] = runtimePath
        app.launchEnvironment["MEETING_ASSISTANT_TRANSCRIPTION_MODEL"] = modelPath
        app.launchEnvironment["MEETING_ASSISTANT_WHISPER_SMOKE_AUDIO"] = smokeAudioURL.path
    }

    func cleanup() {
        guard FileManager.default.fileExists(atPath: rootURL.path) else {
            return
        }
        do {
            try FileManager.default.removeItem(at: rootURL)
        } catch {
            // Cleanup is best-effort; it must not mask the real smoke failure.
        }
    }

    func writeTimeoutDiagnostics(
        statusDescription: String,
        errorDescription: String
    ) -> String {
        var candidateDirectories: [URL] = []
        if let diagnosticDirectoryURL {
            candidateDirectories.append(diagnosticDirectoryURL)
        }
        candidateDirectories.append(
            FileManager.default.temporaryDirectory
                .appendingPathComponent("meeting-assistant-real-runtime-diagnostics", isDirectory: true)
        )

        for diagnosticDirectoryURL in candidateDirectories {
            if let result = writeTimeoutDiagnostics(
                statusDescription: statusDescription,
                errorDescription: errorDescription,
                to: diagnosticDirectoryURL
            ) {
                return result
            }
        }
        return "<write failed>"
    }

    private func writeTimeoutDiagnostics(
        statusDescription: String,
        errorDescription: String,
        to diagnosticDirectoryURL: URL
    ) -> String? {
        do {
            try FileManager.default.createDirectory(
                at: diagnosticDirectoryURL,
                withIntermediateDirectories: true
            )
            let reportURL = diagnosticDirectoryURL
                .appendingPathComponent("real-runtime-timeout-\(sessionID).json", isDirectory: false)
            let session = (try? sessionMetadata()) ?? [:]
            let artifacts = session["artifacts"] as? [[String: Any]] ?? []
            let artifactSummaries = artifacts.map(Self.artifactSummary)
            let payload: [String: Any] = [
                "report_schema": 1,
                "component": "native-app",
                "release_gate": "opt-in-native-app-bundle-ui-automation",
                "smoke": "real-runtime-app-bundle",
                "blocker_type": "real_runtime_processing_timeout",
                "not_release_readiness": true,
                "session_id": sessionID,
                "ui": [
                    "processing_status": statusDescription,
                    "processing_error": errorDescription,
                ],
                "provider": [
                    "cli": Self.fileSummary(path: cliURL.path, executable: true),
                    "runtime": Self.fileSummary(path: runtimePath, executable: true),
                    "model": Self.fileSummary(path: modelPath, executable: false),
                    "audio": Self.fileSummary(path: smokeAudioURL.path, executable: false),
                    "requested_runtime": "whisper_cpp",
                    "requested_language": "zh",
                ],
                "workspace": [
                    "root_exists": FileManager.default.fileExists(atPath: workspaceURL.path),
                    "session_exists": FileManager.default.fileExists(atPath: sessionRootURL.path),
                    "session_metadata_exists": FileManager.default.fileExists(
                        atPath: sessionRootURL.appendingPathComponent("session.json").path
                    ),
                    "artifact_count": artifactSummaries.count,
                    "artifact_summaries": artifactSummaries,
                    "processing_log": Self.processingLogSummary(
                        at: sessionRootURL.appendingPathComponent("logs/processing.log", isDirectory: false)
                    ),
                ],
                "residual_risks": [
                    "does not prove real runtime processing completed from the launched app bundle",
                    "does not include transcript text, audio content, model content, or full local paths",
                ],
            ]
            try writeJSON(payload, to: reportURL)
            return reportURL.path
        } catch {
            return nil
        }
    }

    func sessionMetadata() throws -> [String: Any] {
        let data = try Data(contentsOf: sessionRootURL.appendingPathComponent("session.json"))
        let payload = try JSONSerialization.jsonObject(with: data)
        return try XCTUnwrap(payload as? [String: Any])
    }

    func transcriptPayload() throws -> [String: Any] {
        let session = try sessionMetadata()
        let artifacts = try XCTUnwrap(session["artifacts"] as? [[String: Any]])
        let transcript = try XCTUnwrap(artifacts.first { $0["artifact_type"] as? String == "transcript_text" })
        let path = try XCTUnwrap(transcript["path"] as? String)
        let transcriptURL = URL(fileURLWithPath: path, relativeTo: sessionRootURL)
        let data = try Data(contentsOf: transcriptURL)
        let payload = try JSONSerialization.jsonObject(with: data)
        return try XCTUnwrap(payload as? [String: Any])
    }

    private func createNativeRecordingWorkspace() throws {
        let artifactsURL = sessionRootURL.appendingPathComponent("artifacts", isDirectory: true)
        let audioURL = artifactsURL.appendingPathComponent("mixed_audio.wav", isDirectory: false)
        let audioData = try Data(contentsOf: smokeAudioURL)
        try audioData.write(to: audioURL)
        let audioChecksum = Self.sha256(audioData)
        let now = "2026-07-05T00:00:00Z"

        _ = try writeJSON(
            [
                "id": sessionID,
                "title": "Real whisper runtime app-bundle fixture",
                "source_type": "native_recording",
                "status": "recorded",
                "started_at": now,
                "workspace_dir": sessionRootURL.path,
                "created_at": now,
                "updated_at": now,
                "artifacts": [
                    [
                        "id": "artifact-real-runtime-mixed",
                        "session_id": sessionID,
                        "artifact_type": "mixed_audio",
                        "path": "artifacts/mixed_audio.wav",
                        "format": "wav",
                        "capture_status": "available",
                        "checksum": audioChecksum,
                        "created_at": now,
                    ],
                ],
            ],
            to: sessionRootURL.appendingPathComponent("session.json", isDirectory: false)
        )
    }

    @discardableResult
    private func writeJSON(_ payload: Any, to url: URL) throws -> String {
        let data = try JSONSerialization.data(withJSONObject: payload, options: [.prettyPrinted, .sortedKeys])
        try data.write(to: url)
        return Self.sha256(data)
    }

    private static func artifactSummary(_ artifact: [String: Any]) -> [String: Any] {
        let relativePath = artifact["path"] as? String ?? ""
        return [
            "artifact_type": artifact["artifact_type"] as? String ?? "<missing>",
            "capture_status": artifact["capture_status"] as? String ?? "<missing>",
            "format": artifact["format"] as? String ?? "<missing>",
            "path_basename": URL(fileURLWithPath: relativePath).lastPathComponent,
            "has_checksum": artifact["checksum"] != nil,
        ]
    }

    private static func fileSummary(path: String, executable: Bool) -> [String: Any] {
        let url = URL(fileURLWithPath: path)
        var payload: [String: Any] = [
            "basename": url.lastPathComponent,
            "exists": FileManager.default.fileExists(atPath: path),
            "allowed_root": allowedRootKind(for: url),
        ]
        if executable {
            payload["is_executable"] = FileManager.default.isExecutableFile(atPath: path)
        } else {
            payload["is_readable"] = FileManager.default.isReadableFile(atPath: path)
        }
        if let attributes = try? FileManager.default.attributesOfItem(atPath: path),
           let size = attributes[.size] as? NSNumber {
            payload["size_bytes"] = size.int64Value
        }
        return payload
    }

    private static func allowedRootKind(for url: URL) -> String {
        let path = url.standardizedFileURL.path
        let home = FileManager.default.homeDirectoryForCurrentUser.standardizedFileURL.path
        let root = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .standardizedFileURL
            .path
        if path.hasPrefix("\(home)/.local/bin/") {
            return "user_local_bin"
        }
        if path.hasPrefix("\(home)/.local/opt/whisper.cpp/") {
            return "user_local_whisper_runtime"
        }
        if path.hasPrefix("\(home)/.local/share/ai-models/whisper.cpp/") {
            return "user_local_whisper_model"
        }
        if path.hasPrefix("\(home)/.local/share/ai-fixtures/asr/zh-en-tech/") {
            return "user_local_asr_fixture"
        }
        if path.hasPrefix("\(root)/e2e/") {
            return "repo_platform_e2e"
        }
        return "other"
    }

    private static func processingLogSummary(at url: URL) -> [String: Any] {
        guard let text = try? String(contentsOf: url, encoding: .utf8) else {
            return [
                "exists": false,
                "line_count": 0,
                "events": [],
            ]
        }
        let lines = text
            .split(separator: "\n")
            .map(String.init)
        let events = lines.suffix(8).map { line in
            [
                "command": token(named: "command", in: line) ?? "<missing>",
                "code": token(named: "code", in: line) ?? "<missing>",
            ]
        }
        return [
            "exists": true,
            "line_count": lines.count,
            "events": events,
        ]
    }

    private static func token(named name: String, in line: String) -> String? {
        let prefix = "\(name)="
        return line
            .split(separator: " ")
            .first { $0.hasPrefix(prefix) }
            .map { String($0.dropFirst(prefix.count)) }
    }

    private static func sha256(_ data: Data) -> String {
        let digest = SHA256.hash(data: data)
        let hex = digest.map { String(format: "%02x", $0) }.joined()
        return "sha256:\(hex)"
    }
}

private final class AppMVPFullStackCLIFixture {
    let rootURL: URL
    let workspaceURL: URL
    let cliURL: URL
    let sessionID = "session-app-ui-smoke"

    var sessionRootURL: URL {
        workspaceURL
            .appendingPathComponent("sessions", isDirectory: true)
            .appendingPathComponent(sessionID, isDirectory: true)
    }

    var exportURL: URL {
        workspaceURL
            .appendingPathComponent("exports", isDirectory: true)
            .appendingPathComponent("\(sessionID).md", isDirectory: false)
    }

    var deleteEventURL: URL {
        workspaceURL
            .appendingPathComponent("events", isDirectory: true)
            .appendingPathComponent("meeting_session.deleted.v1.jsonl", isDirectory: false)
    }

    init(sourceFile: StaticString = #filePath) throws {
        let nativeAppRootURL = URL(fileURLWithPath: String(describing: sourceFile))
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
        cliURL = nativeAppRootURL
            .deletingLastPathComponent()
            .appendingPathComponent("e2e", isDirectory: true)
            .appendingPathComponent("ma-cli-local.sh", isDirectory: false)

        guard FileManager.default.isExecutableFile(atPath: cliURL.path) else {
            throw CocoaError(.fileNoSuchFile, userInfo: [NSFilePathErrorKey: cliURL.path])
        }

        rootURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("ma-native-mvp-full-stack-app-\(UUID().uuidString)", isDirectory: true)
        workspaceURL = rootURL.appendingPathComponent("workspace", isDirectory: true)
        try FileManager.default.createDirectory(
            at: exportURL.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
    }

    deinit {
        cleanup()
    }

    func applyLaunchEnvironment(to app: XCUIApplication) {
        app.launchEnvironment["MA_NATIVE_RECORDING_CLIENT"] = "controlled"
        app.launchEnvironment["MA_NATIVE_RECORDING_CONTROLLED_MIXED_AUDIO"] = "1"
        app.launchEnvironment["MA_NATIVE_PROCESSING_CLIENT"] = "process"
        app.launchEnvironment["MA_NATIVE_TRANSCRIPT_ACTION_CLIENT"] = "process"
        app.launchEnvironment["MA_NATIVE_APP_XCTEST"] = "1"
        app.launchEnvironment["MEETING_ASSISTANT_CLI_PATH"] = cliURL.path
        app.launchEnvironment["MEETING_ASSISTANT_WORKSPACE"] = workspaceURL.path
        app.launchEnvironment["MA_NATIVE_RECORDING_WORKSPACE"] = workspaceURL.path
    }

    func cleanup() {
        try? FileManager.default.removeItem(at: rootURL)
    }

    func sessionMetadata() throws -> [String: Any] {
        let data = try Data(contentsOf: sessionRootURL.appendingPathComponent("session.json"))
        let payload = try JSONSerialization.jsonObject(with: data)
        return try XCTUnwrap(payload as? [String: Any])
    }

    func exportContent() throws -> String {
        try String(contentsOf: exportURL, encoding: .utf8)
    }

    func deleteEventContent() throws -> String {
        try String(contentsOf: deleteEventURL, encoding: .utf8)
    }
}
