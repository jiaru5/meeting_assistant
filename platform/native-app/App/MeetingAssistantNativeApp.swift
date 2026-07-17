import Foundation
import AppKit
import SwiftUI

private enum NativeTranscriptPresentationError: LocalizedError {
    case missingTranscript
    case sessionMismatch

    var errorDescription: String? {
        switch self {
        case .missingTranscript:
            return "The selected meeting is marked as transcribed, but no readable transcript artifact was found."
        case .sessionMismatch:
            return "The loaded transcript does not belong to the selected meeting."
        }
    }
}

@main
struct MeetingAssistantNativeApp: App {
    init() {
        MeetingAssistantNativeLaunchCoordinator.shared.install()
    }

    var body: some Scene {
        Settings {
            EmptyView()
        }
    }
}

@MainActor
private final class MeetingAssistantNativeLaunchCoordinator {
    static let shared = MeetingAssistantNativeLaunchCoordinator()

    private var didInstall = false
    private var didOpenMainWindow = false
    private var didFinishLaunchingObserver: NSObjectProtocol?
    private var didBecomeActiveObserver: NSObjectProtocol?

    func install() {
        guard !didInstall else {
            return
        }
        didInstall = true
        didFinishLaunchingObserver = NotificationCenter.default.addObserver(
            forName: NSApplication.didFinishLaunchingNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor in
                self?.openMainWindowOnce()
            }
        }
        didBecomeActiveObserver = NotificationCenter.default.addObserver(
            forName: NSApplication.didBecomeActiveNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor in
                self?.reopenMainWindowIfNeeded()
            }
        }

        DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) { [weak self] in
            Task { @MainActor in
                self?.openMainWindowOnce()
            }
        }
    }

    private func openMainWindowOnce() {
        guard !didOpenMainWindow else {
            return
        }
        didOpenMainWindow = true
        MeetingAssistantNativeMainWindow.shared.openMainWindow()
    }

    private func reopenMainWindowIfNeeded() {
        guard didOpenMainWindow,
              !MeetingAssistantNativeMainWindow.shared.hasVisibleWindow else {
            return
        }
        MeetingAssistantNativeMainWindow.shared.openMainWindow()
    }
}

@MainActor
private final class MeetingAssistantNativeMainWindow {
    static let shared = MeetingAssistantNativeMainWindow()

    private var windowController: NSWindowController?

    var hasVisibleWindow: Bool {
        windowController?.window?.isVisible == true
    }

    func openMainWindow() {
        NSApp.setActivationPolicy(.regular)
        if let window = windowController?.window {
            show(window: window)
            return
        }

        let configuration = NativeControlPlaneFixtureConfiguration.fromLaunchContext()
        let windowPlacement = NativeAppWindowPlacement.fromLaunchContext()
        let smokeStateReporter = NativeLocalAppSmokeStateReporter.fromLaunchContext()
        let rootView = NativeControlPlaneRootView(
            configuration: configuration,
            smokeStateReporter: smokeStateReporter
        )
            .background(WindowPlacementView(placement: windowPlacement))
        let hostingController = NSHostingController(rootView: rootView)
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 1180, height: 760),
            styleMask: [.titled, .closable, .miniaturizable, .resizable],
            backing: .buffered,
            defer: false
        )
        window.appearance = NSAppearance(named: .aqua)
        window.title = "Meeting Assistant Native"
        window.contentViewController = hostingController
        window.isReleasedWhenClosed = false
        window.setAccessibilityElement(true)
        window.setAccessibilityRole(.window)
        window.setAccessibilitySubrole(.standardWindow)
        window.setAccessibilityTitle("Meeting Assistant Native")
        hostingController.view.setAccessibilityElement(true)
        hostingController.view.setAccessibilityRole(.group)
        hostingController.view.setAccessibilityLabel("Meeting Assistant")
        window.setFrameAutosaveName("meeting-assistant-main")
        window.center()

        let controller = NSWindowController(window: window)
        windowController = controller
        controller.showWindow(nil)
        show(window: window)
    }

    private func show(window: NSWindow) {
        NSApp.activate(ignoringOtherApps: true)
        window.makeKeyAndOrderFront(nil)
        window.orderFrontRegardless()
    }
}

private struct NativeControlPlaneRootView: View {
    @StateObject private var workspaceCoordinator: MeetingWorkspaceCoordinator
    @StateObject private var permissionViewModel: PermissionDependencyStatusViewModel
    @StateObject private var recordingViewModel: RecordingControlViewModel
    @StateObject private var processingViewModel: ProcessingStateViewModel
    @StateObject private var transcriptActionViewModel: TranscriptReviewActionsViewModel
    @State private var transcriptViewModel: TranscriptReviewViewModel
    @State private var loadedTranscriptSessionID: String?
    private let launchTranscriptInput: TranscriptReviewInput
    private let workspaceURL: URL
    private let usesTestFixture: Bool
    private let autoRefreshPreflightOnAppear: Bool
    private let smokeStateReporter: NativeLocalAppSmokeStateReporter?

    init(
        configuration: NativeControlPlaneFixtureConfiguration,
        smokeStateReporter: NativeLocalAppSmokeStateReporter? = nil
    ) {
        let readinessState = configuration.initialReadinessState()
        let configuredWorkspaceURL = configuration.recordingWorkspaceURL()
        let usesTestFixture = isNativeAppXCTestEnvironment(ProcessInfo.processInfo.environment)
        let recordingWorkspaceURL = configuredWorkspaceURL
            ?? (usesTestFixture
                ? FileManager.default.temporaryDirectory
                    .appendingPathComponent(
                        "MeetingAssistantNative-XCTest-\(ProcessInfo.processInfo.processIdentifier)",
                        isDirectory: true
                    )
                : RecordingSessionStore.defaultWorkspaceURL)
        let autoRefreshPreflightOnAppear = configuration.autoRefreshPreflightOnAppear()
        let recordingCommandClient = configuration.makeRecordingCommandClient()
        let dependencyCheckRunner = configuration.makeDependencyCheckRunner()
        let processingCommandClient = configuration.makeProcessingCommandClient()
        let transcriptActionCommandClient = configuration.makeTranscriptActionCommandClient()
        let transcriptActionOSClients = configuration.makeTranscriptActionOSClients()
        let initialSessions = Self.initialSessions(
            from: configuration.transcriptInput,
            fallbackSessionID: usesTestFixture && configuration.sessionID.contains("processing")
                ? configuration.sessionID
                : nil,
            configuredSession: usesTestFixture ? configuration.initialSession : nil
        )
        self.workspaceURL = recordingWorkspaceURL
        self.launchTranscriptInput = configuration.transcriptInput
        self.usesTestFixture = usesTestFixture
        self.autoRefreshPreflightOnAppear = autoRefreshPreflightOnAppear
        self.smokeStateReporter = smokeStateReporter
        _workspaceCoordinator = StateObject(
            wrappedValue: MeetingWorkspaceCoordinator(
                workspaceURL: recordingWorkspaceURL,
                initialSessions: initialSessions,
                recordingDraft: MeetingRecordingDraft(
                    captureSystemAudio: configuration.captureSystemAudio,
                    captureMicrophoneAudio: configuration.captureMicrophoneAudio
                )
            )
        )
        _permissionViewModel = StateObject(
            wrappedValue: PermissionDependencyStatusViewModel(
                runner: dependencyCheckRunner,
                initialState: readinessState
            )
        )
        _recordingViewModel = StateObject(
            wrappedValue: RecordingControlViewModel(
                commandClient: recordingCommandClient,
                readinessState: readinessState,
                captureTarget: .screen,
                workspaceURL: recordingWorkspaceURL,
                captureSystemAudio: configuration.captureSystemAudio,
                captureMicrophoneAudio: configuration.captureMicrophoneAudio
            )
        )
        _processingViewModel = StateObject(
            wrappedValue: ProcessingStateViewModel(
                commandClient: processingCommandClient,
                readinessState: readinessState,
                defaultSessionID: "",
                defaultLanguage: configuration.processingDefaultLanguage,
                defaultRuntime: configuration.processingDefaultRuntime
            )
        )
        let emptyTranscriptInput = TranscriptReviewInput(sessionTitle: nil, transcript: nil)
        _transcriptViewModel = State(initialValue: TranscriptReviewViewModel(input: emptyTranscriptInput))
        _transcriptActionViewModel = StateObject(
            wrappedValue: TranscriptReviewActionsViewModel(
                input: emptyTranscriptInput,
                commandClient: transcriptActionCommandClient,
                clipboard: transcriptActionOSClients.clipboard,
                destinationSelector: transcriptActionOSClients.destinationSelector,
                workspaceDir: configuration.workspaceDir ?? recordingWorkspaceURL.path
            )
        )
    }

