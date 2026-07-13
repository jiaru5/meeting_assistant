import AppKit
import CryptoKit
import XCTest

@MainActor
final class DesignedNativeShellAppBundleTests: XCTestCase {
    private enum ID {
        static let meetingsHeading = "ma.meetings.heading"
        static let meetingsEmpty = "ma.meetings.empty"
        static let newRecordingButton = "ma.meetings.newRecordingButton"
        static let recentMeetings = "ma.meetings.recent"
        static let workspaceNotice = "ma.meetings.notice"
        static let meetingsNavigation = "ma.navigation.meetings"
        static let newRecordingNavigation = "ma.navigation.newRecording"
        static let currentMeetingNavigation = "ma.navigation.currentMeeting"
        static let diagnosticsNavigation = "ma.navigation.diagnostics"

        static let newRecordingHeading = "ma.newRecording.heading"
        static let titleField = "ma.newRecording.titleField"
        static let screenTarget = "ma.newRecording.target.screen"
        static let systemAudio = "ma.newRecording.systemAudio"
        static let microphone = "ma.newRecording.microphone"
        static let readiness = "ma.newRecording.readiness"
        static let checkAgain = "ma.newRecording.checkAgain"

        static let detailHeading = "ma.meetingDetail.heading"
        static let detailStatus = "ma.meetingDetail.status"
        static let recordingTimer = "ma.meetingDetail.recordingTimer"
        static let audioSummary = "ma.meetingDetail.audioSummary"
        static let savedSummary = "ma.meetingDetail.savedSummary"
        static let transcriptLoadError = "ma.meetingDetail.transcriptLoadError"
        static let reloadTranscript = "ma.meetingDetail.reloadTranscript"
        static let recoveryStatus = "ma.meetingDetail.recoveryStatus"
        static let startNewRecording = "ma.meetingDetail.startNewRecording"
        static let technicalDetails = "ma.meetingDetail.technicalDetails"

        static let diagnosticsHeading = "ma.diagnostics.heading"
        static let diagnosticsWorkspacePath = "ma.diagnostics.workspacePath"

        // These command identifiers are shared with the component controls. The
        // surrounding page identifiers above prove which MVP.1 task owns them.
        static let startRecording = "ma.recording.startButton"
        static let stopRecording = "ma.recording.stopButton"
        static let generateTranscript = "ma.processing.startButton"
        static let processingStatus = "ma.processing.status"
        static let retryProcessing = "ma.processing.retryButton"
        static let copyTranscript = "ma.transcriptAction.copyButton"
        static let exportTranscript = "ma.transcriptAction.exportButton"
        static let deleteMeeting = "ma.transcriptAction.deleteButton"
        static let deletePrompt = "ma.transcriptAction.deletePrompt"
        static let deletePromptText = "ma.transcriptAction.deletePromptText"
        static let confirmDelete = "ma.transcriptAction.deleteConfirmButton"
        static let actionSuccess = "ma.transcriptAction.success"

        static let primaryTaskActions = [
            newRecordingButton,
            startRecording,
            stopRecording,
            generateTranscript,
            checkAgain,
            retryProcessing,
            startNewRecording,
            copyTranscript,
            exportTranscript,
        ]

        static func artifactStatus(_ artifactType: String) -> String {
            "ma.recording.artifact.\(artifactType).status"
        }

        static func meetingRow(_ sessionID: String) -> String {
            "ma.meetings.row.\(sessionID)"
        }
    }

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

