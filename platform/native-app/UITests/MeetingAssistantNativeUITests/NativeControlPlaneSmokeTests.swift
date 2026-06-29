import AppKit
import SwiftUI
import XCTest
@testable import MeetingAssistantNative

@MainActor
final class NativeControlPlaneSmokeTests: XCTestCase {
    func testPermissionDependencyBlockedStateIsHostedVisibleAndLocated() throws {
        let state = blockedReadinessState()
        let viewModel = PermissionDependencyStatusViewModel(
            runner: UnusedDependencyCheckRunner(),
            initialState: state
        )
        let host = HostedSwiftUIView(PermissionDependencyStatusView(viewModel: viewModel))

        host.assertHosted()
        XCTAssertEqual(viewModel.state.phase, .blocked)
        XCTAssertFalse(viewModel.state.canStartRecording)
        XCTAssertFalse(viewModel.state.canRunProcessing)
        XCTAssertEqual(
            viewModel.state.summary,
            "Recording and processing are blocked by missing permissions and dependencies."
        )
        XCTAssertEqual(viewModel.state.missingRequiredCheckIDs, ["media_tool.ffmpeg"])

        let screenPermission = try XCTUnwrap(
            viewModel.state.permissions.first { $0.id == "permission.screen_recording" }
        )
        XCTAssertEqual(screenPermission.title, "Screen Recording")
        XCTAssertEqual(screenPermission.state, .denied)
        XCTAssertEqual(
            screenPermission.message,
            "Screen Recording permission is denied. Open System Settings to grant access."
        )

        let ffmpeg = try XCTUnwrap(
            viewModel.state.dependencies.first { $0.id == "media_tool.ffmpeg" }
        )
        XCTAssertEqual(ffmpeg.title, "Media Tool")
        XCTAssertEqual(ffmpeg.status, "missing")
        XCTAssertFalse(ffmpeg.isPassing)
        XCTAssertEqual(ffmpeg.message, "FFmpeg executable was not found.")

        assertPermissionDependencyLocators()
        SwiftUIViewSourceContract.assertPermissionDependencyViewUsesAccessibleStates()
    }

    func testRecordingReadinessBlockedIsHostedAndDoesNotStart() async {
        let client = FakeRecordingCommandClient()
        let viewModel = RecordingControlViewModel(
            commandClient: client,
            readinessState: blockedReadinessState()
        )
        let host = HostedSwiftUIView(RecordingControlView(viewModel: viewModel))

        host.assertHosted()
        XCTAssertEqual(viewModel.state.phase, .idle)
        XCTAssertEqual(viewModel.state.statusText, "Run readiness checks before recording.")
        XCTAssertEqual(viewModel.canStart, false)
        XCTAssertEqual(viewModel.canStop, false)
        XCTAssertEqual(
            hostedReadinessStatusText(for: viewModel.state.phase),
            "Recording readiness is pending."
        )
        assertRecordingLocators()
        SwiftUIViewSourceContract.assertRecordingViewUsesAccessibleStates()

        await viewModel.start()

        let startRequests = await client.startRequests
        XCTAssertTrue(startRequests.isEmpty)
        XCTAssertEqual(viewModel.state.phase, .idle)
    }

