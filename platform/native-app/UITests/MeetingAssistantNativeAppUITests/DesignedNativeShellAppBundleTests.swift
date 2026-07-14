import AppKit
import CryptoKit
import XCTest

@MainActor
final class DesignedNativeShellAppBundleTests: XCTestCase {
    private enum RegisteredTranscriptFailure: String, CaseIterable {
        case missing
        case checksumDrift = "checksum-drift"
        case corruptJSON = "corrupt-json"
    }

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
        static let audioSourcePicker = "ma.meetingDetail.audioSourcePicker"
        static let transcriptToolbar = "ma.meetingDetail.transcriptToolbar"
        static let transcriptLoadError = "ma.meetingDetail.transcriptLoadError"
        static let reloadTranscript = "ma.meetingDetail.reloadTranscript"
        static let recoveryStatus = "ma.meetingDetail.recoveryStatus"
        static let startNewRecording = "ma.meetingDetail.startNewRecording"
        static let technicalDetails = "ma.meetingDetail.technicalDetails"

        static let diagnosticsHeading = "ma.diagnostics.heading"
        static let diagnosticsWorkspacePath = "ma.diagnostics.workspacePath"
        static let openScreenRecordingSettings = "ma.permissionDependency.openPrivacySettingsButton"
        static let openMicrophoneSettings = "ma.permissionDependency.openMicrophoneSettingsButton"

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

