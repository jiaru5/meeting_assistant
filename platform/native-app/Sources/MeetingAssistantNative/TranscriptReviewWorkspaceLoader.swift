import CryptoKit
import Foundation

public enum TranscriptReviewWorkspaceLoaderError: Error, Equatable, Sendable, LocalizedError {
    case invalidSessionID(String)
    case sessionNotFound(String)
    case sessionRootSymlink(String)
    case sessionRootEscape(String)
    case sessionMetadataSymlink(String)
    case sessionMetadataHardlink(String)
    case sessionMetadataNotRegularFile(String)
    case invalidSessionMetadata(String)
    case sessionIDMismatch(expected: String, actual: String)
    case artifactSessionMismatch(artifactID: String, expected: String, actual: String)
    case artifactPathEscape(artifactID: String, path: String)
    case artifactSymlink(artifactID: String, path: String)
    case artifactHardlink(artifactID: String, path: String)
    case artifactMissing(artifactID: String, path: String)
    case artifactNotRegularFile(artifactID: String, path: String)
    case invalidArtifactJSON(artifactID: String, path: String)
    case invalidChecksum(artifactID: String, checksum: String)
    case checksumDrift(artifactID: String, expected: String, actual: String)

    public var errorDescription: String? {
        switch self {
        case .invalidSessionID(let sessionID):
            return "Session id contains unsupported path characters: \(sessionID)"
        case .sessionNotFound(let path):
            return "Session metadata was not found at \(path)"
        case .sessionRootSymlink(let path):
            return "Session root must not be a symlink: \(path)"
        case .sessionRootEscape(let path):
            return "Session root escapes the workspace boundary: \(path)"
        case .sessionMetadataSymlink(let path):
            return "Session metadata must not be a symlink: \(path)"
        case .sessionMetadataHardlink(let path):
            return "Session metadata must not be a hardlink: \(path)"
        case .sessionMetadataNotRegularFile(let path):
            return "Session metadata must be a regular file: \(path)"
        case .invalidSessionMetadata(let path):
            return "Session metadata could not be decoded: \(path)"
        case .sessionIDMismatch(let expected, let actual):
            return "Session metadata id mismatch; expected \(expected), got \(actual)"
        case .artifactSessionMismatch(let artifactID, let expected, let actual):
            return "Artifact \(artifactID) session mismatch; expected \(expected), got \(actual)"
        case .artifactPathEscape(let artifactID, let path):
            return "Artifact \(artifactID) path escapes the session boundary: \(path)"
        case .artifactSymlink(let artifactID, let path):
            return "Artifact \(artifactID) must not be a symlink: \(path)"
        case .artifactHardlink(let artifactID, let path):
            return "Artifact \(artifactID) must not be a hardlink: \(path)"
        case .artifactMissing(let artifactID, let path):
            return "Artifact \(artifactID) file was not found: \(path)"
        case .artifactNotRegularFile(let artifactID, let path):
            return "Artifact \(artifactID) must be a regular file: \(path)"
        case .invalidArtifactJSON(let artifactID, let path):
            return "Artifact \(artifactID) JSON could not be decoded: \(path)"
        case .invalidChecksum(let artifactID, let checksum):
            return "Artifact \(artifactID) checksum is invalid: \(checksum)"
        case .checksumDrift(let artifactID, let expected, let actual):
            return "Artifact \(artifactID) checksum drifted; expected \(expected), got \(actual)"
        }
    }
}

public enum TranscriptReviewWorkspaceLoader {
    private static let speakerLabelsUnavailableReason =
        "Speaker labels could not be safely loaded. The transcript is still available."

