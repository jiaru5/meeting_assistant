import CryptoKit
import Foundation

public struct MeetingProcessableAudioSource: Identifiable, Equatable, Sendable {
    public let id: String
    public let artifactType: String

    public init(id: String, artifactType: String) {
        self.id = id
        self.artifactType = artifactType
    }

    static func providerCompatibleSources(
        from candidates: [MeetingProcessableAudioSource]
    ) -> [MeetingProcessableAudioSource] {
        if let mixedAudio = candidates.first(where: { $0.artifactType == "mixed_audio" }) {
            return [mixedAudio]
        }

        if let normalizedAudio = candidates.first(where: { $0.artifactType == "normalized_audio" }) {
            return [normalizedAudio]
        }

        return ["system_audio", "microphone_audio"].compactMap { artifactType in
            candidates.first(where: { $0.artifactType == artifactType })
        }
    }
}

public struct MeetingSessionSummary: Identifiable, Equatable, Sendable {
    public let id: String
    public let title: String?
    public let status: String
    public let startedAt: String
    public let endedAt: String?
    public let updatedAt: String
    public let durationLabel: String?
    public let artifactCount: Int
    public let hasTranscript: Bool
    public let hasRegisteredTranscript: Bool
    public let hasSpeakerLabels: Bool
    public let hasProcessableAudio: Bool
    public let processableAudioSources: [MeetingProcessableAudioSource]

    public init(
        id: String,
        title: String?,
        status: String,
        startedAt: String,
        endedAt: String?,
        updatedAt: String,
        durationLabel: String?,
        artifactCount: Int,
        hasTranscript: Bool,
        hasSpeakerLabels: Bool,
        hasProcessableAudio: Bool,
        processableAudioSources: [MeetingProcessableAudioSource] = [],
        hasRegisteredTranscript: Bool? = nil
    ) {
        self.id = id
        self.title = title
        self.status = status
        self.startedAt = startedAt
        self.endedAt = endedAt
        self.updatedAt = updatedAt
        self.durationLabel = durationLabel
        self.artifactCount = artifactCount
        self.hasTranscript = hasTranscript
        self.hasRegisteredTranscript = hasRegisteredTranscript ?? hasTranscript
        self.hasSpeakerLabels = hasSpeakerLabels
        self.hasProcessableAudio = hasProcessableAudio
        self.processableAudioSources = processableAudioSources
    }
}

public struct MeetingSessionWorkspaceIssue: Error, Equatable, LocalizedError, Sendable {
    public enum Kind: String, Equatable, Sendable {
        case invalidSessionEntry
        case unsafeSessionEntry
        case missingMetadata
        case unsafeMetadata
        case invalidMetadata
        case sessionIDMismatch
        case artifactSessionMismatch
        case artifactPathEscape
    }

    public let kind: Kind
    public let sessionID: String?
    public let path: String
    public let reason: String

    public init(kind: Kind, sessionID: String?, path: String, reason: String) {
        self.kind = kind
        self.sessionID = sessionID
        self.path = path
        self.reason = reason
    }

    public var errorDescription: String? {
        "\(path): \(reason)"
    }
}

public struct MeetingSessionWorkspaceSnapshot: Equatable, Sendable {
    public let sessions: [MeetingSessionSummary]
    public let issues: [MeetingSessionWorkspaceIssue]

    public init(
        sessions: [MeetingSessionSummary],
        issues: [MeetingSessionWorkspaceIssue]
    ) {
        self.sessions = sessions
        self.issues = issues
    }
}

public enum MeetingSessionWorkspaceRepositoryError: Error, Equatable, LocalizedError, Sendable {
    case workspaceSymlink(String)
    case workspaceNotDirectory(String)
    case sessionsRootSymlink(String)
    case sessionsRootNotDirectory(String)
    case sessionsRootEscape(String)
    case sessionsRootUnreadable(String)
    case selectedSessionDeleted(String)

