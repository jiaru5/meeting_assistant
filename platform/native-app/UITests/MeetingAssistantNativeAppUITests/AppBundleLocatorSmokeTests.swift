import XCTest

final class AppBundleLocatorSmokeTests: XCTestCase {
    private var launchedApp: XCUIApplication?

    override func setUp() {
        continueAfterFailure = false
    }

    override func tearDown() {
        launchedApp?.terminate()
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
        let startButton = button("ma.recording.startButton", in: app)
        waitForEnabled(startButton)
        app.activate()
        dismissSpotlightIfPresent()
        startButton.click()

        assertElement("ma.recording.status", in: app, contains: "Recording in progress.")
        assertElement("ma.recording.sessionID", in: app, contains: "session-app-ui-smoke")
        let stopButton = button("ma.recording.stopButton", in: app)
        waitForEnabled(stopButton)
        app.activate()
        dismissSpotlightIfPresent()
        stopButton.click()

        assertElement("ma.recording.status", in: app, contains: "Recording saved.")
        assertElement("ma.recording.savedSummary", in: app, contains: "Saved 2 recording artifacts.")
    }

    func testStartFailureFixtureShowsStableErrorLocatorFromLaunchedAppBundle() {
        let app = launchApp(fixture: "start-failure")

        let startButton = button("ma.recording.startButton", in: app)
        waitForEnabled(startButton)
        app.activate()
        dismissSpotlightIfPresent()
        startButton.click()

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

    func testEmptyTranscriptFixtureExposesStableEmptyStateFromLaunchedAppBundle() {
        let app = launchApp(fixture: "transcript-empty")

        assertElement("ma.transcript.heading", in: app, contains: "Empty transcript fixture")
        assertElement("ma.transcript.empty", in: app, contains: "Transcript has no segments to review.")
        assertElement("ma.transcript.degradation", in: app, contains: "speaker labeling skipped")
    }

    private func launchApp(fixture: String? = nil) -> XCUIApplication {
        dismissSpotlightIfPresent()
        let app = XCUIApplication()
        app.launchArguments += ["-ApplePersistenceIgnoreState", "YES"]
        if let fixture {
            app.launchEnvironment["MA_NATIVE_APP_SMOKE_FIXTURE"] = fixture
        }
        app.launch()
        XCTAssertTrue(app.wait(for: .runningForeground, timeout: 10), "Expected app bundle to run foreground.")
        XCTAssertTrue(appWindow(in: app).waitForExistence(timeout: 5), "Expected app bundle window to exist.")
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
        let element = appWindow(in: app)
            .descendants(matching: .button)
            .matching(identifier: identifier)
            .firstMatch
        XCTAssertTrue(element.waitForExistence(timeout: 5), "Expected button \(identifier) to exist.")
        return element
    }

    private func element(_ identifier: String, in app: XCUIApplication) -> XCUIElement {
        let element = appWindow(in: app)
            .descendants(matching: .any)
            .matching(identifier: identifier)
            .firstMatch
        XCTAssertTrue(element.waitForExistence(timeout: 5), "Expected element \(identifier) to exist.")
        return element
    }

    private func appWindow(in app: XCUIApplication) -> XCUIElement {
        app.windows.firstMatch
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
        let element = appWindow(in: app)
            .descendants(matching: .any)
            .matching(identifier: identifier)
            .firstMatch
        XCTAssertFalse(element.waitForExistence(timeout: 1), "Expected element \(identifier) not to exist.", file: file, line: line)
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
}