    func testFirstRunCompletesTheFocusedRecordProcessReviewJourney() {
        let app = launchApp(fixture: "ready")

        // First use begins with one empty-state action, not the implementation
        // dashboard that MVP.1 replaces.
        assertElement(ID.meetingsHeading, in: app, contains: "Meetings")
        assertExists(ID.meetingsEmpty, in: app)
        assertText("Record your first meeting", in: app)
        assertOnlyPrimaryTaskActions([ID.newRecordingButton], in: app)

        tapButton(ID.newRecordingButton, in: app)
        assertElement(ID.newRecordingHeading, in: app, contains: "Set up your recording")
        assertElement(ID.screenTarget, in: app, contains: "Entire screen")
        assertExists(ID.readiness, in: app)
        assertText("Ready to record", in: app)

        replaceText(in: ID.titleField, with: "MVP.1 planning review", in: app)
        setToggle(ID.systemAudio, to: true, in: app)
        setToggle(ID.microphone, to: false, in: app)
        assertToggle(ID.systemAudio, isOn: true, in: app)
        assertToggle(ID.microphone, isOn: false, in: app)
        assertOnlyPrimaryTaskActions([ID.startRecording], in: app)

        tapButton(ID.startRecording, in: app)
        assertElement(ID.detailStatus, in: app, contains: "Recording")
        assertElement(ID.detailHeading, in: app, contains: "MVP.1 planning review")
        assertExists(ID.recordingTimer, in: app)
        assertElement(ID.audioSummary, in: app, contains: "System audio")
        assertOnlyPrimaryTaskActions([ID.stopRecording], in: app)

        tapButton(ID.stopRecording, in: app)
        assertElement(ID.detailHeading, in: app, contains: "MVP.1 planning review")
        assertElement(ID.savedSummary, in: app, contains: "2 meeting files are ready")
        assertOnlyPrimaryTaskActions([ID.generateTranscript], in: app)

        tapButton(ID.generateTranscript, in: app)
        assertElement(ID.detailHeading, in: app, contains: "MVP.1 planning review")
        assertText("The meeting transcript is ready for review.", in: app)
        assertOnlyPrimaryTaskActions([ID.copyTranscript, ID.exportTranscript], in: app)

        tapButton(ID.copyTranscript, in: app)
        assertElement(ID.actionSuccess, in: app, contains: "Transcript copied")

        tapButton(ID.exportTranscript, in: app)
        assertElement(ID.actionSuccess, in: app, contains: "Transcript exported")
        assertOnlyPrimaryTaskActions([ID.copyTranscript, ID.exportTranscript], in: app)
    }

    func testReturningUserOpensRecentTranscriptThenDeletesTheMeeting() {
        let app = launchApp(fixture: "transcript-review")
        let sessionID = "session-app-ui-transcript"

        assertElement(ID.meetingsHeading, in: app, contains: "Meetings")
        assertExists(ID.recentMeetings, in: app)
        assertOnlyPrimaryTaskActions([ID.newRecordingButton], in: app)

        tapButton(ID.meetingRow(sessionID), in: app)
        assertElement(ID.detailHeading, in: app, contains: "Transcript Review Fixture")
        assertText("First transcript segment for review.", in: app)
        assertOnlyPrimaryTaskActions([ID.copyTranscript, ID.exportTranscript], in: app)

        tapButton(ID.deleteMeeting, in: app)
        assertExists(ID.deletePrompt, in: app)
        assertElement(ID.deletePromptText, in: app, contains: "Exports saved elsewhere on this Mac will be kept")
        tapButton(ID.confirmDelete, in: app)

        assertElement(ID.meetingsHeading, in: app, contains: "Meetings")
        assertElement(ID.workspaceNotice, in: app, contains: "Meeting deleted")
        assertOnlyPrimaryTaskActions([ID.newRecordingButton], in: app)
        assertDoesNotExist(ID.meetingRow(sessionID), in: app)
        assertDoesNotExist(ID.currentMeetingNavigation, in: app)
        assertDoesNotExist(ID.deleteMeeting, in: app)
        assertDoesNotExist(ID.deletePrompt, in: app)
        assertDoesNotExist(ID.copyTranscript, in: app)
        assertDoesNotExist(ID.exportTranscript, in: app)
    }