    func testFakeRecordingStartRecordingAndStopSavedSummaryAreHosted() async {
        let client = FakeRecordingCommandClient(sessionID: "session-ui-smoke")
        let viewModel = RecordingControlViewModel(
            commandClient: client,
            readinessState: readyReadinessState()
        )
        let host = HostedSwiftUIView(RecordingControlView(viewModel: viewModel))

        host.assertHosted()
        XCTAssertEqual(viewModel.state.phase, .ready)
        XCTAssertEqual(viewModel.state.statusText, "Ready to start recording.")

        await viewModel.start()
        host.flush()

        XCTAssertEqual(viewModel.state.phase, .recording)
        XCTAssertEqual(viewModel.state.sessionID, "session-ui-smoke")
        XCTAssertEqual(viewModel.state.statusText, "Recording in progress.")
        XCTAssertFalse(viewModel.canStart)
        XCTAssertTrue(viewModel.canStop)
        XCTAssertEqual(
            hostedReadinessStatusText(for: viewModel.state.phase),
            "Recording command is active."
        )
        SwiftUIViewSourceContract.assertRecordingViewUsesAccessibleStates()

        await viewModel.stop()
        host.flush()

        XCTAssertEqual(viewModel.state.phase, .recorded)
        XCTAssertEqual(viewModel.state.sessionID, "session-ui-smoke")
        XCTAssertEqual(viewModel.state.statusText, "Recording saved.")
        XCTAssertEqual(viewModel.state.savedSummary, "Saved 2 recording artifacts.")
        XCTAssertEqual(viewModel.state.artifacts.map(\.artifactType), ["screen_video", "mixed_audio"])
        XCTAssertEqual(
            hostedReadinessStatusText(for: viewModel.state.phase),
            "Recording command is active."
        )
        SwiftUIViewSourceContract.assertRecordingViewUsesAccessibleStates()

        let startRequests = await client.startRequests
        let stopRequests = await client.stopRequests
        XCTAssertEqual(startRequests.count, 1)
        XCTAssertEqual(stopRequests, [StopRecordingRequest(sessionID: "session-ui-smoke")])
    }

    func testStartFailureIsHostedWithStableFailureState() async {
        let client = FakeRecordingCommandClient(
            script: .startFailure(
                code: "permission_denied",
                message: "Screen Recording permission is missing."
            )
        )
        let viewModel = RecordingControlViewModel(
            commandClient: client,
            readinessState: readyReadinessState()
        )
        let host = HostedSwiftUIView(RecordingControlView(viewModel: viewModel))

        await viewModel.start()
        host.flush()

        XCTAssertEqual(viewModel.state.phase, .failed)
        XCTAssertEqual(viewModel.state.statusText, "Recording failed.")
        XCTAssertEqual(viewModel.state.sessionID, nil)
        XCTAssertEqual(viewModel.state.errorCode, .permissionDenied)
        XCTAssertEqual(viewModel.state.errorMessage, "Screen Recording permission is missing.")
        XCTAssertEqual(
            hostedReadinessStatusText(for: viewModel.state.phase),
            "Recording command failed."
        )
        assertRecordingLocators()
        SwiftUIViewSourceContract.assertRecordingViewUsesAccessibleStates()
    }

    func testStopFailureIsHostedWithStableFailureState() async {
        let client = FakeRecordingCommandClient(
            script: .stopFailure(
                code: "capture_failed",
                message: "Recording could not be saved."
            ),
            sessionID: "session-stop-failure"
        )
        let viewModel = RecordingControlViewModel(
            commandClient: client,
            readinessState: readyReadinessState()
        )
        let host = HostedSwiftUIView(RecordingControlView(viewModel: viewModel))

        await viewModel.start()
        await viewModel.stop()
        host.flush()

        XCTAssertEqual(viewModel.state.phase, .failed)
        XCTAssertEqual(viewModel.state.statusText, "Recording failed.")
        XCTAssertEqual(viewModel.state.sessionID, "session-stop-failure")
        XCTAssertEqual(viewModel.state.errorCode, .captureFailed)
        XCTAssertEqual(viewModel.state.errorMessage, "Recording could not be saved.")
        XCTAssertEqual(
            hostedReadinessStatusText(for: viewModel.state.phase),
            "Recording command failed."
        )
        assertRecordingLocators()
        SwiftUIViewSourceContract.assertRecordingViewUsesAccessibleStates()
    }

    func testStableAccessibilityIdentifierContract() {
        assertPermissionDependencyLocators()
        assertRecordingLocators()
    }