    var body: some View {
        DesignedNativeShellView(
            coordinator: workspaceCoordinator,
            permissionViewModel: permissionViewModel,
            recordingViewModel: recordingViewModel,
            processingViewModel: processingViewModel,
            transcriptViewModel: transcriptViewModel,
            transcriptActionViewModel: transcriptActionViewModel,
            autoRefreshPreflightOnAppear: autoRefreshPreflightOnAppear,
            startRecording: beginRecording,
            stopRecording: { _ = requestStopRecording() },
            startProcessing: { _ = requestStartProcessing() },
            openMeeting: openMeeting,
            reloadTranscript: reloadCurrentTranscript,
            confirmDelete: confirmCurrentMeetingDeletion
        )
        .background {
            NativeLocalAppKeyboardShortcutView(
                startRecording: {
                    guard workspaceCoordinator.route == .newRecording,
                          workspaceCoordinator.activity == .idle,
                          recordingViewModel.canStart else {
                        return false
                    }
                    beginRecording(workspaceCoordinator.recordingDraft)
                    return true
                },
                stopRecording: {
                    requestStopRecording()
                },
                startProcessing: {
                    requestStartProcessing()
                },
                copyTranscript: {
                    guard workspaceCoordinator.route == .meetingDetail,
                          workspaceCoordinator.activity == .idle,
                          workspaceCoordinator.currentSession?.id == transcriptActionViewModel.state.sessionID,
                          transcriptActionViewModel.state.canCopy else {
                        return false
                    }
                    Task {
                        await transcriptActionViewModel.copyTranscript()
                    }
                    return true
                },
                exportTranscript: {
                    guard workspaceCoordinator.route == .meetingDetail,
                          workspaceCoordinator.activity == .idle,
                          workspaceCoordinator.currentSession?.id == transcriptActionViewModel.state.sessionID,
                          transcriptActionViewModel.state.canExport else {
                        return false
                    }
                    Task {
                        await transcriptActionViewModel.exportTranscript()
                    }
                    return true
                },
                requestDelete: {
                    guard workspaceCoordinator.route == .meetingDetail,
                          workspaceCoordinator.activity == .idle,
                          workspaceCoordinator.currentSession?.id == transcriptActionViewModel.state.sessionID,
                          transcriptActionViewModel.state.canRequestDelete else {
                        return false
                    }
                    transcriptActionViewModel.requestDeleteConfirmation()
                    return true
                },
                cancelDelete: {
                    guard workspaceCoordinator.route == .meetingDetail,
                          workspaceCoordinator.activity == .idle,
                          workspaceCoordinator.currentSession?.id == transcriptActionViewModel.state.sessionID,
                          transcriptActionViewModel.state.isDeletePromptVisible else {
                        return false
                    }
                    transcriptActionViewModel.cancelDelete()
                    return true
                }
            )
        }
        .background {
            smokeStateReportView
        }
        .onChange(of: recordingViewModel.state) { _, newState in
            synchronizeProcessingSession(with: newState)
        }
        .onChange(of: processingViewModel.state) { _, newState in
            synchronizeTranscriptReview(with: newState)
        }
    }

    @MainActor
    private func synchronizeProcessingSession(with recordingState: RecordingControlState) {
        switch recordingState.phase {
        case .starting:
            workspaceCoordinator.recordingWillStart()
        case .recording:
            guard let sessionID = recordingState.sessionID else {
                return
            }
            if workspaceCoordinator.currentSession?.id != sessionID
                || workspaceCoordinator.activity != .recording {
                workspaceCoordinator.recordingDidStart(sessionID: sessionID)
            }
        case .stopping:
            workspaceCoordinator.recordingWillSave()
        case .recorded:
            guard let sessionID = recordingState.sessionID else {
                return
            }
            workspaceCoordinator.recordingDidSave(recordingState)
            let audioStatus = processableAudioStatus(from: recordingState.artifacts)
            processingViewModel.bindSession(
                sessionID: sessionID,
                sessionStatus: "recorded",
                processableAudioStatus: audioStatus
            )
            transcriptViewModel = TranscriptReviewViewModel(
                input: TranscriptReviewInput(
                    sessionTitle: workspaceCoordinator.currentMeetingTitle,
                    transcript: nil
                )
            )
            transcriptActionViewModel.updateSession(
                sessionID: sessionID,
                sessionTitle: workspaceCoordinator.currentMeetingTitle,
                transcript: nil
            )
            loadedTranscriptSessionID = nil
        case .failed:
            workspaceCoordinator.recordingDidFail(hasActiveSession: recordingState.sessionID != nil)
            if recordingState.errorCode == .permissionDenied {
                Task {
                    await permissionViewModel.refresh(workspaceURL: workspaceURL)
                }
            }
        case .idle, .ready:
            break
        }
    }

    @MainActor
    private func synchronizeTranscriptReview(with processingState: ProcessingState) {
        switch processingState.phase {
        case .generatingTranscript, .generatingSpeakerLabels:
            workspaceCoordinator.processingWillStart()
            return
        case .failed:
            workspaceCoordinator.processingDidFail()
            return
        case .completed, .degraded:
            workspaceCoordinator.processingDidFinish()
        case .idle, .blocked:
            return
        }

        guard processingState.phase == .completed || processingState.phase == .degraded,
              let sessionID = processingState.sessionID,
              sessionID == workspaceCoordinator.currentSession?.id,
              sessionID != loadedTranscriptSessionID
        else {
            return
        }

        guard let loadToken = workspaceCoordinator.transcriptWillLoad(for: sessionID) else {
            return
        }
        Task {
            do {
                let input = try await transcriptInput(
                    for: sessionID,
                    allowGeneratedTestFixture: true
                )
                guard workspaceCoordinator.isCurrentTranscriptLoad(loadToken) else {
                    return
                }
                installTranscript(input, loadToken: loadToken)
            } catch {
                guard workspaceCoordinator.isCurrentTranscriptLoad(loadToken) else {
                    return
                }
                clearTranscriptForCurrentSession()
                workspaceCoordinator.transcriptDidFailToLoad(error, token: loadToken)
            }
        }
    }

    @MainActor
    private func beginRecording(_ draft: MeetingRecordingDraft) {
        guard workspaceCoordinator.route == .newRecording,
              workspaceCoordinator.activity == .idle,
              recordingViewModel.canStart else {
            return
        }
        workspaceCoordinator.recordingWillStart()
        processingViewModel.clearSessionBinding()
        transcriptActionViewModel.clearSession()
        transcriptViewModel = TranscriptReviewViewModel(
            input: TranscriptReviewInput(sessionTitle: draft.normalizedTitle, transcript: nil)
        )
        loadedTranscriptSessionID = nil
        Task {
            await recordingViewModel.start(
                title: draft.normalizedTitle,
                captureTarget: .screen,
                workspaceURL: workspaceURL,
                captureSystemAudio: draft.captureSystemAudio,
                captureMicrophoneAudio: draft.captureMicrophoneAudio
            )
        }
    }

    @MainActor
    @discardableResult
    private func requestStopRecording() -> Bool {
        guard workspaceCoordinator.route == .meetingDetail,
              let sessionID = recordingViewModel.state.sessionID,
              workspaceCoordinator.currentSession?.id == sessionID,
              recordingViewModel.canStop else {
            return false
        }
        workspaceCoordinator.recordingWillSave()
        Task {
            await recordingViewModel.stop()
        }
        return true
    }

    @MainActor
    @discardableResult
    private func requestStartProcessing() -> Bool {
        guard workspaceCoordinator.route == .meetingDetail,
              workspaceCoordinator.activity == .idle,
              let currentSession = workspaceCoordinator.currentSession,
              !currentSession.hasRegisteredTranscript,
              workspaceCoordinator.transcriptLoadError == nil,
              processingViewModel.boundSessionID == currentSession.id,
              processingViewModel.canStart else {
            return false
        }
        let sessionID = currentSession.id
        workspaceCoordinator.processingWillStart()
        let sourceArtifactID = workspaceCoordinator.processingRequestSourceArtifactID
        Task {
            await processingViewModel.start(
                sessionID: sessionID,
                sourceArtifactID: sourceArtifactID
            )
        }
        return true
    }

