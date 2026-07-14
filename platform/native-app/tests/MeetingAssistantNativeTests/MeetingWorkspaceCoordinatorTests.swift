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
        coordinator.recordingDraft.title = "Previous meeting"
        coordinator.recordingDraft.captureSystemAudio = false
        coordinator.recordingDraft.captureMicrophoneAudio = true

        #expect(coordinator.route == .meetings)
        #expect(coordinator.currentSession == nil)
        #expect(coordinator.navigationIsLocked == false)

        coordinator.beginNewRecording()

        #expect(coordinator.route == .newRecording)
        #expect(coordinator.currentSession == nil)
        #expect(coordinator.recordingDraft.title.isEmpty)
        #expect(coordinator.recordingDraft.captureSystemAudio == false)
        #expect(coordinator.recordingDraft.captureMicrophoneAudio)
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
                        id: "artifact-system",
                        sessionID: "session-current",
                        artifactType: "system_audio",
                        path: "artifacts/system_audio.wav",
                        captureStatus: "degraded",
                        degradationReason: "System audio was recovered from the partial save.",
                        checksum: "sha256:3333333333333333333333333333333333333333333333333333333333333333"
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
        #expect(coordinator.currentSession?.artifactCount == 3)
        #expect(coordinator.currentSession?.hasProcessableAudio == true)
        #expect(coordinator.currentSession?.processableAudioSources == [
            MeetingProcessableAudioSource(id: "artifact-audio", artifactType: "mixed_audio"),
        ])
        #expect(coordinator.selectedProcessingAudioSourceID == "artifact-audio")
        #expect(coordinator.currentSession?.durationLabel == "01:05")
        #expect(coordinator.recentSessions.first?.id == "session-current")
    }

    @Test
    func openingAnotherMeetingReplacesCurrentIdentityAndClearsTransientErrors() async throws {
        let first = summary(id: "session-first", title: "First", hasTranscript: true)
        let second = summary(id: "session-second", title: "Second", hasTranscript: false)
        let coordinator = makeCoordinator(initialSessions: [first, second])

        await coordinator.open(first)
        let firstLoad = try #require(coordinator.transcriptWillLoad(for: first.id))
        coordinator.transcriptDidFailToLoad(TestFailure(), token: firstLoad)
        #expect(coordinator.transcriptLoadError != nil)

        await coordinator.open(second)

        #expect(coordinator.currentSession?.id == "session-second")
        #expect(coordinator.currentMeetingTitle == "Second")
        #expect(coordinator.transcriptLoadError == nil)
        #expect(coordinator.route == .meetingDetail)
    }

    @Test
    func processingAudioSelectionUsesProviderCompatiblePriorityAndCommandSource() async {
        let first = summary(
            id: "session-first",
            title: "First",
            hasTranscript: false,
            processableAudioSources: [
                MeetingProcessableAudioSource(id: "artifact-system", artifactType: "system_audio"),
                MeetingProcessableAudioSource(id: "artifact-mixed", artifactType: "mixed_audio"),
            ]
        )
        let second = summary(
            id: "session-second",
            title: "Second",
            hasTranscript: false,
            processableAudioSources: [
                MeetingProcessableAudioSource(id: "artifact-system-2", artifactType: "system_audio"),
                MeetingProcessableAudioSource(
                    id: "artifact-normalized",
                    artifactType: "normalized_audio"
                ),
            ]
        )
        let fallback = summary(
            id: "session-fallback",
            title: "Fallback",
            hasTranscript: false,
            processableAudioSources: [
                MeetingProcessableAudioSource(id: "artifact-system-3", artifactType: "system_audio"),
                MeetingProcessableAudioSource(id: "artifact-microphone", artifactType: "microphone_audio"),
            ]
        )
        let coordinator = makeCoordinator(initialSessions: [first, second, fallback])

        await coordinator.open(first)
        #expect(coordinator.selectedProcessingAudioSourceID == "artifact-mixed")
        #expect(coordinator.selectableProcessingAudioSources.map(\.id) == ["artifact-mixed"])
        #expect(!coordinator.selectProcessingAudioSource(id: "artifact-system"))
        #expect(coordinator.processingRequestSourceArtifactID == nil)

        await coordinator.open(second)
        #expect(coordinator.selectableProcessingAudioSources.map(\.id) == ["artifact-normalized"])
        #expect(coordinator.selectedProcessingAudioSourceID == "artifact-normalized")
        #expect(coordinator.processingRequestSourceArtifactID == "artifact-normalized")

        await coordinator.open(fallback)
        #expect(coordinator.selectableProcessingAudioSources.map(\.id) == [
            "artifact-system-3",
            "artifact-microphone",
        ])
        #expect(coordinator.selectedProcessingAudioSourceID == "artifact-system-3")
        #expect(coordinator.processingRequestSourceArtifactID == "artifact-system-3")
        #expect(coordinator.selectProcessingAudioSource(id: "artifact-microphone"))
        #expect(coordinator.processingRequestSourceArtifactID == "artifact-microphone")

        await coordinator.open(first)
        await coordinator.open(fallback)
        #expect(coordinator.selectedProcessingAudioSourceID == "artifact-microphone")
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

        await coordinator.refreshSessions()

        #expect(checksumProbe.paths.isEmpty)
        let projected = try #require(coordinator.recentSessions.first)
        #expect(projected.hasProcessableAudio)

        let selected = await coordinator.open(projected)

        #expect(selected?.id == sessionID)
        #expect(selected?.hasProcessableAudio == true)
        #expect(selected?.processableAudioSources == [
            MeetingProcessableAudioSource(
                id: "artifact-selected-audio",
                artifactType: "mixed_audio"
            ),
        ])
        #expect(coordinator.currentSession == selected)
        #expect(coordinator.selectedProcessingAudioSourceID == "artifact-selected-audio")
        #expect(checksumProbe.paths == [artifactURL.path])
        #expect(checksumProbe.mainThreadObservations == [false])
    }

    @Test
    func refreshValidatesRegisteredTranscriptBeforePublishingRecentAvailability() async throws {
        let workspace = try makeDeletionWorkspace()
        defer { try? FileManager.default.removeItem(at: workspace) }
        let sessionID = "session-refresh-transcript-drift"
        let originalTranscript = Data("original transcript payload".utf8)
        let expectedChecksum = "sha256:" + SHA256.hash(data: originalTranscript).map {
            String(format: "%02x", $0)
        }.joined()
        try writeDeletionWorkspaceSession(
            workspace: workspace,
            sessionID: sessionID,
            title: "Transcript drift",
            status: "transcribed",
            artifacts: [[
                "id": "artifact-refresh-transcript",
                "session_id": sessionID,
                "artifact_type": "transcript_text",
                "path": "artifacts/transcript.json",
                "capture_status": "available",
                "checksum": expectedChecksum,
            ]]
        )
        let transcriptURL = workspace
            .appendingPathComponent("sessions/\(sessionID)/artifacts", isDirectory: true)
            .appendingPathComponent("transcript.json", isDirectory: false)
        try FileManager.default.createDirectory(
            at: transcriptURL.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        try Data("changed transcript payload".utf8).write(to: transcriptURL)
        let coordinator = makeCoordinator(workspaceURL: workspace)

        await coordinator.refreshSessions()

        let recent = try #require(coordinator.recentSessions.first)
        #expect(!coordinator.sessionsAreLoading)
        #expect(recent.id == sessionID)
        #expect(recent.hasRegisteredTranscript)
        #expect(!recent.hasTranscript)
    }

    @Test
    func refreshKeepsValidRegisteredTranscriptAvailable() async throws {
        let workspace = try makeDeletionWorkspace()
        defer { try? FileManager.default.removeItem(at: workspace) }
        let sessionID = "session-refresh-transcript-valid"
        let transcriptData = try JSONSerialization.data(
            withJSONObject: [
                "id": "transcript-refresh-valid",
                "session_id": sessionID,
                "source_artifact_id": "artifact-source-audio",
                "status": "succeeded",
                "segments": [[
                    "segment_id": "segment-refresh-valid",
                    "start_ms": 0,
                    "end_ms": 1_000,
                    "text": "A valid transcript remains ready.",
                ]],
            ],
            options: [.prettyPrinted, .sortedKeys]
        )
        let checksum = "sha256:" + SHA256.hash(data: transcriptData).map {
            String(format: "%02x", $0)
        }.joined()
        try writeDeletionWorkspaceSession(
            workspace: workspace,
            sessionID: sessionID,
            title: "Valid transcript",
            status: "transcribed",
            artifacts: [[
                "id": "artifact-refresh-transcript",
                "session_id": sessionID,
                "artifact_type": "transcript_text",
                "path": "artifacts/transcript.json",
                "capture_status": "available",
                "checksum": checksum,
            ]]
        )
        let transcriptURL = workspace
            .appendingPathComponent("sessions/\(sessionID)/artifacts", isDirectory: true)
            .appendingPathComponent("transcript.json", isDirectory: false)
        try FileManager.default.createDirectory(
            at: transcriptURL.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        try transcriptData.write(to: transcriptURL)
        let coordinator = makeCoordinator(workspaceURL: workspace)

        await coordinator.refreshSessions()

        let recent = try #require(coordinator.recentSessions.first)
        #expect(!coordinator.sessionsAreLoading)
        #expect(recent.id == sessionID)
        #expect(recent.hasRegisteredTranscript)
        #expect(recent.hasTranscript)
        #expect(!recent.hasSpeakerLabels)
    }

    @Test
    func refreshKeepsValidTranscriptWhenRegisteredSpeakerLabelsAreCorrupt() async throws {
        let workspace = try makeDeletionWorkspace()
        defer { try? FileManager.default.removeItem(at: workspace) }
        let sessionID = "session-refresh-speakers-corrupt"
        let transcriptData = try JSONSerialization.data(
            withJSONObject: [
                "id": "transcript-refresh-speakers-corrupt",
                "session_id": sessionID,
                "source_artifact_id": "artifact-source-audio",
                "status": "succeeded",
                "segments": [[
                    "segment_id": "segment-refresh-speakers-corrupt",
                    "start_ms": 0,
                    "end_ms": 1_000,
                    "text": "The transcript stays readable without labels.",
                ]],
            ],
            options: [.prettyPrinted, .sortedKeys]
        )
        let speakerData = Data("not speaker label json".utf8)
        let transcriptChecksum = "sha256:" + SHA256.hash(data: transcriptData).map {
            String(format: "%02x", $0)
        }.joined()
        let speakerChecksum = "sha256:" + SHA256.hash(data: speakerData).map {
            String(format: "%02x", $0)
        }.joined()
        try writeDeletionWorkspaceSession(
            workspace: workspace,
            sessionID: sessionID,
            title: "Transcript-only fallback",
            status: "transcribed",
            artifacts: [
                [
                    "id": "artifact-refresh-transcript",
                    "session_id": sessionID,
                    "artifact_type": "transcript_text",
                    "path": "artifacts/transcript.json",
                    "capture_status": "available",
                    "checksum": transcriptChecksum,
                ],
                [
                    "id": "artifact-refresh-speakers",
                    "session_id": sessionID,
                    "artifact_type": "speaker_labels",
                    "path": "artifacts/speaker_labels.json",
                    "capture_status": "available",
                    "checksum": speakerChecksum,
                ],
            ]
        )
        let artifactsURL = workspace
            .appendingPathComponent("sessions/\(sessionID)/artifacts", isDirectory: true)
        try FileManager.default.createDirectory(
            at: artifactsURL,
            withIntermediateDirectories: true
        )
        try transcriptData.write(to: artifactsURL.appendingPathComponent("transcript.json"))
        try speakerData.write(to: artifactsURL.appendingPathComponent("speaker_labels.json"))
        let reviewInput = try TranscriptReviewWorkspaceLoader.load(
            workspaceURL: workspace,
            sessionID: sessionID
        )
        #expect(reviewInput.transcript?.sessionID == sessionID)
        #expect(reviewInput.speakerLabels == nil)
        #expect(reviewInput.speakerLabelsDegradationReason?.contains("could not be safely loaded") == true)
        let coordinator = makeCoordinator(workspaceURL: workspace)

        await coordinator.refreshSessions()

        let recent = try #require(coordinator.recentSessions.first)
        #expect(recent.id == sessionID)
        #expect(recent.hasRegisteredTranscript)
        #expect(recent.hasTranscript)
        #expect(!recent.hasSpeakerLabels)
    }

    @Test
    func staleTranscriptValidationCannotOverwriteAUserOpenedSession() async throws {
        let workspace = try makeDeletionWorkspace()
        defer { try? FileManager.default.removeItem(at: workspace) }
        let sessionID = "session-refresh-open-race"
        let transcriptData = try JSONSerialization.data(
            withJSONObject: [
                "id": "transcript-refresh-open-race",
                "session_id": sessionID,
                "source_artifact_id": "artifact-source-audio",
                "status": "succeeded",
                "segments": [[
                    "segment_id": "segment-refresh-open-race",
                    "start_ms": 0,
                    "end_ms": 1_000,
                    "text": "Opening wins over stale validation.",
                ]],
            ],
            options: [.prettyPrinted, .sortedKeys]
        )
        let checksum = "sha256:" + SHA256.hash(data: transcriptData).map {
            String(format: "%02x", $0)
        }.joined()
        try writeDeletionWorkspaceSession(
            workspace: workspace,
            sessionID: sessionID,
            title: "Refresh race",
            status: "transcribed",
            artifacts: [[
                "id": "artifact-refresh-transcript",
                "session_id": sessionID,
                "artifact_type": "transcript_text",
                "path": "artifacts/transcript.json",
                "capture_status": "available",
                "checksum": checksum,
            ]]
        )
        let transcriptURL = workspace
            .appendingPathComponent("sessions/\(sessionID)/artifacts", isDirectory: true)
            .appendingPathComponent("transcript.json", isDirectory: false)
        try FileManager.default.createDirectory(
            at: transcriptURL.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        try transcriptData.write(to: transcriptURL)
        let validationProbe = CoordinatorTranscriptValidationProbe()
        defer { validationProbe.resume() }
        let coordinator = makeCoordinator(
            workspaceURL: workspace,
            registeredTranscriptsValidator: validationProbe.validate
        )

        let refreshTask = Task { await coordinator.refreshSessions() }
        await validationProbe.waitUntilStarted()

        let pending = try #require(coordinator.recentSessions.first)
        #expect(!coordinator.sessionsAreLoading)
        #expect(coordinator.transcriptValidationPendingSessionIDs == [sessionID])
        #expect(!pending.hasTranscript)

        let opened = await coordinator.open(pending)
        #expect(opened?.hasTranscript == true)
        #expect(coordinator.transcriptValidationPendingSessionIDs.isEmpty)

        validationProbe.resume()
        await refreshTask.value

        let recent = try #require(coordinator.recentSessions.first)
        #expect(recent.hasTranscript)
        #expect(coordinator.currentSession?.hasTranscript == true)
        #expect(!coordinator.sessionsAreLoading)
        #expect(coordinator.transcriptValidationPendingSessionIDs.isEmpty)
    }

    @Test
    func projectionMutationDuringRefreshRetriesWithoutDroppingHistory() async throws {
        let historical = summary(
            id: "session-historical",
            title: "Historical meeting",
            hasTranscript: false
        )
        let projectionProbe = CoordinatorProjectionLoadProbe(
            snapshot: MeetingSessionWorkspaceSnapshot(
                sessions: [historical],
                issues: []
            )
        )
        defer { projectionProbe.resumeFirstLoad() }
        let coordinator = makeCoordinator(
            sessionsProjectionLoader: projectionProbe.load
        )

        let refreshTask = Task { await coordinator.refreshSessions() }
        await projectionProbe.waitUntilFirstLoadStarted()

        coordinator.recordingDraft.title = "New meeting"
        coordinator.recordingDidStart(
            sessionID: "session-new",
            now: Date(timeIntervalSince1970: 2_000)
        )
        coordinator.recordingDidSave(
            .recorded(sessionID: "session-new", artifacts: []),
            now: Date(timeIntervalSince1970: 2_010)
        )
        projectionProbe.resumeFirstLoad()
        await refreshTask.value

        #expect(projectionProbe.loadCount >= 2)
        #expect(Set(coordinator.recentSessions.map(\.id)) == [
            "session-historical",
            "session-new",
        ])
        #expect(!coordinator.sessionsAreLoading)
        #expect(coordinator.transcriptValidationPendingSessionIDs.isEmpty)
    }

    @Test
    func cancellingRefreshDuringProjectionCancelsDetachedLoadAndClearsLoading() async {
        let projectionProbe = CoordinatorCancellableProjectionLoadProbe()
        let coordinator = makeCoordinator(
            sessionsProjectionLoader: projectionProbe.load
        )

        let refreshTask = Task { await coordinator.refreshSessions() }
        await projectionProbe.waitUntilStarted()
        refreshTask.cancel()
        await refreshTask.value

        #expect(projectionProbe.didObserveCancellation)
        #expect(!coordinator.sessionsAreLoading)
        #expect(coordinator.recentSessions.isEmpty)
        #expect(coordinator.transcriptValidationPendingSessionIDs.isEmpty)
    }

    @Test
    func stableProjectionWithoutRegisteredTranscriptsInvalidatesOlderValidation() async throws {
        let pendingSession = summary(
            id: "session-old-pending",
            title: "Old pending",
            hasTranscript: true
        )
        let stableSession = summary(
            id: "session-new-stable",
            title: "New stable",
            hasTranscript: false
        )
        let projectionProbe = CoordinatorSequentialProjectionLoadProbe(
            snapshots: [
                MeetingSessionWorkspaceSnapshot(sessions: [pendingSession], issues: []),
                MeetingSessionWorkspaceSnapshot(sessions: [stableSession], issues: []),
            ]
        )
        let validationProbe = CoordinatorTranscriptValidationProbe()
        defer { validationProbe.resume() }
        let coordinator = makeCoordinator(
            sessionsProjectionLoader: projectionProbe.load,
            registeredTranscriptsValidator: validationProbe.validate
        )

        let firstRefresh = Task { await coordinator.refreshSessions() }
        await validationProbe.waitUntilStarted()
        #expect(coordinator.transcriptValidationPendingSessionIDs == [pendingSession.id])

        await coordinator.refreshSessions()
        #expect(coordinator.recentSessions.map(\.id) == [stableSession.id])
        #expect(coordinator.transcriptValidationPendingSessionIDs.isEmpty)

        validationProbe.resume()
        await firstRefresh.value

        #expect(coordinator.recentSessions.map(\.id) == [stableSession.id])
        #expect(coordinator.transcriptValidationPendingSessionIDs.isEmpty)
    }

    @Test
    func repeatedPendingRefreshCarriesStableRollbackIntoNewestValidation() async throws {
        let stableSession = summary(
            id: "session-stable-before-refreshes",
            title: "Stable before refreshes",
            hasTranscript: true
        )
        let snapshot = MeetingSessionWorkspaceSnapshot(
            sessions: [stableSession],
            issues: []
        )
        let validationProbe = CoordinatorMultiTranscriptValidationProbe()
        defer { validationProbe.resume(count: 2) }
        let coordinator = makeCoordinator(
            initialSessions: [stableSession],
            sessionsProjectionLoader: { _ in snapshot },
            registeredTranscriptsValidator: validationProbe.validate
        )

        let firstRefresh = Task { await coordinator.refreshSessions() }
        await validationProbe.waitUntilCallCount(1)
        #expect(coordinator.transcriptValidationPendingSessionIDs == [stableSession.id])

        let secondRefresh = Task { await coordinator.refreshSessions() }
        await validationProbe.waitUntilCallCount(2)
        secondRefresh.cancel()
        validationProbe.resume(count: 2)
        await secondRefresh.value
        await firstRefresh.value

        let restored = try #require(coordinator.recentSessions.first)
        #expect(restored.id == stableSession.id)
        #expect(restored.hasTranscript)
        #expect(coordinator.transcriptValidationPendingSessionIDs.isEmpty)
    }

    @Test
    func cancellingRefreshCancelsTranscriptValidationAndClearsPendingState() async throws {
        let registeredTranscript = summary(
            id: "session-cancel-validation",
            title: "Cancel validation",
            hasTranscript: true
        )
        let snapshot = MeetingSessionWorkspaceSnapshot(
            sessions: [registeredTranscript],
            issues: []
        )
        let validationProbe = CoordinatorCancellableTranscriptValidationProbe()
        let coordinator = makeCoordinator(
            sessionsProjectionLoader: { _ in snapshot },
            registeredTranscriptsValidator: validationProbe.validate
        )

        let refreshTask = Task { await coordinator.refreshSessions() }
        await validationProbe.waitUntilStarted()

        #expect(coordinator.transcriptValidationPendingSessionIDs == [registeredTranscript.id])
        #expect(coordinator.recentSessions.first?.hasTranscript == false)
        refreshTask.cancel()
        await refreshTask.value

        #expect(validationProbe.didObserveCancellation)
        #expect(!coordinator.sessionsAreLoading)
        #expect(coordinator.transcriptValidationPendingSessionIDs.isEmpty)
        #expect(coordinator.recentSessions.allSatisfy {
            $0.id != registeredTranscript.id
        })
    }

    @Test
    func refreshRejectsRegisteredTranscriptWithInvalidJSONAfterChecksumPasses() async throws {
        let workspace = try makeDeletionWorkspace()
        defer { try? FileManager.default.removeItem(at: workspace) }
        let sessionID = "session-refresh-transcript-corrupt"
        let corruptTranscript = Data("not transcript json".utf8)
        let checksum = "sha256:" + SHA256.hash(data: corruptTranscript).map {
            String(format: "%02x", $0)
        }.joined()
        try writeDeletionWorkspaceSession(
            workspace: workspace,
            sessionID: sessionID,
            title: "Corrupt transcript",
            status: "transcribed",
            artifacts: [[
                "id": "artifact-refresh-transcript",
                "session_id": sessionID,
                "artifact_type": "transcript_text",
                "path": "artifacts/transcript.json",
                "capture_status": "available",
                "checksum": checksum,
            ]]
        )
        let transcriptURL = workspace
            .appendingPathComponent("sessions/\(sessionID)/artifacts", isDirectory: true)
            .appendingPathComponent("transcript.json", isDirectory: false)
        try FileManager.default.createDirectory(
            at: transcriptURL.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        try corruptTranscript.write(to: transcriptURL)
        let coordinator = makeCoordinator(workspaceURL: workspace)

        await coordinator.refreshSessions()

        let recent = try #require(coordinator.recentSessions.first)
        #expect(!coordinator.sessionsAreLoading)
        #expect(recent.id == sessionID)
        #expect(recent.hasRegisteredTranscript)
        #expect(!recent.hasTranscript)
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
    func transcriptFailurePersistsAcrossDiagnosticsWithoutExposingTechnicalPath() async throws {
        let meeting = summary(id: "session-broken", title: "Broken", hasTranscript: true)
        let coordinator = makeCoordinator(initialSessions: [meeting])
        await coordinator.open(meeting)
        let loadToken = try #require(coordinator.transcriptWillLoad(for: meeting.id))
        coordinator.transcriptDidFailToLoad(PathFailure(), token: loadToken)

        #expect(coordinator.transcriptLoadError?.contains("/Users/jerry") == false)
        #expect(coordinator.transcriptTechnicalError?.contains("/Users/jerry/Meetings/broken.json") == true)
        #expect(coordinator.currentSession?.hasRegisteredTranscript == true)
        #expect(coordinator.currentSession?.hasTranscript == false)
        #expect(coordinator.recentSessions.first?.hasTranscript == false)

        coordinator.navigate(to: .diagnostics)
        coordinator.navigate(to: .meetingDetail)

        #expect(coordinator.transcriptLoadError != nil)
        #expect(coordinator.currentSession?.id == "session-broken")
    }

    @Test
    func unavailableRegisteredTranscriptRequiresRepairWithoutUnsafeReplacement() async throws {
        let meeting = summary(
            id: "session-transcribed-recovery",
            title: "Recovery",
            status: "transcribed",
            hasTranscript: false
        )
        let coordinator = makeCoordinator(initialSessions: [meeting])
        await coordinator.open(meeting)

        let loadToken = try #require(coordinator.transcriptWillLoad(for: meeting.id))
        coordinator.transcriptDidFailToLoad(TestFailure(), token: loadToken)

        #expect(coordinator.transcriptLoadError?.contains("original recording is still safe") == true)
        #expect(coordinator.transcriptLoadError?.contains("will not replace a registered transcript") == true)
        #expect(coordinator.transcriptLoadError?.contains("Reload it after repairing") == true)
        #expect(coordinator.transcriptLoadError != nil)
    }

    @Test
    func unavailableTranscriptWithoutAudioExplainsFailClosedDeletePath() async throws {
        let meeting = summary(
            id: "session-transcribed-no-audio",
            title: "No audio",
            status: "transcribed",
            hasTranscript: false,
            hasProcessableAudio: false
        )
        let coordinator = makeCoordinator(initialSessions: [meeting])
        await coordinator.open(meeting)

        let loadToken = try #require(coordinator.transcriptWillLoad(for: meeting.id))
        coordinator.transcriptDidFailToLoad(TestFailure(), token: loadToken)

        #expect(coordinator.transcriptLoadError?.contains("available files are still safe") == true)
        #expect(coordinator.transcriptLoadError?.contains("delete the meeting") == true)
        #expect(coordinator.transcriptLoadError != nil)
    }

    @Test
    func transcriptCompletionOnlyUpdatesTheCurrentLoadGeneration() async throws {
        let first = summary(id: "session-first", title: "First", hasTranscript: false)
        let second = summary(id: "session-second", title: "Second", hasTranscript: false)
        let coordinator = makeCoordinator(initialSessions: [first, second])
        await coordinator.open(first)
        let firstLoad = try #require(coordinator.transcriptWillLoad(for: first.id))
        await coordinator.open(second)

        coordinator.transcriptDidLoad(firstLoad)
        #expect(coordinator.currentSession?.hasTranscript == false)

        let secondLoad = try #require(coordinator.transcriptWillLoad(for: second.id))
        coordinator.transcriptDidLoad(secondLoad)
        #expect(coordinator.currentSession?.hasTranscript == true)
        #expect(coordinator.currentSession?.status == "transcribed")
    }

    @Test
    func transcriptCompletionPublishesActualSpeakerLabelAvailability() async throws {
        let meeting = summary(
            id: "session-speaker-degradation",
            title: "Speaker degradation",
            hasTranscript: true
        )
        let coordinator = makeCoordinator(initialSessions: [meeting])
        await coordinator.open(meeting)

        let loadToken = try #require(coordinator.transcriptWillLoad(for: meeting.id))
        coordinator.transcriptDidLoad(loadToken, hasSpeakerLabels: false)

        #expect(coordinator.currentSession?.hasTranscript == true)
        #expect(coordinator.currentSession?.hasSpeakerLabels == false)
        #expect(coordinator.recentSessions.first?.hasSpeakerLabels == false)
    }

    @Test
    func transcriptLoadingOnlyStartsForCurrentSessionAndClearsAtTerminalTransitions() async throws {
        let meeting = summary(id: "session-current", title: "Current", hasTranscript: false)
        let coordinator = makeCoordinator(initialSessions: [meeting])
        await coordinator.open(meeting)

        #expect(coordinator.transcriptWillLoad(for: "session-other") == nil)
        #expect(!coordinator.transcriptIsLoading)

        let successfulLoad = try #require(coordinator.transcriptWillLoad(for: meeting.id))
        #expect(coordinator.transcriptIsLoading)
        coordinator.transcriptDidLoad(successfulLoad)
        #expect(!coordinator.transcriptIsLoading)

        let failedLoad = try #require(coordinator.transcriptWillLoad(for: meeting.id))
        #expect(coordinator.transcriptIsLoading)
        coordinator.transcriptDidFailToLoad(TestFailure(), token: failedLoad)
        #expect(!coordinator.transcriptIsLoading)

        _ = coordinator.transcriptWillLoad(for: meeting.id)
        coordinator.beginNewRecording()
        #expect(!coordinator.transcriptIsLoading)
    }

    @Test
    func staleTranscriptLoadTokensCannotOverwriteABASessionOrSameSessionReloads() async throws {
        let first = summary(id: "session-first", title: "First", hasTranscript: false)
        let second = summary(id: "session-second", title: "Second", hasTranscript: false)
        let coordinator = makeCoordinator(initialSessions: [first, second])

        await coordinator.open(first)
        let oldFirstLoad = try #require(coordinator.transcriptWillLoad(for: first.id))
        await coordinator.open(second)
        let secondLoad = try #require(coordinator.transcriptWillLoad(for: second.id))
        await coordinator.open(first)
        let currentFirstLoad = try #require(coordinator.transcriptWillLoad(for: first.id))

        coordinator.transcriptDidFailToLoad(TestFailure(), token: oldFirstLoad)
        coordinator.transcriptDidLoad(secondLoad)
        #expect(coordinator.currentSession?.id == first.id)
        #expect(coordinator.currentSession?.hasTranscript == false)
        #expect(coordinator.transcriptIsLoading)
        #expect(coordinator.transcriptLoadError == nil)

        coordinator.transcriptDidLoad(currentFirstLoad)
        #expect(coordinator.currentSession?.hasTranscript == true)
        #expect(!coordinator.transcriptIsLoading)

        let supersededReload = try #require(coordinator.transcriptWillLoad(for: first.id))
        let currentReload = try #require(coordinator.transcriptWillLoad(for: first.id))
        coordinator.transcriptDidFailToLoad(TestFailure(), token: supersededReload)
        #expect(coordinator.transcriptIsLoading)
        #expect(coordinator.transcriptLoadError == nil)

        coordinator.transcriptDidFailToLoad(TestFailure(), token: currentReload)
        #expect(!coordinator.transcriptIsLoading)
        #expect(coordinator.transcriptLoadError != nil)
    }

    @Test
    func transcriptTerminalStateDoesNotPullUserAwayFromChosenRoute() async throws {
        let meeting = summary(id: "session-route", title: "Route", hasTranscript: false)
        let coordinator = makeCoordinator(initialSessions: [meeting])
        await coordinator.open(meeting)

        let successfulLoad = try #require(coordinator.transcriptWillLoad(for: meeting.id))
        coordinator.navigate(to: .diagnostics)
        coordinator.transcriptDidLoad(successfulLoad)
        #expect(coordinator.route == .diagnostics)

        let failedLoad = try #require(coordinator.transcriptWillLoad(for: meeting.id))
        coordinator.transcriptDidFailToLoad(TestFailure(), token: failedLoad)
        #expect(coordinator.route == .diagnostics)
        #expect(coordinator.transcriptLoadError != nil)
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
    func deletionReconciliationPreservesRecordedSessionTranscriptRepairSignal() async throws {
        let workspace = try makeDeletionWorkspace()
        defer { try? FileManager.default.removeItem(at: workspace) }
        let sessionID = "session-recorded-transcript-repair"
        try writeDeletionWorkspaceSession(
            workspace: workspace,
            sessionID: sessionID,
            title: "Recorded transcript repair",
            status: "recorded",
            artifacts: [[
                "id": "artifact-missing-transcript",
                "session_id": sessionID,
                "artifact_type": "transcript_text",
                "path": "artifacts/transcript.json",
                "capture_status": "available",
                "checksum": "sha256:registered-but-missing",
            ]]
        )
        let coordinator = makeCoordinator(workspaceURL: workspace)
        await coordinator.refreshSessions()
        let recent = try #require(coordinator.recentSessions.first)

        let openedSession = await coordinator.open(recent)
        let opened = try #require(openedSession)
        #expect(opened.status == "recorded")
        #expect(opened.hasRegisteredTranscript)
        #expect(!opened.hasTranscript)

        coordinator.deletionWillStart()
        let reconciliation = await coordinator.reconcileDeletionAttempt(
            sessionID: sessionID,
            commandReportedDeletion: false
        )

        guard case .sessionPresent(let refreshed) = reconciliation else {
            Issue.record("Expected the recorded session to survive the failed delete attempt.")
            return
        }
        #expect(refreshed.hasRegisteredTranscript)
        #expect(!refreshed.hasTranscript)
        #expect(coordinator.currentSession?.hasRegisteredTranscript == true)
    }

    @Test
    func deletionReconciliationNeverPublishesAnotherRegisteredTranscriptAsReadyBeforeValidation() async throws {
        let workspace = try makeDeletionWorkspace()
        defer { try? FileManager.default.removeItem(at: workspace) }
        let remainingSessionID = "session-remaining-transcript"
        try writeDeletionWorkspaceSession(
            workspace: workspace,
            sessionID: remainingSessionID,
            title: "Remaining transcript",
            status: "transcribed",
            artifacts: [[
                "id": "artifact-remaining-transcript",
                "session_id": remainingSessionID,
                "artifact_type": "transcript_text",
                "path": "artifacts/transcript.json",
                "capture_status": "available",
                "checksum": "sha256:registered-but-unverified",
            ]]
        )
        let validationProbe = CoordinatorTranscriptValidationProbe()
        defer { validationProbe.resume() }
        let coordinator = makeCoordinator(
            workspaceURL: workspace,
            registeredTranscriptsValidator: validationProbe.validate
        )

        let reconciliationTask = Task {
            await coordinator.reconcileDeletionAttempt(
                sessionID: "session-deleted",
                commandReportedDeletion: true
            )
        }
        await validationProbe.waitUntilStarted()

        let pending = try #require(coordinator.recentSessions.first)
        #expect(pending.id == remainingSessionID)
        #expect(pending.hasRegisteredTranscript)
        #expect(!pending.hasTranscript)
        #expect(coordinator.transcriptValidationPendingSessionIDs == [remainingSessionID])

        let reconciliation = await reconciliationTask.value
        validationProbe.resume()
        for _ in 0..<1_000 {
            if coordinator.transcriptValidationPendingSessionIDs.isEmpty {
                break
            }
            await Task.yield()
        }

        #expect(reconciliation == .sessionMissing)
        #expect(coordinator.recentSessions.first?.hasTranscript == false)
        #expect(coordinator.transcriptValidationPendingSessionIDs.isEmpty)
    }

    @Test
    func deletionBackgroundValidationCancelsWhenCoordinatorIsReleased() async throws {
        let workspace = try makeDeletionWorkspace()
        defer { try? FileManager.default.removeItem(at: workspace) }
        let remainingSessionID = "session-lifetime-validation"
        try writeDeletionWorkspaceSession(
            workspace: workspace,
            sessionID: remainingSessionID,
            title: "Lifetime validation",
            status: "transcribed",
            artifacts: [[
                "id": "artifact-lifetime-transcript",
                "session_id": remainingSessionID,
                "artifact_type": "transcript_text",
                "path": "artifacts/transcript.json",
                "capture_status": "available",
                "checksum": "sha256:registered-for-lifetime-test",
            ]]
        )
        let validationProbe = CoordinatorCancellableTranscriptValidationProbe()
        var coordinator: MeetingWorkspaceCoordinator? = makeCoordinator(
            workspaceURL: workspace,
            registeredTranscriptsValidator: validationProbe.validate
        )
        weak let weakCoordinator = coordinator

        let reconciliation = await coordinator?.reconcileDeletionAttempt(
            sessionID: "session-already-deleted",
            commandReportedDeletion: true
        )
        #expect(reconciliation == .sessionMissing)
        await validationProbe.waitUntilStarted()

        coordinator = nil
        for _ in 0..<1_000 {
            if weakCoordinator == nil, validationProbe.didObserveCancellation {
                break
            }
            try? await Task.sleep(nanoseconds: 1_000_000)
        }

        #expect(weakCoordinator == nil)
        #expect(validationProbe.didObserveCancellation)
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
        #expect(coordinator.currentSession?.artifactCount == 0)
        #expect(coordinator.currentSession?.processableAudioSources.isEmpty == true)
        #expect(coordinator.selectedProcessingAudioSourceID == nil)
    }

    private func makeCoordinator(
        workspaceURL: URL? = nil,
        initialSessions: [MeetingSessionSummary] = [],
        repository: MeetingSessionWorkspaceRepository = MeetingSessionWorkspaceRepository(),
        sessionsProjectionLoader: (@Sendable (
            URL
        ) throws -> MeetingSessionWorkspaceSnapshot)? = nil,
        registeredTranscriptsValidator: (@Sendable (
            MeetingSessionWorkspaceSnapshot,
            URL
        ) -> MeetingSessionWorkspaceSnapshot?)? = nil
    ) -> MeetingWorkspaceCoordinator {
        let resolvedWorkspaceURL = workspaceURL
            ?? FileManager.default.temporaryDirectory
                .appendingPathComponent("meeting-coordinator-tests-\(UUID().uuidString)")
        if sessionsProjectionLoader != nil || registeredTranscriptsValidator != nil {
            let resolvedProjectionLoader = sessionsProjectionLoader ?? { url in
                try repository.load(workspaceURL: url)
            }
            let resolvedValidator = registeredTranscriptsValidator ?? { snapshot, _ in
                snapshot
            }
            return MeetingWorkspaceCoordinator(
                workspaceURL: resolvedWorkspaceURL,
                repository: repository,
                initialSessions: initialSessions,
                sessionsProjectionLoader: resolvedProjectionLoader,
                registeredTranscriptsValidator: resolvedValidator
            )
        }
        return MeetingWorkspaceCoordinator(
            workspaceURL: resolvedWorkspaceURL,
            repository: repository,
            initialSessions: initialSessions
        )
    }

    private func summary(
        id: String,
        title: String,
        status: String? = nil,
        hasTranscript: Bool,
        hasProcessableAudio: Bool = true,
        processableAudioSources: [MeetingProcessableAudioSource] = []
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
            hasProcessableAudio: hasProcessableAudio,
            processableAudioSources: processableAudioSources
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

private final class CoordinatorProjectionLoadProbe: @unchecked Sendable {
    private let lock = NSLock()
    private let snapshot: MeetingSessionWorkspaceSnapshot
    private var capturedLoadCount = 0
    private var firstLoadStarted = false
    private var firstLoadContinuation: CheckedContinuation<Void, Never>?
    private let resumeFirstLoadSemaphore = DispatchSemaphore(value: 0)

    init(snapshot: MeetingSessionWorkspaceSnapshot) {
        self.snapshot = snapshot
    }

    var loadCount: Int {
        lock.lock()
        defer { lock.unlock() }
        return capturedLoadCount
    }

    func load(_ workspaceURL: URL) throws -> MeetingSessionWorkspaceSnapshot {
        _ = workspaceURL
        lock.lock()
        capturedLoadCount += 1
        let isFirstLoad = capturedLoadCount == 1
        if isFirstLoad {
            firstLoadStarted = true
        }
        let continuation = isFirstLoad ? firstLoadContinuation : nil
        if isFirstLoad {
            firstLoadContinuation = nil
        }
        lock.unlock()
        continuation?.resume()

        if isFirstLoad {
            resumeFirstLoadSemaphore.wait()
        }
        try Task.checkCancellation()
        return snapshot
    }

    func waitUntilFirstLoadStarted() async {
        await withCheckedContinuation { continuation in
            lock.lock()
            if firstLoadStarted {
                lock.unlock()
                continuation.resume()
            } else {
                firstLoadContinuation = continuation
                lock.unlock()
            }
        }
    }

    func resumeFirstLoad() {
        resumeFirstLoadSemaphore.signal()
    }
}

private final class CoordinatorCancellableProjectionLoadProbe: @unchecked Sendable {
    private let lock = NSLock()
    private var loadStarted = false
    private var cancellationObserved = false
    private var startedContinuation: CheckedContinuation<Void, Never>?

    var didObserveCancellation: Bool {
        lock.lock()
        defer { lock.unlock() }
        return cancellationObserved
    }

    func load(_ workspaceURL: URL) throws -> MeetingSessionWorkspaceSnapshot {
        _ = workspaceURL
        lock.lock()
        loadStarted = true
        let continuation = startedContinuation
        startedContinuation = nil
        lock.unlock()
        continuation?.resume()

        let timeout = Date().addingTimeInterval(1)
        while !Task.isCancelled, Date() < timeout {
            Thread.sleep(forTimeInterval: 0.002)
        }
        if Task.isCancelled {
            lock.lock()
            cancellationObserved = true
            lock.unlock()
            throw CancellationError()
        }
        return MeetingSessionWorkspaceSnapshot(sessions: [], issues: [])
    }

    func waitUntilStarted() async {
        await withCheckedContinuation { continuation in
            lock.lock()
            if loadStarted {
                lock.unlock()
                continuation.resume()
            } else {
                startedContinuation = continuation
                lock.unlock()
            }
        }
    }
}

private final class CoordinatorSequentialProjectionLoadProbe: @unchecked Sendable {
    private let lock = NSLock()
    private let snapshots: [MeetingSessionWorkspaceSnapshot]
    private var nextSnapshotIndex = 0

    init(snapshots: [MeetingSessionWorkspaceSnapshot]) {
        precondition(!snapshots.isEmpty)
        self.snapshots = snapshots
    }

    func load(_ workspaceURL: URL) throws -> MeetingSessionWorkspaceSnapshot {
        _ = workspaceURL
        lock.lock()
        let index = min(nextSnapshotIndex, snapshots.count - 1)
        nextSnapshotIndex += 1
        let snapshot = snapshots[index]
        lock.unlock()
        return snapshot
    }
}

private final class CoordinatorTranscriptValidationProbe: @unchecked Sendable {
    private let lock = NSLock()
    private var validationStarted = false
    private var startedContinuation: CheckedContinuation<Void, Never>?
    private let resumeValidation = DispatchSemaphore(value: 0)

    func validate(
        snapshot: MeetingSessionWorkspaceSnapshot,
        workspaceURL: URL
    ) -> MeetingSessionWorkspaceSnapshot? {
        _ = workspaceURL
        lock.lock()
        validationStarted = true
        let continuation = startedContinuation
        startedContinuation = nil
        lock.unlock()
        continuation?.resume()
        resumeValidation.wait()
        let staleSessions = snapshot.sessions.map { session in
            MeetingSessionSummary(
                id: session.id,
                title: session.title,
                status: session.status,
                startedAt: session.startedAt,
                endedAt: session.endedAt,
                updatedAt: session.updatedAt,
                durationLabel: session.durationLabel,
                artifactCount: session.artifactCount,
                hasTranscript: false,
                hasSpeakerLabels: false,
                hasProcessableAudio: session.hasProcessableAudio,
                processableAudioSources: session.processableAudioSources,
                hasRegisteredTranscript: session.hasRegisteredTranscript
            )
        }
        return MeetingSessionWorkspaceSnapshot(
            sessions: staleSessions,
            issues: snapshot.issues
        )
    }

    func waitUntilStarted() async {
        await withCheckedContinuation { continuation in
            lock.lock()
            if validationStarted {
                lock.unlock()
                continuation.resume()
            } else {
                startedContinuation = continuation
                lock.unlock()
            }
        }
    }

    func resume() {
        resumeValidation.signal()
    }
}

private final class CoordinatorMultiTranscriptValidationProbe: @unchecked Sendable {
    private let lock = NSLock()
    private var capturedCallCount = 0
    private var callCountContinuations: [
        (target: Int, continuation: CheckedContinuation<Void, Never>)
    ] = []
    private let resumeValidation = DispatchSemaphore(value: 0)

    var callCount: Int {
        lock.lock()
        defer { lock.unlock() }
        return capturedCallCount
    }

    func validate(
        snapshot: MeetingSessionWorkspaceSnapshot,
        workspaceURL: URL
    ) -> MeetingSessionWorkspaceSnapshot? {
        _ = workspaceURL
        lock.lock()
        capturedCallCount += 1
        let readyContinuations = callCountContinuations.filter {
            capturedCallCount >= $0.target
        }
        callCountContinuations.removeAll {
            capturedCallCount >= $0.target
        }
        lock.unlock()
        readyContinuations.forEach { $0.continuation.resume() }
        resumeValidation.wait()
        return snapshot
    }

    func waitUntilCallCount(_ target: Int) async {
        await withCheckedContinuation { continuation in
            lock.lock()
            if capturedCallCount >= target {
                lock.unlock()
                continuation.resume()
            } else {
                callCountContinuations.append((target, continuation))
                lock.unlock()
            }
        }
    }

    func resume(count: Int) {
        for _ in 0..<count {
            resumeValidation.signal()
        }
    }
}

private final class CoordinatorCancellableTranscriptValidationProbe: @unchecked Sendable {
    private let lock = NSLock()
    private var validationStarted = false
    private var cancellationObserved = false
    private var startedContinuation: CheckedContinuation<Void, Never>?

    var didObserveCancellation: Bool {
        lock.lock()
        defer { lock.unlock() }
        return cancellationObserved
    }

    func validate(
        snapshot: MeetingSessionWorkspaceSnapshot,
        workspaceURL: URL
    ) -> MeetingSessionWorkspaceSnapshot? {
        _ = snapshot
        _ = workspaceURL
        lock.lock()
        validationStarted = true
        let continuation = startedContinuation
        startedContinuation = nil
        lock.unlock()
        continuation?.resume()

        let timeout = Date().addingTimeInterval(5)
        while !Task.isCancelled, Date() < timeout {
            Thread.sleep(forTimeInterval: 0.002)
        }
        guard Task.isCancelled else {
            return nil
        }
        lock.lock()
        cancellationObserved = true
        lock.unlock()
        return nil
    }

    func waitUntilStarted() async {
        await withCheckedContinuation { continuation in
            lock.lock()
            if validationStarted {
                lock.unlock()
                continuation.resume()
            } else {
                startedContinuation = continuation
                lock.unlock()
            }
        }
    }
}

private struct TestFailure: Error {}

private struct PathFailure: LocalizedError {
    var errorDescription: String? {
        "Transcript could not be read at /Users/jerry/Meetings/broken.json"
    }
}