    private func assertPermissionDependencyLocators(
        file: StaticString = #filePath,
        line: UInt = #line
    ) {
        XCTAssertEqual(
            PermissionDependencyAccessibilityID.heading,
            "ma.permissionDependency.heading",
            file: file,
            line: line
        )
        XCTAssertEqual(
            PermissionDependencyAccessibilityID.summary,
            "ma.permissionDependency.summary",
            file: file,
            line: line
        )
        XCTAssertEqual(
            PermissionDependencyAccessibilityID.checkButton,
            "ma.permissionDependency.checkButton",
            file: file,
            line: line
        )
        XCTAssertEqual(
            PermissionDependencyAccessibilityID.permissionsSection,
            "ma.permissionDependency.permissions",
            file: file,
            line: line
        )
        XCTAssertEqual(
            PermissionDependencyAccessibilityID.dependenciesSection,
            "ma.permissionDependency.dependencies",
            file: file,
            line: line
        )
    }

    private func assertRecordingLocators(
        file: StaticString = #filePath,
        line: UInt = #line
    ) {
        XCTAssertEqual(
            RecordingAccessibilityID.heading,
            "ma.recording.heading",
            file: file,
            line: line
        )
        XCTAssertEqual(
            RecordingAccessibilityID.readinessStatus,
            "ma.recording.readinessStatus",
            file: file,
            line: line
        )
        XCTAssertEqual(
            RecordingAccessibilityID.status,
            "ma.recording.status",
            file: file,
            line: line
        )
        XCTAssertEqual(
            RecordingAccessibilityID.startButton,
            "ma.recording.startButton",
            file: file,
            line: line
        )
        XCTAssertEqual(
            RecordingAccessibilityID.stopButton,
            "ma.recording.stopButton",
            file: file,
            line: line
        )
        XCTAssertEqual(
            RecordingAccessibilityID.error,
            "ma.recording.error",
            file: file,
            line: line
        )
        XCTAssertEqual(
            RecordingAccessibilityID.savedSummary,
            "ma.recording.savedSummary",
            file: file,
            line: line
        )
    }
}

private struct UnusedDependencyCheckRunner: DependencyCheckRunning {
    func checkDependencies(workspaceURL: URL?) async throws -> DependencyCheckResponse {
        throw XCTSkip("The hosted UI smoke uses an injected initial state.")
    }
}

@MainActor
private final class HostedSwiftUIView<Content: View> {
    private let controller: NSHostingController<Content>
    private let window: NSWindow

    init(_ rootView: Content) {
        controller = NSHostingController(rootView: rootView)
        window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 900, height: 700),
            styleMask: [.titled],
            backing: .buffered,
            defer: false
        )
        window.contentViewController = controller
        window.makeKeyAndOrderFront(nil)
        controller.view.setFrameSize(NSSize(width: 900, height: 700))
        flush()
    }

    func flush() {
        controller.view.needsLayout = true
        controller.view.layoutSubtreeIfNeeded()
        controller.view.displayIfNeeded()
        window.displayIfNeeded()
        RunLoop.main.run(until: Date(timeIntervalSinceNow: 0.02))
    }

    func assertHosted(
        file: StaticString = #filePath,
        line: UInt = #line
    ) {
        flush()
        XCTAssertFalse(controller.view.frame.isEmpty, file: file, line: line)
    }
}

private enum SwiftUIViewSourceContract {
    static func assertPermissionDependencyViewUsesAccessibleStates(
        file: StaticString = #filePath,
        line: UInt = #line
    ) {
        let source = readSource("PermissionDependencyStatusView.swift", file: file, line: line)
        assertSource(
            source,
            contains: [
                "Text(\"Meeting Assistant Readiness\")",
                ".accessibilityIdentifier(PermissionDependencyAccessibilityID.heading)",
                ".accessibilityIdentifier(PermissionDependencyAccessibilityID.summary)",
                ".accessibilityIdentifier(PermissionDependencyAccessibilityID.checkButton)",
                "identifier: PermissionDependencyAccessibilityID.permissionsSection",
                "identifier: PermissionDependencyAccessibilityID.dependenciesSection",
                ".accessibilityIdentifier(identifier)",
                "\"ma.permission.\\(item.id).status\"",
                "\"ma.dependency.\\(item.id).status\"",
            ],
            file: file,
            line: line
        )
    }