    @MainActor
    private func openMeeting(_ session: MeetingSessionSummary) {
        guard !workspaceCoordinator.navigationIsLocked else {
            return
        }
        Task {
            guard let selectedSession = await workspaceCoordinator.open(session) else {
                return
            }
            recordingViewModel.resetForNewTask()
            loadedTranscriptSessionID = nil
            clearTranscriptForCurrentSession()
            processingViewModel.bindSession(
                sessionID: selectedSession.id,
                sessionStatus: selectedSession.status,
                processableAudioStatus: selectedSession.hasProcessableAudio ? .available : nil
            )
            transcriptActionViewModel.updateSession(
                sessionID: selectedSession.id,
                sessionTitle: displayTitle(for: selectedSession),
                transcript: nil
            )
            guard selectedSession.hasTranscript else {
                if selectedSession.hasRegisteredTranscript {
                    if let loadToken = workspaceCoordinator.transcriptWillLoad(for: selectedSession.id) {
                        workspaceCoordinator.transcriptDidFailToLoad(
                            NativeTranscriptPresentationError.missingTranscript,
                            token: loadToken
                        )
                    }
                }
                return
            }
            guard let loadToken = workspaceCoordinator.transcriptWillLoad(for: selectedSession.id) else {
                return
            }
            do {
                let input = try await transcriptInput(
                    for: selectedSession.id,
                    allowGeneratedTestFixture: false
                )
                guard workspaceCoordinator.isCurrentTranscriptLoad(loadToken) else {
                    return
                }
                installTranscript(input, loadToken: loadToken)
            } catch {
                guard workspaceCoordinator.isCurrentTranscriptLoad(loadToken) else {
                    return
                }
                clearTranscriptForCurrentSession()
                workspaceCoordinator.transcriptDidFailToLoad(error, token: loadToken)
            }
        }
    }

    @MainActor
    private func reloadCurrentTranscript() {
        guard let sessionID = workspaceCoordinator.currentSession?.id else {
            return
        }
        workspaceCoordinator.clearTranscriptError()
        guard let loadToken = workspaceCoordinator.transcriptWillLoad(for: sessionID) else {
            return
        }
        Task {
            do {
                let input = try await transcriptInput(
                    for: sessionID,
                    allowGeneratedTestFixture: false
                )
                guard workspaceCoordinator.isCurrentTranscriptLoad(loadToken) else {
                    return
                }
                installTranscript(input, loadToken: loadToken)
            } catch {
                guard workspaceCoordinator.isCurrentTranscriptLoad(loadToken) else {
                    return
                }
                clearTranscriptForCurrentSession()
                workspaceCoordinator.transcriptDidFailToLoad(error, token: loadToken)
            }
        }
    }

    @MainActor
    private func confirmCurrentMeetingDeletion() {
        guard let expectedSessionID = workspaceCoordinator.currentSession?.id,
              transcriptActionViewModel.state.sessionID == expectedSessionID else {
            return
        }
        workspaceCoordinator.deletionWillStart()
        Task {
            let deletedSessionID = await transcriptActionViewModel.confirmDelete()
            guard workspaceCoordinator.currentSession?.id == expectedSessionID else {
                workspaceCoordinator.deletionDidFail()
                await workspaceCoordinator.refreshSessions()
                return
            }

            let commandReportedDeletion = deletedSessionID == expectedSessionID
            let reconciliation = await workspaceCoordinator.reconcileDeletionAttempt(
                sessionID: expectedSessionID,
                commandReportedDeletion: commandReportedDeletion
            )
            recordingViewModel.resetForNewTask()
            processingViewModel.clearSessionBinding()
            loadedTranscriptSessionID = nil

            switch reconciliation {
            case .sessionPresent(let session):
                let preservesDeleteFailure = !commandReportedDeletion
                clearTranscriptForCurrentSession(
                    preservingActionFailure: preservesDeleteFailure
                )
                processingViewModel.bindSession(
                    sessionID: session.id,
                    sessionStatus: session.status,
                    processableAudioStatus: session.hasProcessableAudio ? .available : nil
                )

                if session.hasTranscript {
                    if let loadToken = workspaceCoordinator.transcriptWillLoad(for: session.id) {
                        do {
                            let input = try await transcriptInput(
                                for: session.id,
                                allowGeneratedTestFixture: false
                            )
                            guard workspaceCoordinator.isCurrentTranscriptLoad(loadToken) else {
                                return
                            }
                            installTranscript(
                                input,
                                loadToken: loadToken,
                                preservingActionFailure: preservesDeleteFailure
                            )
                        } catch {
                            guard workspaceCoordinator.isCurrentTranscriptLoad(loadToken) else {
                                return
                            }
                            clearTranscriptForCurrentSession(
                                preservingActionFailure: preservesDeleteFailure
                            )
                            workspaceCoordinator.transcriptDidFailToLoad(
                                error,
                                token: loadToken
                            )
                        }
                    }
                } else if session.hasRegisteredTranscript {
                    if let loadToken = workspaceCoordinator.transcriptWillLoad(for: session.id) {
                        workspaceCoordinator.transcriptDidFailToLoad(
                            NativeTranscriptPresentationError.missingTranscript,
                            token: loadToken
                        )
                    }
                }

                if commandReportedDeletion {
                    transcriptActionViewModel.reportDeleteReconciliationFailure()
                }
            case .sessionMissing, .workspaceUnreadable:
                clearTranscriptForCurrentSession()
            }
        }
    }

    @MainActor
    private func installTranscript(
        _ input: TranscriptReviewInput,
        loadToken: MeetingTranscriptLoadToken,
        preservingActionFailure: Bool = false
    ) {
        guard workspaceCoordinator.isCurrentTranscriptLoad(loadToken) else {
            return
        }
        let sessionID = loadToken.sessionID
        guard let transcript = input.transcript else {
            clearTranscriptForCurrentSession(
                preservingActionFailure: preservingActionFailure
            )
            workspaceCoordinator.transcriptDidFailToLoad(
                NativeTranscriptPresentationError.missingTranscript,
                token: loadToken
            )
            return
        }
        guard transcript.sessionID == sessionID else {
            clearTranscriptForCurrentSession(
                preservingActionFailure: preservingActionFailure
            )
            workspaceCoordinator.transcriptDidFailToLoad(
                NativeTranscriptPresentationError.sessionMismatch,
                token: loadToken
            )
            return
        }
        transcriptViewModel = TranscriptReviewViewModel(input: input)
        transcriptActionViewModel.updateSession(
            sessionID: sessionID,
            sessionTitle: input.sessionTitle ?? workspaceCoordinator.currentMeetingTitle,
            transcript: input.transcript,
            preservingFailureFeedback: preservingActionFailure
        )
        loadedTranscriptSessionID = sessionID
        workspaceCoordinator.transcriptDidLoad(
            loadToken,
            hasSpeakerLabels: input.speakerLabels != nil
        )
    }

    @MainActor
    private func clearTranscriptForCurrentSession(
        preservingActionFailure: Bool = false
    ) {
        transcriptViewModel = TranscriptReviewViewModel(
            input: TranscriptReviewInput(
                sessionTitle: workspaceCoordinator.currentSession.map(displayTitle),
                transcript: nil
            )
        )
        if let session = workspaceCoordinator.currentSession {
            transcriptActionViewModel.updateSession(
                sessionID: session.id,
                sessionTitle: displayTitle(for: session),
                transcript: nil,
                preservingFailureFeedback: preservingActionFailure
            )
        } else {
            transcriptActionViewModel.clearSession()
        }
    }

    @MainActor
    private func transcriptInput(
        for sessionID: String,
        allowGeneratedTestFixture: Bool
    ) async throws -> TranscriptReviewInput {
        if launchTranscriptInput.transcript?.sessionID == sessionID {
            return launchTranscriptInput
        }
        let workspaceURL = workspaceURL
        do {
            return try await Task.detached(priority: .userInitiated) {
                try TranscriptReviewWorkspaceLoader.load(
                    workspaceURL: workspaceURL,
                    sessionID: sessionID
                )
            }.value
        } catch {
            guard usesTestFixture, allowGeneratedTestFixture else {
                throw error
            }
            return Self.generatedTestTranscript(
                sessionID: sessionID,
                title: workspaceCoordinator.currentMeetingTitle,
                degraded: processingViewModel.state.phase == .degraded
            )
        }
    }

    private func processableAudioStatus(
        from artifacts: [RecordingCommandArtifact]
    ) -> NativeCaptureArtifactStatus? {
        let processableTypes = Set(["mixed_audio", "system_audio", "microphone_audio"])
        let matches = artifacts.filter {
            processableTypes.contains($0.artifactType)
                && $0.path?.isEmpty == false
                && $0.checksum?.isEmpty == false
        }
        if matches.contains(where: { $0.captureStatus == "available" }) {
            return .available
        }
        if matches.contains(where: { $0.captureStatus == "degraded" }) {
            return .degraded
        }
        return nil
    }