    func testStartFailureRemainsVisibleAcrossNavigationAndOffersRecovery() {
        let app = launchApp(fixture: "start-failure")

        tapButton(ID.newRecordingButton, in: app)
        replaceText(in: ID.titleField, with: "Failure recovery check", in: app)
        tapButton(ID.startRecording, in: app)

        assertElement(ID.newRecordingHeading, in: app, contains: "Set up your recording")
        assertText("Recording did not start", in: app)
        assertText("Screen Recording permission is missing.", in: app)
        let recovery = button(ID.startRecording, in: app)
        XCTAssertTrue(recovery.isEnabled, "Expected the failed start task to offer a retry.")
        XCTAssertTrue(recovery.label.contains("Try recording again"), "Expected the primary action to become an explicit retry.")
        assertOnlyPrimaryTaskActions([ID.startRecording], in: app)

        tapButton(ID.diagnosticsNavigation, in: app)
        assertElement(ID.diagnosticsHeading, in: app, contains: "Keep Meeting Assistant ready")
        assertExists(ID.diagnosticsWorkspacePath, in: app)
        assertOnlyPrimaryTaskActions([], in: app)

        tapButton(ID.newRecordingNavigation, in: app)
        assertElement(ID.newRecordingHeading, in: app, contains: "Set up your recording")
        assertText("Recording did not start", in: app)
        assertText("Screen Recording permission is missing.", in: app)
        assertOnlyPrimaryTaskActions([ID.startRecording], in: app)

        tapButton(ID.startRecording, in: app)
        assertText("Recording did not start", in: app)
        assertText("Screen Recording permission is missing.", in: app)
        XCTAssertTrue(button(ID.startRecording, in: app).isEnabled)
    }

    func testBlockedPreflightFailsClosedWithOneEnabledRecoveryAction() {
        let app = launchApp(fixture: "blocked")

        tapButton(ID.newRecordingButton, in: app)

        assertElement(ID.newRecordingHeading, in: app, contains: "Set up your recording")
        assertElement(ID.readiness, in: app, contains: "Setup needs attention")
        assertText("A required permission or local transcript tool is missing", in: app)
        assertOnlyPrimaryTaskActions(
            [ID.checkAgain],
            disabled: [ID.startRecording],
            in: app
        )

        tapButton(ID.checkAgain, in: app)
        assertElement(ID.readiness, in: app, contains: "Setup needs attention")
        assertOnlyPrimaryTaskActions(
            [ID.checkAgain],
            disabled: [ID.startRecording],
            in: app
        )
    }

    func testSavedDegradedMeetingExplainsSafeFilesBeforeProcessing() {
        let app = launchApp(fixture: "saved-degraded")

        tapButton(ID.newRecordingButton, in: app)
        replaceText(in: ID.titleField, with: "Degraded capture check", in: app)
        tapButton(ID.startRecording, in: app)
        assertElement(ID.detailStatus, in: app, contains: "Recording")
        tapButton(ID.stopRecording, in: app)

        assertElement(ID.detailHeading, in: app, contains: "Degraded capture check")
        assertElement(ID.savedSummary, in: app, contains: "1 requested source was unavailable")
        let meetingAudio = element(ID.artifactStatus("mixed_audio"), in: app)
        let microphone = element(ID.artifactStatus("microphone_audio"), in: app)
        XCTAssertTrue(meetingAudio.label.contains("Meeting audio, Saved with limited quality"))
        XCTAssertFalse(meetingAudio.label.contains("mixed_audio"))
        XCTAssertFalse(meetingAudio.label.contains("degraded"))
        XCTAssertTrue(microphone.label.contains("Microphone, Not captured"))
        XCTAssertFalse(microphone.label.contains("microphone_audio"))
        XCTAssertFalse(microphone.label.contains("missing"))
        assertText("Saved with limited quality", in: app)
        assertText("Successful files were kept", in: app)
        assertOnlyPrimaryTaskActions([ID.generateTranscript], in: app)
    }

    func testHistoricalProcessingMeetingOffersSafeRecoveryInsteadOfSaved() throws {
        let sessionID = "session-app-ui-historical-processing"
        let workspaceURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("MeetingAssistantNative-Historical-\(UUID().uuidString)", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: workspaceURL) }
        try materializeHistoricalMeetingWorkspace(
            workspaceURL: workspaceURL,
            sessionID: sessionID,
            status: "processing"
        )
        let app = launchApp(workspaceURL: workspaceURL)

