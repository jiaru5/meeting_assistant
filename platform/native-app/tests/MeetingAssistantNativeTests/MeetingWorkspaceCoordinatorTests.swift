import CryptoKit
import Foundation
import Testing
@testable import MeetingAssistantNative

@Suite("Meeting workspace coordinator")
@MainActor
struct MeetingWorkspaceCoordinatorTests {
    @Test
    func startsAtMeetingsAndRoutesToOneTaskAtATime() {
        let coordinator = makeCoordinator()

        #expect(coordinator.route == .meetings)
        #expect(coordinator.currentSession == nil)
        #expect(coordinator.navigationIsLocked == false)

        coordinator.beginNewRecording()

        #expect(coordinator.route == .newRecording)
        #expect(coordinator.currentSession == nil)
    }

    @Test
    func recordingLifecycleKeepsOneCurrentSessionAndProjectsSavedAudio() {
        let coordinator = makeCoordinator()
        coordinator.recordingDraft.title = "Weekly planning"
        coordinator.recordingWillStart()

        #expect(coordinator.navigationIsLocked)
        coordinator.navigate(to: .diagnostics)
        #expect(coordinator.route == .meetings)

        coordinator.recordingDidStart(
            sessionID: "session-current",
            now: Date(timeIntervalSince1970: 1_000)
        )

        #expect(coordinator.route == .meetingDetail)
        #expect(coordinator.currentSession?.id == "session-current")
        #expect(coordinator.currentMeetingTitle == "Weekly planning")
        #expect(coordinator.activity == .recording)

        coordinator.recordingDidSave(
            .recorded(
                sessionID: "session-current",
                artifacts: [
                    RecordingCommandArtifact(
                        id: "artifact-screen",
                        sessionID: "session-current",
                        artifactType: "screen_video",
                        path: "artifacts/screen_video.mov",
                        captureStatus: "available",
                        checksum: "sha256:1111111111111111111111111111111111111111111111111111111111111111"
                    ),
                    RecordingCommandArtifact(
                        id: "artifact-audio",
                        sessionID: "session-current",
                        artifactType: "mixed_audio",
                        path: "artifacts/mixed_audio.wav",
                        captureStatus: "available",
                        checksum: "sha256:2222222222222222222222222222222222222222222222222222222222222222"
                    ),
                ]
            ),
            now: Date(timeIntervalSince1970: 1_065)
        )

        #expect(coordinator.activity == .idle)
        #expect(coordinator.currentSession?.status == "recorded")
        #expect(coordinator.currentSession?.artifactCount == 2)
        #expect(coordinator.currentSession?.hasProcessableAudio == true)
        #expect(coordinator.currentSession?.durationLabel == "01:05")
        #expect(coordinator.recentSessions.first?.id == "session-current")
    }

    @Test
    func openingAnotherMeetingReplacesCurrentIdentityAndClearsTransientErrors() async {
        let first = summary(id: "session-first", title: "First", hasTranscript: true)
        let second = summary(id: "session-second", title: "Second", hasTranscript: false)
        let coordinator = makeCoordinator(initialSessions: [first, second])

        await coordinator.open(first)
        coordinator.transcriptDidFailToLoad(TestFailure())
        #expect(coordinator.transcriptLoadError != nil)

        await coordinator.open(second)

        #expect(coordinator.currentSession?.id == "session-second")
        #expect(coordinator.currentMeetingTitle == "Second")
        #expect(coordinator.transcriptLoadError == nil)
        #expect(coordinator.route == .meetingDetail)
    }

