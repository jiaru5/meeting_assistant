import CryptoKit
import Foundation

public enum RecordingSessionStoreError: Error, Equatable, LocalizedError, Sendable {
    case invalidSessionID(String)
    case pathConflict(String)
    case sessionNotFound(String)
    case invalidSessionMetadata(String)
    case unavailableArtifactData(String)

    public var errorDescription: String? {
        switch self {
        case .invalidSessionID(let sessionID):
            return "Session id contains unsupported path characters: \(sessionID)"
        case .pathConflict(let message):
            return message
        case .sessionNotFound(let path):
            return "Recording session metadata was not found at \(path)"
        case .invalidSessionMetadata(let path):
            return "Recording session metadata could not be decoded: \(path)"
        case .unavailableArtifactData(let artifactType):
            return "Native capture did not provide file data for available \(artifactType)."
        }
    }
}

public struct RecordingSessionReference: Equatable, Sendable {
    public let sessionID: String
    public let workspaceURL: URL
    public let sessionURL: URL
    public let artifactsURL: URL

    public init(sessionID: String, workspaceURL: URL, sessionURL: URL, artifactsURL: URL) {
        self.sessionID = sessionID
        self.workspaceURL = workspaceURL
        self.sessionURL = sessionURL
        self.artifactsURL = artifactsURL
    }
}

public struct RecordingSessionStore: Sendable {
    public init() {}

    public static var defaultWorkspaceURL: URL {
        FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Movies", isDirectory: true)
            .appendingPathComponent("MeetingAssistant", isDirectory: true)
    }

    public func makeStartContext(
        request: StartNativeRecordingRequest,
        sessionID: String,
        startedAt: String
    ) throws -> NativeCaptureStartContext {
        guard Self.isValidSessionID(sessionID) else {
            throw RecordingSessionStoreError.invalidSessionID(sessionID)
        }

        let workspaceURL = try plannedWorkspaceRoot(request.workspaceURL ?? Self.defaultWorkspaceURL)
        let sessionURL = workspaceURL
            .appendingPathComponent("sessions", isDirectory: true)
            .appendingPathComponent(sessionID, isDirectory: true)
            .standardizedFileURL
        let artifactsURL = sessionURL.appendingPathComponent("artifacts", isDirectory: true)

        guard Self.isWithin(sessionURL, root: workspaceURL) else {
            throw RecordingSessionStoreError.pathConflict(
                "Recording session path escapes the workspace boundary: \(sessionURL.path)"
            )
        }

        return NativeCaptureStartContext(
            request: request,
            sessionID: sessionID,
            workspaceURL: workspaceURL,
            sessionURL: sessionURL,
            artifactsURL: artifactsURL,
            startedAt: startedAt
        )
    }

    public func createRecordingSession(
        context: NativeCaptureStartContext,
        title: String?
    ) throws -> RecordingSessionReference {
        let workspaceURL = try prepareWorkspaceRoot(context.workspaceURL)
        let sessionsURL = try prepareDirectory(
            workspaceURL.appendingPathComponent("sessions", isDirectory: true),
            boundaryRoot: workspaceURL,
            label: "sessions directory"
        )
        let sessionURL = sessionsURL
            .appendingPathComponent(context.sessionID, isDirectory: true)
            .standardizedFileURL
        guard Self.isWithin(sessionURL, root: workspaceURL) else {
            throw RecordingSessionStoreError.pathConflict(
                "Recording session path escapes the workspace boundary: \(sessionURL.path)"
            )
        }
        guard !Self.fileExists(sessionURL) else {
            throw RecordingSessionStoreError.pathConflict(
                "Recording session already exists: \(sessionURL.path)"
            )
        }

        try FileManager.default.createDirectory(
            at: sessionURL,
            withIntermediateDirectories: false
        )
        let artifactsURL = try prepareDirectory(
            sessionURL.appendingPathComponent("artifacts", isDirectory: true),
            boundaryRoot: sessionURL,
            label: "artifacts directory"
        )
        let reference = RecordingSessionReference(
            sessionID: context.sessionID,
            workspaceURL: workspaceURL,
            sessionURL: sessionURL,
            artifactsURL: artifactsURL
        )

        let metadata = RecordingSessionMetadata(
            id: context.sessionID,
            title: title,
            sourceType: "native_recording",
            status: "recording",
            startedAt: context.startedAt,
            endedAt: nil,
            workspaceDir: sessionURL.path,
            createdAt: context.startedAt,
            updatedAt: context.startedAt,
            artifacts: []
        )
        try writeSession(metadata, reference: reference)
        return reference
    }

