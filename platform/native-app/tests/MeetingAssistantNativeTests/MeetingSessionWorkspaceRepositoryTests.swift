import CryptoKit
import Foundation
import Testing
@testable import MeetingAssistantNative

@Suite("Meeting session workspace repository")
struct MeetingSessionWorkspaceRepositoryTests {
    @Test
    func returnsEmptyProjectionForFreshOrMissingWorkspace() throws {
        let missing = FileManager.default.temporaryDirectory
            .appendingPathComponent("ma-session-repository-missing-\(UUID().uuidString)")
        let missingSnapshot = try MeetingSessionWorkspaceRepository().load(workspaceURL: missing)
        #expect(missingSnapshot == MeetingSessionWorkspaceSnapshot(sessions: [], issues: []))

        let workspace = try makeRepositoryWorkspace()
        defer { try? FileManager.default.removeItem(at: workspace) }

        let emptySnapshot = try MeetingSessionWorkspaceRepository().load(workspaceURL: workspace)
        #expect(emptySnapshot.sessions.isEmpty)
        #expect(emptySnapshot.issues.isEmpty)
    }

    @Test
    func buildsSortedProjectionFromExistingSessionMetadata() throws {
        let workspace = try makeRepositoryWorkspace()
        defer { try? FileManager.default.removeItem(at: workspace) }

        try writeRepositorySession(
            workspace: workspace,
            sessionID: "session-older",
            title: "Older planning meeting",
            status: "transcribed",
            startedAt: "2026-07-12T08:00:00Z",
            endedAt: "2026-07-12T09:02:03Z",
            updatedAt: "2026-07-12T10:00:00Z",
            artifacts: [
                repositoryArtifact(
                    id: "artifact-mixed",
                    sessionID: "session-older",
                    type: "mixed_audio",
                    path: "artifacts/mixed_audio.wav",
                    status: "degraded"
                ),
                repositoryArtifact(
                    id: "artifact-transcript",
                    sessionID: "session-older",
                    type: "transcript_text",
                    path: "artifacts/transcript.json",
                    status: "available"
                ),
                repositoryArtifact(
                    id: "artifact-speakers",
                    sessionID: "session-older",
                    type: "speaker_labels",
                    path: "artifacts/speaker_labels.json",
                    status: "degraded"
                ),
                repositoryArtifact(
                    id: "artifact-screen",
                    sessionID: "session-older",
                    type: "screen_video",
                    path: "artifacts/screen_video.mov",
                    status: "missing"
                ),
            ]
        )
        try writeRepositorySession(
            workspace: workspace,
            sessionID: "session-newer",
            title: nil,
            status: "recorded",
            startedAt: "2026-07-12T10:57:55Z",
            endedAt: "2026-07-12T11:00:00Z",
            updatedAt: "2026-07-12T11:00:00.500Z",
            artifacts: [
                repositoryArtifact(
                    id: "artifact-microphone",
                    sessionID: "session-newer",
                    type: "microphone_audio",
                    path: "artifacts/microphone_audio.m4a",
                    status: "available"
                ),
                repositoryArtifact(
                    id: "artifact-failed-transcript",
                    sessionID: "session-newer",
                    type: "transcript_text",
                    path: "artifacts/transcript.json",
                    status: "failed"
                ),
            ]
        )

        let snapshot = try MeetingSessionWorkspaceRepository().load(workspaceURL: workspace)

        #expect(snapshot.issues.isEmpty)
        #expect(snapshot.sessions.map(\.id) == ["session-newer", "session-older"])
        #expect(snapshot.sessions[0].title == nil)
        #expect(snapshot.sessions[0].durationLabel == "02:05")
        #expect(snapshot.sessions[0].artifactCount == 2)
        #expect(snapshot.sessions[0].hasProcessableAudio)
        #expect(!snapshot.sessions[0].hasTranscript)
        #expect(!snapshot.sessions[0].hasSpeakerLabels)
        #expect(snapshot.sessions[1].durationLabel == "1:02:03")
        #expect(snapshot.sessions[1].artifactCount == 4)
        #expect(snapshot.sessions[1].hasProcessableAudio)
        #expect(snapshot.sessions[1].hasTranscript)
        #expect(snapshot.sessions[1].hasSpeakerLabels)
    }