    private func displayTitle(for session: MeetingSessionSummary) -> String {
        let title = session.title?.trimmingCharacters(in: .whitespacesAndNewlines)
        return title?.isEmpty == false ? title! : "Untitled meeting"
    }

    private static func initialSessions(
        from input: TranscriptReviewInput,
        fallbackSessionID: String?,
        configuredSession: MeetingSessionSummary?
    ) -> [MeetingSessionSummary] {
        if let configuredSession {
            return [configuredSession]
        }
        let sessionID = input.transcript?.sessionID ?? fallbackSessionID
        guard let sessionID else {
            return []
        }
        let hasTranscript = input.transcript != nil
        return [MeetingSessionSummary(
            id: sessionID,
            title: input.sessionTitle,
            status: hasTranscript ? "transcribed" : "recorded",
            startedAt: "2026-07-01T09:00:00Z",
            endedAt: "2026-07-01T09:30:00Z",
            updatedAt: "2026-07-01T09:31:00Z",
            durationLabel: "30:00",
            artifactCount: hasTranscript ? (input.speakerLabels == nil ? 2 : 3) : 2,
            hasTranscript: hasTranscript,
            hasSpeakerLabels: hasTranscript && input.speakerLabels != nil,
            hasProcessableAudio: true
        )]
    }

    private static func generatedTestTranscript(
        sessionID: String,
        title: String,
        degraded: Bool
    ) -> TranscriptReviewInput {
        TranscriptReviewInput(
            sessionTitle: title,
            transcript: TranscriptReviewTranscript(
                id: "transcript-task-flow",
                sessionID: sessionID,
                sourceArtifactID: "artifact-meeting-audio",
                status: "succeeded",
                segments: [
                    TranscriptReviewSegment(
                        segmentID: "segment-1",
                        startMS: 0,
                        endMS: 4_000,
                        text: "The meeting transcript is ready for review.",
                        speakerLabel: degraded ? nil : "A"
                    ),
                ]
            ),
            speakerLabels: degraded ? nil : SpeakerLabelsReviewArtifact(
                sessionID: sessionID,
                labels: [
                    SpeakerLabelReviewEntry(
                        label: "A",
                        sessionID: sessionID,
                        isVerifiedIdentity: false
                    ),
                ],
                segmentMapping: [SpeakerLabelSegmentMapping(segmentID: "segment-1", label: "A")]
            ),
            speakerLabelsDegradationReason: degraded ? "Speaker labeling is unavailable." : nil
        )
    }

    @ViewBuilder
    private var smokeStateReportView: some View {
        if let smokeStateReporter {
            NativeLocalAppSmokeStateReportView(
                reporter: smokeStateReporter,
                workspaceCoordinator: workspaceCoordinator,
                permissionViewModel: permissionViewModel,
                recordingViewModel: recordingViewModel,
                processingViewModel: processingViewModel
            )
        } else {
            EmptyView()
        }
    }
}

private struct NativeLocalAppKeyboardShortcutView: NSViewRepresentable {
    let startRecording: () -> Bool
    let stopRecording: () -> Bool
    let startProcessing: () -> Bool
    let copyTranscript: () -> Bool
    let exportTranscript: () -> Bool
    let requestDelete: () -> Bool
    let cancelDelete: () -> Bool

    func makeCoordinator() -> Coordinator {
        Coordinator(
            startRecording: startRecording,
            stopRecording: stopRecording,
            startProcessing: startProcessing,
            copyTranscript: copyTranscript,
            exportTranscript: exportTranscript,
            requestDelete: requestDelete,
            cancelDelete: cancelDelete
        )
    }

    func makeNSView(context: Context) -> NSView {
        context.coordinator.install()
        return NSView(frame: .zero)
    }

    func updateNSView(_ nsView: NSView, context: Context) {
        context.coordinator.startRecording = startRecording
        context.coordinator.stopRecording = stopRecording
        context.coordinator.startProcessing = startProcessing
        context.coordinator.copyTranscript = copyTranscript
        context.coordinator.exportTranscript = exportTranscript
        context.coordinator.requestDelete = requestDelete
        context.coordinator.cancelDelete = cancelDelete
    }

    final class Coordinator {
        var startRecording: () -> Bool
        var stopRecording: () -> Bool
        var startProcessing: () -> Bool
        var copyTranscript: () -> Bool
        var exportTranscript: () -> Bool
        var requestDelete: () -> Bool
        var cancelDelete: () -> Bool
        private var monitor: Any?

        init(
            startRecording: @escaping () -> Bool,
            stopRecording: @escaping () -> Bool,
            startProcessing: @escaping () -> Bool,
            copyTranscript: @escaping () -> Bool,
            exportTranscript: @escaping () -> Bool,
            requestDelete: @escaping () -> Bool,
            cancelDelete: @escaping () -> Bool
        ) {
            self.startRecording = startRecording
            self.stopRecording = stopRecording
            self.startProcessing = startProcessing
            self.copyTranscript = copyTranscript
            self.exportTranscript = exportTranscript
            self.requestDelete = requestDelete
            self.cancelDelete = cancelDelete
        }

        deinit {
            if let monitor {
                NSEvent.removeMonitor(monitor)
            }
        }

        func install() {
            guard monitor == nil else {
                return
            }
            monitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
                self?.handle(event) ?? event
            }
        }

        private func handle(_ event: NSEvent) -> NSEvent? {
            if event.keyCode == 36 || event.keyCode == 76 {
                return cancelDelete() ? nil : event
            }

            let flags = event.modifierFlags.intersection(.deviceIndependentFlagsMask)
            guard flags.contains(.command), flags.contains(.option) else {
                return event
            }
            let handled: Bool
            switch event.charactersIgnoringModifiers?.lowercased() {
            case "r":
                handled = startRecording()
            case "s":
                handled = stopRecording()
            case "p":
                handled = startProcessing()
            case "c":
                handled = copyTranscript()
            case "e":
                handled = exportTranscript()
            case "d":
                handled = requestDelete()
            default:
                return event
            }
            return handled ? nil : event
        }
    }
}

private struct NativeLocalAppSmokeStateReportView: View {
    let reporter: NativeLocalAppSmokeStateReporter
    @ObservedObject var workspaceCoordinator: MeetingWorkspaceCoordinator
    @ObservedObject var permissionViewModel: PermissionDependencyStatusViewModel
    @ObservedObject var recordingViewModel: RecordingControlViewModel
    @ObservedObject var processingViewModel: ProcessingStateViewModel

    var body: some View {
        Color.clear
            .frame(width: 0, height: 0)
            .task {
                write(reason: "appeared")
            }
            .onChange(of: permissionViewModel.state) { _, _ in
                write(reason: "preflight-changed")
            }
            .onChange(of: recordingViewModel.state) { _, _ in
                write(reason: "recording-changed")
            }
            .onChange(of: processingViewModel.state) { _, _ in
                write(reason: "processing-changed")
            }
            .onChange(of: workspaceCoordinator.route) { _, _ in
                write(reason: "route-changed")
            }
            .onChange(of: workspaceCoordinator.recordingDraft) { _, _ in
                write(reason: "recording-draft-changed")
            }
    }

    @MainActor
    private func write(reason: String) {
        reporter.write(
            reason: reason,
            workspaceCoordinator: workspaceCoordinator,
            permissionViewModel: permissionViewModel,
            recordingViewModel: recordingViewModel,
            processingViewModel: processingViewModel,
            captureSystemAudio: workspaceCoordinator.recordingDraft.captureSystemAudio,
            captureMicrophoneAudio: workspaceCoordinator.recordingDraft.captureMicrophoneAudio
        )
    }
}

private struct NativeLocalAppSmokeStateReporter {
    let reportURL: URL
    let environment: [String: String]

    static func fromLaunchContext(
        environment: [String: String] = ProcessInfo.processInfo.environment
    ) -> NativeLocalAppSmokeStateReporter? {
        guard let rawPath = environment["MA_NATIVE_LOCAL_APP_SMOKE_STATE_REPORT"]?
            .trimmingCharacters(in: .whitespacesAndNewlines),
            !rawPath.isEmpty
        else {
            return nil
        }

        return NativeLocalAppSmokeStateReporter(
            reportURL: URL(fileURLWithPath: rawPath),
            environment: environment
        )
    }