    static func assertRecordingViewUsesAccessibleStates(
        file: StaticString = #filePath,
        line: UInt = #line
    ) {
        let source = readSource("RecordingControlView.swift", file: file, line: line)
        assertSource(
            source,
            contains: [
                "Text(\"Recording\")",
                "Button(\"Start Recording\")",
                "Button(\"Stop Recording\")",
                "\"Recording readiness is pending.\"",
                "\"Recording command is active.\"",
                "\"Recording command failed.\"",
                ".accessibilityIdentifier(RecordingControlAccessibilityID.heading)",
                ".accessibilityIdentifier(RecordingControlAccessibilityID.readinessStatus)",
                ".accessibilityIdentifier(RecordingControlAccessibilityID.status)",
                ".accessibilityIdentifier(RecordingControlAccessibilityID.startButton)",
                ".accessibilityIdentifier(RecordingControlAccessibilityID.stopButton)",
                ".accessibilityIdentifier(RecordingControlAccessibilityID.sessionID)",
                ".accessibilityIdentifier(RecordingControlAccessibilityID.success)",
                ".accessibilityIdentifier(RecordingControlAccessibilityID.failure)",
            ],
            file: file,
            line: line
        )
    }

    private static func readSource(
        _ filename: String,
        file: StaticString,
        line: UInt
    ) -> String {
        let path = "Sources/MeetingAssistantNative/\(filename)"
        do {
            return try String(contentsOfFile: path, encoding: .utf8)
        } catch {
            XCTFail("Could not read \(path): \(error)", file: file, line: line)
            return ""
        }
    }

    private static func assertSource(
        _ source: String,
        contains snippets: [String],
        file: StaticString,
        line: UInt
    ) {
        for snippet in snippets {
            XCTAssertTrue(
                source.contains(snippet),
                "Missing SwiftUI source snippet: \(snippet)",
                file: file,
                line: line
            )
        }
    }
}

private func hostedReadinessStatusText(for phase: RecordingControlPhase) -> String {
    switch phase {
    case .idle:
        return "Recording readiness is pending."
    case .ready:
        return "Recording readiness is ready."
    case .starting, .recording, .stopping, .recorded:
        return "Recording command is active."
    case .failed:
        return "Recording command failed."
    }
}

private func readyReadinessState() -> PermissionDependencyStatusState {
    PermissionDependencyStatusState.from(
        DependencyCheckResponse(
            ok: true,
            requestID: "local-ui-ready",
            checks: [
                dependencyCheck("permission.screen_recording", status: "granted", required: false, ok: true),
                dependencyCheck("permission.microphone", status: "granted", required: false, ok: true),
                dependencyCheck("media_tool.ffmpeg", status: "available", required: true, ok: true),
                dependencyCheck("dependency_downloads.automatic", status: "not_attempted", required: true, ok: true),
            ]
        )
    )
}

private func blockedReadinessState() -> PermissionDependencyStatusState {
    PermissionDependencyStatusState.from(
        DependencyCheckResponse(
            ok: false,
            requestID: "local-ui-blocked",
            code: "dependency_missing",
            message: "One or more required dependencies are missing or unsupported.",
            checks: [
                dependencyCheck(
                    "permission.screen_recording",
                    status: "denied",
                    required: false,
                    ok: false,
                    message: "Screen Recording permission is denied. Open System Settings to grant access."
                ),
                dependencyCheck(
                    "permission.microphone",
                    status: "granted",
                    required: false,
                    ok: true,
                    message: "Microphone permission is granted."
                ),
                dependencyCheck(
                    "media_tool.ffmpeg",
                    status: "missing",
                    required: true,
                    ok: false,
                    message: "FFmpeg executable was not found."
                ),
            ]
        )
    )
}

private func dependencyCheck(
    _ id: String,
    status: String,
    required: Bool,
    ok: Bool,
    message: String? = nil
) -> DependencyCheckItem {
    DependencyCheckItem(
        id: id,
        status: status,
        required: required,
        ok: ok,
        message: message ?? "\(id) is \(status)."
    )
}