        let row = element(ID.meetingRow(sessionID), in: app)
        XCTAssertTrue(row.label.contains("Transcript interrupted"))
        XCTAssertFalse(row.label.contains("Saved"))
        tapButton(ID.meetingRow(sessionID), in: app)

        assertElement(ID.recoveryStatus, in: app, contains: "Meeting needs attention")
        assertText("Existing meeting files were not changed", in: app)
        assertOnlyPrimaryTaskActions([ID.startNewRecording], in: app)
        assertDoesNotExist(ID.generateTranscript, in: app)
        assertDoesNotExist(ID.retryProcessing, in: app)
        assertExists(ID.deleteMeeting, in: app)
        assertExists(ID.technicalDetails, in: app)
    }

    func testProcessingRunningLocksNavigationAndExposesNoCompetingTaskAction() {
        let app = launchApp(fixture: "processing-running")
        let sessionID = "session-app-ui-processing-running"

        tapButton(ID.meetingRow(sessionID), in: app)
        assertOnlyPrimaryTaskActions([ID.generateTranscript], in: app)
        tapButton(ID.generateTranscript, in: app)

        assertElement(ID.processingStatus, in: app, contains: "Transcribing meeting audio")
        assertText("The original recording is safe while local processing runs", in: app)
        assertOnlyPrimaryTaskActions([], in: app)
        XCTAssertFalse(
            button(ID.meetingsNavigation, in: app).isEnabled,
            "Expected task navigation to stay locked while processing is running."
        )
    }

    func testProcessingFailureKeepsRecordingSafeAndRetriesThroughStableControl() {
        let app = launchApp(fixture: "processing-failure")
        let sessionID = "session-app-ui-processing"

        tapButton(ID.meetingRow(sessionID), in: app)
        tapButton(ID.generateTranscript, in: app)

        assertText("The transcript could not be created", in: app)
        assertText("The original recording is unchanged and safe to retry", in: app)
        assertOnlyPrimaryTaskActions([ID.retryProcessing], in: app)
        XCTAssertTrue(button(ID.retryProcessing, in: app).label.contains("Retry transcript"))

        tapButton(ID.retryProcessing, in: app)
        assertText("The transcript could not be created", in: app)
        assertOnlyPrimaryTaskActions([ID.retryProcessing], in: app)
    }

    func testStopSaveFailureKeepsCurrentSessionAndRetriesThroughStopControl() {
        let app = launchApp(fixture: "stop-failure")

        tapButton(ID.newRecordingButton, in: app)
        replaceText(in: ID.titleField, with: "Save retry check", in: app)
        tapButton(ID.startRecording, in: app)
        assertElement(ID.detailStatus, in: app, contains: "Recording")
        tapButton(ID.stopRecording, in: app)

        assertElement(ID.detailHeading, in: app, contains: "Save retry check")
        assertText("The recording could not be saved", in: app)
        assertText("The current session is still available for another stop attempt", in: app)
        assertOnlyPrimaryTaskActions([ID.stopRecording], in: app)
        XCTAssertTrue(button(ID.stopRecording, in: app).label.contains("Try saving again"))

        tapButton(ID.stopRecording, in: app)
        assertElement(ID.detailHeading, in: app, contains: "Save retry check")
        assertText("The recording could not be saved", in: app)
        assertOnlyPrimaryTaskActions([ID.stopRecording], in: app)
    }

    func testTranscribedMeetingWithMissingTranscriptRegeneratesFromSavedAudio() {
        let app = launchApp(fixture: "transcript-missing-recoverable")
        let sessionID = "session-app-ui-transcript-missing-recoverable"

        assertElement(ID.meetingRow(sessionID), in: app, contains: "Transcript unavailable")
        tapButton(ID.meetingRow(sessionID), in: app)

        assertElement(ID.transcriptLoadError, in: app, contains: "original recording is still safe")
        assertElement(ID.transcriptLoadError, in: app, contains: "Regenerate the transcript from the saved meeting audio")
        assertOnlyPrimaryTaskActions([ID.generateTranscript], in: app)
        XCTAssertTrue(button(ID.generateTranscript, in: app).label.contains("Regenerate transcript"))
        assertExists(ID.reloadTranscript, in: app)

        tapButton(ID.generateTranscript, in: app)

        assertDoesNotExist(ID.transcriptLoadError, in: app)
        assertText("The meeting transcript is ready for review", in: app)
        assertOnlyPrimaryTaskActions([ID.copyTranscript, ID.exportTranscript], in: app)
    }

    func testTranscribedMeetingWithoutAudioFailsClosedAndCanBeDeleted() {
        let app = launchApp(fixture: "transcript-missing-no-audio")
        let sessionID = "session-app-ui-transcript-missing-no-audio"

        tapButton(ID.meetingRow(sessionID), in: app)

        assertElement(ID.transcriptLoadError, in: app, contains: "no processable audio for regeneration")
        assertOnlyPrimaryTaskActions([], in: app)
        assertDoesNotExist(ID.generateTranscript, in: app)
        assertExists(ID.reloadTranscript, in: app)

        tapButton(ID.deleteMeeting, in: app)
        assertExists(ID.deletePrompt, in: app)
        tapButton(ID.confirmDelete, in: app)

        assertElement(ID.meetingsHeading, in: app, contains: "Meetings")
        assertDoesNotExist(ID.meetingRow(sessionID), in: app)
    }

    func testTranscriptLoadFailurePersistsUntilWorkspaceRepairMakesReloadSucceed() throws {
        let sessionID = "session-app-ui-transcript-load-failure"
        let workspaceURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("MeetingAssistantNative-Reload-\(UUID().uuidString)", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: workspaceURL) }
        let sessionURL = workspaceURL
            .appendingPathComponent("sessions", isDirectory: true)
            .appendingPathComponent(sessionID, isDirectory: true)
            .appendingPathComponent("session.json", isDirectory: false)
        let transcriptURL = sessionURL
            .deletingLastPathComponent()
            .appendingPathComponent("artifacts/transcript.json", isDirectory: false)
        let app = launchApp(fixture: "transcript-load-failure", workspaceURL: workspaceURL)

        XCTAssertFalse(FileManager.default.fileExists(atPath: sessionURL.path))
        XCTAssertFalse(FileManager.default.fileExists(atPath: transcriptURL.path))

        tapButton(ID.meetingRow(sessionID), in: app)

        assertElement(ID.detailHeading, in: app, contains: "Unreadable transcript fixture")
        assertElement(ID.transcriptLoadError, in: app, contains: "The original recording is still safe")
        assertText("The transcript could not be opened", in: app)
        assertOnlyPrimaryTaskActions([ID.generateTranscript], in: app)
        assertExists(ID.reloadTranscript, in: app)
        assertDoesNotExist(ID.copyTranscript, in: app)
        assertDoesNotExist(ID.exportTranscript, in: app)

        tapButton(ID.reloadTranscript, in: app)
        assertElement(ID.transcriptLoadError, in: app, contains: "The original recording is still safe")
        assertOnlyPrimaryTaskActions([ID.generateTranscript], in: app)
        assertExists(ID.reloadTranscript, in: app)
        assertDoesNotExist(ID.copyTranscript, in: app)
        assertDoesNotExist(ID.exportTranscript, in: app)

        try materializeReloadTranscriptWorkspace(
            workspaceURL: workspaceURL,
            sessionID: sessionID
        )
        XCTAssertTrue(FileManager.default.fileExists(atPath: sessionURL.path))
        XCTAssertTrue(FileManager.default.fileExists(atPath: transcriptURL.path))

        tapButton(ID.reloadTranscript, in: app)
        assertDoesNotExist(ID.transcriptLoadError, in: app)
        assertText("The meeting transcript is ready for review", in: app)
        assertOnlyPrimaryTaskActions([ID.copyTranscript, ID.exportTranscript], in: app)

        XCTAssertTrue(FileManager.default.fileExists(atPath: sessionURL.path))
        XCTAssertTrue(FileManager.default.fileExists(atPath: transcriptURL.path))
        let sessionData = try? Data(contentsOf: sessionURL)
        let sessionPayload = sessionData.flatMap { data in
            (try? JSONSerialization.jsonObject(with: data)) as? [String: Any]
        }
        XCTAssertEqual(sessionPayload?["id"] as? String, sessionID)
        let artifacts = sessionPayload?["artifacts"] as? [[String: Any]]
        XCTAssertEqual(artifacts?.first?["artifact_type"] as? String, "transcript_text")
        XCTAssertEqual(artifacts?.first?["path"] as? String, "artifacts/transcript.json")
        XCTAssertTrue((artifacts?.first?["checksum"] as? String)?.hasPrefix("sha256:") == true)
    }

    private func materializeReloadTranscriptWorkspace(
        workspaceURL: URL,
        sessionID: String
    ) throws {
        let sessionRoot = workspaceURL
            .appendingPathComponent("sessions", isDirectory: true)
            .appendingPathComponent(sessionID, isDirectory: true)
        let artifactsRoot = sessionRoot.appendingPathComponent("artifacts", isDirectory: true)
        try FileManager.default.createDirectory(
            at: artifactsRoot,
            withIntermediateDirectories: true
        )

        let transcriptData = try JSONSerialization.data(
            withJSONObject: [
                "id": "transcript-reload-recovery",
                "session_id": sessionID,
                "source_artifact_id": "artifact-meeting-audio",
                "status": "succeeded",
                "segments": [
                    [
                        "segment_id": "segment-reload-recovery",
                        "start_ms": 0,
                        "end_ms": 4_000,
                        "text": "The meeting transcript is ready for review.",
                        "speaker_label": "A",
                    ],
                ],
            ],
            options: [.prettyPrinted, .sortedKeys]
        )
        let transcriptURL = artifactsRoot.appendingPathComponent("transcript.json", isDirectory: false)
        try transcriptData.write(to: transcriptURL, options: .atomic)
        let digest = SHA256.hash(data: transcriptData)
        let checksum = "sha256:" + digest.map { String(format: "%02x", $0) }.joined()

        let sessionData = try JSONSerialization.data(
            withJSONObject: [
                "id": sessionID,
                "title": "Unreadable transcript fixture",
                "artifacts": [
                    [
                        "id": "artifact-transcript-reload-recovery",
                        "session_id": sessionID,
                        "artifact_type": "transcript_text",
                        "path": "artifacts/transcript.json",
                        "capture_status": "available",
                        "checksum": checksum,
                    ],
                ],
            ],
            options: [.prettyPrinted, .sortedKeys]
        )
        try sessionData.write(
            to: sessionRoot.appendingPathComponent("session.json", isDirectory: false),
            options: .atomic
        )
    }

    private func materializeHistoricalMeetingWorkspace(
        workspaceURL: URL,
        sessionID: String,
        status: String
    ) throws {
        let sessionRoot = workspaceURL
            .appendingPathComponent("sessions", isDirectory: true)
            .appendingPathComponent(sessionID, isDirectory: true)
        try FileManager.default.createDirectory(
            at: sessionRoot,
            withIntermediateDirectories: true
        )
        let sessionData = try JSONSerialization.data(
            withJSONObject: [
                "id": sessionID,
                "title": "Interrupted transcript fixture",
                "status": status,
                "started_at": "2026-07-13T10:00:00Z",
                "updated_at": "2026-07-13T10:05:00Z",
                "artifacts": [],
            ],
            options: [.prettyPrinted, .sortedKeys]
        )
        try sessionData.write(
            to: sessionRoot.appendingPathComponent("session.json", isDirectory: false),
            options: .atomic
        )
    }

    private func launchApp(
        fixture: String? = nil,
        workspaceURL: URL? = nil
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
        if let workspaceURL {
            app.launchEnvironment["MA_NATIVE_RECORDING_WORKSPACE"] = workspaceURL.path
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

    private func replaceText(in identifier: String, with text: String, in app: XCUIApplication) {
        let field = app.descendants(matching: .textField).matching(identifier: identifier).firstMatch
        XCTAssertTrue(field.waitForExistence(timeout: 5), "Expected text field \(identifier) to exist.")
        field.click()
        field.typeKey("a", modifierFlags: .command)
        field.typeText(text)
        XCTAssertEqual(field.value as? String, text)
    }

    private func setToggle(_ identifier: String, to isOn: Bool, in app: XCUIApplication) {
        let toggle = element(identifier, in: app)
        if toggleIsOn(toggle) != isOn {
            toggle.click()
        }
        assertToggle(identifier, isOn: isOn, in: app)
    }

    private func assertToggle(
        _ identifier: String,
        isOn: Bool,
        in app: XCUIApplication,
        file: StaticString = #filePath,
        line: UInt = #line
    ) {
        let toggle = element(identifier, in: app)
        XCTAssertEqual(
            toggleIsOn(toggle),
            isOn,
            "Expected toggle \(identifier) to be \(isOn ? "on" : "off"). Value: \(String(describing: toggle.value))",
            file: file,
            line: line
        )
    }

    private func toggleIsOn(_ toggle: XCUIElement) -> Bool {
        if let number = toggle.value as? NSNumber {
            return number.boolValue
        }
        let value = String(describing: toggle.value ?? "").lowercased()
        return value == "1" || value == "true" || value == "on" || value == "selected"
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

    private func assertText(
        _ expectedText: String,
        in app: XCUIApplication,
        file: StaticString = #filePath,
        line: UInt = #line
    ) {
        let predicate = NSPredicate(
            format: "label CONTAINS %@ OR value CONTAINS %@",
            expectedText,
            expectedText
        )
        let match = app.descendants(matching: .any).matching(predicate).firstMatch
        XCTAssertTrue(
            match.waitForExistence(timeout: 8),
            "Expected visible text containing \(expectedText).",
            file: file,
            line: line
        )
    }

    private func assertOnlyPrimaryTaskActions(
        _ expectedIdentifiers: [String],
        disabled disabledIdentifiers: [String] = [],
        in app: XCUIApplication,
        file: StaticString = #filePath,
        line: UInt = #line
    ) {
        let expected = Set(expectedIdentifiers)
        let disabled = Set(disabledIdentifiers)
        for identifier in ID.primaryTaskActions {
            let candidate = app.descendants(matching: .button).matching(identifier: identifier).firstMatch
            if expected.contains(identifier) {
                if !candidate.waitForExistence(timeout: 2) || !candidate.isHittable {
                    scrollTowardElement(identifier, in: app)
                }
                XCTAssertTrue(
                    candidate.waitForExistence(timeout: 5),
                    "Expected current task action \(identifier) to exist.",
                    file: file,
                    line: line
                )
                XCTAssertTrue(candidate.isEnabled, "Expected \(identifier) to be enabled.", file: file, line: line)
                XCTAssertTrue(candidate.isHittable, "Expected \(identifier) to be hittable.", file: file, line: line)
            } else if disabled.contains(identifier) {
                XCTAssertTrue(
                    candidate.waitForExistence(timeout: 5),
                    "Expected disabled current-task action \(identifier) to exist.",
                    file: file,
                    line: line
                )
                XCTAssertFalse(candidate.isEnabled, "Expected \(identifier) to be disabled.", file: file, line: line)
            } else {
                XCTAssertFalse(
                    candidate.exists,
                    "Expected action from another task step \(identifier) to be absent.",
                    file: file,
                    line: line
                )
            }
        }
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
        let element = app.descendants(matching: .any).matching(identifier: identifier).firstMatch
        let predicate = NSPredicate(format: "exists == false")
        let expectation = XCTNSPredicateExpectation(predicate: predicate, object: element)
        let result = XCTWaiter.wait(for: [expectation], timeout: 5)
        XCTAssertEqual(result, .completed, "Expected \(identifier) to be absent.", file: file, line: line)
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
