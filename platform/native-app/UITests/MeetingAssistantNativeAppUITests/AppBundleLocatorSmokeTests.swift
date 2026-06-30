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
    }

    func testReadyFixtureStartsAndStopsFakeRecordingFromLaunchedAppBundle() {
        let app = launchApp(fixture: "ready")

        assertElement("ma.permissionDependency.summary", in: app, contains: "Permissions and required dependencies are ready.")
        tapButton("ma.recording.startButton", in: app)

        assertElement("ma.recording.status", in: app, contains: "Recording in progress.")
        assertElement("ma.recording.sessionID", in: app, contains: "session-app-ui-smoke")
        tapButton("ma.recording.stopButton", in: app)

        assertElement("ma.recording.status", in: app, contains: "Recording saved.")
        assertElement("ma.recording.savedSummary", in: app, contains: "Saved 2 recording artifacts.")
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

    private func launchApp(
        fixture: String? = nil,
        workspaceURL: URL? = nil,
        sessionID: String? = nil
    ) -> XCUIApplication {
        dismissSpotlightIfPresent()
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
        app.terminate()
        _ = app.wait(for: .notRunning, timeout: 5)
        app.launch()
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
        let element = app
            .descendants(matching: .button)
            .matching(identifier: identifier)
            .firstMatch
        XCTAssertTrue(element.waitForExistence(timeout: 5), "Expected button \(identifier) to exist.")
        return element
    }

    private func element(_ identifier: String, in app: XCUIApplication) -> XCUIElement {
        let element = app
            .descendants(matching: .any)
            .matching(identifier: identifier)
            .firstMatch
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

        let windowFrame = appWindow(in: app).frame
        let windowCenter = CGPoint(x: windowFrame.midX, y: windowFrame.midY)
        XCTAssertTrue(
            screen.frame.contains(windowCenter),
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
        let control = button(identifier, in: app)
        waitForHittable(control, file: file, line: line)
        control.click()
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