    @Test
    func keepsHealthySessionsAndReportsBrokenOnes() throws {
        let workspace = try makeRepositoryWorkspace()
        defer { try? FileManager.default.removeItem(at: workspace) }

        try writeRepositorySession(
            workspace: workspace,
            sessionID: "session-valid",
            title: "Valid meeting",
            status: "recorded",
            startedAt: "2026-07-12T10:00:00Z",
            endedAt: nil,
            updatedAt: "2026-07-12T10:00:00Z",
            artifacts: []
        )
        let invalidRoot = try makeRepositorySessionRoot(
            workspace: workspace,
            sessionID: "session-invalid-json"
        )
        try Data("{broken".utf8).write(to: invalidRoot.appendingPathComponent("session.json"))
        _ = try makeRepositorySessionRoot(workspace: workspace, sessionID: "session-missing-json")
        try FileManager.default.createDirectory(
            at: workspace
                .appendingPathComponent("sessions")
                .appendingPathComponent(".invalid-name"),
            withIntermediateDirectories: false
        )

        let snapshot = try MeetingSessionWorkspaceRepository().load(workspaceURL: workspace)

        #expect(snapshot.sessions.map(\.id) == ["session-valid"])
        #expect(snapshot.issues.map(\.kind) == [
            .invalidSessionEntry,
            .invalidMetadata,
            .missingMetadata,
        ])
        #expect(snapshot.issues[1].sessionID == "session-invalid-json")
        #expect(snapshot.issues[2].path.hasSuffix("/session-missing-json/session.json"))
    }

    @Test
    func normalizedAudioIsProcessableButDegradedPlaceholderIsNot() throws {
        let workspace = try makeRepositoryWorkspace()
        defer { try? FileManager.default.removeItem(at: workspace) }

        try writeRepositorySession(
            workspace: workspace,
            sessionID: "session-normalized",
            title: "Normalized retry",
            status: "recorded",
            startedAt: "2026-07-12T10:00:00Z",
            endedAt: "2026-07-12T10:05:00Z",
            updatedAt: "2026-07-12T10:05:00Z",
            artifacts: [
                repositoryArtifact(
                    id: "artifact-normalized",
                    sessionID: "session-normalized",
                    type: "normalized_audio",
                    path: "artifacts/normalized_audio.wav",
                    status: "available"
                ),
            ]
        )
        try writeRepositorySession(
            workspace: workspace,
            sessionID: "session-placeholder",
            title: "Missing degraded audio",
            status: "recorded",
            startedAt: "2026-07-12T09:00:00Z",
            endedAt: "2026-07-12T09:05:00Z",
            updatedAt: "2026-07-12T09:05:00Z",
            artifacts: [
                repositoryArtifact(
                    id: "artifact-degraded-placeholder",
                    sessionID: "session-placeholder",
                    type: "mixed_audio",
                    path: "artifacts/mixed_audio.wav",
                    status: "degraded"
                ),
            ]
        )
        try FileManager.default.removeItem(
            at: workspace
                .appendingPathComponent("sessions/session-placeholder/artifacts/mixed_audio.wav")
        )

        let snapshot = try MeetingSessionWorkspaceRepository().load(workspaceURL: workspace)

        #expect(snapshot.sessions.first { $0.id == "session-normalized" }?.hasProcessableAudio == true)
        #expect(snapshot.sessions.first { $0.id == "session-placeholder" }?.hasProcessableAudio == false)
    }

    @Test
    func selectedSessionRequiresMatchingChecksumsAfterRecentProjectionDefersPayloadReads() throws {
        let workspace = try makeRepositoryWorkspace()
        defer { try? FileManager.default.removeItem(at: workspace) }

        try writeRepositorySession(
            workspace: workspace,
            sessionID: "session-transcript-drift",
            title: "Transcript drift",
            status: "transcribed",
            startedAt: "2026-07-12T10:00:00Z",
            endedAt: "2026-07-12T10:05:00Z",
            updatedAt: "2026-07-12T10:05:00Z",
            artifacts: [
                repositoryArtifact(
                    id: "artifact-transcript-drift",
                    sessionID: "session-transcript-drift",
                    type: "transcript_text",
                    path: "artifacts/transcript.json",
                    status: "available"
                ),
                repositoryArtifact(
                    id: "artifact-speakers-drift",
                    sessionID: "session-transcript-drift",
                    type: "speaker_labels",
                    path: "artifacts/speaker_labels.json",
                    status: "available"
                ),
            ]
        )
        let sessionRoot = workspace.appendingPathComponent(
            "sessions/session-transcript-drift",
            isDirectory: true
        )
        try Data("changed transcript".utf8).write(
            to: sessionRoot.appendingPathComponent("artifacts/transcript.json")
        )
        try FileManager.default.removeItem(
            at: sessionRoot.appendingPathComponent("artifacts/speaker_labels.json")
        )

        let repository = MeetingSessionWorkspaceRepository()
        let snapshot = try repository.load(workspaceURL: workspace)

        #expect(snapshot.sessions.count == 1)
        #expect(snapshot.sessions[0].hasTranscript == true)
        #expect(snapshot.sessions[0].hasSpeakerLabels == false)

        let selected = try repository.loadSelectedSession(
            workspaceURL: workspace,
            sessionID: "session-transcript-drift"
        )

        #expect(selected?.hasTranscript == false)
        #expect(selected?.hasSpeakerLabels == false)
    }

    @Test
    func recentProjectionDoesNotReadArtifactPayloadsButSelectedMeetingDoes() throws {
        let workspace = try makeRepositoryWorkspace()
        defer { try? FileManager.default.removeItem(at: workspace) }
        try writeRepositorySession(
            workspace: workspace,
            sessionID: "session-layered-validation",
            title: "Layered validation",
            status: "transcribed",
            startedAt: "2026-07-12T10:00:00Z",
            endedAt: "2026-07-12T10:30:00Z",
            updatedAt: "2026-07-12T10:30:00Z",
            artifacts: [
                repositoryArtifact(
                    id: "artifact-large-audio",
                    sessionID: "session-layered-validation",
                    type: "mixed_audio",
                    path: "artifacts/mixed_audio.wav",
                    status: "available"
                ),
                repositoryArtifact(
                    id: "artifact-transcript",
                    sessionID: "session-layered-validation",
                    type: "transcript_text",
                    path: "artifacts/transcript.json",
                    status: "available"
                ),
            ]
        )
        let probe = RepositoryChecksumProbe()
        let repository = MeetingSessionWorkspaceRepository { url in
            probe.checksum(of: url)
        }

        let projection = try repository.load(workspaceURL: workspace)

        #expect(projection.sessions.count == 1)
        #expect(projection.sessions[0].hasProcessableAudio)
        #expect(projection.sessions[0].hasTranscript)
        #expect(probe.paths.isEmpty)

        let selected = try repository.loadSelectedSession(
            workspaceURL: workspace,
            sessionID: "session-layered-validation"
        )

        #expect(selected?.hasProcessableAudio == true)
        #expect(selected?.hasTranscript == true)
        #expect(Set(probe.paths.map { URL(fileURLWithPath: $0).lastPathComponent }) == Set([
            "mixed_audio.wav",
            "transcript.json",
        ]))
    }

    @Test
    func recentProjectionRejectsArtifactSymlinksAndHardlinksWithoutReadingPayloads() throws {
        let workspace = try makeRepositoryWorkspace()
        defer { try? FileManager.default.removeItem(at: workspace) }
        for sessionID in ["session-symlink-audio", "session-hardlink-audio"] {
            try writeRepositorySession(
                workspace: workspace,
                sessionID: sessionID,
                title: sessionID,
                status: "recorded",
                startedAt: "2026-07-12T10:00:00Z",
                endedAt: "2026-07-12T10:30:00Z",
                updatedAt: "2026-07-12T10:30:00Z",
                artifacts: [
                    repositoryArtifact(
                        id: "artifact-\(sessionID)",
                        sessionID: sessionID,
                        type: "mixed_audio",
                        path: "artifacts/mixed_audio.wav",
                        status: "available"
                    ),
                ]
            )
        }

        let symlinkRoot = workspace.appendingPathComponent(
            "sessions/session-symlink-audio/artifacts",
            isDirectory: true
        )
        let symlinkArtifact = symlinkRoot.appendingPathComponent("mixed_audio.wav")
        let symlinkTarget = symlinkRoot.appendingPathComponent("managed-target.wav")
        try FileManager.default.moveItem(at: symlinkArtifact, to: symlinkTarget)
        try FileManager.default.createSymbolicLink(
            at: symlinkArtifact,
            withDestinationURL: symlinkTarget
        )

        let hardlinkRoot = workspace.appendingPathComponent(
            "sessions/session-hardlink-audio/artifacts",
            isDirectory: true
        )
        let hardlinkArtifact = hardlinkRoot.appendingPathComponent("mixed_audio.wav")
        let hardlinkSource = hardlinkRoot.appendingPathComponent("managed-source.wav")
        try FileManager.default.moveItem(at: hardlinkArtifact, to: hardlinkSource)
        try FileManager.default.linkItem(at: hardlinkSource, to: hardlinkArtifact)

        let probe = RepositoryChecksumProbe()
        let repository = MeetingSessionWorkspaceRepository { url in
            probe.checksum(of: url)
        }

        let projection = try repository.load(workspaceURL: workspace)

        #expect(projection.issues.isEmpty)
        #expect(projection.sessions.count == 2)
        #expect(projection.sessions.allSatisfy { !$0.hasProcessableAudio })
        #expect(probe.paths.isEmpty)
    }

    @Test
    func rejectsUnknownSessionStatusAndOmitsDeletedSessionsFromRecentAndSelection() throws {
        let workspace = try makeRepositoryWorkspace()
        defer { try? FileManager.default.removeItem(at: workspace) }
        try writeRepositorySession(
            workspace: workspace,
            sessionID: "session-unknown-status",
            title: "Unknown",
            status: "archived",
            startedAt: "2026-07-12T10:00:00Z",
            endedAt: nil,
            updatedAt: "2026-07-12T10:00:00Z",
            artifacts: []
        )
        try writeRepositorySession(
            workspace: workspace,
            sessionID: "session-deleted",
            title: "Deleted",
            status: "deleted",
            startedAt: "2026-07-12T09:00:00Z",
            endedAt: "2026-07-12T09:30:00Z",
            updatedAt: "2026-07-12T09:30:00Z",
            artifacts: []
        )
        let repository = MeetingSessionWorkspaceRepository()

        let projection = try repository.load(workspaceURL: workspace)

        #expect(projection.sessions.isEmpty)
        #expect(projection.issues.map(\.kind) == [.invalidMetadata])
        #expect(projection.issues[0].sessionID == "session-unknown-status")

        do {
            _ = try repository.loadSelectedSession(
                workspaceURL: workspace,
                sessionID: "session-unknown-status"
            )
            Issue.record("Expected an unknown status to fail strict selection.")
        } catch let issue as MeetingSessionWorkspaceIssue {
            #expect(issue.kind == .invalidMetadata)
        }

        do {
            _ = try repository.loadSelectedSession(
                workspaceURL: workspace,
                sessionID: "session-deleted"
            )
            Issue.record("Expected a deleted meeting to be unavailable for selection.")
        } catch let error as MeetingSessionWorkspaceRepositoryError {
            #expect(error == .selectedSessionDeleted("session-deleted"))
        }
    }

    @Test
    func reportsSessionArtifactIdentityAndPathCorruption() throws {
        let workspace = try makeRepositoryWorkspace()
        defer { try? FileManager.default.removeItem(at: workspace) }

        try writeRepositorySession(
            workspace: workspace,
            sessionID: "session-id-mismatch",
            metadataID: "another-session",
            title: nil,
            status: "recorded",
            startedAt: "2026-07-12T10:00:00Z",
            endedAt: nil,
            updatedAt: "2026-07-12T10:00:00Z",
            artifacts: []
        )
        try writeRepositorySession(
            workspace: workspace,
            sessionID: "session-artifact-mismatch",
            title: nil,
            status: "recorded",
            startedAt: "2026-07-12T10:00:00Z",
            endedAt: nil,
            updatedAt: "2026-07-12T10:00:00Z",
            artifacts: [
                repositoryArtifact(
                    id: "artifact-other",
                    sessionID: "other-session",
                    type: "mixed_audio",
                    path: "artifacts/mixed_audio.wav",
                    status: "available"
                ),
            ]
        )
        try writeRepositorySession(
            workspace: workspace,
            sessionID: "session-path-escape",
            title: nil,
            status: "recorded",
            startedAt: "2026-07-12T10:00:00Z",
            endedAt: nil,
            updatedAt: "2026-07-12T10:00:00Z",
            artifacts: [
                repositoryArtifact(
                    id: "artifact-escape",
                    sessionID: "session-path-escape",
                    type: "transcript_text",
                    path: "../outside.json",
                    status: "available"
                ),
            ]
        )

        let snapshot = try MeetingSessionWorkspaceRepository().load(workspaceURL: workspace)

        #expect(snapshot.sessions.isEmpty)
        #expect(Set(snapshot.issues.map(\.kind)) == Set([
            .artifactSessionMismatch,
            .sessionIDMismatch,
            .artifactPathEscape,
        ]))
    }

    @Test
    func reportsSessionAndMetadataLinksWithoutFollowingThem() throws {
        let workspace = try makeRepositoryWorkspace()
        defer { try? FileManager.default.removeItem(at: workspace) }
        let outside = FileManager.default.temporaryDirectory
            .appendingPathComponent("ma-session-repository-outside-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: outside, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: outside) }

        let sessionsRoot = workspace.appendingPathComponent("sessions", isDirectory: true)
        try FileManager.default.createSymbolicLink(
            at: sessionsRoot.appendingPathComponent("session-linked-root"),
            withDestinationURL: outside
        )

        let symlinkMetadataRoot = try makeRepositorySessionRoot(
            workspace: workspace,
            sessionID: "session-linked-metadata"
        )
        let externalMetadata = outside.appendingPathComponent("session.json")
        try writeRepositoryJSON(
            repositorySessionPayload(
                sessionRoot: symlinkMetadataRoot,
                sessionID: "session-linked-metadata",
                metadataID: "session-linked-metadata",
                title: nil,
                status: "recorded",
                startedAt: "2026-07-12T10:00:00Z",
                endedAt: nil,
                updatedAt: "2026-07-12T10:00:00Z",
                artifacts: []
            ),
            to: externalMetadata
        )
        try FileManager.default.createSymbolicLink(
            at: symlinkMetadataRoot.appendingPathComponent("session.json"),
            withDestinationURL: externalMetadata
        )

        let hardlinkMetadataRoot = try makeRepositorySessionRoot(
            workspace: workspace,
            sessionID: "session-hardlinked-metadata"
        )
        let hardlinkSource = outside.appendingPathComponent("hardlink-source.json")
        try writeRepositoryJSON(
            repositorySessionPayload(
                sessionRoot: hardlinkMetadataRoot,
                sessionID: "session-hardlinked-metadata",
                metadataID: "session-hardlinked-metadata",
                title: nil,
                status: "recorded",
                startedAt: "2026-07-12T10:00:00Z",
                endedAt: nil,
                updatedAt: "2026-07-12T10:00:00Z",
                artifacts: []
            ),
            to: hardlinkSource
        )
        try FileManager.default.linkItem(
            at: hardlinkSource,
            to: hardlinkMetadataRoot.appendingPathComponent("session.json")
        )

        let snapshot = try MeetingSessionWorkspaceRepository().load(workspaceURL: workspace)

        #expect(snapshot.sessions.isEmpty)
        #expect(snapshot.issues.filter { $0.kind == .unsafeMetadata }.count == 2)
        #expect(snapshot.issues.filter { $0.kind == .unsafeSessionEntry }.count == 1)
        #expect(FileManager.default.fileExists(atPath: externalMetadata.path))
        #expect(FileManager.default.fileExists(atPath: hardlinkSource.path))
    }

    @Test
    func rejectsArtifactPathThatEscapesThroughAnIntermediateSymlink() throws {
        let workspace = try makeRepositoryWorkspace()
        defer { try? FileManager.default.removeItem(at: workspace) }
        let outside = FileManager.default.temporaryDirectory
            .appendingPathComponent("ma-session-repository-artifact-outside-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: outside, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: outside) }

        let sessionID = "session-linked-artifact-parent"
        let sessionRoot = try makeRepositorySessionRoot(
            workspace: workspace,
            sessionID: sessionID
        )
        let outsideAudio = outside.appendingPathComponent("meeting.m4a")
        try Data("outside audio".utf8).write(to: outsideAudio)
        try FileManager.default.createSymbolicLink(
            at: sessionRoot.appendingPathComponent("linked-artifacts", isDirectory: true),
            withDestinationURL: outside
        )
        try writeRepositoryJSON(
            repositorySessionPayload(
                sessionRoot: sessionRoot,
                sessionID: sessionID,
                metadataID: sessionID,
                title: "Linked artifact parent",
                status: "recorded",
                startedAt: "2026-07-12T10:00:00Z",
                endedAt: "2026-07-12T10:30:00Z",
                updatedAt: "2026-07-12T10:30:00Z",
                artifacts: [[
                    "id": "artifact-linked-audio",
                    "session_id": sessionID,
                    "artifact_type": "mixed_audio",
                    "path": "linked-artifacts/meeting.m4a",
                    "capture_status": "available",
                    "checksum": "sha256:untrusted",
                ]]
            ),
            to: sessionRoot.appendingPathComponent("session.json")
        )

        let snapshot = try MeetingSessionWorkspaceRepository().load(workspaceURL: workspace)

        #expect(snapshot.sessions.isEmpty)
        #expect(snapshot.issues.map(\.kind) == [.artifactPathEscape])
        #expect(FileManager.default.fileExists(atPath: outsideAudio.path))
    }

    @Test
    func rejectsSymlinkedWorkspaceAndSessionsRoots() throws {
        let target = try makeRepositoryWorkspace()
        defer { try? FileManager.default.removeItem(at: target) }
        let workspaceLink = FileManager.default.temporaryDirectory
            .appendingPathComponent("ma-session-repository-link-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: workspaceLink) }
        try FileManager.default.createSymbolicLink(at: workspaceLink, withDestinationURL: target)

        do {
            _ = try MeetingSessionWorkspaceRepository().load(workspaceURL: workspaceLink)
            Issue.record("Expected a symlinked workspace to be rejected.")
        } catch let error as MeetingSessionWorkspaceRepositoryError {
            guard case .workspaceSymlink(let path) = error else {
                Issue.record("Expected workspaceSymlink, got \(error).")
                return
            }
            #expect(path == workspaceLink.path)
        }

        let workspace = FileManager.default.temporaryDirectory
            .appendingPathComponent("ma-session-repository-root-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: workspace, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: workspace) }
        try FileManager.default.createSymbolicLink(
            at: workspace.appendingPathComponent("sessions"),
            withDestinationURL: target.appendingPathComponent("sessions")
        )

        do {
            _ = try MeetingSessionWorkspaceRepository().load(workspaceURL: workspace)
            Issue.record("Expected a symlinked sessions root to be rejected.")
        } catch let error as MeetingSessionWorkspaceRepositoryError {
            guard case .sessionsRootSymlink(let path) = error else {
                Issue.record("Expected sessionsRootSymlink, got \(error).")
                return
            }
            #expect(path.hasSuffix("/sessions"))
        }
    }
}

private func makeRepositoryWorkspace() throws -> URL {
    let workspace = FileManager.default.temporaryDirectory
        .appendingPathComponent("ma-session-repository-\(UUID().uuidString)", isDirectory: true)
    try FileManager.default.createDirectory(
        at: workspace.appendingPathComponent("sessions", isDirectory: true),
        withIntermediateDirectories: true
    )
    return workspace
}

private func makeRepositorySessionRoot(workspace: URL, sessionID: String) throws -> URL {
    let sessionRoot = workspace
        .appendingPathComponent("sessions", isDirectory: true)
        .appendingPathComponent(sessionID, isDirectory: true)
    try FileManager.default.createDirectory(
        at: sessionRoot.appendingPathComponent("artifacts", isDirectory: true),
        withIntermediateDirectories: true
    )
    return sessionRoot
}

private func writeRepositorySession(
    workspace: URL,
    sessionID: String,
    metadataID: String? = nil,
    title: String?,
    status: String,
    startedAt: String,
    endedAt: String?,
    updatedAt: String,
    artifacts: [[String: Any]]
) throws {
    let sessionRoot = try makeRepositorySessionRoot(workspace: workspace, sessionID: sessionID)
    var storedArtifacts = artifacts
    for index in storedArtifacts.indices {
        guard let status = storedArtifacts[index]["capture_status"] as? String,
              status == "available" || status == "degraded",
              let path = storedArtifacts[index]["path"] as? String,
              !path.hasPrefix("/"),
              !path.split(separator: "/").contains("..") else {
            continue
        }
        let artifactURL = sessionRoot.appendingPathComponent(path, isDirectory: false)
        try FileManager.default.createDirectory(
            at: artifactURL.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        let data = Data("repository fixture \(storedArtifacts[index]["id"] ?? index)".utf8)
        try data.write(to: artifactURL)
        let digest = SHA256.hash(data: data)
        storedArtifacts[index]["checksum"] = "sha256:" + digest.map {
            String(format: "%02x", $0)
        }.joined()
    }
    try writeRepositoryJSON(
        repositorySessionPayload(
            sessionRoot: sessionRoot,
            sessionID: sessionID,
            metadataID: metadataID ?? sessionID,
            title: title,
            status: status,
            startedAt: startedAt,
            endedAt: endedAt,
            updatedAt: updatedAt,
            artifacts: storedArtifacts
        ),
        to: sessionRoot.appendingPathComponent("session.json")
    )
}

private func repositorySessionPayload(
    sessionRoot: URL,
    sessionID: String,
    metadataID: String,
    title: String?,
    status: String,
    startedAt: String,
    endedAt: String?,
    updatedAt: String,
    artifacts: [[String: Any]]
) -> [String: Any] {
    var payload: [String: Any] = [
        "id": metadataID,
        "source_type": "native_recording",
        "status": status,
        "started_at": startedAt,
        "workspace_dir": sessionRoot.path,
        "created_at": startedAt,
        "updated_at": updatedAt,
        "artifacts": artifacts,
    ]
    if let title {
        payload["title"] = title
    }
    if let endedAt {
        payload["ended_at"] = endedAt
    }
    return payload
}

private func repositoryArtifact(
    id: String,
    sessionID: String,
    type: String,
    path: String,
    status: String
) -> [String: Any] {
    [
        "id": id,
        "session_id": sessionID,
        "artifact_type": type,
        "path": path,
        "format": "json",
        "capture_status": status,
        "created_at": "2026-07-12T10:00:00Z",
    ]
}

private func writeRepositoryJSON(_ object: Any, to url: URL) throws {
    let data = try JSONSerialization.data(withJSONObject: object, options: [.prettyPrinted, .sortedKeys])
    try data.write(to: url)
}

private final class RepositoryChecksumProbe: @unchecked Sendable {
    private let lock = NSLock()
    private var capturedPaths: [String] = []

    var paths: [String] {
        lock.lock()
        defer { lock.unlock() }
        return capturedPaths
    }

    func checksum(of url: URL) -> String? {
        lock.lock()
        capturedPaths.append(url.path)
        lock.unlock()

        guard let data = try? Data(contentsOf: url) else {
            return nil
        }
        let digest = SHA256.hash(data: data)
        return "sha256:" + digest.map { String(format: "%02x", $0) }.joined()
    }
}