    public var errorDescription: String? {
        switch self {
        case .workspaceSymlink(let path):
            return "Meeting workspace must not be a symlink: \(path)"
        case .workspaceNotDirectory(let path):
            return "Meeting workspace must be a directory: \(path)"
        case .sessionsRootSymlink(let path):
            return "Meeting sessions directory must not be a symlink: \(path)"
        case .sessionsRootNotDirectory(let path):
            return "Meeting sessions directory must be a directory: \(path)"
        case .sessionsRootEscape(let path):
            return "Meeting sessions directory escapes the workspace boundary: \(path)"
        case .sessionsRootUnreadable(let path):
            return "Meeting sessions directory could not be read: \(path)"
        case .selectedSessionDeleted(let sessionID):
            return "Meeting session is marked deleted and cannot be opened: \(sessionID)"
        }
    }
}

/// Builds the existing meeting-session list projection directly from managed
/// `session.json` files. It never creates, mutates, or follows content outside
/// the supplied workspace.
private enum ArtifactContentValidation: Sendable {
    case projection
    case selectedSession
}

public struct MeetingSessionWorkspaceRepository: Sendable {
    private let checksumCalculator: @Sendable (URL) -> String?

    public init() {
        checksumCalculator = Self.sha256Checksum
    }

    init(checksumCalculator: @escaping @Sendable (URL) -> String?) {
        self.checksumCalculator = checksumCalculator
    }

    public func load(workspaceURL: URL) throws -> MeetingSessionWorkspaceSnapshot {
        try Task.checkCancellation()
        guard let sessionsRoot = try validatedSessionsRoot(workspaceURL: workspaceURL) else {
            return MeetingSessionWorkspaceSnapshot(sessions: [], issues: [])
        }

        let entries: [URL]
        do {
            entries = try FileManager.default.contentsOfDirectory(
                at: sessionsRoot,
                includingPropertiesForKeys: [.isDirectoryKey, .isSymbolicLinkKey],
                options: []
            )
        } catch {
            throw MeetingSessionWorkspaceRepositoryError.sessionsRootUnreadable(sessionsRoot.path)
        }
        try Task.checkCancellation()

        var sessions: [MeetingSessionSummary] = []
        var issues: [MeetingSessionWorkspaceIssue] = []
        for entry in entries.sorted(by: { $0.lastPathComponent < $1.lastPathComponent }) {
            try Task.checkCancellation()
            switch loadSession(
                entry: entry,
                sessionsRoot: sessionsRoot,
                contentValidation: .projection
            ) {
            case .success(let summary) where summary.status != "deleted":
                sessions.append(summary)
            case .success:
                break
            case .failure(let issue):
                issues.append(issue)
            }
        }

        sessions.sort(by: Self.isMoreRecent)
        return MeetingSessionWorkspaceSnapshot(sessions: sessions, issues: issues)
    }

    /// Strictly validates one user-selected meeting, including every checksum
    /// the processing provider verifies before accepting a transcript request.
    /// Recent-list loading intentionally defers payload hashing so a large
    /// meeting archive cannot make app startup hash every historical media file.
    public func loadSelectedSession(
        workspaceURL: URL,
        sessionID: String
    ) throws -> MeetingSessionSummary? {
        guard Self.isValidSessionID(sessionID) else {
            throw issue(
                .invalidSessionEntry,
                sessionID: nil,
                path: sessionID,
                reason: "Session id is not valid."
            )
        }
        guard let sessionsRoot = try validatedSessionsRoot(workspaceURL: workspaceURL) else {
            return nil
        }
        let entry = sessionsRoot
            .appendingPathComponent(sessionID, isDirectory: true)
            .standardizedFileURL
        guard Self.fileExists(entry) else {
            return nil
        }

        switch loadSession(
            entry: entry,
            sessionsRoot: sessionsRoot,
            contentValidation: .selectedSession
        ) {
        case .success(let summary) where summary.status != "deleted":
            return summary
        case .success:
            throw MeetingSessionWorkspaceRepositoryError.selectedSessionDeleted(sessionID)
        case .failure(let issue):
            throw issue
        }
    }