    public func finalizeRecording(
        reference: RecordingSessionReference,
        adapterArtifacts: [NativeCaptureArtifactResult],
        endedAt: String,
        defaultFailureReason: String?,
        requestID: String
    ) throws -> RecordingCommandResponse {
        let existing = try loadSession(reference: reference)
        if isFinal(existing) {
            return response(for: existing, requestID: requestID)
        }

        guard existing.status == "recording" else {
            throw RecordingSessionStoreError.pathConflict(
                "Recording session \(reference.sessionID) is not in recording status."
            )
        }

        let artifacts = try materializeArtifacts(
            adapterArtifacts,
            reference: reference,
            createdAt: endedAt,
            defaultFailureReason: defaultFailureReason
        )
        let hasAvailableMedia = artifacts.contains { $0.captureStatus == "available" }
        var finalized = existing
        finalized.status = hasAvailableMedia ? "recorded" : "failed"
        finalized.endedAt = endedAt
        finalized.updatedAt = endedAt
        finalized.artifacts = artifacts

        try writeSession(finalized, reference: reference)
        return response(for: finalized, requestID: requestID)
    }

    public func finalResponseIfAvailable(
        reference: RecordingSessionReference,
        requestID: String
    ) throws -> RecordingCommandResponse? {
        let session = try loadSession(reference: reference)
        guard isFinal(session) else {
            return nil
        }
        return response(for: session, requestID: requestID)
    }

    public func existingSessionReference(
        sessionID: String,
        workspaceURL: URL
    ) throws -> RecordingSessionReference {
        guard Self.isValidSessionID(sessionID) else {
            throw RecordingSessionStoreError.invalidSessionID(sessionID)
        }

        let workspaceRoot = try plannedWorkspaceRoot(workspaceURL)
        let sessionsURL = workspaceRoot.appendingPathComponent("sessions", isDirectory: true)
            .standardizedFileURL
        guard Self.isWithin(sessionsURL, root: workspaceRoot) else {
            throw RecordingSessionStoreError.pathConflict(
                "Recording sessions directory escapes the workspace boundary: \(sessionsURL.path)"
            )
        }
        guard Self.fileExists(sessionsURL) else {
            let sessionJSON = sessionsURL
                .appendingPathComponent(sessionID, isDirectory: true)
                .appendingPathComponent("session.json", isDirectory: false)
            throw RecordingSessionStoreError.sessionNotFound(sessionJSON.path)
        }
        guard Self.isExistingDirectory(sessionsURL), !Self.isSymlink(sessionsURL) else {
            throw RecordingSessionStoreError.pathConflict(
                "Recording sessions directory is not a managed directory: \(sessionsURL.path)"
            )
        }

        let sessionURL = sessionsURL.appendingPathComponent(sessionID, isDirectory: true)
            .standardizedFileURL
        guard Self.isWithin(sessionURL, root: workspaceRoot) else {
            throw RecordingSessionStoreError.pathConflict(
                "Recording session path escapes the workspace boundary: \(sessionURL.path)"
            )
        }
        guard Self.fileExists(sessionURL) else {
            throw RecordingSessionStoreError.sessionNotFound(
                sessionURL.appendingPathComponent("session.json", isDirectory: false).path
            )
        }
        guard Self.isExistingDirectory(sessionURL), !Self.isSymlink(sessionURL) else {
            throw RecordingSessionStoreError.pathConflict(
                "Recording session directory is not a managed directory: \(sessionURL.path)"
            )
        }

        let artifactsURL = sessionURL.appendingPathComponent("artifacts", isDirectory: true)
            .standardizedFileURL
        guard Self.isWithin(artifactsURL, root: sessionURL) else {
            throw RecordingSessionStoreError.pathConflict(
                "Recording artifacts directory escapes the session boundary: \(artifactsURL.path)"
            )
        }
        guard Self.fileExists(artifactsURL),
              Self.isExistingDirectory(artifactsURL),
              !Self.isSymlink(artifactsURL)
        else {
            throw RecordingSessionStoreError.pathConflict(
                "Recording artifacts directory is not a managed directory: \(artifactsURL.path)"
            )
        }

        let reference = RecordingSessionReference(
            sessionID: sessionID,
            workspaceURL: workspaceRoot,
            sessionURL: sessionURL,
            artifactsURL: artifactsURL
        )
        _ = try loadSession(reference: reference)
        return reference
    }

