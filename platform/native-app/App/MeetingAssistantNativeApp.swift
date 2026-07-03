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
    @StateObject private var processingViewModel: ProcessingStateViewModel
    @StateObject private var transcriptActionViewModel: TranscriptReviewActionsViewModel
    private let transcriptViewModel: TranscriptReviewViewModel

    init(configuration: NativeControlPlaneFixtureConfiguration) {
        let readinessState = configuration.readinessState
        let recordingWorkspaceURL = configuration.recordingWorkspaceURL()
        let recordingCommandClient = configuration.makeRecordingCommandClient()
        let processingCommandClient = configuration.makeProcessingCommandClient()
        let transcriptActionCommandClient = configuration.makeTranscriptActionCommandClient()
        _permissionViewModel = StateObject(
            wrappedValue: PermissionDependencyStatusViewModel(
                runner: StaticDependencyCheckRunner(response: configuration.dependencyResponse),
                initialState: readinessState
            )
        )
        _recordingViewModel = StateObject(
            wrappedValue: RecordingControlViewModel(
                commandClient: recordingCommandClient,
                readinessState: readinessState,
                title: "UI smoke recording",
                captureTarget: .screen,
                workspaceURL: recordingWorkspaceURL
            )
        )
        _processingViewModel = StateObject(
            wrappedValue: ProcessingStateViewModel(
                commandClient: processingCommandClient,
                readinessState: readinessState,
                defaultSessionID: configuration.sessionID
            )
        )
        transcriptViewModel = TranscriptReviewViewModel(input: configuration.transcriptInput)
        _transcriptActionViewModel = StateObject(
            wrappedValue: TranscriptReviewActionsViewModel(
                input: configuration.transcriptInput,
                commandClient: transcriptActionCommandClient,
                clipboard: TranscriptActionMemoryClipboard(),
                destinationSelector: TranscriptActionStaticDestinationSelector(
                    targetPath: configuration.exportDestinationPath
                ),
                workspaceDir: configuration.workspaceDir
            )
        )
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                PermissionDependencyStatusView(viewModel: permissionViewModel)
                    .frame(minHeight: 360, maxHeight: 420)

                Divider()

                RecordingControlView(viewModel: recordingViewModel)

                Divider()

                ProcessingStateView(viewModel: processingViewModel)

                Divider()

                TranscriptReviewView(viewModel: transcriptViewModel)

                if transcriptActionViewModel.state.isAvailable {
                    Divider()

                    TranscriptReviewActionsView(viewModel: transcriptActionViewModel)
                }
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
    private let retryLimit = 40
    private let retryDelay: TimeInterval = 0.05

    func makeCoordinator() -> Coordinator {
        Coordinator(retryLimit: retryLimit, retryDelay: retryDelay)
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
        guard let placement else {
            return
        }
        context.coordinator.placeWindow(placement: placement, view: view)
    }

    @MainActor
    final class Coordinator {
        private let retryLimit: Int
        private let retryDelay: TimeInterval
        private var didPlaceWindow = false
        private var scheduledRetry = false
        private var attempts = 0

        init(retryLimit: Int, retryDelay: TimeInterval) {
            self.retryLimit = retryLimit
            self.retryDelay = retryDelay
        }

        func placeWindow(placement: NativeAppWindowPlacement, view: NSView) {
            guard !didPlaceWindow, !scheduledRetry, attempts < retryLimit else {
                return
            }

            scheduledRetry = true
            DispatchQueue.main.async { [weak self, weak view] in
                self?.attemptPlacement(placement: placement, view: view)
            }
        }

        private func attemptPlacement(placement: NativeAppWindowPlacement, view: NSView?) {
            scheduledRetry = false
            guard !didPlaceWindow else {
                return
            }

            attempts += 1
            guard placement.apply(to: view?.window) else {
                retryIfNeeded(placement: placement, view: view)
                return
            }

            didPlaceWindow = true
        }

        private func retryIfNeeded(placement: NativeAppWindowPlacement, view: NSView?) {
            guard attempts < retryLimit else {
                return
            }

            scheduledRetry = true
            DispatchQueue.main.asyncAfter(deadline: .now() + retryDelay) { [weak self, weak view] in
                self?.attemptPlacement(placement: placement, view: view)
            }
        }
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

    @discardableResult
    @MainActor
    func apply(to window: NSWindow?) -> Bool {
        guard let window, let targetScreen = Self.screen(matching: displaySelector) else {
            return false
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
        return true
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
    let processingTranscriptScript: ProcessingCommandFakeClient.TranscriptScript
    let processingSpeakerLabelsScript: ProcessingCommandFakeClient.SpeakerLabelsScript
    let processingClientMode: NativeProcessingClientMode
    let sessionID: String
    let transcriptInput: TranscriptReviewInput
    let exportScript: TranscriptActionFakeCommandClient.ExportScript
    let deleteScript: TranscriptActionFakeCommandClient.DeleteScript
    let exportDestinationPath: String?
    let workspaceDir: String?

    init(
        dependencyResponse: DependencyCheckResponse,
        recordingScript: FakeRecordingCommandClient.Script,
        processingTranscriptScript: ProcessingCommandFakeClient.TranscriptScript,
        processingSpeakerLabelsScript: ProcessingCommandFakeClient.SpeakerLabelsScript,
        processingClientMode: NativeProcessingClientMode = .fake,
        sessionID: String,
        transcriptInput: TranscriptReviewInput,
        exportScript: TranscriptActionFakeCommandClient.ExportScript,
        deleteScript: TranscriptActionFakeCommandClient.DeleteScript,
        exportDestinationPath: String?,
        workspaceDir: String?
    ) {
        self.dependencyResponse = dependencyResponse
        self.recordingScript = recordingScript
        self.processingTranscriptScript = processingTranscriptScript
        self.processingSpeakerLabelsScript = processingSpeakerLabelsScript
        self.processingClientMode = processingClientMode
        self.sessionID = sessionID
        self.transcriptInput = transcriptInput
        self.exportScript = exportScript
        self.deleteScript = deleteScript
        self.exportDestinationPath = exportDestinationPath
        self.workspaceDir = workspaceDir
    }

    var readinessState: PermissionDependencyStatusState {
        PermissionDependencyStatusState.from(dependencyResponse)
    }

    func makeRecordingCommandClient(
        environment: [String: String] = ProcessInfo.processInfo.environment,
        arguments: [String] = CommandLine.arguments
    ) -> any RecordingCaptureControlling {
        let workspaceURL = recordingWorkspaceURL(environment: environment, arguments: arguments)
        switch NativeRecordingClientMode.fromLaunchEnvironment(environment, workspaceURL: workspaceURL) {
        case .fake:
            return FakeRecordingCommandClient(
                script: recordingScript,
                sessionID: sessionID
            )
        case .controlled:
            return NativeRecordingCommandClient(
                permissionChecker: StaticNativeCapturePermissionChecker(snapshot: .granted),
                captureAdapter: ControlledNativeCaptureAdapter(
                    stopBehavior: .success(artifacts: Self.controlledRecordingArtifacts)
                ),
                sessionIDProvider: { sessionID },
                timestampProvider: { "2026-07-01T00:00:00Z" },
                requestIDProvider: { command in "app-controlled-\(command.rawValue)" }
            )
        }
    }

    func recordingWorkspaceURL(
        environment: [String: String] = ProcessInfo.processInfo.environment,
        arguments: [String] = CommandLine.arguments
    ) -> URL? {
        Self.recordingWorkspaceURL(environment: environment, arguments: arguments)
    }

    func makeProcessingCommandClient(
        environment: [String: String] = ProcessInfo.processInfo.environment
    ) -> any ProcessingCommandClient {
        switch processingClientMode {
        case .fake:
            return ProcessingCommandFakeClient(
                transcriptScript: processingTranscriptScript,
                speakerLabelsScript: processingSpeakerLabelsScript
            )
        case .process:
            return ProcessingCommandProcessRunner(environment: environment)
        }
    }

    func makeTranscriptActionCommandClient(
        environment: [String: String] = ProcessInfo.processInfo.environment
    ) -> any TranscriptActionCommandClient {
        switch NativeTranscriptActionClientMode.fromLaunchEnvironment(environment) {
        case .fake:
            return TranscriptActionFakeCommandClient(
                exportScript: exportScript,
                deleteScript: deleteScript
            )
        case .process:
            return TranscriptActionProcessRunner(environment: environment)
        }
    }

    static func fromLaunchContext(
        environment: [String: String] = ProcessInfo.processInfo.environment,
        arguments: [String] = CommandLine.arguments
    ) -> NativeControlPlaneFixtureConfiguration {
        let processingClientMode = NativeProcessingClientMode.fromLaunchEnvironment(environment)
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
                processingTranscriptScript: .success(),
                processingSpeakerLabelsScript: .success(
                    labelStatus: "transcript_only",
                    degradationReason: "speaker labels degraded from workspace fixture"
                ),
                processingClientMode: processingClientMode,
                sessionID: transcriptSessionID,
                transcriptInput: transcriptInput,
                exportScript: .success(content: "Workspace transcript content copied from deterministic fixture."),
                deleteScript: .success(retainedExternalExports: ["/tmp/workspace-transcript.md"]),
                exportDestinationPath: "\(workspacePath)/exports/\(transcriptSessionID).md",
                workspaceDir: workspacePath
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
                processingTranscriptScript: .success(),
                processingSpeakerLabelsScript: .success(),
                processingClientMode: processingClientMode,
                sessionID: "session-app-ui-smoke",
                transcriptInput: .missingFixture,
                exportScript: .success(content: "Ready fixture transcript content."),
                deleteScript: .success(),
                exportDestinationPath: "/tmp/ready-fixture-transcript.md",
                workspaceDir: nil
            )
        case "start-failure":
            return NativeControlPlaneFixtureConfiguration(
                dependencyResponse: .readyFixture,
                recordingScript: .startFailure(
                    code: "permission_denied",
                    message: "Screen Recording permission is missing."
                ),
                processingTranscriptScript: .success(),
                processingSpeakerLabelsScript: .success(),
                processingClientMode: processingClientMode,
                sessionID: "session-app-ui-start-failure",
                transcriptInput: .missingFixture,
                exportScript: .success(content: "Start failure fixture transcript content."),
                deleteScript: .success(),
                exportDestinationPath: "/tmp/start-failure-transcript.md",
                workspaceDir: nil
            )
        case "stop-failure":
            return NativeControlPlaneFixtureConfiguration(
                dependencyResponse: .readyFixture,
                recordingScript: .stopFailure(
                    code: "capture_failed",
                    message: "Recording could not be saved."
                ),
                processingTranscriptScript: .success(),
                processingSpeakerLabelsScript: .success(),
                processingClientMode: processingClientMode,
                sessionID: "session-app-ui-stop-failure",
                transcriptInput: .missingFixture,
                exportScript: .success(content: "Stop failure fixture transcript content."),
                deleteScript: .success(),
                exportDestinationPath: "/tmp/stop-failure-transcript.md",
                workspaceDir: nil
            )
        case "transcript-review":
            return NativeControlPlaneFixtureConfiguration(
                dependencyResponse: .readyFixture,
                recordingScript: .success,
                processingTranscriptScript: .success(),
                processingSpeakerLabelsScript: .success(),
                processingClientMode: processingClientMode,
                sessionID: "session-app-ui-transcript",
                transcriptInput: .reviewFixture,
                exportScript: .success(content: "Transcript Review Fixture copy content."),
                deleteScript: .success(retainedExternalExports: ["/tmp/transcript-review.md"]),
                exportDestinationPath: "/tmp/transcript-review.md",
                workspaceDir: nil
            )
        case "transcript-empty":
            return NativeControlPlaneFixtureConfiguration(
                dependencyResponse: .readyFixture,
                recordingScript: .success,
                processingTranscriptScript: .success(),
                processingSpeakerLabelsScript: .success(),
                processingClientMode: processingClientMode,
                sessionID: "session-app-ui-empty-transcript",
                transcriptInput: .emptyFixture,
                exportScript: .success(content: "Empty transcript fixture copy content."),
                deleteScript: .success(),
                exportDestinationPath: "/tmp/transcript-empty.md",
                workspaceDir: nil
            )
        case "transcript-only":
            return NativeControlPlaneFixtureConfiguration(
                dependencyResponse: .readyFixture,
                recordingScript: .success,
                processingTranscriptScript: .success(),
                processingSpeakerLabelsScript: .success(
                    labelStatus: "transcript_only",
                    degradationReason: "speaker labeling runtime unavailable"
                ),
                processingClientMode: processingClientMode,
                sessionID: "session-app-ui-transcript-only",
                transcriptInput: .transcriptOnlyFixture,
                exportScript: .success(content: "Transcript-only fixture copy content."),
                deleteScript: .success(retainedExternalExports: ["/tmp/transcript-only.md"]),
                exportDestinationPath: "/tmp/transcript-only.md",
                workspaceDir: nil
            )
        case "transcript-action-copy-success":
            return NativeControlPlaneFixtureConfiguration(
                dependencyResponse: .readyFixture,
                recordingScript: .success,
                processingTranscriptScript: .success(),
                processingSpeakerLabelsScript: .success(),
                processingClientMode: processingClientMode,
                sessionID: "session-app-ui-transcript",
                transcriptInput: .reviewFixture,
                exportScript: .success(content: "Copy fixture transcript content."),
                deleteScript: .success(),
                exportDestinationPath: "/tmp/copy-success.md",
                workspaceDir: nil
            )
        case "transcript-action-copy-failure":
            return NativeControlPlaneFixtureConfiguration(
                dependencyResponse: .readyFixture,
                recordingScript: .success,
                processingTranscriptScript: .success(),
                processingSpeakerLabelsScript: .success(),
                processingClientMode: processingClientMode,
                sessionID: "session-app-ui-transcript",
                transcriptInput: .reviewFixture,
                exportScript: .failure(
                    code: "artifact_missing",
                    message: "Transcript artifact is missing."
                ),
                deleteScript: .success(),
                exportDestinationPath: "/tmp/copy-failure.md",
                workspaceDir: nil
            )
        case "transcript-action-export-success":
            return NativeControlPlaneFixtureConfiguration(
                dependencyResponse: .readyFixture,
                recordingScript: .success,
                processingTranscriptScript: .success(),
                processingSpeakerLabelsScript: .success(),
                processingClientMode: processingClientMode,
                sessionID: "session-app-ui-transcript",
                transcriptInput: .reviewFixture,
                exportScript: .success(exportPackageID: "export-package-app-fixture"),
                deleteScript: .success(),
                exportDestinationPath: "/tmp/meeting-assistant-export.md",
                workspaceDir: nil
            )
        case "transcript-action-export-cancel":
            return NativeControlPlaneFixtureConfiguration(
                dependencyResponse: .readyFixture,
                recordingScript: .success,
                processingTranscriptScript: .success(),
                processingSpeakerLabelsScript: .success(),
                processingClientMode: processingClientMode,
                sessionID: "session-app-ui-transcript",
                transcriptInput: .reviewFixture,
                exportScript: .success(exportPackageID: "export-package-app-fixture"),
                deleteScript: .success(),
                exportDestinationPath: nil,
                workspaceDir: nil
            )
        case "transcript-action-export-failure":
            return NativeControlPlaneFixtureConfiguration(
                dependencyResponse: .readyFixture,
                recordingScript: .success,
                processingTranscriptScript: .success(),
                processingSpeakerLabelsScript: .success(),
                processingClientMode: processingClientMode,
                sessionID: "session-app-ui-transcript",
                transcriptInput: .reviewFixture,
                exportScript: .failure(
                    code: "path_conflict",
                    message: "Export target already exists."
                ),
                deleteScript: .success(),
                exportDestinationPath: "/tmp/meeting-assistant-export.md",
                workspaceDir: nil
            )
        case "transcript-action-delete-success":
            return NativeControlPlaneFixtureConfiguration(
                dependencyResponse: .readyFixture,
                recordingScript: .success,
                processingTranscriptScript: .success(),
                processingSpeakerLabelsScript: .success(),
                processingClientMode: processingClientMode,
                sessionID: "session-app-ui-transcript",
                transcriptInput: .reviewFixture,
                exportScript: .success(content: "Delete success fixture copy content."),
                deleteScript: .success(
                    deletedItems: [
                        "artifacts/transcript.json",
                        "artifacts/speaker_labels.json",
                        "logs/processing.log",
                    ],
                    retainedExternalExports: ["/tmp/meeting-assistant-export.md"]
                ),
                exportDestinationPath: "/tmp/delete-success.md",
                workspaceDir: nil
            )
        case "transcript-action-delete-failure":
            return NativeControlPlaneFixtureConfiguration(
                dependencyResponse: .readyFixture,
                recordingScript: .success,
                processingTranscriptScript: .success(),
                processingSpeakerLabelsScript: .success(),
                processingClientMode: processingClientMode,
                sessionID: "session-app-ui-transcript",
                transcriptInput: .reviewFixture,
                exportScript: .success(content: "Delete failure fixture copy content."),
                deleteScript: .failure(
                    code: "path_conflict",
                    message: "Session path escaped the workspace."
                ),
                exportDestinationPath: "/tmp/delete-failure.md",
                workspaceDir: nil
            )
        case "processing-success":
            return NativeControlPlaneFixtureConfiguration(
                dependencyResponse: .readyFixture,
                recordingScript: .success,
                processingTranscriptScript: .success(
                    transcriptID: "transcript-app-processing",
                    artifactID: "artifact-app-transcript",
                    segmentCount: 2
                ),
                processingSpeakerLabelsScript: .success(
                    labelStatus: "labeled",
                    speakerLabelsArtifactID: "artifact-app-speakers"
                ),
                processingClientMode: processingClientMode,
                sessionID: "session-app-ui-processing",
                transcriptInput: .missingFixture,
                exportScript: .success(content: "Processing success fixture copy content."),
                deleteScript: .success(),
                exportDestinationPath: "/tmp/processing-success.md",
                workspaceDir: nil
            )
        case "processing-transcript-only":
            return NativeControlPlaneFixtureConfiguration(
                dependencyResponse: .readyFixture,
                recordingScript: .success,
                processingTranscriptScript: .success(
                    transcriptID: "transcript-app-processing",
                    artifactID: "artifact-app-transcript",
                    segmentCount: 1
                ),
                processingSpeakerLabelsScript: .success(
                    labelStatus: "transcript_only",
                    speakerLabelsArtifactID: "artifact-app-speakers",
                    degradationReason: "speaker labeling runtime unavailable"
                ),
                processingClientMode: processingClientMode,
                sessionID: "session-app-ui-processing",
                transcriptInput: .missingFixture,
                exportScript: .success(content: "Processing transcript-only fixture copy content."),
                deleteScript: .success(),
                exportDestinationPath: "/tmp/processing-transcript-only.md",
                workspaceDir: nil
            )
        case "processing-failure":
            return NativeControlPlaneFixtureConfiguration(
                dependencyResponse: .readyFixture,
                recordingScript: .success,
                processingTranscriptScript: .failure(
                    code: "processing_failed",
                    message: "Transcript adapter failed."
                ),
                processingSpeakerLabelsScript: .success(),
                processingClientMode: processingClientMode,
                sessionID: "session-app-ui-processing",
                transcriptInput: .missingFixture,
                exportScript: .success(content: "Processing failure fixture copy content."),
                deleteScript: .success(),
                exportDestinationPath: "/tmp/processing-failure.md",
                workspaceDir: nil
            )
        default:
            return NativeControlPlaneFixtureConfiguration(
                dependencyResponse: .blockedFixture,
                recordingScript: .success,
                processingTranscriptScript: .success(),
                processingSpeakerLabelsScript: .success(),
                processingClientMode: processingClientMode,
                sessionID: "session-app-ui-blocked",
                transcriptInput: .missingFixture,
                exportScript: .success(content: "Blocked fixture transcript content."),
                deleteScript: .success(),
                exportDestinationPath: "/tmp/blocked-fixture-transcript.md",
                workspaceDir: nil
            )
        }
    }

    private static func argumentValue(named name: String, in arguments: [String]) -> String? {
        let prefix = "\(name)="
        return arguments
            .first { $0.hasPrefix(prefix) }
            .map { String($0.dropFirst(prefix.count)) }
    }

    private static func recordingWorkspaceURL(
        environment: [String: String],
        arguments: [String]
    ) -> URL? {
        let workspacePath = environment["MA_NATIVE_RECORDING_WORKSPACE"]
            ?? environment["MEETING_ASSISTANT_WORKSPACE"]
            ?? argumentValue(named: "--ma-native-recording-workspace", in: arguments)
        guard let workspacePath = workspacePath?.trimmingCharacters(in: .whitespacesAndNewlines),
              !workspacePath.isEmpty else {
            return nil
        }
        return URL(fileURLWithPath: workspacePath, isDirectory: true)
    }

    private static var controlledRecordingArtifacts: [NativeCaptureArtifactResult] {
        [
            .available(
                .screenVideo,
                format: "mov",
                data: Data("controlled app screen video".utf8)
            ),
            .missing(
                .systemAudio,
                reason: "system audio unavailable in controlled app fixture"
            ),
            .degraded(
                .microphoneAudio,
                reason: "microphone audio degraded in controlled app fixture"
            ),
            .missing(
                .mixedAudio,
                reason: "mixed audio missing because controlled app fixture lacks one input"
            ),
        ]
    }
}

private enum NativeRecordingClientMode {
    case fake
    case controlled

    static func fromLaunchEnvironment(
        _ environment: [String: String],
        workspaceURL: URL?
    ) -> NativeRecordingClientMode {
        let rawValue = environment["MA_NATIVE_RECORDING_CLIENT"]?
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .lowercased()
        guard rawValue == "controlled",
              workspaceURL != nil,
              isRecordingClientTestHookAllowed(environment)
        else {
            return .fake
        }
        return .controlled
    }

    private static func isRecordingClientTestHookAllowed(_ environment: [String: String]) -> Bool {
        #if DEBUG
        return isNativeAppXCTestEnvironment(environment)
        #else
        return false
        #endif
    }
}

private enum NativeProcessingClientMode {
    case fake
    case process

    static func fromLaunchEnvironment(_ environment: [String: String]) -> NativeProcessingClientMode {
        let rawValue = environment["MA_NATIVE_PROCESSING_CLIENT"]?
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .lowercased()
        guard rawValue == "process", isProcessClientTestHookAllowed(environment) else {
            return .fake
        }
        return .process
    }

    private static func isProcessClientTestHookAllowed(_ environment: [String: String]) -> Bool {
        #if DEBUG
        return isNativeAppXCTestEnvironment(environment)
        #else
        return false
        #endif
    }
}

private enum NativeTranscriptActionClientMode {
    case fake
    case process

    static func fromLaunchEnvironment(_ environment: [String: String]) -> NativeTranscriptActionClientMode {
        let rawValue = environment["MA_NATIVE_TRANSCRIPT_ACTION_CLIENT"]?
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .lowercased()
        guard rawValue == "process", isTranscriptActionClientTestHookAllowed(environment) else {
            return .fake
        }
        return .process
    }

    private static func isTranscriptActionClientTestHookAllowed(_ environment: [String: String]) -> Bool {
        #if DEBUG
        return isNativeAppXCTestEnvironment(environment)
        #else
        return false
        #endif
    }
}

private func isNativeAppXCTestEnvironment(_ environment: [String: String]) -> Bool {
    environment["MA_NATIVE_APP_XCTEST"] == "1"
        || environment["XCTestConfigurationFilePath"] != nil
        || environment["XCTestBundlePath"] != nil
        || environment["XCInjectBundleInto"] != nil
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