    private func validatedSessionsRoot(workspaceURL: URL) throws -> URL? {
        let requestedWorkspace = workspaceURL.standardizedFileURL
        guard Self.fileExists(requestedWorkspace) else {
            return nil
        }
        guard !Self.isSymlink(requestedWorkspace) else {
            throw MeetingSessionWorkspaceRepositoryError.workspaceSymlink(requestedWorkspace.path)
        }
        guard Self.isExistingDirectory(requestedWorkspace) else {
            throw MeetingSessionWorkspaceRepositoryError.workspaceNotDirectory(requestedWorkspace.path)
        }

        let workspaceRoot = requestedWorkspace.resolvingSymlinksInPath().standardizedFileURL
        let requestedSessionsRoot = workspaceRoot
            .appendingPathComponent("sessions", isDirectory: true)
            .standardizedFileURL
        guard Self.fileExists(requestedSessionsRoot) else {
            return nil
        }
        guard !Self.isSymlink(requestedSessionsRoot) else {
            throw MeetingSessionWorkspaceRepositoryError.sessionsRootSymlink(requestedSessionsRoot.path)
        }
        guard Self.isExistingDirectory(requestedSessionsRoot) else {
            throw MeetingSessionWorkspaceRepositoryError.sessionsRootNotDirectory(requestedSessionsRoot.path)
        }

        let sessionsRoot = requestedSessionsRoot.resolvingSymlinksInPath().standardizedFileURL
        guard Self.isWithin(sessionsRoot, root: workspaceRoot) else {
            throw MeetingSessionWorkspaceRepositoryError.sessionsRootEscape(sessionsRoot.path)
        }
        return sessionsRoot
    }

    private func loadSession(
        entry: URL,
        sessionsRoot: URL,
        contentValidation: ArtifactContentValidation
    ) -> Result<MeetingSessionSummary, MeetingSessionWorkspaceIssue> {
        let sessionID = entry.lastPathComponent
        guard Self.isValidSessionID(sessionID) else {
            return .failure(issue(
                .invalidSessionEntry,
                sessionID: nil,
                path: entry.path,
                reason: "Session directory name is not a valid session id."
            ))
        }
        guard !Self.isSymlink(entry), Self.isExistingDirectory(entry) else {
            return .failure(issue(
                .unsafeSessionEntry,
                sessionID: sessionID,
                path: entry.path,
                reason: "Session entry must be a managed directory and must not be a symlink."
            ))
        }

        let sessionRoot = entry.resolvingSymlinksInPath().standardizedFileURL
        guard Self.isWithin(sessionRoot, root: sessionsRoot) else {
            return .failure(issue(
                .unsafeSessionEntry,
                sessionID: sessionID,
                path: sessionRoot.path,
                reason: "Session directory resolves outside the managed sessions directory."
            ))
        }

        let sessionJSON = sessionRoot.appendingPathComponent("session.json", isDirectory: false)
        guard Self.fileExists(sessionJSON) else {
            return .failure(issue(
                .missingMetadata,
                sessionID: sessionID,
                path: sessionJSON.path,
                reason: "Session metadata was not found."
            ))
        }
        guard !Self.isSymlink(sessionJSON),
              Self.isRegularFile(sessionJSON),
              !Self.isHardlink(sessionJSON)
        else {
            return .failure(issue(
                .unsafeMetadata,
                sessionID: sessionID,
                path: sessionJSON.path,
                reason: "Session metadata must be a managed regular file, not a symlink or hardlink."
            ))
        }

        let resolvedSessionJSON = sessionJSON.resolvingSymlinksInPath().standardizedFileURL
        guard Self.isWithin(resolvedSessionJSON, root: sessionRoot) else {
            return .failure(issue(
                .unsafeMetadata,
                sessionID: sessionID,
                path: resolvedSessionJSON.path,
                reason: "Session metadata resolves outside the managed session directory."
            ))
        }

        let metadata: WorkspaceSessionMetadata
        do {
            metadata = try JSONDecoder().decode(
                WorkspaceSessionMetadata.self,
                from: Data(contentsOf: resolvedSessionJSON)
            )
        } catch {
            return .failure(issue(
                .invalidMetadata,
                sessionID: sessionID,
                path: sessionJSON.path,
                reason: "Session metadata could not be decoded."
            ))
        }

        guard metadata.id == sessionID else {
            return .failure(issue(
                .sessionIDMismatch,
                sessionID: sessionID,
                path: sessionJSON.path,
                reason: "Session metadata id \(metadata.id) does not match directory \(sessionID)."
            ))
        }

        guard Self.validSessionStatuses.contains(metadata.status) else {
            return .failure(issue(
                .invalidMetadata,
                sessionID: sessionID,
                path: sessionJSON.path,
                reason: "Session metadata status \(metadata.status) is not a defined MeetingSessionStatus."
            ))
        }

        if let mismatchedArtifact = metadata.artifacts.first(where: { $0.sessionID != sessionID }) {
            return .failure(issue(
                .artifactSessionMismatch,
                sessionID: sessionID,
                path: sessionJSON.path,
                reason: "Artifact \(mismatchedArtifact.id) belongs to another session."
            ))
        }

        if let escapingArtifact = metadata.artifacts.first(where: {
            !Self.artifactPathIsWithinSession($0.path, sessionRoot: sessionRoot)
        }) {
            return .failure(issue(
                .artifactPathEscape,
                sessionID: sessionID,
                path: escapingArtifact.path,
                reason: "Artifact \(escapingArtifact.id) path escapes the managed session directory."
            ))
        }

        return .success(summary(
            from: metadata,
            sessionRoot: sessionRoot,
            contentValidation: contentValidation
        ))
    }

