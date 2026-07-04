import AppKit
import XCTest

final class DesignedNativeShellAppBundleTests: XCTestCase {
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

    func testDesignedShellExposesNavigationStatusBoardAndAllSections() {
        let app = launchApp(fixture: "transcript-review")

        assertElement("ma.shell.heading", in: app, contains: "Meeting Assistant")
        assertElement(
            "ma.shell.subtitle",
            in: app,
            contains: "Designed native app shell"
        )
        assertExists("ma.shell.navigation", in: app)
        assertElement("ma.shell.selectedSection", in: app, contains: "Preflight selected.")
        assertElement("ma.shell.status.preflight", in: app, contains: "Ready")
        assertElement("ma.shell.status.recording", in: app, contains: "Ready")
        assertElement("ma.shell.status.processing", in: app, contains: "Ready")
        assertElement("ma.shell.status.transcript", in: app, contains: "Available")
        assertElement("ma.shell.status.actions", in: app, contains: "Ready")

        for section in ["preflight", "recording", "artifacts", "processing", "transcript", "actions"] {
            assertExists("ma.shell.nav.\(section)", in: app)
            assertExists("ma.shell.section.\(section)", in: app)
            assertExists("ma.shell.section.\(section).heading", in: app)
        }

        tapButton("ma.shell.nav.artifacts", in: app)
        assertElement("ma.shell.selectedSection", in: app, contains: "Session artifacts selected.")

        tapButton("ma.shell.nav.processing", in: app)
        assertElement("ma.shell.selectedSection", in: app, contains: "Processing selected.")

        tapButton("ma.shell.nav.actions", in: app)
        assertElement("ma.shell.selectedSection", in: app, contains: "Export and delete selected.")
    }

    func testDesignedShellMainActionsUseExistingCommandClients() {
        let app = launchApp(fixture: "transcript-review")

        tapButton("ma.recording.startButton", in: app)
        assertElement("ma.recording.status", in: app, contains: "Recording in progress.")
        assertElement("ma.shell.status.recording", in: app, contains: "Recording")

        tapButton("ma.recording.stopButton", in: app)
        assertElement("ma.recording.status", in: app, contains: "Recording saved.")
        assertElement("ma.shell.status.recording", in: app, contains: "Saved")
        assertElement("ma.sessionArtifact.screen_video.status", in: app, contains: "screen_video: available")
        assertElement("ma.sessionArtifact.mixed_audio.status", in: app, contains: "mixed_audio: available")

        tapButton("ma.processing.startButton", in: app)
        assertElement("ma.processing.status", in: app, contains: "Processing complete.")
        assertElement("ma.shell.status.processing", in: app, contains: "Complete")
        assertElement(
            "ma.shell.processingStep.transcript",
            in: app,
            contains: "Transcript transcript-fake generated with 2 segments."
        )
        assertElement(
            "ma.shell.processingStep.exportReady",
            in: app,
            contains: "Transcript can be reviewed before user-triggered export."
        )

        tapButton("ma.transcriptAction.copyButton", in: app)
        assertElement("ma.transcriptAction.status", in: app, contains: "Copy complete.")

        tapButton("ma.transcriptAction.exportButton", in: app)
        assertElement("ma.transcriptAction.status", in: app, contains: "Export complete.")

        tapButton("ma.transcriptAction.deleteButton", in: app)
        assertElement("ma.transcriptAction.deletePromptText", in: app, contains: "session-app-ui-transcript")
        assertElement("ma.transcriptAction.deletePromptText", in: app, contains: "External exports are retained.")
        tapButton("ma.transcriptAction.deleteConfirmButton", in: app)
        assertElement("ma.transcriptAction.status", in: app, contains: "Delete complete.")
    }