    public static func load(
        workspaceURL: URL,
        sessionID: String
    ) throws -> TranscriptReviewInput {
        guard isValidSessionID(sessionID) else {
            throw TranscriptReviewWorkspaceLoaderError.invalidSessionID(sessionID)
        }

        let workspaceRoot = workspaceURL.standardizedFileURL.resolvingSymlinksInPath()
        let sessionRoot = try resolveSessionRoot(workspaceRoot: workspaceRoot, sessionID: sessionID)
        let sessionURL = sessionRoot.appendingPathComponent("session.json", isDirectory: false)
        try validateSessionMetadataURL(sessionURL, sessionRoot: sessionRoot)
        let session: WorkspaceSessionMetadata = try decodeSessionMetadata(from: sessionURL)

        guard session.id == sessionID else {
            throw TranscriptReviewWorkspaceLoaderError.sessionIDMismatch(expected: sessionID, actual: session.id)
        }

        guard let transcriptArtifact = session.artifacts.first(where: {
            $0.artifactType == "transcript_text" && $0.isReadableArtifact
        }) else {
            return TranscriptReviewInput(sessionTitle: session.title, transcript: nil)
        }
        try validateArtifactSession(transcriptArtifact, expectedSessionID: sessionID)
        let transcriptPayload = try validatedArtifactPayload(
            sessionRoot: sessionRoot,
            artifact: transcriptArtifact
        )
        let transcript: TranscriptReviewTranscript = try decodeArtifact(
            TranscriptReviewTranscript.self,
            from: transcriptPayload.data,
            path: transcriptPayload.url.path,
            artifactID: transcriptArtifact.id
        )
        guard transcript.sessionID == sessionID else {
            throw TranscriptReviewWorkspaceLoaderError.artifactSessionMismatch(
                artifactID: transcriptArtifact.id,
                expected: sessionID,
                actual: transcript.sessionID
            )
        }

        let speakerArtifact = session.artifacts.first {
            $0.artifactType == "speaker_labels" && $0.isReadableArtifact
        }
        let speakerPayload: (artifact: SpeakerLabelsReviewArtifact?, degradationReason: String?)
        do {
            speakerPayload = try loadSpeakerLabels(
                artifact: speakerArtifact,
                sessionRoot: sessionRoot,
                sessionID: sessionID
            )
        } catch {
            speakerPayload = (nil, speakerLabelsUnavailableReason)
        }

        return TranscriptReviewInput(
            sessionTitle: session.title,
            transcript: transcript,
            speakerLabels: speakerPayload.artifact,
            speakerLabelsDegradationReason: speakerPayload.degradationReason
        )
    }

    private static func loadSpeakerLabels(
        artifact: WorkspaceArtifact?,
        sessionRoot: URL,
        sessionID: String
    ) throws -> (artifact: SpeakerLabelsReviewArtifact?, degradationReason: String?) {
        guard let artifact else {
            return (nil, nil)
        }
        try validateArtifactSession(artifact, expectedSessionID: sessionID)

        let speakerPayload = try validatedArtifactPayload(
            sessionRoot: sessionRoot,
            artifact: artifact
        )
        let speakerLabels: SpeakerLabelsReviewArtifact = try decodeArtifact(
            SpeakerLabelsReviewArtifact.self,
            from: speakerPayload.data,
            path: speakerPayload.url.path,
            artifactID: artifact.id
        )
        guard speakerLabels.sessionID == sessionID else {
            throw TranscriptReviewWorkspaceLoaderError.artifactSessionMismatch(
                artifactID: artifact.id,
                expected: sessionID,
                actual: speakerLabels.sessionID
            )
        }

        let degradationReason = artifact.captureStatus == "degraded"
            ? artifact.degradationReason
            : nil
        return (speakerLabels, degradationReason)
    }

    private static func resolveSessionRoot(workspaceRoot: URL, sessionID: String) throws -> URL {
        let sessionRoot = workspaceRoot
            .appendingPathComponent("sessions", isDirectory: true)
            .appendingPathComponent(sessionID, isDirectory: true)
            .standardizedFileURL

        if isSymlink(sessionRoot) {
            throw TranscriptReviewWorkspaceLoaderError.sessionRootSymlink(sessionRoot.path)
        }

        guard isExistingDirectory(sessionRoot) else {
            throw TranscriptReviewWorkspaceLoaderError.sessionNotFound(
                sessionRoot.appendingPathComponent("session.json", isDirectory: false).path
            )
        }

        let resolved = sessionRoot.resolvingSymlinksInPath().standardizedFileURL
        guard isWithin(resolved, root: workspaceRoot) else {
            throw TranscriptReviewWorkspaceLoaderError.sessionRootEscape(resolved.path)
        }
        return resolved
    }

    private static func validateSessionMetadataURL(_ url: URL, sessionRoot: URL) throws {
        let standardized = url.standardizedFileURL
        guard isWithin(standardized, root: sessionRoot) else {
            throw TranscriptReviewWorkspaceLoaderError.sessionRootEscape(standardized.path)
        }
        guard !isSymlink(standardized) else {
            throw TranscriptReviewWorkspaceLoaderError.sessionMetadataSymlink(standardized.path)
        }
        guard fileExists(standardized) else {
            throw TranscriptReviewWorkspaceLoaderError.sessionNotFound(standardized.path)
        }
        guard isRegularFile(standardized) else {
            throw TranscriptReviewWorkspaceLoaderError.sessionMetadataNotRegularFile(standardized.path)
        }
        guard !isHardlink(standardized) else {
            throw TranscriptReviewWorkspaceLoaderError.sessionMetadataHardlink(standardized.path)
        }

        let resolved = standardized.resolvingSymlinksInPath().standardizedFileURL
        guard isWithin(resolved, root: sessionRoot) else {
            throw TranscriptReviewWorkspaceLoaderError.sessionRootEscape(resolved.path)
        }
    }

