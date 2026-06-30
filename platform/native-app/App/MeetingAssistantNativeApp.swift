import Foundation
import AppKit
import SwiftUI

@main
struct MeetingAssistantNativeApp: App {
    private let configuration = NativeControlPlaneFixtureConfiguration.fromLaunchContext()
    private let windowPlacement = NativeAppWindowPlacement.fromLaunchContext()

    var body: some Scene {
        WindowGroup("Meeting Assistant Native") {
            NativeControlPlaneRootView(configuration: configuration)
                .background(WindowPlacementView(placement: windowPlacement))
        }
        .defaultSize(width: 900, height: 760)
    }
}

private struct NativeControlPlaneRootView: View {
    @StateObject private var permissionViewModel: PermissionDependencyStatusViewModel
    @StateObject private var recordingViewModel: RecordingControlViewModel
    private let transcriptViewModel: TranscriptReviewViewModel

    init(configuration: NativeControlPlaneFixtureConfiguration) {
        let readinessState = configuration.readinessState
        _permissionViewModel = StateObject(
            wrappedValue: PermissionDependencyStatusViewModel(
                runner: StaticDependencyCheckRunner(response: configuration.dependencyResponse),
                initialState: readinessState
            )
        )
        _recordingViewModel = StateObject(
            wrappedValue: RecordingControlViewModel(
                commandClient: FakeRecordingCommandClient(
                    script: configuration.recordingScript,
                    sessionID: configuration.sessionID
                ),
                readinessState: readinessState,
                title: "UI smoke recording",
                captureTarget: .screen
            )
        )
        transcriptViewModel = TranscriptReviewViewModel(input: configuration.transcriptInput)
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                PermissionDependencyStatusView(viewModel: permissionViewModel)
                    .frame(minHeight: 360, maxHeight: 420)

                Divider()

                RecordingControlView(viewModel: recordingViewModel)

                Divider()

                TranscriptReviewView(viewModel: transcriptViewModel)
            }
            .padding(20)
            .frame(minWidth: 760, minHeight: 640, alignment: .topLeading)
        }
    }
}

private struct StaticDependencyCheckRunner: DependencyCheckRunning {
    let response: DependencyCheckResponse

    func checkDependencies(workspaceURL: URL?) async throws -> DependencyCheckResponse {
        response
    }
}

private struct WindowPlacementView: NSViewRepresentable {
    let placement: NativeAppWindowPlacement?

    func makeCoordinator() -> Coordinator {
        Coordinator()
    }

    func makeNSView(context: Context) -> NSView {
        let view = NSView(frame: .zero)
        placeWindow(for: view, context: context)
        return view
    }

    func updateNSView(_ view: NSView, context: Context) {
        placeWindow(for: view, context: context)
    }

    private func placeWindow(for view: NSView, context: Context) {
        guard let placement, !context.coordinator.didPlaceWindow else {
            return
        }
        let coordinator = context.coordinator
        DispatchQueue.main.async { [weak view, weak coordinator] in
            guard let coordinator, !coordinator.didPlaceWindow, let window = view?.window else {
                return
            }
            placement.apply(to: window)
            coordinator.didPlaceWindow = true
        }
    }

    final class Coordinator {
        var didPlaceWindow = false
    }
}

private struct NativeAppWindowPlacement {
    let displaySelector: String

    static func fromLaunchContext(
        environment: [String: String] = ProcessInfo.processInfo.environment
    ) -> NativeAppWindowPlacement? {
        guard let selector = environment["MA_NATIVE_APP_TEST_DISPLAY"]?.trimmingCharacters(in: .whitespacesAndNewlines),
              !selector.isEmpty else {
            return nil
        }

        return NativeAppWindowPlacement(displaySelector: selector)
    }

    func apply(to window: NSWindow?) {
        guard let window, let targetScreen = Self.screen(matching: displaySelector) else {
            return
        }

        let visibleFrame = targetScreen.visibleFrame
        let currentFrame = window.frame
        let targetSize = NSSize(
            width: min(currentFrame.width, visibleFrame.width),
            height: min(currentFrame.height, visibleFrame.height)
        )
        let targetFrame = NSRect(
            x: visibleFrame.midX - targetSize.width / 2,
            y: visibleFrame.midY - targetSize.height / 2,
            width: targetSize.width,
            height: targetSize.height
        )

        if !targetFrame.equalTo(currentFrame) {
            window.setFrame(targetFrame, display: true)
        }
        window.makeKeyAndOrderFront(nil)
    }