    private func plannedWorkspaceRoot(_ url: URL) throws -> URL {
        let standardized = url.standardizedFileURL
        if Self.fileExists(standardized) {
            guard Self.isExistingDirectory(standardized) else {
                throw RecordingSessionStoreError.pathConflict(
                    "Recording workspace must be a directory: \(standardized.path)"
                )
            }
            guard !Self.isSymlink(standardized) else {
                throw RecordingSessionStoreError.pathConflict(
                    "Recording workspace must not be a symlink: \(standardized.path)"
                )
            }
        }

        let workspaceURL = standardized.resolvingSymlinksInPath().standardizedFileURL
        let sessionsURL = workspaceURL.appendingPathComponent("sessions", isDirectory: true)
        if Self.fileExists(sessionsURL), Self.isSymlink(sessionsURL) {
            throw RecordingSessionStoreError.pathConflict(
                "Recording sessions directory must not be a symlink: \(sessionsURL.path)"
            )
        }
        return workspaceURL
    }

    private func prepareWorkspaceRoot(_ url: URL) throws -> URL {
        let workspaceURL = try plannedWorkspaceRoot(url)
        if !Self.fileExists(workspaceURL) {
            try FileManager.default.createDirectory(at: workspaceURL, withIntermediateDirectories: true)
        }
        guard Self.isExistingDirectory(workspaceURL), !Self.isSymlink(workspaceURL) else {
            throw RecordingSessionStoreError.pathConflict(
                "Recording workspace is not a writable managed directory: \(workspaceURL.path)"
            )
        }
        return workspaceURL
    }

    private func prepareDirectory(
        _ url: URL,
        boundaryRoot: URL,
        label: String
    ) throws -> URL {
        let standardized = url.standardizedFileURL
        guard Self.isWithin(standardized, root: boundaryRoot) else {
            throw RecordingSessionStoreError.pathConflict(
                "Recording \(label) escapes its managed boundary: \(standardized.path)"
            )
        }
        if Self.fileExists(standardized) {
            guard Self.isExistingDirectory(standardized), !Self.isSymlink(standardized) else {
                throw RecordingSessionStoreError.pathConflict(
                    "Recording \(label) is not a managed directory: \(standardized.path)"
                )
            }
            return standardized.resolvingSymlinksInPath().standardizedFileURL
        }

        try FileManager.default.createDirectory(at: standardized, withIntermediateDirectories: false)
        return standardized
    }

    private func loadSession(reference: RecordingSessionReference) throws -> RecordingSessionMetadata {
        let sessionJSON = reference.sessionURL.appendingPathComponent("session.json", isDirectory: false)
        try validateSessionMetadataURL(sessionJSON, sessionRoot: reference.sessionURL)
        do {
            let data = try Data(contentsOf: sessionJSON)
            let session = try JSONDecoder().decode(RecordingSessionMetadata.self, from: data)
            guard session.id == reference.sessionID else {
                throw RecordingSessionStoreError.pathConflict(
                    "Recording session metadata id mismatch; expected \(reference.sessionID), got \(session.id)."
                )
            }
            return session
        } catch let error as RecordingSessionStoreError {
            throw error
        } catch {
            throw RecordingSessionStoreError.invalidSessionMetadata(sessionJSON.path)
        }
    }