        static func transcriptText(_ segmentID: String) -> String {
            "ma.transcript.text.\(segmentID)"
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
        attachScreenshot("01-meetings-empty", of: app)

        tapButton(ID.newRecordingButton, in: app)
        assertElement(ID.newRecordingHeading, in: app, contains: "Set up your recording")
        assertElement(ID.screenTarget, in: app, contains: "Entire screen")
        assertElement(ID.readiness, in: app, contains: "Ready to record")
        attachScreenshot("02-new-recording-ready", of: app)

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
        attachScreenshot("03-recording-live", of: app)

        tapButton(ID.stopRecording, in: app)
        assertElement(ID.detailHeading, in: app, contains: "MVP.1 planning review")
        assertElement(ID.savedSummary, in: app, contains: "2 meeting files are ready")
        assertOnlyPrimaryTaskActions([ID.generateTranscript], in: app)
        attachScreenshot("04-recording-saved", of: app)

        tapButton(ID.generateTranscript, in: app)
        assertElement(ID.detailHeading, in: app, contains: "MVP.1 planning review")
        assertElement(
            ID.transcriptText("segment-1"),
            in: app,
            contains: "The meeting transcript is ready for review."
        )
        assertOnlyPrimaryTaskActions([ID.copyTranscript, ID.exportTranscript], in: app)
        attachScreenshot("06-transcript-ready", of: app)

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
        attachScreenshot("00-meetings-recent", of: app)

        tapButton(ID.meetingRow(sessionID), in: app)
        assertElement(ID.detailHeading, in: app, contains: "Transcript Review Fixture")
        assertElement(
            ID.transcriptText("seg-1"),
            in: app,
            contains: "First transcript segment for review."
        )
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

    func testLongTranscriptKeepsCopyAndExportVisibleWhileContentScrolls() {
        let app = launchApp(fixture: "transcript-long")
        let sessionID = "session-app-ui-long-transcript"

        tapButton(ID.meetingRow(sessionID), in: app)
        assertElement(ID.detailHeading, in: app, contains: "Long Transcript Fixture")
        assertExists(ID.transcriptToolbar, in: app)
        let toolbar = app.descendants(matching: .any)
            .matching(identifier: ID.transcriptToolbar)
            .firstMatch
        let firstSegment = element(ID.transcriptText("seg-long-0"), in: app)
        let initialToolbarMinY = toolbar.frame.minY
        let initialFirstSegmentMinY = firstSegment.frame.minY

        let contentScrollView = app.scrollViews.allElementsBoundByIndex.first {
            $0.exists && $0.frame.width > 300
        }
        XCTAssertNotNil(contentScrollView, "Expected a transcript content scroll view.")
        for _ in 0..<5 {
            contentScrollView?.swipeUp()
        }

        let copy = app.descendants(matching: .button)
            .matching(identifier: ID.copyTranscript)
            .firstMatch
        let export = app.descendants(matching: .button)
            .matching(identifier: ID.exportTranscript)
            .firstMatch
        XCTAssertTrue(toolbar.exists)
        XCTAssertFalse(toolbar.frame.isEmpty)
        XCTAssertTrue(app.windows.firstMatch.frame.intersects(toolbar.frame))
        XCTAssertEqual(toolbar.frame.minY, initialToolbarMinY, accuracy: 3)
        XCTAssertTrue(
            !firstSegment.exists
                || firstSegment.frame.minY < initialFirstSegmentMinY - 20
                || !app.windows.firstMatch.frame.intersects(firstSegment.frame),
            "Expected transcript content to move while the action toolbar remained fixed."
        )
        XCTAssertTrue(copy.exists && copy.isHittable)
        XCTAssertTrue(export.exists && export.isHittable)
        assertOnlyPrimaryTaskActions([ID.copyTranscript, ID.exportTranscript], in: app)
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
        attachScreenshot("07-diagnostics", of: app)

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
        assertElement(ID.readiness, in: app, contains: "A permission or capture requirement")
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

        tapButton(ID.diagnosticsNavigation, in: app)
        assertExists(ID.openScreenRecordingSettings, in: app)
        assertDoesNotExist(ID.openMicrophoneSettings, in: app)
    }

    func testMissingTranscriptToolsDoNotBlockASafeRecording() {
        let app = launchApp(fixture: "capture-ready-processing-blocked")

        tapButton(ID.newRecordingButton, in: app)

        assertElement(ID.readiness, in: app, contains: "Ready to record")
        assertElement(ID.readiness, in: app, contains: "create the transcript later")
        assertOnlyPrimaryTaskActions([ID.startRecording], in: app)
        tapButton(ID.startRecording, in: app)
        assertElement(ID.detailStatus, in: app, contains: "Recording")
        assertOnlyPrimaryTaskActions([ID.stopRecording], in: app)
    }

    func testMicrophonePermissionOnlyBlocksWhenMicrophoneIsRequested() {
        let app = launchApp(fixture: "microphone-denied")

        tapButton(ID.newRecordingButton, in: app)
        assertToggle(ID.microphone, isOn: true, in: app)
        assertElement(ID.readiness, in: app, contains: "Setup needs attention")
        assertOnlyPrimaryTaskActions(
            [ID.checkAgain],
            disabled: [ID.startRecording],
            in: app
        )

        setToggle(ID.microphone, to: false, in: app)
        assertElement(ID.readiness, in: app, contains: "Ready to record")
        assertOnlyPrimaryTaskActions([ID.startRecording], in: app)

        setToggle(ID.microphone, to: true, in: app)
        assertElement(ID.readiness, in: app, contains: "Setup needs attention")
        assertOnlyPrimaryTaskActions(
            [ID.checkAgain],
            disabled: [ID.startRecording],
            in: app
        )

        tapButton(ID.diagnosticsNavigation, in: app)
        assertExists(ID.openMicrophoneSettings, in: app)
        assertDoesNotExist(ID.openScreenRecordingSettings, in: app)
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
        assertElement(ID.artifactStatus("mixed_audio"), in: app, contains: "Saved with limited quality")
        assertElement(ID.savedSummary, in: app, contains: "Successful files were kept")
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
        let app = launchApp(fixture: "ready", workspaceURL: workspaceURL)

        let row = element(ID.meetingRow(sessionID), in: app)
        XCTAssertTrue(row.label.contains("Transcript interrupted"))
        XCTAssertFalse(row.label.contains("Saved"))
        tapButton(ID.meetingRow(sessionID), in: app)

        assertElement(ID.recoveryStatus, in: app, contains: "Meeting needs attention")
        assertText("The original meeting audio is still safe", in: app)
        assertText("Confirm the audio source", in: app)
        assertExists(ID.audioSourcePicker, in: app)
        assertOnlyPrimaryTaskActions([ID.generateTranscript], in: app)
        XCTAssertTrue(button(ID.generateTranscript, in: app).label.contains("Retry transcript"))
        assertDoesNotExist(ID.startNewRecording, in: app)
        assertDoesNotExist(ID.retryProcessing, in: app)
        assertExists(ID.deleteMeeting, in: app)
        assertExists(ID.technicalDetails, in: app)

        tapButton(ID.generateTranscript, in: app)
        assertElement(
            ID.transcriptText("segment-1"),
            in: app,
            contains: "The meeting transcript is ready for review"
        )
        assertOnlyPrimaryTaskActions([ID.copyTranscript, ID.exportTranscript], in: app)
    }

    func testFallbackAudioPickerSendsTheSelectedMicrophoneArtifactID() throws {
        let sessionID = "session-app-ui-fallback-audio"
        let workspaceURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("MeetingAssistantNative-FallbackAudio-\(UUID().uuidString)", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: workspaceURL) }
        try materializeFallbackAudioWorkspace(
            workspaceURL: workspaceURL,
            sessionID: sessionID
        )
        let processingFixture = try AppProcessingProcessFixture(
            mode: "success",
            workspaceURL: workspaceURL
        )
        defer { processingFixture.cleanup() }
        let app = launchApp(
            fixture: "ready",
            workspaceURL: workspaceURL,
            processingFixture: processingFixture
        )

        tapButton(ID.meetingRow(sessionID), in: app)
        let picker = element(ID.audioSourcePicker, in: app)
        XCTAssertTrue(picker.isHittable)
        let defaultAudioSelected = XCTNSPredicateExpectation(
            predicate: NSPredicate(format: "value == %@", "System audio"),
            object: picker
        )
        XCTAssertEqual(XCTWaiter.wait(for: [defaultAudioSelected], timeout: 3), .completed)
        picker.click()
        let microphone = app.menuItems["Microphone"].firstMatch
        XCTAssertTrue(microphone.waitForExistence(timeout: 5))
        microphone.click()
        let microphoneSelected = XCTNSPredicateExpectation(
            predicate: NSPredicate(format: "value == %@", "Microphone"),
            object: picker
        )
        XCTAssertEqual(XCTWaiter.wait(for: [microphoneSelected], timeout: 3), .completed)

        tapButton(ID.generateTranscript, in: app)
        assertElement(
            ID.transcriptText("seg-process-1"),
            in: app,
            contains: "The meeting transcript is ready for review"
        )
        XCTAssertEqual(
            try processingFixture.invocationLines().first,
            [
                ["generate", "transcript"].joined(separator: "_"),
                "--session-id",
                sessionID,
                "--source-artifact-id",
                "artifact-fallback-microphone",
            ].joined(separator: " ")
        )
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
        attachScreenshot("05-processing", of: app)
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
        assertDoesNotExist(ID.audioSourcePicker, in: app)
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

    func testTranscribedMeetingWithMissingTranscriptRequiresRepairWithoutReplacement() {
        let app = launchApp(fixture: "transcript-missing-recoverable")
        let sessionID = "session-app-ui-transcript-missing-recoverable"

        assertElement(ID.meetingRow(sessionID), in: app, contains: "Transcript needs repair")
        tapButton(ID.meetingRow(sessionID), in: app)

        assertElement(ID.transcriptLoadError, in: app, contains: "original recording is still safe")
        assertElement(ID.transcriptLoadError, in: app, contains: "will not replace a registered transcript")
        assertOnlyPrimaryTaskActions([], in: app)
        assertDoesNotExist(ID.generateTranscript, in: app)
        assertExists(ID.reloadTranscript, in: app)
    }

    func testTranscribedMeetingWithoutAudioFailsClosedAndCanBeDeleted() {
        let app = launchApp(fixture: "transcript-missing-no-audio")
        let sessionID = "session-app-ui-transcript-missing-no-audio"

        tapButton(ID.meetingRow(sessionID), in: app)

        assertElement(ID.transcriptLoadError, in: app, contains: "available files are still safe")
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
        assertOnlyPrimaryTaskActions([], in: app)
        assertDoesNotExist(ID.generateTranscript, in: app)
        assertExists(ID.reloadTranscript, in: app)
        assertDoesNotExist(ID.copyTranscript, in: app)
        assertDoesNotExist(ID.exportTranscript, in: app)

        tapButton(ID.reloadTranscript, in: app)
        assertElement(ID.transcriptLoadError, in: app, contains: "The original recording is still safe")
        assertOnlyPrimaryTaskActions([], in: app)
        assertDoesNotExist(ID.generateTranscript, in: app)
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
        assertElement(
            ID.transcriptText("segment-reload-recovery"),
            in: app,
            contains: "The meeting transcript is ready for review"
        )
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

    func testRecordedWorkspaceMeetingWithRegisteredBrokenTranscriptNeverOffersGenerate() throws {
        for failure in RegisteredTranscriptFailure.allCases {
            let workspaceURL = FileManager.default.temporaryDirectory
                .appendingPathComponent(
                    "MeetingAssistantNative-RegisteredTranscript-\(failure.rawValue)-\(UUID().uuidString)",
                    isDirectory: true
                )
            defer { try? FileManager.default.removeItem(at: workspaceURL) }
            let sessionID = "session-app-ui-recorded-transcript-\(failure.rawValue)"
            try materializeRecordedTranscriptRepairWorkspace(
                workspaceURL: workspaceURL,
                sessionID: sessionID,
                failure: failure
            )
            let app = launchApp(
                fixture: "transcript-action-delete-failure",
                workspaceURL: workspaceURL
            )

            let row = element(ID.meetingRow(sessionID), in: app)
            XCTAssertTrue(
                row.label.contains("Checking transcript")
                    || row.label.contains("Transcript needs repair"),
                "Expected \(failure.rawValue) to begin in a safe checking or repair state. Actual label: \(row.label)"
            )
            XCTAssertFalse(
                row.label.contains("Transcript ready"),
                "Expected \(failure.rawValue) never to be exposed as a ready transcript. Actual label: \(row.label)"
            )
            XCTAssertFalse(
                row.label.contains("Ready to transcribe"),
                "Expected \(failure.rawValue) never to expose unsafe regeneration. Actual label: \(row.label)"
            )
            let repairPredicate = NSPredicate(
                format: "exists == true AND label CONTAINS %@",
                "Transcript needs repair"
            )
            let repairExpectation = XCTNSPredicateExpectation(predicate: repairPredicate, object: row)
            XCTAssertEqual(
                XCTWaiter.wait(for: [repairExpectation], timeout: 8),
                .completed,
                "Expected \(failure.rawValue) to be presented as a transcript repair state. Actual label: \(row.label)"
            )
            XCTAssertFalse(row.label.contains("Ready to transcribe"))
            tapButton(ID.meetingRow(sessionID), in: app)

            assertElement(ID.detailHeading, in: app, contains: "Recorded transcript repair")
            assertElement(ID.transcriptLoadError, in: app, contains: "will not replace a registered transcript")
            assertOnlyPrimaryTaskActions([], in: app)
            assertDoesNotExist(ID.generateTranscript, in: app)
            assertExists(ID.reloadTranscript, in: app)
            assertExists(ID.deleteMeeting, in: app)

            app.typeKey("p", modifierFlags: [.command, .option])
            assertElement(ID.transcriptLoadError, in: app, contains: "will not replace a registered transcript")
            assertOnlyPrimaryTaskActions([], in: app)
            assertDoesNotExist(ID.generateTranscript, in: app)

            tapButton(ID.deleteMeeting, in: app)
            assertExists(ID.deletePrompt, in: app)
            tapButton(ID.confirmDelete, in: app)

            assertElement(ID.transcriptLoadError, in: app, contains: "will not replace a registered transcript")
            assertOnlyPrimaryTaskActions([], in: app)
            assertDoesNotExist(ID.generateTranscript, in: app)
            assertExists(ID.reloadTranscript, in: app)
            assertExists(ID.deleteMeeting, in: app)
        }
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

    private func materializeRecordedTranscriptRepairWorkspace(
        workspaceURL: URL,
        sessionID: String,
        failure: RegisteredTranscriptFailure
    ) throws {
        let sessionRoot = workspaceURL
            .appendingPathComponent("sessions", isDirectory: true)
            .appendingPathComponent(sessionID, isDirectory: true)
        let artifactsRoot = sessionRoot.appendingPathComponent("artifacts", isDirectory: true)
        try FileManager.default.createDirectory(
            at: artifactsRoot,
            withIntermediateDirectories: true
        )

        let audioData = Data("registered transcript repair audio".utf8)
        try audioData.write(
            to: artifactsRoot.appendingPathComponent("mixed_audio.wav"),
            options: .atomic
        )
        let audioChecksum = sha256(audioData)

        let expectedTranscriptData = Data("expected registered transcript".utf8)
        let transcriptData: Data?
        let transcriptChecksum: String
        switch failure {
        case .missing:
            transcriptData = nil
            transcriptChecksum = sha256(expectedTranscriptData)
        case .checksumDrift:
            transcriptData = Data("changed registered transcript".utf8)
            transcriptChecksum = sha256(expectedTranscriptData)
        case .corruptJSON:
            let corruptData = Data("{not-valid-json".utf8)
            transcriptData = corruptData
            transcriptChecksum = sha256(corruptData)
        }
        if let transcriptData {
            try transcriptData.write(
                to: artifactsRoot.appendingPathComponent("transcript.json"),
                options: .atomic
            )
        }

        let sessionData = try JSONSerialization.data(
            withJSONObject: [
                "id": sessionID,
                "source_type": "native_recording",
                "status": "recorded",
                "title": "Recorded transcript repair",
                "started_at": "2026-07-13T10:00:00Z",
                "ended_at": "2026-07-13T10:30:00Z",
                "created_at": "2026-07-13T10:00:00Z",
                "updated_at": "2026-07-13T10:31:00Z",
                "workspace_dir": sessionRoot.path,
                "artifacts": [
                    [
                        "id": "artifact-repair-audio",
                        "session_id": sessionID,
                        "artifact_type": "mixed_audio",
                        "path": "artifacts/mixed_audio.wav",
                        "format": "wav",
                        "capture_status": "available",
                        "checksum": audioChecksum,
                        "created_at": "2026-07-13T10:30:00Z",
                    ],
                    [
                        "id": "artifact-repair-transcript",
                        "session_id": sessionID,
                        "artifact_type": "transcript_text",
                        "path": "artifacts/transcript.json",
                        "format": "json",
                        "capture_status": "available",
                        "checksum": transcriptChecksum,
                        "created_at": "2026-07-13T10:31:00Z",
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

    private func sha256(_ data: Data) -> String {
        "sha256:" + SHA256.hash(data: data)
            .map { String(format: "%02x", $0) }
            .joined()
    }

    private func materializeHistoricalMeetingWorkspace(
        workspaceURL: URL,
        sessionID: String,
        status: String
    ) throws {
        let sessionRoot = workspaceURL
            .appendingPathComponent("sessions", isDirectory: true)
            .appendingPathComponent(sessionID, isDirectory: true)
        let artifactsRoot = sessionRoot.appendingPathComponent("artifacts", isDirectory: true)
        try FileManager.default.createDirectory(
            at: artifactsRoot,
            withIntermediateDirectories: true
        )
        let audioData = Data("interrupted processing audio fixture".utf8)
        let audioURL = artifactsRoot.appendingPathComponent("meeting-audio.wav", isDirectory: false)
        try audioData.write(to: audioURL, options: .atomic)
        let audioChecksum = "sha256:" + SHA256.hash(data: audioData)
            .map { String(format: "%02x", $0) }
            .joined()
        let sessionData = try JSONSerialization.data(
            withJSONObject: [
                "id": sessionID,
                "title": "Interrupted transcript fixture",
                "status": status,
                "started_at": "2026-07-13T10:00:00Z",
                "updated_at": "2026-07-13T10:05:00Z",
                "artifacts": [
                    [
                        "id": "artifact-interrupted-audio",
                        "session_id": sessionID,
                        "artifact_type": "mixed_audio",
                        "path": "artifacts/meeting-audio.wav",
                        "capture_status": "available",
                        "checksum": audioChecksum,
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

    private func materializeFallbackAudioWorkspace(
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
        let systemData = Data("fallback system audio".utf8)
        let microphoneData = Data("fallback microphone audio".utf8)
        try systemData.write(
            to: artifactsRoot.appendingPathComponent("system-audio.wav", isDirectory: false),
            options: .atomic
        )
        try microphoneData.write(
            to: artifactsRoot.appendingPathComponent("microphone-audio.wav", isDirectory: false),
            options: .atomic
        )
        let sessionData = try JSONSerialization.data(
            withJSONObject: [
                "id": sessionID,
                "title": "Fallback audio choice",
                "status": "recorded",
                "started_at": "2026-07-13T10:00:00Z",
                "updated_at": "2026-07-13T10:05:00Z",
                "artifacts": [
                    [
                        "id": "artifact-fallback-system",
                        "session_id": sessionID,
                        "artifact_type": "system_audio",
                        "path": "artifacts/system-audio.wav",
                        "capture_status": "available",
                        "checksum": sha256(systemData),
                    ],
                    [
                        "id": "artifact-fallback-microphone",
                        "session_id": sessionID,
                        "artifact_type": "microphone_audio",
                        "path": "artifacts/microphone-audio.wav",
                        "capture_status": "available",
                        "checksum": sha256(microphoneData),
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

    private func launchApp(
        fixture: String? = nil,
        workspaceURL: URL? = nil,
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
        processingFixture?.applyLaunchEnvironment(to: app)
        app.terminate()
        _ = app.wait(for: .notRunning, timeout: 5)
        app.launch()
        app.activate()
        XCTAssertTrue(app.wait(for: .runningForeground, timeout: 10), "Expected app bundle to run foreground.")
        let window = app.windows.firstMatch
        XCTAssertTrue(window.waitForExistence(timeout: 5), "Expected app bundle window to exist.")
        XCTAssertFalse(window.frame.isEmpty, "Expected app bundle window to have a visible frame.")
        window.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.02)).click()
        app.activate()
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

    private func attachScreenshot(_ name: String, of app: XCUIApplication) {
        let window = app.windows.firstMatch
        XCTAssertTrue(window.waitForExistence(timeout: 5), "Expected the target window before capturing \(name).")
        let attachment = XCTAttachment(screenshot: window.screenshot())
        attachment.name = name
        attachment.lifetime = .keepAlways
        add(attachment)
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
        let existingMatches = matches.allElementsBoundByIndex.filter(\.exists)
        XCTAssertEqual(existingMatches.count, 1, "Expected exactly one button with identifier \(identifier).")
        return existingMatches.first { $0.isHittable } ?? element
    }

    private func tapButton(_ identifier: String, in app: XCUIApplication) {
        app.activate()
        XCTAssertTrue(app.wait(for: .runningForeground, timeout: 5), "Expected app to be foreground before tapping \(identifier).")
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
        app.activate()
        let field = app.descendants(matching: .textField).matching(identifier: identifier).firstMatch
        XCTAssertTrue(field.waitForExistence(timeout: 5), "Expected text field \(identifier) to exist.")
        field.click()
        field.typeKey("a", modifierFlags: .command)
        let words = text.split(separator: " ", omittingEmptySubsequences: false)
        for (index, word) in words.enumerated() {
            if index > 0 {
                field.typeKey(" ", modifierFlags: [])
            }
            if !word.isEmpty {
                field.typeText(String(word))
            }
        }
        let expectation = XCTNSPredicateExpectation(
            predicate: NSPredicate(format: "value == %@", text),
            object: field
        )
        XCTAssertEqual(XCTWaiter.wait(for: [expectation], timeout: 3), .completed)
    }

    private func setToggle(_ identifier: String, to isOn: Bool, in app: XCUIApplication) {
        app.activate()
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
        XCTAssertTrue(element.waitForExistence(timeout: 8), "Expected element \(identifier) to exist.")
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
            format: "exists == true AND (label CONTAINS %@ OR value CONTAINS %@)",
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
        let match = app.staticTexts.matching(predicate).firstMatch
        XCTAssertTrue(
            match.waitForExistence(timeout: 8),
            "Expected visible text containing \(expectedText).",
            file: file,
            line: line
        )
        XCTAssertFalse(match.frame.isEmpty, "Expected \(expectedText) to have a visible frame.", file: file, line: line)
        XCTAssertTrue(
            app.windows.firstMatch.frame.intersects(match.frame),
            "Expected \(expectedText) to be visible in the app window.",
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
                XCTAssertEqual(
                    app.descendants(matching: .button)
                        .matching(identifier: identifier)
                        .allElementsBoundByIndex
                        .filter(\.exists)
                        .count,
                    1,
                    "Expected exactly one current-task action \(identifier).",
                    file: file,
                    line: line
                )
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