    @MainActor
    func write(
        reason: String,
        workspaceCoordinator: MeetingWorkspaceCoordinator,
        permissionViewModel: PermissionDependencyStatusViewModel,
        recordingViewModel: RecordingControlViewModel,
        processingViewModel: ProcessingStateViewModel,
        captureSystemAudio: Bool,
        captureMicrophoneAudio: Bool
    ) {
        do {
            let payload = makePayload(
                reason: reason,
                workspaceCoordinator: workspaceCoordinator,
                permissionViewModel: permissionViewModel,
                recordingViewModel: recordingViewModel,
                processingViewModel: processingViewModel,
                captureSystemAudio: captureSystemAudio,
                captureMicrophoneAudio: captureMicrophoneAudio
            )
            let data = try JSONSerialization.data(withJSONObject: payload, options: [.prettyPrinted, .sortedKeys])
            try FileManager.default.createDirectory(
                at: reportURL.deletingLastPathComponent(),
                withIntermediateDirectories: true
            )
            let temporaryURL = reportURL.appendingPathExtension("tmp")
            try data.write(to: temporaryURL, options: [.atomic])
            if FileManager.default.fileExists(atPath: reportURL.path) {
                try FileManager.default.removeItem(at: reportURL)
            }
            try FileManager.default.moveItem(at: temporaryURL, to: reportURL)
        } catch {
            fputs("MeetingAssistantNative local smoke state report failed: \(error.localizedDescription)\n", stderr)
        }
    }

    @MainActor
    private func makePayload(
        reason: String,
        workspaceCoordinator: MeetingWorkspaceCoordinator,
        permissionViewModel: PermissionDependencyStatusViewModel,
        recordingViewModel: RecordingControlViewModel,
        processingViewModel: ProcessingStateViewModel,
        captureSystemAudio: Bool,
        captureMicrophoneAudio: Bool
    ) -> [String: Any] {
        let permissionState = permissionViewModel.state
        let recordingState = recordingViewModel.state
        let processingState = processingViewModel.state
        let recordingSetupText = Self.recordingSetupText(
            captureSystemAudio: captureSystemAudio,
            captureMicrophoneAudio: captureMicrophoneAudio
        )

        return [
            "report_schema": 1,
            "release_gate": "local-direct-app-state-smoke",
            "not_release_readiness": true,
            "reason": reason,
            "pid": ProcessInfo.processInfo.processIdentifier,
            "bundle": bundlePayload(),
            "launch_environment": launchEnvironmentPayload(),
            "shell": [
                "title": "Meeting Assistant",
                "selected_section": workspaceCoordinator.route.rawValue,
                "selected_section_label": "\(workspaceCoordinator.route.title) selected",
                "current_session_id": workspaceCoordinator.currentSession?.id ?? "",
                "recording_setup_text": recordingSetupText,
                "root_identifier": DesignedNativeShellAccessibilityID.root,
            ],
            "preflight": [
                "phase": permissionState.phase.rawValue,
                "summary": permissionState.summary(
                    captureMicrophoneAudio: captureMicrophoneAudio
                ),
                "can_start_recording": permissionState.canStartRecording(
                    captureMicrophoneAudio: captureMicrophoneAudio
                ),
                "can_run_processing": permissionState.canRunProcessing,
                "missing_required_check_ids": permissionState.missingRequiredCheckIDs,
                "warnings": permissionState.warnings,
                "permissions": permissionState.permissions.map(permissionPayload),
                "dependencies": permissionState.dependencies.map(dependencyPayload),
            ],
            "recording": [
                "phase": recordingState.phase.rawValue,
                "status_text": recordingState.statusText,
                "session_id": recordingState.sessionID ?? "",
                "error_code": recordingState.errorCode?.rawValue ?? "",
                "error_message": recordingState.errorMessage ?? "",
                "warnings": recordingState.warnings,
                "artifacts": recordingState.artifacts.map(recordingArtifactPayload),
                "can_start": recordingViewModel.canStart,
                "can_stop": recordingViewModel.canStop,
                "start_button_identifier": RecordingControlAccessibilityID.startButton,
                "stop_button_identifier": RecordingControlAccessibilityID.stopButton,
            ],
            "processing": [
                "phase": processingState.phase.rawValue,
                "status_text": processingState.statusText,
                "can_start": processingViewModel.canStart,
                "can_retry": processingViewModel.canRetry,
                "start_button_identifier": ProcessingAccessibilityID.startButton,
                "retry_button_identifier": ProcessingAccessibilityID.retryButton,
            ],
            "checked_controls": [
                [
                    "identifier": RecordingControlAccessibilityID.startButton,
                    "enabled": recordingViewModel.canStart,
                ],
                [
                    "identifier": RecordingControlAccessibilityID.stopButton,
                    "enabled": recordingViewModel.canStop,
                ],
                [
                    "identifier": ProcessingAccessibilityID.startButton,
                    "enabled": processingViewModel.canStart,
                ],
                [
                    "identifier": ProcessingAccessibilityID.retryButton,
                    "enabled": processingViewModel.canRetry,
                ],
            ],
            "checked_markers": [
                "Meeting Assistant",
                permissionState.summary,
                recordingState.statusText,
                processingState.statusText,
                recordingSetupText,
            ],
            "modifies_tcc_or_system_settings": false,
            "opens_system_settings": false,
            "starts_recording": false,
            "requires_developer_id_or_notarization": false,
        ]
    }

    private func bundlePayload(bundle: Bundle = .main) -> [String: Any] {
        [
            "path": bundle.bundlePath,
            "identifier": bundle.bundleIdentifier ?? "unknown",
            "name": bundle.object(forInfoDictionaryKey: "CFBundleName") as? String ?? "unknown",
            "display_name": bundle.object(forInfoDictionaryKey: "CFBundleDisplayName") as? String ?? "",
        ]
    }

    private func launchEnvironmentPayload() -> [String: Any] {
        [
            "workspace": environment["MEETING_ASSISTANT_WORKSPACE"] ?? "",
            "cli_path": environment["MEETING_ASSISTANT_CLI_PATH"] ?? "",
            "transcription_runtime": environment["MEETING_ASSISTANT_TRANSCRIPTION_RUNTIME"] ?? "",
            "transcription_model": environment["MEETING_ASSISTANT_TRANSCRIPTION_MODEL"] ?? "",
            "ffmpeg_path": environment["MEETING_ASSISTANT_FFMPEG_PATH"] ?? "",
            "recording_client": environment["MA_NATIVE_RECORDING_CLIENT"] ?? "",
            "processing_client": environment["MA_NATIVE_PROCESSING_CLIENT"] ?? "",
            "transcript_action_client": environment["MA_NATIVE_TRANSCRIPT_ACTION_CLIENT"] ?? "",
            "transcript_action_os_client": environment["MA_NATIVE_TRANSCRIPT_ACTION_OS_CLIENT"] ?? "",
        ]
    }

    private func permissionPayload(_ item: PermissionStatusItem) -> [String: Any] {
        [
            "id": item.id,
            "title": item.title,
            "state": item.state.rawValue,
            "message": item.message,
        ]
    }

    private func dependencyPayload(_ item: DependencyStatusItem) -> [String: Any] {
        [
            "id": item.id,
            "title": item.title,
            "status": item.status,
            "required": item.required,
            "is_passing": item.isPassing,
            "message": item.message,
        ]
    }

    private func recordingArtifactPayload(_ item: RecordingCommandArtifact) -> [String: Any] {
        [
            "artifact_id": item.id,
            "artifact_type": item.artifactType,
            "capture_status": item.captureStatus,
            "relative_path": item.path ?? "",
            "checksum": item.checksum ?? "",
            "degradation_reason": item.degradationReason ?? "",
        ]
    }