    private func writeSession(
        _ session: RecordingSessionMetadata,
        reference: RecordingSessionReference
    ) throws {
        let sessionJSON = reference.sessionURL.appendingPathComponent("session.json", isDirectory: false)
        if Self.fileExists(sessionJSON) {
            try validateSessionMetadataURL(sessionJSON, sessionRoot: reference.sessionURL)
        }

        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
        let data = try encoder.encode(session)
        try data.write(to: sessionJSON, options: [.atomic])
        try validateSessionMetadataURL(sessionJSON, sessionRoot: reference.sessionURL)
    }

    private func validateSessionMetadataURL(_ url: URL, sessionRoot: URL) throws {
        let standardized = url.standardizedFileURL
        guard Self.isWithin(standardized, root: sessionRoot) else {
            throw RecordingSessionStoreError.pathConflict(
                "Recording session metadata escapes the session boundary: \(standardized.path)"
            )
        }
        guard Self.fileExists(standardized) else {
            throw RecordingSessionStoreError.sessionNotFound(standardized.path)
        }
        guard !Self.isSymlink(standardized) else {
            throw RecordingSessionStoreError.pathConflict(
                "Recording session metadata must not be a symlink: \(standardized.path)"
            )
        }
        guard Self.isRegularFile(standardized) else {
            throw RecordingSessionStoreError.pathConflict(
                "Recording session metadata must be a regular file: \(standardized.path)"
            )
        }
        guard !Self.isHardlink(standardized) else {
            throw RecordingSessionStoreError.pathConflict(
                "Recording session metadata must not be a hardlink: \(standardized.path)"
            )
        }

        let resolved = standardized.resolvingSymlinksInPath().standardizedFileURL
        guard Self.isWithin(resolved, root: sessionRoot) else {
            throw RecordingSessionStoreError.pathConflict(
                "Recording session metadata resolves outside the session boundary: \(resolved.path)"
            )
        }
    }

    private func materializeArtifacts(
        _ results: [NativeCaptureArtifactResult],
        reference: RecordingSessionReference,
        createdAt: String,
        defaultFailureReason: String?
    ) throws -> [RecordingArtifactMetadata] {
        let byType = Dictionary(grouping: results, by: \.artifactType)
        for artifactType in NativeCaptureArtifactType.allCases {
            if (byType[artifactType]?.count ?? 0) > 1 {
                throw RecordingSessionStoreError.pathConflict(
                    "Recording capture adapter returned multiple \(artifactType.rawValue) artifacts."
                )
            }
        }

        return try NativeCaptureArtifactType.allCases.map { artifactType in
            let result = byType[artifactType]?.first ?? defaultResult(
                artifactType: artifactType,
                defaultFailureReason: defaultFailureReason
            )
            return try materializeArtifact(
                result,
                reference: reference,
                createdAt: createdAt,
                defaultFailureReason: defaultFailureReason
            )
        }
    }

    private func defaultResult(
        artifactType: NativeCaptureArtifactType,
        defaultFailureReason: String?
    ) -> NativeCaptureArtifactResult {
        if let defaultFailureReason {
            return .failed(
                artifactType,
                reason: "Native capture interrupted before \(artifactType.rawValue) was produced: \(defaultFailureReason)"
            )
        }
        return .missing(
            artifactType,
            reason: "Native capture adapter did not produce \(artifactType.rawValue)."
        )
    }