    private static func screen(matching selector: String) -> NSScreen? {
        let normalizedSelector = normalize(selector)
        if ["builtin", "built-in", "internal", "color-lcd", "colorlcd"].contains(normalizedSelector) {
            return NSScreen.screens.first(where: isBuiltIn)
        }

        return NSScreen.screens.first {
            normalize($0.localizedName).contains(normalizedSelector)
        }
    }

    private static func isBuiltIn(_ screen: NSScreen) -> Bool {
        guard let screenNumber = screen.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? NSNumber else {
            return false
        }
        return CGDisplayIsBuiltin(CGDirectDisplayID(screenNumber.uint32Value)) != 0
    }

    private static func normalize(_ value: String) -> String {
        value
            .lowercased()
            .replacingOccurrences(of: " ", with: "")
            .replacingOccurrences(of: "_", with: "-")
    }
}

private struct NativeControlPlaneFixtureConfiguration {
    let dependencyResponse: DependencyCheckResponse
    let recordingScript: FakeRecordingCommandClient.Script
    let sessionID: String
    let transcriptInput: TranscriptReviewInput

    var readinessState: PermissionDependencyStatusState {
        PermissionDependencyStatusState.from(dependencyResponse)
    }

    static func fromLaunchContext(
        environment: [String: String] = ProcessInfo.processInfo.environment,
        arguments: [String] = CommandLine.arguments
    ) -> NativeControlPlaneFixtureConfiguration {
        if let workspacePath = environment["MA_NATIVE_TRANSCRIPT_WORKSPACE"]
            ?? argumentValue(named: "--ma-native-transcript-workspace", in: arguments),
            let transcriptSessionID = environment["MA_NATIVE_TRANSCRIPT_SESSION_ID"]
            ?? argumentValue(named: "--ma-native-transcript-session-id", in: arguments),
            !workspacePath.isEmpty,
            !transcriptSessionID.isEmpty {
            let transcriptInput = (try? TranscriptReviewWorkspaceLoader.load(
                workspaceURL: URL(fileURLWithPath: workspacePath, isDirectory: true),
                sessionID: transcriptSessionID
            )) ?? TranscriptReviewInput(sessionTitle: "Workspace transcript fixture", transcript: nil)

            return NativeControlPlaneFixtureConfiguration(
                dependencyResponse: .readyFixture,
                recordingScript: .success,
                sessionID: transcriptSessionID,
                transcriptInput: transcriptInput
            )
        }

        let fixture = environment["MA_NATIVE_APP_SMOKE_FIXTURE"]
            ?? argumentValue(named: "--ma-native-fixture", in: arguments)
            ?? "blocked"

        switch fixture {
        case "ready":
            return NativeControlPlaneFixtureConfiguration(
                dependencyResponse: .readyFixture,
                recordingScript: .success,
                sessionID: "session-app-ui-smoke",
                transcriptInput: .missingFixture
            )
        case "start-failure":
            return NativeControlPlaneFixtureConfiguration(
                dependencyResponse: .readyFixture,
                recordingScript: .startFailure(
                    code: "permission_denied",
                    message: "Screen Recording permission is missing."
                ),
                sessionID: "session-app-ui-start-failure",
                transcriptInput: .missingFixture
            )
        case "stop-failure":
            return NativeControlPlaneFixtureConfiguration(
                dependencyResponse: .readyFixture,
                recordingScript: .stopFailure(
                    code: "capture_failed",
                    message: "Recording could not be saved."
                ),
                sessionID: "session-app-ui-stop-failure",
                transcriptInput: .missingFixture
            )
        case "transcript-review":
            return NativeControlPlaneFixtureConfiguration(
                dependencyResponse: .readyFixture,
                recordingScript: .success,
                sessionID: "session-app-ui-transcript",
                transcriptInput: .reviewFixture
            )
        case "transcript-empty":
            return NativeControlPlaneFixtureConfiguration(
                dependencyResponse: .readyFixture,
                recordingScript: .success,
                sessionID: "session-app-ui-empty-transcript",
                transcriptInput: .emptyFixture
            )
        case "transcript-only":
            return NativeControlPlaneFixtureConfiguration(
                dependencyResponse: .readyFixture,
                recordingScript: .success,
                sessionID: "session-app-ui-transcript-only",
                transcriptInput: .transcriptOnlyFixture
            )
        default:
            return NativeControlPlaneFixtureConfiguration(
                dependencyResponse: .blockedFixture,
                recordingScript: .success,
                sessionID: "session-app-ui-blocked",
                transcriptInput: .missingFixture
            )
        }
    }