    private static func recordingSetupText(
        captureSystemAudio: Bool,
        captureMicrophoneAudio: Bool
    ) -> String {
        switch (captureSystemAudio, captureMicrophoneAudio) {
        case (true, true):
            return "Capture target: screen. System audio and microphone capture are requested through the recording command client."
        case (true, false):
            return "Capture target: screen. System audio capture is requested; microphone capture is not requested for this run."
        case (false, true):
            return "Capture target: screen. Microphone capture is requested; system audio capture is not requested for this run."
        case (false, false):
            return "Capture target: screen. Audio capture is not requested for this run; unavailable audio artifacts must stay missing with reasons."
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

        func placeWindow(placement: NativeAppWindowPlacement?, view: NSView) {
            guard !didPlaceWindow, !scheduledRetry, attempts < retryLimit else {
                return
            }

            scheduledRetry = true
            DispatchQueue.main.async { [weak self, weak view] in
                self?.attemptPlacement(placement: placement, view: view)
            }
        }

        private func attemptPlacement(placement: NativeAppWindowPlacement?, view: NSView?) {
            scheduledRetry = false
            guard !didPlaceWindow else {
                return
            }

            attempts += 1
            guard let window = view?.window else {
                retryIfNeeded(placement: placement, view: view)
                return
            }

            window.setFrameAutosaveName("meeting-assistant-main")
            window.makeKeyAndOrderFront(nil)
            if let placement, !placement.apply(to: window) {
                retryIfNeeded(placement: placement, view: view)
                return
            }
            didPlaceWindow = true
        }

        private func retryIfNeeded(placement: NativeAppWindowPlacement?, view: NSView?) {
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
    let refreshedDependencyResponse: DependencyCheckResponse?
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
    let captureSystemAudio: Bool
    let captureMicrophoneAudio: Bool
    let processingDefaultLanguage: String?
    let processingDefaultRuntime: ProcessingTranscriptRuntime?
    let processingResponseDelayNanoseconds: UInt64
    let initialSession: MeetingSessionSummary?

    init(
        dependencyResponse: DependencyCheckResponse,
        refreshedDependencyResponse: DependencyCheckResponse? = nil,
        recordingScript: FakeRecordingCommandClient.Script,
        processingTranscriptScript: ProcessingCommandFakeClient.TranscriptScript,
        processingSpeakerLabelsScript: ProcessingCommandFakeClient.SpeakerLabelsScript,
        processingClientMode: NativeProcessingClientMode = .fake,
        sessionID: String,
        transcriptInput: TranscriptReviewInput,
        exportScript: TranscriptActionFakeCommandClient.ExportScript,
        deleteScript: TranscriptActionFakeCommandClient.DeleteScript,
        exportDestinationPath: String?,
        workspaceDir: String?,
        captureSystemAudio: Bool? = nil,
        captureMicrophoneAudio: Bool? = nil,
        processingResponseDelayNanoseconds: UInt64 = 0,
        initialSession: MeetingSessionSummary? = nil
    ) {
        self.dependencyResponse = dependencyResponse
        self.refreshedDependencyResponse = refreshedDependencyResponse
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
        self.captureSystemAudio = captureSystemAudio ?? Self.captureAudioFlag(
            named: "MA_NATIVE_CAPTURE_SMOKE_SYSTEM_AUDIO",
            defaultValue: true
        )
        self.captureMicrophoneAudio = captureMicrophoneAudio ?? Self.captureAudioFlag(
            named: "MA_NATIVE_CAPTURE_SMOKE_MICROPHONE_AUDIO",
            defaultValue: true
        )
        self.processingDefaultLanguage = Self.processingDefaultLanguage()
        self.processingDefaultRuntime = Self.processingDefaultRuntime()
        self.processingResponseDelayNanoseconds = processingResponseDelayNanoseconds
        self.initialSession = initialSession
    }

    var readinessState: PermissionDependencyStatusState {
        PermissionDependencyStatusState.from(dependencyResponse)
    }

    private static func usesStaticDependencyFixture(_ environment: [String: String]) -> Bool {
        isNativeAppXCTestEnvironment(environment)
    }

    func makeDependencyCheckRunner(
        environment: [String: String] = ProcessInfo.processInfo.environment
    ) -> any DependencyCheckRunning {
        if Self.usesStaticDependencyFixture(environment) {
            return StaticDependencyCheckRunner(
                response: refreshedDependencyResponse ?? dependencyResponse
            )
        }
        return ProcessingCLIDependencyCheckRunner(environment: environment)
    }

    func initialReadinessState(
        environment: [String: String] = ProcessInfo.processInfo.environment
    ) -> PermissionDependencyStatusState {
        if Self.usesStaticDependencyFixture(environment) {
            return readinessState
        }
        return .idle
    }

    func autoRefreshPreflightOnAppear(
        environment: [String: String] = ProcessInfo.processInfo.environment
    ) -> Bool {
        !Self.usesStaticDependencyFixture(environment)
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
                    stopBehavior: .success(artifacts: Self.controlledRecordingArtifacts(environment: environment))
                ),
                sessionIDProvider: { sessionID },
                timestampProvider: { "2026-07-01T00:00:00Z" },
                requestIDProvider: { command in "app-controlled-\(command.rawValue)" }
            )
        case .appleScreenCaptureKit:
            return NativeRecordingCommandClient(
                permissionChecker: MacOSNativeCapturePermissionChecker(
                    screenRecordingProbe: CoreGraphicsScreenRecordingPermissionProbe(
                        requestAccessWhenDenied: true
                    ),
                    microphonePermissionProbe: AVFoundationMicrophonePermissionProbe(
                        requestAccessWhenUndetermined: true
                    )
                ),
                captureAdapter: AppleScreenCaptureKitNativeCaptureAdapter(),
                sessionIDProvider: Self.realCaptureSessionIDProvider(environment: environment),
                requestIDProvider: { command in "app-apple-screencapturekit-\(command.rawValue)" }
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
                speakerLabelsScript: processingSpeakerLabelsScript,
                responseDelayNanoseconds: processingResponseDelayNanoseconds
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

    func makeTranscriptActionOSClients(
        environment: [String: String] = ProcessInfo.processInfo.environment
    ) -> (clipboard: any TranscriptClipboardWriting, destinationSelector: any TranscriptExportDestinationSelecting) {
        switch NativeTranscriptActionOSClientMode.fromLaunchEnvironment(environment) {
        case .deterministic:
            return (
                TranscriptActionMemoryClipboard(),
                TranscriptActionStaticDestinationSelector(targetPath: exportDestinationPath)
            )
        case .system:
            return (
                TranscriptActionPasteboardClipboard(),
                TranscriptActionSavePanelDestinationSelector(
                    defaultDirectoryURL: Self.transcriptActionSavePanelDefaultDirectoryURL(environment: environment)
                )
            )
        }
    }

    private static func transcriptActionSavePanelDefaultDirectoryURL(
        environment: [String: String] = ProcessInfo.processInfo.environment
    ) -> URL? {
        guard isNativeAppXCTestEnvironment(environment),
              let rawPath = environment["MA_NATIVE_TRANSCRIPT_ACTION_SAVE_PANEL_DEFAULT_DIR"]?
                .trimmingCharacters(in: .whitespacesAndNewlines),
              !rawPath.isEmpty else {
            return nil
        }

        return URL(fileURLWithPath: rawPath, isDirectory: true)
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

        let fixture = smokeFixtureName(environment: environment, arguments: arguments)

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
        case "permission-unconfirmed":
            return NativeControlPlaneFixtureConfiguration(
                dependencyResponse: .unconfirmedScreenRecordingFixture,
                recordingScript: .success,
                processingTranscriptScript: .success(),
                processingSpeakerLabelsScript: .success(),
                processingClientMode: processingClientMode,
                sessionID: "session-app-ui-permission-unconfirmed",
                transcriptInput: .missingFixture,
                exportScript: .success(content: "Unconfirmed permission fixture transcript content."),
                deleteScript: .success(),
                exportDestinationPath: "/tmp/unconfirmed-permission-fixture-transcript.md",
                workspaceDir: nil
            )
        case "capture-ready-processing-blocked":
            return NativeControlPlaneFixtureConfiguration(
                dependencyResponse: .captureReadyProcessingBlockedFixture,
                recordingScript: .success,
                processingTranscriptScript: .success(),
                processingSpeakerLabelsScript: .success(),
                processingClientMode: processingClientMode,
                sessionID: "session-app-ui-capture-ready",
                transcriptInput: .missingFixture,
                exportScript: .success(content: "Capture-ready fixture transcript content."),
                deleteScript: .success(),
                exportDestinationPath: "/tmp/capture-ready-transcript.md",
                workspaceDir: nil
            )
        case "microphone-denied":
            return NativeControlPlaneFixtureConfiguration(
                dependencyResponse: .microphoneDeniedFixture,
                recordingScript: .success,
                processingTranscriptScript: .success(),
                processingSpeakerLabelsScript: .success(),
                processingClientMode: processingClientMode,
                sessionID: "session-app-ui-microphone-denied",
                transcriptInput: .missingFixture,
                exportScript: .success(content: "Microphone-denied fixture transcript content."),
                deleteScript: .success(),
                exportDestinationPath: "/tmp/microphone-denied-transcript.md",
                workspaceDir: nil
            )
        case "start-failure":
            return NativeControlPlaneFixtureConfiguration(
                dependencyResponse: .readyFixture,
                refreshedDependencyResponse: .screenRecordingDeniedFixture,
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
        case "saved-degraded":
            let sessionID = "session-app-ui-saved-degraded"
            return NativeControlPlaneFixtureConfiguration(
                dependencyResponse: .readyFixture,
                recordingScript: .successWithArtifacts([
                    RecordingCommandArtifact(
                        id: "artifact-app-degraded-screen",
                        sessionID: sessionID,
                        artifactType: "screen_video",
                        format: "mov",
                        path: "sessions/\(sessionID)/artifacts/screen_video.mov",
                        checksum: "sha256:3333333333333333333333333333333333333333333333333333333333333333"
                    ),
                    RecordingCommandArtifact(
                        id: "artifact-app-degraded-audio",
                        sessionID: sessionID,
                        artifactType: "mixed_audio",
                        format: "wav",
                        path: "sessions/\(sessionID)/artifacts/mixed_audio.wav",
                        captureStatus: "degraded",
                        degradationReason: "Meeting audio was recovered with limited quality.",
                        checksum: "sha256:4444444444444444444444444444444444444444444444444444444444444444"
                    ),
                    RecordingCommandArtifact(
                        id: "artifact-app-missing-microphone",
                        sessionID: sessionID,
                        artifactType: "microphone_audio",
                        format: "m4a",
                        captureStatus: "missing",
                        degradationReason: "Microphone audio could not be captured."
                    ),
                ]),
                processingTranscriptScript: .success(),
                processingSpeakerLabelsScript: .success(),
                processingClientMode: processingClientMode,
                sessionID: sessionID,
                transcriptInput: .missingFixture,
                exportScript: .success(content: "Saved degraded fixture transcript content."),
                deleteScript: .success(),
                exportDestinationPath: "/tmp/saved-degraded-transcript.md",
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
        case "transcript-long":
            return NativeControlPlaneFixtureConfiguration(
                dependencyResponse: .readyFixture,
                recordingScript: .success,
                processingTranscriptScript: .success(),
                processingSpeakerLabelsScript: .success(),
                processingClientMode: processingClientMode,
                sessionID: "session-app-ui-long-transcript",
                transcriptInput: .longReviewFixture,
                exportScript: .success(content: "Long transcript fixture copy content."),
                deleteScript: .success(),
                exportDestinationPath: "/tmp/transcript-long.md",
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
        case "processing-running":
            return NativeControlPlaneFixtureConfiguration(
                dependencyResponse: .readyFixture,
                recordingScript: .success,
                processingTranscriptScript: .success(
                    transcriptID: "transcript-app-processing-running",
                    artifactID: "artifact-app-processing-running",
                    segmentCount: 2
                ),
                processingSpeakerLabelsScript: .success(),
                processingClientMode: processingClientMode,
                sessionID: "session-app-ui-processing-running",
                transcriptInput: .missingFixture,
                exportScript: .success(content: "Processing running fixture copy content."),
                deleteScript: .success(),
                exportDestinationPath: "/tmp/processing-running.md",
                workspaceDir: nil,
                processingResponseDelayNanoseconds: 60_000_000_000
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
        case "transcript-missing-recoverable":
            let sessionID = "session-app-ui-transcript-missing-recoverable"
            return NativeControlPlaneFixtureConfiguration(
                dependencyResponse: .readyFixture,
                recordingScript: .success,
                processingTranscriptScript: .success(),
                processingSpeakerLabelsScript: .success(),
                processingClientMode: processingClientMode,
                sessionID: sessionID,
                transcriptInput: .missingFixture,
                exportScript: .success(content: "Regenerated transcript fixture copy content."),
                deleteScript: .success(),
                exportDestinationPath: "/tmp/transcript-missing-recoverable.md",
                workspaceDir: nil,
                initialSession: MeetingSessionSummary(
                    id: sessionID,
                    title: "Transcript recovery fixture",
                    status: "transcribed",
                    startedAt: "2026-07-01T11:00:00Z",
                    endedAt: "2026-07-01T11:20:00Z",
                    updatedAt: "2026-07-01T11:21:00Z",
                    durationLabel: "20:00",
                    artifactCount: 2,
                    hasTranscript: false,
                    hasSpeakerLabels: false,
                    hasProcessableAudio: true,
                    hasRegisteredTranscript: true
                )
            )
        case "transcript-missing-no-audio":
            let sessionID = "session-app-ui-transcript-missing-no-audio"
            return NativeControlPlaneFixtureConfiguration(
                dependencyResponse: .readyFixture,
                recordingScript: .success,
                processingTranscriptScript: .success(),
                processingSpeakerLabelsScript: .success(),
                processingClientMode: processingClientMode,
                sessionID: sessionID,
                transcriptInput: .missingFixture,
                exportScript: .success(content: "Unavailable transcript fixture copy content."),
                deleteScript: .success(),
                exportDestinationPath: "/tmp/transcript-missing-no-audio.md",
                workspaceDir: nil,
                initialSession: MeetingSessionSummary(
                    id: sessionID,
                    title: "Transcript without audio fixture",
                    status: "transcribed",
                    startedAt: "2026-07-01T12:00:00Z",
                    endedAt: "2026-07-01T12:20:00Z",
                    updatedAt: "2026-07-01T12:21:00Z",
                    durationLabel: "20:00",
                    artifactCount: 1,
                    hasTranscript: false,
                    hasSpeakerLabels: false,
                    hasProcessableAudio: false,
                    hasRegisteredTranscript: true
                )
            )
        case "transcript-load-failure":
            let sessionID = "session-app-ui-transcript-load-failure"
            return NativeControlPlaneFixtureConfiguration(
                dependencyResponse: .readyFixture,
                recordingScript: .success,
                processingTranscriptScript: .success(),
                processingSpeakerLabelsScript: .success(),
                processingClientMode: processingClientMode,
                sessionID: sessionID,
                transcriptInput: .missingFixture,
                exportScript: .success(content: "Reloaded transcript fixture copy content."),
                deleteScript: .success(),
                exportDestinationPath: "/tmp/transcript-load-failure.md",
                workspaceDir: nil,
                initialSession: MeetingSessionSummary(
                    id: sessionID,
                    title: "Unreadable transcript fixture",
                    status: "transcribed",
                    startedAt: "2026-07-01T10:00:00Z",
                    endedAt: "2026-07-01T10:20:00Z",
                    updatedAt: "2026-07-01T10:21:00Z",
                    durationLabel: "20:00",
                    artifactCount: 3,
                    hasTranscript: true,
                    hasSpeakerLabels: false,
                    hasProcessableAudio: true
                )
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

    private static func smokeFixtureName(
        environment: [String: String],
        arguments: [String]
    ) -> String {
        #if DEBUG
        guard isNativeAppXCTestEnvironment(environment) else {
            return "blocked"
        }
        return environment["MA_NATIVE_APP_SMOKE_FIXTURE"]
            ?? argumentValue(named: "--ma-native-fixture", in: arguments)
            ?? "blocked"
        #else
        return "blocked"
        #endif
    }

    private static func captureAudioFlag(
        named name: String,
        defaultValue: Bool,
        environment: [String: String] = ProcessInfo.processInfo.environment
    ) -> Bool {
        switch environment[name]?.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() {
        case "1", "true", "yes":
            return true
        case "0", "false", "no":
            return false
        default:
            return defaultValue
        }
    }

    private static func processingDefaultLanguage(
        environment: [String: String] = ProcessInfo.processInfo.environment
    ) -> String? {
        let value = environment["MA_NATIVE_PROCESSING_LANGUAGE"]?
            .trimmingCharacters(in: .whitespacesAndNewlines)
        if value?.isEmpty == false {
            return value
        }
        return isExplicitProcessingRuntimeConfigured(environment) ? "zh" : nil
    }

    private static func processingDefaultRuntime(
        environment: [String: String] = ProcessInfo.processInfo.environment
    ) -> ProcessingTranscriptRuntime? {
        switch environment["MA_NATIVE_PROCESSING_RUNTIME"]?
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .lowercased() {
        case "whisper_cpp", "whisper-cpp":
            return .whisperCpp
        default:
            return nil
        }
    }

    private static func isRealRuntimeProcessingSmokeEnabled(_ environment: [String: String]) -> Bool {
        guard isNativeAppXCTestEnvironment(environment) else {
            return false
        }
        switch environment["MA_NATIVE_APP_REAL_RUNTIME_SMOKE"]?
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .lowercased() {
        case "1", "true", "yes":
            return true
        default:
            return false
        }
    }

    private static func isExplicitProcessingRuntimeConfigured(_ environment: [String: String]) -> Bool {
        environment["MA_NATIVE_PROCESSING_RUNTIME"]?
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .isEmpty == false
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

    private static func realCaptureSessionIDProvider(
        environment: [String: String]
    ) -> @Sendable () -> String {
        let configuredSessionID = environment["MA_NATIVE_RECORDING_SESSION_ID"]?
            .trimmingCharacters(in: .whitespacesAndNewlines)
        if let configuredSessionID, !configuredSessionID.isEmpty {
            return { configuredSessionID }
        }
        return { "session-\(UUID().uuidString.lowercased())" }
    }

    private static func controlledRecordingArtifacts(
        environment: [String: String] = ProcessInfo.processInfo.environment
    ) -> [NativeCaptureArtifactResult] {
        var artifacts: [NativeCaptureArtifactResult] = [
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
        ]
        if captureAudioFlag(
            named: "MA_NATIVE_RECORDING_CONTROLLED_MIXED_AUDIO",
            defaultValue: false,
            environment: environment
        ) {
            artifacts.append(
                .available(
                    .mixedAudio,
                    format: "wav",
                    data: controlledMixedAudioWAVData()
                )
            )
        } else {
            artifacts.append(.missing(
                .mixedAudio,
                reason: "mixed audio missing because controlled app fixture lacks one input"
            ))
        }
        return artifacts
    }

    private static func controlledMixedAudioWAVData() -> Data {
        var samples = Data()
        for index in 0..<2_400 {
            let value = Int16((((index + 17) % 96) - 48) * 96)
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
}

private enum NativeRecordingClientMode {
    case fake
    case controlled
    case appleScreenCaptureKit

    static func fromLaunchEnvironment(
        _ environment: [String: String],
        workspaceURL: URL?
    ) -> NativeRecordingClientMode {
        let rawValue = environment["MA_NATIVE_RECORDING_CLIENT"]?
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .lowercased()
        guard let rawValue else {
            return defaultRecordingClientMode(environment)
        }
        switch rawValue {
        case "fake":
            return isRecordingClientTestHookAllowed(environment) ? .fake : defaultRecordingClientMode(environment)
        case "controlled":
            guard workspaceURL != nil,
                  isRecordingClientTestHookAllowed(environment) else {
                return defaultRecordingClientMode(environment)
            }
            return .controlled
        case "apple_screencapturekit", "apple-screencapturekit":
            if isNativeAppXCTestEnvironment(environment),
               (workspaceURL == nil || !isRealNativeCaptureSmokeEnabled(environment)) {
                return .fake
            }
            return .appleScreenCaptureKit
        default:
            return defaultRecordingClientMode(environment)
        }
    }

    private static func defaultRecordingClientMode(_ environment: [String: String]) -> NativeRecordingClientMode {
        isNativeAppXCTestEnvironment(environment) ? .fake : .appleScreenCaptureKit
    }

    private static func isRecordingClientTestHookAllowed(_ environment: [String: String]) -> Bool {
        #if DEBUG
        return isNativeAppXCTestEnvironment(environment)
        #else
        return false
        #endif
    }

    private static func isRealNativeCaptureSmokeEnabled(_ environment: [String: String]) -> Bool {
        switch environment["MA_NATIVE_CAPTURE_SMOKE"]?.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() {
        case "1", "true", "yes":
            return true
        default:
            return false
        }
    }
}

private enum NativeProcessingClientMode {
    case fake
    case process

    static func fromLaunchEnvironment(_ environment: [String: String]) -> NativeProcessingClientMode {
        let rawValue = environment["MA_NATIVE_PROCESSING_CLIENT"]?
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .lowercased()
        switch rawValue {
        case .some("fake"):
            return isProcessClientTestHookAllowed(environment) ? .fake : .process
        case .some("process"):
            return .process
        default:
            return isNativeAppXCTestEnvironment(environment) ? .fake : .process
        }
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
        switch rawValue {
        case .some("fake"):
            return isTranscriptActionClientTestHookAllowed(environment) ? .fake : .process
        case .some("process"):
            return .process
        default:
            return isNativeAppXCTestEnvironment(environment) ? .fake : .process
        }
    }

    private static func isTranscriptActionClientTestHookAllowed(_ environment: [String: String]) -> Bool {
        #if DEBUG
        return isNativeAppXCTestEnvironment(environment)
        #else
        return false
        #endif
    }
}

private enum NativeTranscriptActionOSClientMode {
    case deterministic
    case system

    static func fromLaunchEnvironment(_ environment: [String: String]) -> NativeTranscriptActionOSClientMode {
        let rawValue = environment["MA_NATIVE_TRANSCRIPT_ACTION_OS_CLIENT"]?
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .lowercased()
        switch rawValue {
        case .some("deterministic"):
            return isNativeAppXCTestEnvironment(environment) ? .deterministic : .system
        case .some("system"):
            return .system
        default:
            break
        }

        if isNativeAppXCTestEnvironment(environment) {
            return .deterministic
        }
        return .system
    }
}

private func isNativeAppXCTestEnvironment(_ environment: [String: String]) -> Bool {
    #if DEBUG
    return environment["MA_NATIVE_APP_XCTEST"] == "1"
        || environment["XCTestConfigurationFilePath"] != nil
        || environment["XCTestBundlePath"] != nil
        || environment["XCInjectBundleInto"] != nil
    #else
    return false
    #endif
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

    static let longReviewFixture = TranscriptReviewInput(
        sessionTitle: "Long Transcript Fixture",
        transcript: TranscriptReviewTranscript(
            id: "transcript-app-long-fixture",
            sessionID: "session-app-ui-long-transcript",
            sourceArtifactID: "artifact-normalized-audio",
            status: "succeeded",
            segments: (0..<500).map { index in
                TranscriptReviewSegment(
                    segmentID: "seg-long-\(index)",
                    startMS: index * 4_000,
                    endMS: (index + 1) * 4_000,
                    text: "Long transcript segment \(index + 1) remains readable while the action toolbar stays available.",
                    speakerLabel: index.isMultiple(of: 2) ? "SPEAKER_01" : "SPEAKER_02"
                )
            }
        ),
        speakerLabelsDegradationReason: "speaker labels are omitted in the long transcript rendering fixture"
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
                id: "platform.os",
                status: "supported",
                required: true,
                ok: true,
                message: "macOS is supported."
            ),
            DependencyCheckItem(
                id: "platform.macos_version",
                status: "supported",
                required: true,
                ok: true,
                message: "The macOS version is supported."
            ),
            DependencyCheckItem(
                id: "platform.cpu_arch",
                status: "supported",
                required: true,
                ok: true,
                message: "The CPU architecture is supported."
            ),
            DependencyCheckItem(
                id: "workspace.writable",
                status: "writable",
                required: true,
                ok: true,
                message: "The workspace is writable."
            ),
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

    static let unconfirmedScreenRecordingFixture = DependencyCheckResponse(
        ok: true,
        requestID: "local-app-permission-unconfirmed",
        checks: readyFixture.checks.map { check in
            guard check.id == "permission.screen_recording" else {
                return check
            }
            return DependencyCheckItem(
                id: check.id,
                status: "unknown",
                required: check.required,
                ok: true,
                message: "Screen Recording permission will be confirmed when recording starts."
            )
        }
    )

    static let captureReadyProcessingBlockedFixture = DependencyCheckResponse(
        ok: false,
        requestID: "local-app-capture-ready-processing-blocked",
        code: "dependency_missing",
        message: "Local transcript tools need attention.",
        checks: readyFixture.checks.map { check in
            guard check.id == "media_tool.ffmpeg" else {
                return check
            }
            return DependencyCheckItem(
                id: check.id,
                status: "missing",
                required: true,
                ok: false,
                message: "FFmpeg executable was not found."
            )
        }
    )

    static let microphoneDeniedFixture = DependencyCheckResponse(
        ok: false,
        requestID: "local-app-microphone-denied",
        code: "permission_denied",
        message: "Microphone permission is denied.",
        checks: readyFixture.checks.map { check in
            guard check.id == "permission.microphone" else {
                return check
            }
            return DependencyCheckItem(
                id: check.id,
                status: "denied",
                required: true,
                ok: false,
                message: "Microphone permission is denied."
            )
        }
    )

    static let screenRecordingDeniedFixture = DependencyCheckResponse(
        ok: false,
        requestID: "local-app-screen-recording-denied",
        code: "permission_denied",
        message: "Screen Recording permission is denied.",
        checks: readyFixture.checks.map { check in
            guard check.id == "permission.screen_recording" else {
                return check
            }
            return DependencyCheckItem(
                id: check.id,
                status: "denied",
                required: check.required,
                ok: false,
                message: "Screen Recording permission is denied. Open System Settings to grant access."
            )
        }
    )
}