    private func materializeArtifact(
        _ result: NativeCaptureArtifactResult,
        reference: RecordingSessionReference,
        createdAt: String,
        defaultFailureReason: String?
    ) throws -> RecordingArtifactMetadata {
        let artifactType = result.artifactType
        let format = try safeFormat(result.format ?? artifactType.defaultFormat)
        let relativePath = result.relativePath ?? defaultArtifactRelativePath(
            artifactType: artifactType,
            format: format
        )
        let artifactID = "artifact-\(reference.sessionID)-\(artifactType.rawValue)"

        switch result.status {
        case .available:
            guard let data = result.data else {
                throw RecordingSessionStoreError.unavailableArtifactData(artifactType.rawValue)
            }
            let artifactURL = try managedArtifactURL(
                relativePath: relativePath,
                artifactType: artifactType,
                reference: reference
            )
            try writeAvailableArtifactData(data, to: artifactURL)
            let checksum = try Self.sha256Checksum(for: artifactURL)
            return RecordingArtifactMetadata(
                id: artifactID,
                sessionID: reference.sessionID,
                artifactType: artifactType.rawValue,
                path: relativePath,
                format: format,
                captureStatus: result.status.rawValue,
                degradationReason: nil,
                createdAt: createdAt,
                checksum: checksum
            )
        case .degraded, .missing, .failed:
            let reason = result.degradationReason
                ?? defaultDegradationReason(
                    artifactType: artifactType,
                    status: result.status,
                defaultFailureReason: defaultFailureReason
            )
            let artifactURL = try managedArtifactURL(
                relativePath: relativePath,
                artifactType: artifactType,
                reference: reference
            )
            try validateManagedArtifactRegistrationTarget(artifactURL)
            return RecordingArtifactMetadata(
                id: artifactID,
                sessionID: reference.sessionID,
                artifactType: artifactType.rawValue,
                path: relativePath,
                format: format,
                captureStatus: result.status.rawValue,
                degradationReason: reason,
                createdAt: createdAt,
                checksum: nil
            )
        }
    }

    private func defaultDegradationReason(
        artifactType: NativeCaptureArtifactType,
        status: NativeCaptureArtifactStatus,
        defaultFailureReason: String?
    ) -> String {
        if let defaultFailureReason {
            return "\(artifactType.rawValue) \(status.rawValue): \(defaultFailureReason)"
        }
        return "\(artifactType.rawValue) \(status.rawValue) during native capture."
    }

    private func managedArtifactURL(
        relativePath: String,
        artifactType: NativeCaptureArtifactType,
        reference: RecordingSessionReference
    ) throws -> URL {
        guard !relativePath.isEmpty,
              !relativePath.hasPrefix("/"),
              relativePath.hasPrefix("artifacts/")
        else {
            throw RecordingSessionStoreError.pathConflict(
                "Recording artifact path must be relative to artifacts/: \(relativePath)"
            )
        }

        let components = relativePath.split(separator: "/", omittingEmptySubsequences: false)
        guard components.allSatisfy({ !$0.isEmpty }) else {
            throw RecordingSessionStoreError.pathConflict(
                "Recording artifact path contains empty components: \(relativePath)"
            )
        }
        guard !components.contains(".."), !components.contains(".") else {
            throw RecordingSessionStoreError.pathConflict(
                "Recording artifact path contains traversal components: \(relativePath)"
            )
        }
        guard let filename = components.last,
              filename.hasPrefix("\(artifactType.rawValue).")
        else {
            throw RecordingSessionStoreError.pathConflict(
                "Recording artifact path does not match artifact type \(artifactType.rawValue): \(relativePath)"
            )
        }

        let artifactURL = reference.sessionURL
            .appendingPathComponent(relativePath, isDirectory: false)
            .standardizedFileURL
        guard Self.isWithin(artifactURL, root: reference.artifactsURL) else {
            throw RecordingSessionStoreError.pathConflict(
                "Recording artifact path escapes the artifacts boundary: \(artifactURL.path)"
            )
        }
        return artifactURL
    }

    private func writeAvailableArtifactData(_ data: Data, to url: URL) throws {
        try validateManagedArtifactRegistrationTarget(url)

        if Self.fileExists(url) {
            throw RecordingSessionStoreError.pathConflict(
                "Recording artifact already exists and will not be overwritten: \(url.path)"
            )
        }

        try data.write(to: url, options: [.atomic])
        guard Self.isRegularFile(url), !Self.isSymlink(url), !Self.isHardlink(url) else {
            throw RecordingSessionStoreError.pathConflict(
                "Recording artifact write did not create a managed regular file: \(url.path)"
            )
        }
    }