    private static func argumentValue(named name: String, in arguments: [String]) -> String? {
        let prefix = "\(name)="
        return arguments
            .first { $0.hasPrefix(prefix) }
            .map { String($0.dropFirst(prefix.count)) }
    }
}

private extension TranscriptReviewInput {
    static let missingFixture = TranscriptReviewInput(
        sessionTitle: "UI smoke transcript",
        transcript: nil
    )

    static let emptyFixture = TranscriptReviewInput(
        sessionTitle: "Empty transcript fixture",
        transcript: TranscriptReviewTranscript(
            id: "transcript-empty-fixture",
            sessionID: "session-app-ui-empty-transcript",
            sourceArtifactID: "artifact-normalized-audio",
            status: "succeeded",
            segments: []
        ),
        speakerLabelsDegradationReason: "speaker labeling skipped for empty transcript fixture"
    )

    static let transcriptOnlyFixture = TranscriptReviewInput(
        sessionTitle: "Transcript-only fixture",
        transcript: TranscriptReviewTranscript(
            id: "transcript-only-app-fixture",
            sessionID: "session-app-ui-transcript-only",
            sourceArtifactID: "artifact-normalized-audio",
            status: "succeeded",
            segments: [
                TranscriptReviewSegment(
                    segmentID: "seg-plain",
                    startMS: 2_000,
                    endMS: 4_000,
                    text: "Transcript remains available without speaker labels."
                ),
            ]
        ),
        speakerLabelsDegradationReason: "speaker labeling runtime unavailable; transcript-only review remains available"
    )

    static let reviewFixture = TranscriptReviewInput(
        sessionTitle: "Transcript Review Fixture",
        transcript: TranscriptReviewTranscript(
            id: "transcript-app-fixture",
            sessionID: "session-app-ui-transcript",
            sourceArtifactID: "artifact-normalized-audio",
            status: "succeeded",
            segments: [
                TranscriptReviewSegment(
                    segmentID: "seg-2",
                    startMS: 12_000,
                    endMS: 14_000,
                    text: "Second segment is ordered after the first.",
                    speakerLabel: "SPEAKER_02"
                ),
                TranscriptReviewSegment(
                    segmentID: "seg-1",
                    startMS: 0,
                    endMS: 5_000,
                    text: "First transcript segment for review.",
                    speakerLabel: "SPEAKER_01"
                ),
            ]
        ),
        speakerLabels: SpeakerLabelsReviewArtifact(
            sessionID: "session-app-ui-transcript",
            labels: [
                SpeakerLabelReviewEntry(
                    label: "SPEAKER_01",
                    sessionID: "session-app-ui-transcript",
                    isVerifiedIdentity: false
                ),
                SpeakerLabelReviewEntry(
                    label: "SPEAKER_02",
                    sessionID: "session-app-ui-transcript",
                    isVerifiedIdentity: false
                ),
            ],
            segmentMapping: [
                SpeakerLabelSegmentMapping(segmentID: "seg-1", label: "SPEAKER_01"),
                SpeakerLabelSegmentMapping(segmentID: "seg-2", label: "SPEAKER_02"),
            ]
        ),
        speakerLabelsDegradationReason: "speaker labeling runtime unavailable; transcript-only review remains available"
    )
}

private extension DependencyCheckResponse {
    static let blockedFixture = DependencyCheckResponse(
        ok: false,
        requestID: "local-app-blocked",
        code: "dependency_missing",
        message: "One or more required dependencies are missing or unsupported.",
        checks: [
            DependencyCheckItem(
                id: "permission.screen_recording",
                status: "denied",
                required: false,
                ok: false,
                message: "Screen Recording permission is denied. Open System Settings to grant access."
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

    static let readyFixture = DependencyCheckResponse(
        ok: true,
        requestID: "local-app-ready",
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
                message: "FFmpeg executable is available."
            ),
            DependencyCheckItem(
                id: "dependency_downloads.automatic",
                status: "not_attempted",
                required: true,
                ok: true,
                message: "No automatic dependency download was attempted."
            ),
        ]
    )
}