    @Test
    func openingWorkspaceMeetingRunsStrictChecksumValidationOffTheMainThread() async throws {
        let workspace = try makeDeletionWorkspace()
        defer { try? FileManager.default.removeItem(at: workspace) }
        let sessionID = "session-strict-selection"
        let artifactData = Data("selected meeting audio payload".utf8)
        let checksum = "sha256:" + SHA256.hash(data: artifactData).map {
            String(format: "%02x", $0)
        }.joined()
        try writeDeletionWorkspaceSession(
            workspace: workspace,
            sessionID: sessionID,
            title: "Strict selection",
            status: "recorded",
            artifacts: [[
                "id": "artifact-selected-audio",
                "session_id": sessionID,
                "artifact_type": "mixed_audio",
                "path": "artifacts/mixed_audio.wav",
                "format": "wav",
                "capture_status": "available",
                "checksum": checksum,
                "created_at": "2026-07-01T09:00:00Z",
            ]]
        )
        let artifactURL = workspace
            .appendingPathComponent("sessions/\(sessionID)/artifacts", isDirectory: true)
            .appendingPathComponent("mixed_audio.wav")
        try FileManager.default.createDirectory(
            at: artifactURL.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        try artifactData.write(to: artifactURL)
        let checksumProbe = CoordinatorChecksumProbe()
        let repository = MeetingSessionWorkspaceRepository { url in
            checksumProbe.checksum(of: url)
        }
        let coordinator = makeCoordinator(
            workspaceURL: workspace,
            repository: repository
        )

        coordinator.refreshSessions()

        #expect(checksumProbe.paths.isEmpty)
        let projected = try #require(coordinator.recentSessions.first)
        #expect(projected.hasProcessableAudio)

        let selected = await coordinator.open(projected)

        #expect(selected?.id == sessionID)
        #expect(selected?.hasProcessableAudio == true)
        #expect(coordinator.currentSession == selected)
        #expect(checksumProbe.paths == [artifactURL.path])
        #expect(checksumProbe.mainThreadObservations == [false])
    }

    @Test
    func strictSelectionFailureKeepsUnverifiedMeetingOutOfCurrentSession() async throws {
        let workspace = try makeDeletionWorkspace()
        defer { try? FileManager.default.removeItem(at: workspace) }
        let sessionID = "session-invalid-selection"
        try writeDeletionWorkspaceSession(
            workspace: workspace,
            sessionID: sessionID,
            title: "Invalid selection",
            status: "archived",
            artifacts: []
        )
        let projected = summary(
            id: sessionID,
            title: "Unverified projection",
            hasTranscript: false
        )
        let coordinator = makeCoordinator(
            workspaceURL: workspace,
            initialSessions: [projected]
        )

        let selected = await coordinator.open(projected)

        #expect(selected == nil)
        #expect(coordinator.currentSession == nil)
        #expect(coordinator.route == .meetings)
        #expect(coordinator.workspaceError?.contains("could not safely open") == true)
        #expect(coordinator.workspaceTechnicalError?.contains("archived") == true)
    }

    @Test
    func transcriptFailurePersistsAcrossDiagnosticsWithoutExposingTechnicalPath() async {
        let meeting = summary(id: "session-broken", title: "Broken", hasTranscript: true)
        let coordinator = makeCoordinator(initialSessions: [meeting])
        await coordinator.open(meeting)
        coordinator.transcriptDidFailToLoad(PathFailure())

        #expect(coordinator.transcriptLoadError?.contains("/Users/jerry") == false)
        #expect(coordinator.transcriptTechnicalError?.contains("/Users/jerry/Meetings/broken.json") == true)

        coordinator.navigate(to: .diagnostics)
        coordinator.navigate(to: .meetingDetail)

        #expect(coordinator.transcriptLoadError != nil)
        #expect(coordinator.currentSession?.id == "session-broken")
    }

    @Test
    func unavailableTranscriptExplainsRegenerationWhenSavedAudioExists() async {
        let meeting = summary(
            id: "session-transcribed-recovery",
            title: "Recovery",
            status: "transcribed",
            hasTranscript: false
        )
        let coordinator = makeCoordinator(initialSessions: [meeting])
        await coordinator.open(meeting)

        coordinator.transcriptDidFailToLoad(TestFailure())

        #expect(coordinator.transcriptLoadError?.contains("original recording is still safe") == true)
        #expect(coordinator.transcriptLoadError?.contains("Regenerate the transcript from the saved meeting audio") == true)
        #expect(coordinator.transcriptLoadError != nil)
    }

    @Test
    func unavailableTranscriptWithoutAudioExplainsFailClosedDeletePath() async {
        let meeting = summary(
            id: "session-transcribed-no-audio",
            title: "No audio",
            status: "transcribed",
            hasTranscript: false,
            hasProcessableAudio: false
        )
        let coordinator = makeCoordinator(initialSessions: [meeting])
        await coordinator.open(meeting)

        coordinator.transcriptDidFailToLoad(TestFailure())

        #expect(coordinator.transcriptLoadError?.contains("no processable audio for regeneration") == true)
        #expect(coordinator.transcriptLoadError?.contains("delete the meeting") == true)
        #expect(coordinator.transcriptLoadError != nil)
    }

    @Test
    func transcriptCompletionOnlyUpdatesTheCurrentSession() async {
        let first = summary(id: "session-first", title: "First", hasTranscript: false)
        let second = summary(id: "session-second", title: "Second", hasTranscript: false)
        let coordinator = makeCoordinator(initialSessions: [first, second])
        await coordinator.open(second)

        coordinator.transcriptDidLoad(for: "session-first")
        #expect(coordinator.currentSession?.hasTranscript == false)

        coordinator.transcriptDidLoad(for: "session-second")
        #expect(coordinator.currentSession?.hasTranscript == true)
        #expect(coordinator.currentSession?.status == "transcribed")
    }

    @Test
    func successfulDeletionClearsEveryCurrentSessionSurfaceAndReturnsHome() async {
        let meeting = summary(id: "session-delete", title: "Delete me", hasTranscript: true)
        let coordinator = makeCoordinator(initialSessions: [meeting])
        await coordinator.open(meeting)
        coordinator.processingWillStart()

        coordinator.deletionDidFinish(sessionID: "session-delete")

        #expect(coordinator.currentSession == nil)
        #expect(coordinator.recentSessions.isEmpty)
        #expect(coordinator.route == .meetings)
        #expect(coordinator.activity == .idle)
        #expect(coordinator.transcriptLoadError == nil)
        #expect(coordinator.notice?.contains("Meeting deleted") == true)
    }

    @Test
    func deletionLocksNavigationUntilSuccessOrFailure() async {
        let meeting = summary(id: "session-delete", title: "Delete me", hasTranscript: true)
        let coordinator = makeCoordinator(initialSessions: [meeting])
        await coordinator.open(meeting)

        coordinator.deletionWillStart()

        #expect(coordinator.activity == .deleting)
        #expect(coordinator.navigationIsLocked)
        coordinator.navigate(to: .diagnostics)
        #expect(coordinator.route == .meetingDetail)

        coordinator.deletionDidFail()

        #expect(coordinator.activity == .idle)
        #expect(coordinator.navigationIsLocked == false)
        #expect(coordinator.currentSession?.id == "session-delete")
    }

    @Test
    func partialDeleteRebindsTheSurvivingSessionFromTheFreshWorkspaceProjection() async throws {
        let workspace = try makeDeletionWorkspace()
        defer { try? FileManager.default.removeItem(at: workspace) }
        try writeDeletionWorkspaceSession(
            workspace: workspace,
            sessionID: "session-partial",
            title: "Fresh partial result",
            status: "recorded",
            artifacts: []
        )
        let stale = summary(
            id: "session-partial",
            title: "Stale transcript",
            hasTranscript: true
        )
        let coordinator = makeCoordinator(
            workspaceURL: workspace,
            initialSessions: [stale]
        )
        await coordinator.open(stale)
        coordinator.deletionWillStart()

        let reconciliation = await coordinator.reconcileDeletionAttempt(
            sessionID: stale.id,
            commandReportedDeletion: false
        )

        guard case .sessionPresent(let refreshed) = reconciliation else {
            Issue.record("Expected the surviving session to be rebound.")
            return
        }
        #expect(refreshed.title == "Fresh partial result")
        #expect(refreshed.artifactCount == 0)
        #expect(refreshed.hasTranscript == false)
        #expect(refreshed.hasProcessableAudio == false)
        #expect(coordinator.currentSession == refreshed)
        #expect(coordinator.recentSessions.first == refreshed)
        #expect(coordinator.route == .meetingDetail)
        #expect(coordinator.activity == .idle)
        #expect(coordinator.workspaceError == nil)
        #expect(coordinator.notice == nil)
    }

    @Test
    func failedDeleteWithMissingSessionClearsStaleProjectionWithoutClaimingSuccess() async throws {
        let workspace = try makeDeletionWorkspace()
        defer { try? FileManager.default.removeItem(at: workspace) }
        let stale = summary(
            id: "session-disappeared",
            title: "Stale transcript",
            hasTranscript: true
        )
        let coordinator = makeCoordinator(
            workspaceURL: workspace,
            initialSessions: [stale]
        )
        await coordinator.open(stale)
        coordinator.deletionWillStart()

        let reconciliation = await coordinator.reconcileDeletionAttempt(
            sessionID: stale.id,
            commandReportedDeletion: false
        )

        #expect(reconciliation == .sessionMissing)
        #expect(coordinator.currentSession == nil)
        #expect(coordinator.recentSessions.contains { $0.id == stale.id } == false)
        #expect(coordinator.route == .meetings)
        #expect(coordinator.activity == .idle)
        #expect(coordinator.workspaceError?.contains("no deletion success was assumed") == true)
        #expect(coordinator.notice == nil)
    }

    @Test
    func unreadableWorkspaceAfterDeleteClearsStaleProjectionAndKeepsPersistentFailure() async throws {
        let workspace = FileManager.default.temporaryDirectory
            .appendingPathComponent("ma-delete-workspace-file-\(UUID().uuidString)")
        try Data("not a workspace directory".utf8).write(to: workspace)
        defer { try? FileManager.default.removeItem(at: workspace) }
        let stale = summary(
            id: "session-unreadable",
            title: "Stale transcript",
            hasTranscript: true
        )
        let coordinator = makeCoordinator(
            workspaceURL: workspace,
            initialSessions: [stale]
        )
        await coordinator.open(stale)
        coordinator.deletionWillStart()

        let reconciliation = await coordinator.reconcileDeletionAttempt(
            sessionID: stale.id,
            commandReportedDeletion: true
        )

        #expect(reconciliation == .workspaceUnreadable)
        #expect(coordinator.currentSession == nil)
        #expect(coordinator.recentSessions.contains { $0.id == stale.id } == false)
        #expect(coordinator.route == .meetings)
        #expect(coordinator.activity == .idle)
        #expect(coordinator.workspaceError?.contains("could not refresh the workspace") == true)
        #expect(coordinator.workspaceTechnicalError?.contains(workspace.path) == true)
        #expect(coordinator.notice == nil)
    }

    @Test
    func activeSessionSaveFailureKeepsRecoveryTaskLocked() {
        let coordinator = makeCoordinator()
        coordinator.recordingDraft.title = "Save recovery"
        coordinator.recordingDidStart(sessionID: "session-save-recovery")

        coordinator.recordingDidFail(hasActiveSession: true)

        #expect(coordinator.activity == .saveNeedsAttention)
        #expect(coordinator.navigationIsLocked)
        #expect(coordinator.currentSession?.id == "session-save-recovery")
        coordinator.beginNewRecording()
        #expect(coordinator.currentSession?.id == "session-save-recovery")
        #expect(coordinator.route == .meetingDetail)
    }

    @Test
    func degradedPlaceholderWithoutManagedFileFactsDoesNotEnableProcessing() {
        let coordinator = makeCoordinator()
        coordinator.recordingDidStart(sessionID: "session-placeholder")

        coordinator.recordingDidSave(
            .recorded(
                sessionID: "session-placeholder",
                artifacts: [
                    RecordingCommandArtifact(
                        id: "artifact-placeholder",
                        sessionID: "session-placeholder",
                        artifactType: "mixed_audio",
                        path: "artifacts/mixed_audio.wav",
                        captureStatus: "degraded",
                        degradationReason: "Audio was not produced."
                    ),
                ]
            )
        )

        #expect(coordinator.currentSession?.hasProcessableAudio == false)
    }

    private func makeCoordinator(
        workspaceURL: URL? = nil,
        initialSessions: [MeetingSessionSummary] = [],
        repository: MeetingSessionWorkspaceRepository = MeetingSessionWorkspaceRepository()
    ) -> MeetingWorkspaceCoordinator {
        MeetingWorkspaceCoordinator(
            workspaceURL: workspaceURL
                ?? FileManager.default.temporaryDirectory
                    .appendingPathComponent("meeting-coordinator-tests-\(UUID().uuidString)"),
            repository: repository,
            initialSessions: initialSessions
        )
    }

    private func summary(
        id: String,
        title: String,
        status: String? = nil,
        hasTranscript: Bool,
        hasProcessableAudio: Bool = true
    ) -> MeetingSessionSummary {
        MeetingSessionSummary(
            id: id,
            title: title,
            status: status ?? (hasTranscript ? "transcribed" : "recorded"),
            startedAt: "2026-07-01T09:00:00Z",
            endedAt: "2026-07-01T09:30:00Z",
            updatedAt: "2026-07-01T09:31:00Z",
            durationLabel: "30:00",
            artifactCount: hasTranscript ? 3 : 2,
            hasTranscript: hasTranscript,
            hasSpeakerLabels: hasTranscript,
            hasProcessableAudio: hasProcessableAudio
        )
    }

    private func makeDeletionWorkspace() throws -> URL {
        let workspace = FileManager.default.temporaryDirectory
            .appendingPathComponent("ma-delete-reconcile-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(
            at: workspace.appendingPathComponent("sessions", isDirectory: true),
            withIntermediateDirectories: true
        )
        return workspace
    }

    private func writeDeletionWorkspaceSession(
        workspace: URL,
        sessionID: String,
        title: String,
        status: String,
        artifacts: [[String: Any]]
    ) throws {
        let sessionRoot = workspace
            .appendingPathComponent("sessions", isDirectory: true)
            .appendingPathComponent(sessionID, isDirectory: true)
        try FileManager.default.createDirectory(
            at: sessionRoot,
            withIntermediateDirectories: true
        )
        let payload: [String: Any] = [
            "id": sessionID,
            "title": title,
            "status": status,
            "started_at": "2026-07-01T09:00:00Z",
            "ended_at": "2026-07-01T09:30:00Z",
            "updated_at": "2026-07-01T09:31:00Z",
            "artifacts": artifacts,
        ]
        let data = try JSONSerialization.data(
            withJSONObject: payload,
            options: [.prettyPrinted, .sortedKeys]
        )
        try data.write(to: sessionRoot.appendingPathComponent("session.json"))
    }
}

private final class CoordinatorChecksumProbe: @unchecked Sendable {
    private let lock = NSLock()
    private var capturedPaths: [String] = []
    private var capturedMainThreadObservations: [Bool] = []

    var paths: [String] {
        lock.lock()
        defer { lock.unlock() }
        return capturedPaths
    }

    var mainThreadObservations: [Bool] {
        lock.lock()
        defer { lock.unlock() }
        return capturedMainThreadObservations
    }

    func checksum(of url: URL) -> String? {
        lock.lock()
        capturedPaths.append(url.path)
        capturedMainThreadObservations.append(Thread.isMainThread)
        lock.unlock()

        guard let data = try? Data(contentsOf: url) else {
            return nil
        }
        let digest = SHA256.hash(data: data)
        return "sha256:" + digest.map { String(format: "%02x", $0) }.joined()
    }
}

private struct TestFailure: Error {}

private struct PathFailure: LocalizedError {
    var errorDescription: String? {
        "Transcript could not be read at /Users/jerry/Meetings/broken.json"
    }
}
