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
        assertElement("ma.recording.heading", in: app, contains: "Recording")
        assertElement("ma.recording.readinessStatus", in: app, contains: "Recording readiness is pending.")
        assertElement("ma.recording.status", in: app, contains: "Run readiness checks before recording.")
        XCTAssertTrue(button("ma.recording.startButton", in: app).exists)
        XCTAssertFalse(button("ma.recording.startButton", in: app).isEnabled)
        XCTAssertTrue(button("ma.recording.stopButton", in: app).exists)
        XCTAssertFalse(button("ma.recording.stopButton", in: app).isEnabled)
        assertElement(
            "ma.processing.status",
            in: app,
            contains: "Processing is blocked until required dependencies are available."
        )
        XCTAssertTrue(button("ma.processing.startButton", in: app).exists)
        XCTAssertFalse(button("ma.processing.startButton", in: app).isEnabled)
        XCTAssertTrue(button("ma.processing.retryButton", in: app).exists)
        XCTAssertFalse(button("ma.processing.retryButton", in: app).isEnabled)
    }

    func testReadyFixtureStartsAndStopsFakeRecordingFromLaunchedAppBundle() {
        let app = launchApp(fixture: "ready")

        assertElement("ma.permissionDependency.summary", in: app, contains: "Permissions and required dependencies are ready.")
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
        let processingFixture = try AppProcessingProcessFixture(mode: "success", workspaceURL: recordingFixture.workspaceURL)
        let app = launchApp(fixture: "ready", recordingFixture: recordingFixture, processingFixture: processingFixture)

        tapButton("ma.recording.startButton", in: app)

        assertElement("ma.recording.status", in: app, contains: "Recording in progress.")
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

        tapProcessingButton("ma.processing.startButton", in: app)

        assertElement("ma.processing.status", in: app, contains: "Processing complete.")
        assertElement(
            "ma.processing.transcriptStatus",
            in: app,
            contains: "Transcript transcript-process-fixture generated with 2 segments."
        )
        assertElement(
            "ma.processing.speakerLabelStatus",
            in: app,
            contains: "Speaker labels artifact artifact-process-speakers is available."
        )
        assertElement(
            "ma.processing.success",
            in: app,
            contains: "Generated transcript and speaker labels for session session-app-ui-smoke."
        )
        XCTAssertEqual(
            try processingFixture.invocationLines(),
            successfulProcessingInvocationLines(sessionID: "session-app-ui-smoke")
        )
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
            contains: "Copied plain text transcript for session session-app-ui-transcript."
        )
        assertDoesNotExist("ma.transcriptAction.error", in: successApp)

        let failureApp = launchApp(fixture: "transcript-action-copy-failure")

        tapTranscriptActionButton("ma.transcriptAction.copyButton", in: failureApp)

        assertElement("ma.transcriptAction.status", in: failureApp, contains: "Copy failed.")
        assertElement("ma.transcriptAction.error", in: failureApp, contains: "Transcript artifact is missing.")
        assertElement("ma.transcriptAction.error", in: failureApp, contains: "artifact_missing")
    }

    func testTranscriptActionExportSuccessCancelAndFailureAreUserTriggeredFromLaunchedAppBundle() {
        let successApp = launchApp(fixture: "transcript-action-export-success")

        tapTranscriptActionButton("ma.transcriptAction.exportButton", in: successApp)

        assertElement("ma.transcriptAction.status", in: successApp, contains: "Export complete.")
        assertElement(
            "ma.transcriptAction.success",
            in: successApp,
            contains: "Exported markdown transcript to /tmp/meeting-assistant-export.md."
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
        assertElement("ma.transcriptAction.error", in: failureApp, contains: "path_conflict")
    }

    func testTranscriptActionDeleteConfirmCancelSuccessAndFailureFromLaunchedAppBundle() {
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

        let failureApp = launchApp(fixture: "transcript-action-delete-failure")

        tapTranscriptActionButton("ma.transcriptAction.deleteButton", in: failureApp)
        assertExists("ma.transcriptAction.deletePrompt", in: failureApp)
        assertElement("ma.transcriptAction.deletePromptText", in: failureApp, contains: "External exports are retained.")
        tapTranscriptActionButton("ma.transcriptAction.deleteConfirmButton", in: failureApp)

        assertElement("ma.transcriptAction.status", in: failureApp, contains: "Delete failed.")
        assertElement("ma.transcriptAction.error", in: failureApp, contains: "Session path escaped the workspace.")
        assertElement("ma.transcriptAction.error", in: failureApp, contains: "path_conflict")
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

    private func launchApp(
        fixture: String? = nil,
        workspaceURL: URL? = nil,
        sessionID: String? = nil,
        recordingFixture: AppControlledRecordingFixture? = nil,
        processingFixture: AppProcessingProcessFixture? = nil
    ) -> XCUIApplication {
        dismissSpotlightIfPresent()
        launchedApp?.terminate()
        if let launchedApp {
            _ = launchedApp.wait(for: .notRunning, timeout: 5)
        }
        launchedApp = nil

        let app = XCUIApplication()
        app.launchArguments += ["-ApplePersistenceIgnoreState", "YES"]
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
        if let processingFixture {
            processingFixture.applyLaunchEnvironment(to: app)
        }
        app.terminate()
        _ = app.wait(for: .notRunning, timeout: 5)
        app.launch()
        if !app.wait(for: .runningForeground, timeout: 5) {
            app.activate()
        }
        XCTAssertTrue(app.wait(for: .runningForeground, timeout: 10), "Expected app bundle to run foreground.")
        XCTAssertTrue(appWindow(in: app).waitForExistence(timeout: 5), "Expected app bundle window to exist.")
        assertWindowIsOnBuiltInScreen(app)
        launchedApp = app
        return app
    }

    private func dismissSpotlightIfPresent() {
        let spotlight = XCUIApplication(bundleIdentifier: "com.apple.Spotlight")
        guard spotlight.windows.firstMatch.exists else {
            return
        }
        spotlight.typeKey(.escape, modifierFlags: [])
    }

    private func button(_ identifier: String, in app: XCUIApplication) -> XCUIElement {
        let matches = app
            .descendants(matching: .button)
            .matching(identifier: identifier)
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
        app.windows.firstMatch
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
        let element = element(identifier, in: app)
        let predicate = NSPredicate(
            format: "label CONTAINS %@ OR value CONTAINS %@",
            expectedText,
            expectedText
        )
        let expectation = XCTNSPredicateExpectation(predicate: predicate, object: element)
        return XCTWaiter.wait(for: [expectation], timeout: timeout) == .completed
    }

    private func assertElement(
        _ identifier: String,
        in app: XCUIApplication,
        doesNotContain unexpectedText: String,
        file: StaticString = #filePath,
        line: UInt = #line
    ) {
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
            if waitForElement("ma.recording.status", in: app, contains: expectedStatus, timeout: 12) {
                return
            }
            if !waitForElement("ma.recording.status", in: app, contains: "Recording in progress.", timeout: 0.5) {
                break
            }
        }
        assertElement("ma.recording.status", in: app, contains: expectedStatus, file: file, line: line)
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

    private func tapProcessingButton(
        _ identifier: String,
        in app: XCUIApplication,
        file: StaticString = #filePath,
        line: UInt = #line
    ) {
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
        for attempt in 0..<2 {
            tapProcessingButton(identifier, in: app, file: file, line: line)
            let timeout: TimeInterval = attempt == 0 ? 3 : 7
            if waitForElement("ma.processing.status", in: app, contains: expectedStatus, timeout: timeout) {
                return
            }
        }
        assertElement("ma.processing.status", in: app, contains: expectedStatus, file: file, line: line)
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
        if waitUntilHittable(control, timeout: 1) {
            control.click()
            return
        }
        if isVisibleEnabled(control, in: app) {
            control.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5)).click()
            return
        }
        waitForHittable(control, file: file, line: line)
        control.click()
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
        XCTAssertTrue(
            appWindow(in: app).waitForExistence(timeout: 5),
            "Expected app window before tapping \(identifier).",
            file: file,
            line: line
        )
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

        for _ in 0..<8 {
            let element = app
                .descendants(matching: .any)
                .matching(identifier: targetIdentifier)
                .firstMatch
            if element.exists {
                return
            }
            if app.state != .runningForeground {
                app.activate()
                _ = app.wait(for: .runningForeground, timeout: 5)
            }
            scrollView.swipeUp()
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

private final class AppProcessingProcessFixture {
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

    func sessionMetadata(sessionID: String) throws -> [String: Any] {
        let sessionURL = workspaceURL
            .appendingPathComponent("sessions", isDirectory: true)
            .appendingPathComponent(sessionID, isDirectory: true)
            .appendingPathComponent("session.json", isDirectory: false)
        let data = try Data(contentsOf: sessionURL)
        let payload = try JSONSerialization.jsonObject(with: data)
        return try XCTUnwrap(payload as? [String: Any])
    }
}