    private func issue(
        _ kind: MeetingSessionWorkspaceIssue.Kind,
        sessionID: String?,
        path: String,
        reason: String
    ) -> MeetingSessionWorkspaceIssue {
        MeetingSessionWorkspaceIssue(
            kind: kind,
            sessionID: sessionID,
            path: path,
            reason: reason
        )
    }

    private func summary(
        from metadata: WorkspaceSessionMetadata,
        sessionRoot: URL,
        contentValidation: ArtifactContentValidation
    ) -> MeetingSessionSummary {
        let readableArtifacts = metadata.artifacts.filter(\.isReadable)
        let processableAudioTypes: Set<String> = [
            "mixed_audio",
            "system_audio",
            "microphone_audio",
            "normalized_audio",
        ]
        let processingIntegrityTypes: Set<String> = [
            "screen_video",
            "system_audio",
            "microphone_audio",
            "mixed_audio",
            "normalized_audio",
        ]
        let pathSafeReadableArtifacts = readableArtifacts.filter { artifact in
            artifactIsUsableFile(
                artifact,
                sessionRoot: sessionRoot,
                contentValidation: .projection
            )
        }
        let processingIntegrityArtifacts = metadata.artifacts.filter { artifact in
            processingIntegrityTypes.contains(artifact.artifactType)
                && artifact.checksum?.isEmpty == false
        }
        let processingValidatedArtifacts = processingIntegrityArtifacts.filter { artifact in
            artifactIsUsableFile(
                artifact,
                sessionRoot: sessionRoot,
                contentValidation: contentValidation
            )
        }
        let processingIntegrityPasses =
            processingValidatedArtifacts.count == processingIntegrityArtifacts.count
        let processingValidatedIDs = Set(processingValidatedArtifacts.map(\.id))
        let processableAudioCandidates: [MeetingProcessableAudioSource] = readableArtifacts
            .compactMap { artifact in
                guard processableAudioTypes.contains(artifact.artifactType) else {
                    return nil
                }
                return MeetingProcessableAudioSource(
                    id: artifact.id,
                    artifactType: artifact.artifactType
                )
            }
        let providerCompatibleAudioSources = MeetingProcessableAudioSource.providerCompatibleSources(
            from: processableAudioCandidates
        )
        let processableAudioSources = processingIntegrityPasses
            ? providerCompatibleAudioSources.filter { processingValidatedIDs.contains($0.id) }
            : []
        let transcriptCandidates = pathSafeReadableArtifacts.filter {
            $0.artifactType == "transcript_text"
        }
        let transcriptArtifacts = transcriptCandidates.filter { artifact in
            artifactIsUsableFile(
                artifact,
                sessionRoot: sessionRoot,
                contentValidation: contentValidation
            )
        }
        let speakerLabelCandidates = pathSafeReadableArtifacts.filter {
            $0.artifactType == "speaker_labels"
        }
        let speakerLabelArtifacts = speakerLabelCandidates.filter { artifact in
            artifactIsUsableFile(
                artifact,
                sessionRoot: sessionRoot,
                contentValidation: contentValidation
            )
        }
        let contentValidatedIDs = Set(
            processingValidatedArtifacts.map(\.id)
                + transcriptArtifacts.map(\.id)
                + speakerLabelArtifacts.map(\.id)
        )
        let contentCheckedIDs = Set(
            processingIntegrityArtifacts.map(\.id)
                + transcriptCandidates.map(\.id)
                + speakerLabelCandidates.map(\.id)
        )
        let artifactCount = pathSafeReadableArtifacts.filter { artifact in
            if contentCheckedIDs.contains(artifact.id) {
                return contentValidatedIDs.contains(artifact.id)
            }
            return true
        }.count
        return MeetingSessionSummary(
            id: metadata.id,
            title: metadata.title,
            status: metadata.status,
            startedAt: metadata.startedAt,
            endedAt: metadata.endedAt,
            updatedAt: metadata.updatedAt,
            durationLabel: Self.durationLabel(
                startedAt: metadata.startedAt,
                endedAt: metadata.endedAt
            ),
            artifactCount: artifactCount,
            hasTranscript: !transcriptArtifacts.isEmpty,
            hasSpeakerLabels: !speakerLabelArtifacts.isEmpty,
            hasProcessableAudio: !processableAudioSources.isEmpty,
            processableAudioSources: processableAudioSources,
            hasRegisteredTranscript: metadata.artifacts.contains {
                $0.artifactType == "transcript_text"
            }
        )
    }