    func testDesignedShellBlockedAndDegradedStatesStayQueryable() {
        let blockedApp = launchApp()

        assertElement("ma.shell.status.preflight", in: blockedApp, contains: "Blocked")
        assertElement("ma.shell.status.processing", in: blockedApp, contains: "Blocked")
        assertElement("ma.shell.exportDelete.unavailable", in: blockedApp, contains: "Transcript actions are unavailable")
        XCTAssertFalse(button("ma.recording.startButton", in: blockedApp).isEnabled)
        XCTAssertFalse(button("ma.processing.startButton", in: blockedApp).isEnabled)

        let degradedApp = launchApp(fixture: "processing-transcript-only")
        tapButton("ma.processing.startButton", in: degradedApp)

        assertElement("ma.shell.status.processing", in: degradedApp, contains: "Transcript-only")
        assertElement("ma.processing.degradation", in: degradedApp, contains: "speaker labeling runtime unavailable")
        assertElement(
            "ma.shell.processingStep.speakerLabels",
            in: degradedApp,
            contains: "Speaker labels degraded: speaker labeling runtime unavailable"
        )
    }

    private func launchApp(fixture: String? = nil) -> XCUIApplication {
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
        app.terminate()
        _ = app.wait(for: .notRunning, timeout: 5)
        app.launch()
        if !app.wait(for: .runningForeground, timeout: 5) {
            app.activate()
        }
        XCTAssertTrue(app.wait(for: .runningForeground, timeout: 10), "Expected app bundle to run foreground.")
        XCTAssertTrue(app.windows.firstMatch.waitForExistence(timeout: 5), "Expected app bundle window to exist.")
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

    private func builtInScreen() -> NSScreen? {
        NSScreen.screens.first { screen in
            guard let screenNumber = screen.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? NSNumber else {
                return false
            }
            return CGDisplayIsBuiltin(CGDirectDisplayID(screenNumber.uint32Value)) != 0
        }
    }

    private func button(_ identifier: String, in app: XCUIApplication) -> XCUIElement {
        let matches = app.descendants(matching: .button).matching(identifier: identifier)
        let element = matches.firstMatch
        if !element.waitForExistence(timeout: 2) {
            scrollTowardElement(identifier, in: app)
        }
        XCTAssertTrue(element.waitForExistence(timeout: 5), "Expected button \(identifier) to exist.")
        return matches.allElementsBoundByIndex.first { $0.exists && $0.isHittable } ?? element
    }

    private func tapButton(_ identifier: String, in app: XCUIApplication) {
        if app.state != .runningForeground {
            app.activate()
        }
        let control = button(identifier, in: app)
        for _ in 0..<8 {
            if control.isHittable {
                control.click()
                return
            }
            scrollTowardElement(identifier, in: app)
        }
        XCTAssertTrue(control.isHittable, "Expected button \(identifier) to be hittable.")
        control.click()
    }

    private func element(_ identifier: String, in app: XCUIApplication) -> XCUIElement {
        let element = app.descendants(matching: .any).matching(identifier: identifier).firstMatch
        if !element.waitForExistence(timeout: 2) {
            scrollTowardElement(identifier, in: app)
        }
        XCTAssertTrue(element.waitForExistence(timeout: 5), "Expected element \(identifier) to exist.")
        return element
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
        let result = XCTWaiter.wait(for: [expectation], timeout: 8)
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

    private func scrollTowardElement(_ identifier: String, in app: XCUIApplication) {
        let target = app.descendants(matching: .any).matching(identifier: identifier).firstMatch
        let scrollViews = app.scrollViews.allElementsBoundByIndex
        let scrollView = scrollViews.first { scrollView in
            scrollView.exists && scrollView.frame.width > 300
        } ?? app.scrollViews.firstMatch
        guard scrollView.exists else {
            return
        }

        for attempt in 0..<8 {
            if target.exists, target.isHittable {
                return
            }
            if attempt < 5 {
                scrollView.swipeUp()
            } else {
                scrollView.swipeDown()
            }
        }
    }
}
