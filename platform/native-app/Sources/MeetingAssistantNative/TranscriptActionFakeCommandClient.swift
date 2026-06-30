import Foundation

public actor TranscriptActionFakeCommandClient: TranscriptActionCommandClient {
    public enum ExportScript: Equatable, Sendable {
        case success(
            content: String? = nil,
            exportPackageID: String? = "export-package-fake",
            targetPath: String? = nil,
            warnings: [String] = []
        )
        case failure(
            code: String,
            message: String,
            details: [String] = [],
            warnings: [String] = []
        )
    }

    public enum DeleteScript: Equatable, Sendable {
        case success(
            deletedItems: [String] = [
                "artifacts/transcript.json",
                "artifacts/speaker_labels.json",
            ],
            retainedExternalExports: [String] = [],
            warnings: [String] = []
        )
        case failure(
            code: String,
            message: String,
            details: [String] = [],
            warnings: [String] = []
        )
    }

    public private(set) var exportRequests: [ExportTranscriptRequest] = []
    public private(set) var deleteRequests: [DeleteSessionRequest] = []

    private let exportScript: ExportScript
    private let deleteScript: DeleteScript
    private let responseDelayNanoseconds: UInt64

    public init(
        exportScript: ExportScript = .success(content: "Deterministic transcript content."),
        deleteScript: DeleteScript = .success(),
        responseDelayNanoseconds: UInt64 = 0
    ) {
        self.exportScript = exportScript
        self.deleteScript = deleteScript
        self.responseDelayNanoseconds = responseDelayNanoseconds
    }

    public func exportTranscript(
        _ request: ExportTranscriptRequest
    ) async throws -> ExportTranscriptResponse {
        exportRequests.append(request)
        await delayIfNeeded()

        switch exportScript {
        case .success(let content, let exportPackageID, let targetPath, let warnings):
            return ExportTranscriptResponse(
                ok: true,
                requestID: "local-fake-export",
                sessionID: request.sessionID,
                exportType: request.exportType,
                exportPackageID: exportPackageID,
                targetPath: request.targetPath.map { targetPath ?? $0 },
                content: request.targetPath == nil ? content : nil,
                warnings: warnings
            )
        case .failure(let code, let message, let details, let warnings):
            return ExportTranscriptResponse(
                ok: false,
                requestID: "local-fake-export-failure",
                sessionID: request.sessionID,
                exportType: request.exportType,
                warnings: warnings,
                code: TranscriptActionErrorCode(rawValue: code),
                message: message,
                details: details
            )
        }
    }

    public func deleteSession(
        _ request: DeleteSessionRequest
    ) async throws -> DeleteSessionResponse {
        deleteRequests.append(request)
        await delayIfNeeded()

        switch deleteScript {
        case .success(let deletedItems, let retainedExternalExports, let warnings):
            return DeleteSessionResponse(
                ok: true,
                requestID: "local-fake-delete",
                sessionID: request.sessionID,
                deleted: true,
                deletedItems: deletedItems,
                retainedExternalExports: retainedExternalExports,
                warnings: warnings
            )
        case .failure(let code, let message, let details, let warnings):
            return DeleteSessionResponse(
                ok: false,
                requestID: "local-fake-delete-failure",
                sessionID: request.sessionID,
                warnings: warnings,
                code: TranscriptActionErrorCode(rawValue: code),
                message: message,
                details: details
            )
        }
    }

    public func exportRequestSnapshot() -> [ExportTranscriptRequest] {
        exportRequests
    }

    public func deleteRequestSnapshot() -> [DeleteSessionRequest] {
        deleteRequests
    }

    private func delayIfNeeded() async {
        guard responseDelayNanoseconds > 0 else {
            return
        }
        try? await Task.sleep(nanoseconds: responseDelayNanoseconds)
    }
}

public actor TranscriptActionMemoryClipboard: TranscriptClipboardWriting {
    public private(set) var contents: [String] = []

    public init() {}

    public var latestContent: String? {
        contents.last
    }

    public func latestContentSnapshot() -> String? {
        latestContent
    }

    public func writeTranscript(_ content: String) async {
        contents.append(content)
    }
}

public actor TranscriptActionStaticDestinationSelector: TranscriptExportDestinationSelecting {
    public private(set) var requests: [TranscriptExportDestinationRequest] = []

    private let targetPath: String?

    public init(targetPath: String? = "/tmp/meeting-assistant-transcript.md") {
        self.targetPath = targetPath
    }

    public func destination(for request: TranscriptExportDestinationRequest) async -> String? {
        requests.append(request)
        return targetPath
    }

    public func requestSnapshot() -> [TranscriptExportDestinationRequest] {
        requests
    }
}