    private func validateManagedArtifactRegistrationTarget(_ url: URL) throws {
        let parent = url.deletingLastPathComponent()
        guard Self.isExistingDirectory(parent), !Self.isSymlink(parent) else {
            throw RecordingSessionStoreError.pathConflict(
                "Recording artifact parent is not a managed directory: \(parent.path)"
            )
        }

        guard Self.fileExists(url) else {
            return
        }
        guard !Self.isSymlink(url) else {
            throw RecordingSessionStoreError.pathConflict(
                "Recording artifact must not be a symlink: \(url.path)"
            )
        }
        guard Self.isRegularFile(url) else {
            throw RecordingSessionStoreError.pathConflict(
                "Recording artifact must be a regular file: \(url.path)"
            )
        }
        guard !Self.isHardlink(url) else {
            throw RecordingSessionStoreError.pathConflict(
                "Recording artifact must not be a hardlink: \(url.path)"
            )
        }
    }

    private func response(
        for session: RecordingSessionMetadata,
        requestID: String
    ) -> RecordingCommandResponse {
        let artifacts = session.artifacts.map(\.commandArtifact)
        let isRecorded = session.status == "recorded"
        let hasAvailableMedia = artifacts.contains { $0.captureStatus == "available" }
        return RecordingCommandResponse(
            ok: isRecorded && hasAvailableMedia,
            requestID: requestID,
            command: .stopRecording,
            sessionID: session.id,
            status: session.status,
            artifacts: artifacts,
            warnings: [],
            code: isRecorded && hasAvailableMedia ? nil : .captureFailed,
            message: isRecorded && hasAvailableMedia
                ? nil
                : "Native capture did not produce any available media artifacts.",
            details: isRecorded && hasAvailableMedia ? [] : session.artifacts.compactMap(\.degradationReason)
        )
    }

    private func isFinal(_ session: RecordingSessionMetadata) -> Bool {
        (session.status == "recorded" || session.status == "failed") && session.endedAt != nil
    }

    private func defaultArtifactRelativePath(
        artifactType: NativeCaptureArtifactType,
        format: String
    ) -> String {
        "artifacts/\(artifactType.rawValue).\(format)"
    }

    private func safeFormat(_ value: String) throws -> String {
        guard !value.isEmpty,
              value.unicodeScalars.allSatisfy({ scalar in
                  Self.isASCIILetterOrDigit(scalar) || scalar.value == 95 || scalar.value == 45
              })
        else {
            throw RecordingSessionStoreError.pathConflict(
                "Recording artifact format is not safe for a managed filename: \(value)"
            )
        }
        return value
    }

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
        return FileManager.default.fileExists(atPath: url.path, isDirectory: &isDirectory) && isDirectory.boolValue
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
            return false
        }
        return referenceCount.intValue > 1
    }

    private static func sha256Checksum(for url: URL) throws -> String {
        let digest = SHA256.hash(data: try Data(contentsOf: url))
        let hex = digest.map { String(format: "%02x", $0) }.joined()
        return "sha256:\(hex)"
    }
}

private struct RecordingSessionMetadata: Codable, Equatable, Sendable {
    let id: String
    let title: String?
    let sourceType: String
    var status: String
    let startedAt: String
    var endedAt: String?
    let workspaceDir: String
    let createdAt: String
    var updatedAt: String
    var artifacts: [RecordingArtifactMetadata]

    private enum CodingKeys: String, CodingKey {
        case id
        case title
        case sourceType = "source_type"
        case status
        case startedAt = "started_at"
        case endedAt = "ended_at"
        case workspaceDir = "workspace_dir"
        case createdAt = "created_at"
        case updatedAt = "updated_at"
        case artifacts
    }
}

private struct RecordingArtifactMetadata: Codable, Equatable, Sendable {
    let id: String
    let sessionID: String
    let artifactType: String
    let path: String
    let format: String
    let captureStatus: String
    let degradationReason: String?
    let createdAt: String
    let checksum: String?

    var commandArtifact: RecordingCommandArtifact {
        RecordingCommandArtifact(
            id: id,
            sessionID: sessionID,
            artifactType: artifactType,
            format: format,
            path: path,
            captureStatus: captureStatus,
            degradationReason: degradationReason,
            createdAt: createdAt,
            checksum: checksum
        )
    }

    private enum CodingKeys: String, CodingKey {
        case id
        case sessionID = "session_id"
        case artifactType = "artifact_type"
        case path
        case format
        case captureStatus = "capture_status"
        case degradationReason = "degradation_reason"
        case createdAt = "created_at"
        case checksum
    }
}