    private static func decodeSessionMetadata(from url: URL) throws -> WorkspaceSessionMetadata {
        do {
            let data = try Data(contentsOf: url)
            return try JSONDecoder().decode(WorkspaceSessionMetadata.self, from: data)
        } catch {
            throw TranscriptReviewWorkspaceLoaderError.invalidSessionMetadata(url.path)
        }
    }

    private static func decodeArtifact<T: Decodable>(
        _ type: T.Type,
        from data: Data,
        path: String,
        artifactID: String
    ) throws -> T {
        do {
            return try JSONDecoder().decode(type, from: data)
        } catch {
            throw TranscriptReviewWorkspaceLoaderError.invalidArtifactJSON(
                artifactID: artifactID,
                path: path
            )
        }
    }

    private static func validateArtifactSession(_ artifact: WorkspaceArtifact, expectedSessionID: String) throws {
        guard artifact.sessionID == expectedSessionID else {
            throw TranscriptReviewWorkspaceLoaderError.artifactSessionMismatch(
                artifactID: artifact.id,
                expected: expectedSessionID,
                actual: artifact.sessionID
            )
        }
    }

    private static func validatedArtifactPayload(
        sessionRoot: URL,
        artifact: WorkspaceArtifact
    ) throws -> (url: URL, data: Data) {
        let requested = artifact.path.hasPrefix("/")
            ? URL(fileURLWithPath: artifact.path, isDirectory: false)
            : sessionRoot.appendingPathComponent(artifact.path, isDirectory: false)
        let standardized = requested.standardizedFileURL

        guard isWithin(standardized, root: sessionRoot) else {
            throw TranscriptReviewWorkspaceLoaderError.artifactPathEscape(
                artifactID: artifact.id,
                path: standardized.path
            )
        }
        guard !isSymlink(standardized) else {
            throw TranscriptReviewWorkspaceLoaderError.artifactSymlink(
                artifactID: artifact.id,
                path: standardized.path
            )
        }
        guard fileExists(standardized) else {
            throw TranscriptReviewWorkspaceLoaderError.artifactMissing(
                artifactID: artifact.id,
                path: standardized.path
            )
        }
        guard isRegularFile(standardized) else {
            throw TranscriptReviewWorkspaceLoaderError.artifactNotRegularFile(
                artifactID: artifact.id,
                path: standardized.path
            )
        }
        guard !isHardlink(standardized) else {
            throw TranscriptReviewWorkspaceLoaderError.artifactHardlink(
                artifactID: artifact.id,
                path: standardized.path
            )
        }

        let resolved = standardized.resolvingSymlinksInPath().standardizedFileURL
        guard isWithin(resolved, root: sessionRoot) else {
            throw TranscriptReviewWorkspaceLoaderError.artifactPathEscape(
                artifactID: artifact.id,
                path: resolved.path
            )
        }
        let data = try Data(contentsOf: resolved)
        try validateChecksum(artifact: artifact, data: data)
        return (resolved, data)
    }

    private static func validateChecksum(artifact: WorkspaceArtifact, data: Data) throws {
        guard let checksum = artifact.checksum,
              checksum.hasPrefix("sha256:"),
              checksum.count == "sha256:".count + 64
        else {
            throw TranscriptReviewWorkspaceLoaderError.invalidChecksum(
                artifactID: artifact.id,
                checksum: artifact.checksum ?? ""
            )
        }

        let digest = SHA256.hash(data: data)
        let actual = "sha256:" + digest.map { String(format: "%02x", $0) }.joined()
        guard actual == checksum else {
            throw TranscriptReviewWorkspaceLoaderError.checksumDrift(
                artifactID: artifact.id,
                expected: checksum,
                actual: actual
            )
        }
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
}

private struct WorkspaceSessionMetadata: Decodable {
    let id: String
    let title: String?
    let artifacts: [WorkspaceArtifact]
}

private struct WorkspaceArtifact: Decodable {
    let id: String
    let sessionID: String
    let artifactType: String
    let path: String
    let captureStatus: String
    let checksum: String?
    let degradationReason: String?

    var isReadableArtifact: Bool {
        captureStatus == "available" || captureStatus == "degraded"
    }

    private enum CodingKeys: String, CodingKey {
        case id
        case sessionID = "session_id"
        case artifactType = "artifact_type"
        case path
        case captureStatus = "capture_status"
        case checksum
        case degradationReason = "degradation_reason"
    }
}