    private func artifactIsUsableFile(
        _ artifact: WorkspaceSessionArtifact,
        sessionRoot: URL,
        contentValidation: ArtifactContentValidation
    ) -> Bool {
        guard let checksum = artifact.checksum, !checksum.isEmpty else {
            return false
        }
        let requested = artifact.path.hasPrefix("/")
            ? URL(fileURLWithPath: artifact.path, isDirectory: false)
            : sessionRoot.appendingPathComponent(artifact.path, isDirectory: false)
        let artifactURL = requested.standardizedFileURL
        let resolvedArtifactURL = artifactURL.resolvingSymlinksInPath().standardizedFileURL
        guard Self.isWithin(artifactURL, root: sessionRoot),
              resolvedArtifactURL.path == artifactURL.path,
              Self.isWithin(resolvedArtifactURL, root: sessionRoot),
              !Self.isSymlink(artifactURL),
              !Self.isHardlink(artifactURL),
              Self.isRegularFile(artifactURL) else {
            return false
        }
        switch contentValidation {
        case .projection:
            return true
        case .selectedSession:
            return checksumCalculator(artifactURL) == checksum
        }
    }

    private static func sha256Checksum(of url: URL) -> String? {
        guard let handle = try? FileHandle(forReadingFrom: url) else {
            return nil
        }
        defer { try? handle.close() }

        var hasher = SHA256()
        do {
            while let chunk = try handle.read(upToCount: 1_048_576), !chunk.isEmpty {
                hasher.update(data: chunk)
            }
        } catch {
            return nil
        }
        let digest = hasher.finalize()
        return "sha256:" + digest.map { String(format: "%02x", $0) }.joined()
    }

    private static func isMoreRecent(
        _ lhs: MeetingSessionSummary,
        _ rhs: MeetingSessionSummary
    ) -> Bool {
        let lhsDate = parseDate(lhs.updatedAt) ?? parseDate(lhs.startedAt)
        let rhsDate = parseDate(rhs.updatedAt) ?? parseDate(rhs.startedAt)
        switch (lhsDate, rhsDate) {
        case let (lhsDate?, rhsDate?) where lhsDate != rhsDate:
            return lhsDate > rhsDate
        case (_?, nil):
            return true
        case (nil, _?):
            return false
        default:
            if lhs.updatedAt != rhs.updatedAt {
                return lhs.updatedAt > rhs.updatedAt
            }
            return lhs.id < rhs.id
        }
    }

    private static func durationLabel(startedAt: String, endedAt: String?) -> String? {
        guard let endedAt,
              let start = parseDate(startedAt),
              let end = parseDate(endedAt),
              end >= start
        else {
            return nil
        }
        let seconds = Int(end.timeIntervalSince(start))
        let hours = seconds / 3_600
        let minutes = (seconds % 3_600) / 60
        let remainingSeconds = seconds % 60
        if hours > 0 {
            return String(format: "%d:%02d:%02d", hours, minutes, remainingSeconds)
        }
        return String(format: "%02d:%02d", minutes, remainingSeconds)
    }

    private static func parseDate(_ value: String) -> Date? {
        let fractional = ISO8601DateFormatter()
        fractional.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        if let date = fractional.date(from: value) {
            return date
        }
        return ISO8601DateFormatter().date(from: value)
    }

    private static func artifactPathIsWithinSession(_ path: String, sessionRoot: URL) -> Bool {
        guard !path.isEmpty else {
            return false
        }
        let requested = path.hasPrefix("/")
            ? URL(fileURLWithPath: path, isDirectory: false)
            : sessionRoot.appendingPathComponent(path, isDirectory: false)
        let artifactURL = requested.standardizedFileURL
        let resolvedArtifactURL = artifactURL.resolvingSymlinksInPath().standardizedFileURL
        return isWithin(artifactURL, root: sessionRoot)
            && isWithin(resolvedArtifactURL, root: sessionRoot)
    }

    private static let validSessionStatuses: Set<String> = [
        "created",
        "recording",
        "recorded",
        "processing",
        "transcribed",
        "failed",
        "deleted",
    ]

    private static func isValidSessionID(_ value: String) -> Bool {
        guard value.count <= 128,
              let first = value.unicodeScalars.first,
              isASCIILetterOrDigit(first)
        else {
            return false
        }
        return value.unicodeScalars.allSatisfy { scalar in
            isASCIILetterOrDigit(scalar) || scalar.value == 95 || scalar.value == 46 || scalar.value == 45
        }
    }

    private static func isASCIILetterOrDigit(_ scalar: UnicodeScalar) -> Bool {
        switch scalar.value {
        case 48...57, 65...90, 97...122:
            return true
        default:
            return false
        }
    }

    private static func isWithin(_ candidate: URL, root: URL) -> Bool {
        let rootPath = root.standardizedFileURL.path
        let candidatePath = candidate.standardizedFileURL.path
        return candidatePath == rootPath || candidatePath.hasPrefix("\(rootPath)/")
    }

    private static func fileExists(_ url: URL) -> Bool {
        FileManager.default.fileExists(atPath: url.path)
    }

    private static func isExistingDirectory(_ url: URL) -> Bool {
        var isDirectory: ObjCBool = false
        return FileManager.default.fileExists(atPath: url.path, isDirectory: &isDirectory)
            && isDirectory.boolValue
    }

    private static func isRegularFile(_ url: URL) -> Bool {
        (try? url.resourceValues(forKeys: [.isRegularFileKey]).isRegularFile) == true
    }

    private static func isSymlink(_ url: URL) -> Bool {
        (try? url.resourceValues(forKeys: [.isSymbolicLinkKey]).isSymbolicLink) == true
    }

    private static func isHardlink(_ url: URL) -> Bool {
        guard let referenceCount = try? FileManager.default
            .attributesOfItem(atPath: url.path)[.referenceCount] as? NSNumber
        else {
            return true
        }
        return referenceCount.intValue > 1
    }
}

private struct WorkspaceSessionMetadata: Decodable {
    let id: String
    let title: String?
    let status: String
    let startedAt: String
    let endedAt: String?
    let updatedAt: String
    let artifacts: [WorkspaceSessionArtifact]

    private enum CodingKeys: String, CodingKey {
        case id
        case title
        case status
        case startedAt = "started_at"
        case endedAt = "ended_at"
        case updatedAt = "updated_at"
        case artifacts
    }
}

private struct WorkspaceSessionArtifact: Decodable {
    let id: String
    let sessionID: String
    let artifactType: String
    let path: String
    let captureStatus: String
    let checksum: String?

    var isReadable: Bool {
        captureStatus == "available" || captureStatus == "degraded"
    }

    private enum CodingKeys: String, CodingKey {
        case id
        case sessionID = "session_id"
        case artifactType = "artifact_type"
        case path
        case captureStatus = "capture_status"
        case checksum
    }
}
