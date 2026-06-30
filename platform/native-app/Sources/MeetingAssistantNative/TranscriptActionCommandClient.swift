import Foundation

private enum TranscriptActionDetailsValue: Decodable {
    case string(String)
    case number(String)
    case bool(Bool)
    case array([TranscriptActionDetailsValue])
    case object([String: TranscriptActionDetailsValue])
    case null

    init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        if container.decodeNil() {
            self = .null
        } else if let object = try? container.decode([String: TranscriptActionDetailsValue].self) {
            self = .object(object)
        } else if let array = try? container.decode([TranscriptActionDetailsValue].self) {
            self = .array(array)
        } else if let string = try? container.decode(String.self) {
            self = .string(string)
        } else if let bool = try? container.decode(Bool.self) {
            self = .bool(bool)
        } else if let int = try? container.decode(Int.self) {
            self = .number(String(int))
        } else if let double = try? container.decode(Double.self) {
            self = .number(String(double))
        } else {
            throw DecodingError.dataCorruptedError(
                in: container,
                debugDescription: "Unsupported transcript action details shape."
            )
        }
    }

    var summaryLines: [String] {
        switch self {
        case .string(let value), .number(let value):
            return value.isEmpty ? [] : [value]
        case .bool(let value):
            return [String(value)]
        case .array(let values):
            return values.flatMap(\.summaryLines)
        case .object(let object):
            return object.keys.sorted().flatMap { key in
                guard let value = object[key] else {
                    return [String]()
                }
                let lines = value.summaryLines
                guard !lines.isEmpty else {
                    return [String]()
                }
                return lines.map { "\(key): \($0)" }
            }
        case .null:
            return []
        }
    }
}

private func decodeTranscriptActionDetails<Key: CodingKey>(
    from container: KeyedDecodingContainer<Key>,
    forKey key: Key
) throws -> [String] {
    guard container.contains(key) else {
        return []
    }
    guard !(try container.decodeNil(forKey: key)) else {
        return []
    }
    return try container.decode(TranscriptActionDetailsValue.self, forKey: key).summaryLines
}

public enum TranscriptActionCommandName: String, Decodable, Equatable, Sendable {
    case exportTranscript = "export_transcript"
    case deleteSession = "delete_session"
}

public enum TranscriptExportType: String, Codable, Equatable, Sendable {
    case plainText = "plain_text"
    case markdown
    case json
}

public struct TranscriptActionErrorCode: RawRepresentable, Equatable, Sendable, ExpressibleByStringLiteral {
    public let rawValue: String

    public init(rawValue: String) {
        self.rawValue = rawValue
    }

    public init(stringLiteral value: StringLiteralType) {
        self.rawValue = value
    }
}

public struct ExportTranscriptRequest: Equatable, Sendable {
    public let sessionID: String
    public let exportType: TranscriptExportType
    public let targetPath: String?

    public init(
        sessionID: String,
        exportType: TranscriptExportType,
        targetPath: String? = nil
    ) {
        self.sessionID = sessionID
        self.exportType = exportType
        self.targetPath = targetPath
    }
}

public struct DeleteSessionRequest: Equatable, Sendable {
    public let sessionID: String
    public let workspaceDir: String?
    public let confirm: Bool

    public init(
        sessionID: String,
        workspaceDir: String? = nil,
        confirm: Bool
    ) {
        self.sessionID = sessionID
        self.workspaceDir = workspaceDir
        self.confirm = confirm
    }
}

public struct ExportTranscriptResponse: Decodable, Equatable, Sendable {
    public let ok: Bool
    public let requestID: String
    public let command: TranscriptActionCommandName
    public let sessionID: String?
    public let exportType: TranscriptExportType?
    public let exportPackageID: String?
    public let targetPath: String?
    public let content: String?
    public let warnings: [String]
    public let code: TranscriptActionErrorCode?
    public let message: String?
    public let details: [String]

    private enum CodingKeys: String, CodingKey {
        case ok
        case requestID = "request_id"
        case command
        case sessionID = "session_id"
        case exportType = "export_type"
        case exportPackageID = "export_package_id"
        case targetPath = "target_path"
        case content
        case warnings
        case code
        case message
        case details
    }

    public init(
        ok: Bool,
        requestID: String,
        command: TranscriptActionCommandName = .exportTranscript,
        sessionID: String? = nil,
        exportType: TranscriptExportType? = nil,
        exportPackageID: String? = nil,
        targetPath: String? = nil,
        content: String? = nil,
        warnings: [String] = [],
        code: TranscriptActionErrorCode? = nil,
        message: String? = nil,
        details: [String] = []
    ) {
        self.ok = ok
        self.requestID = requestID
        self.command = command
        self.sessionID = sessionID
        self.exportType = exportType
        self.exportPackageID = exportPackageID
        self.targetPath = targetPath
        self.content = content
        self.warnings = warnings
        self.code = code
        self.message = message
        self.details = details
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        ok = try container.decode(Bool.self, forKey: .ok)
        requestID = try container.decode(String.self, forKey: .requestID)
        command = try container.decode(TranscriptActionCommandName.self, forKey: .command)
        sessionID = try container.decodeIfPresent(String.self, forKey: .sessionID)
        exportType = try container.decodeIfPresent(TranscriptExportType.self, forKey: .exportType)
        exportPackageID = try container.decodeIfPresent(String.self, forKey: .exportPackageID)
        targetPath = try container.decodeIfPresent(String.self, forKey: .targetPath)
        content = try container.decodeIfPresent(String.self, forKey: .content)
        warnings = try container.decodeIfPresent([String].self, forKey: .warnings) ?? []
        code = try container
            .decodeIfPresent(String.self, forKey: .code)
            .map(TranscriptActionErrorCode.init(rawValue:))
        message = try container.decodeIfPresent(String.self, forKey: .message)
        details = try decodeTranscriptActionDetails(from: container, forKey: .details)
    }
}

public struct DeleteSessionResponse: Decodable, Equatable, Sendable {
    public let ok: Bool
    public let requestID: String
    public let command: TranscriptActionCommandName
    public let sessionID: String?
    public let deleted: Bool?
    public let deletedItems: [String]
    public let retainedExternalExports: [String]
    public let hasDeletedItemsField: Bool
    public let hasRetainedExternalExportsField: Bool
    public let warnings: [String]
    public let code: TranscriptActionErrorCode?
    public let message: String?
    public let details: [String]

    private enum CodingKeys: String, CodingKey {
        case ok
        case requestID = "request_id"
        case command
        case sessionID = "session_id"
        case deleted
        case deletedItems = "deleted_items"
        case retainedExternalExports = "retained_external_exports"
        case warnings
        case code
        case message
        case details
    }

    public init(
        ok: Bool,
        requestID: String,
        command: TranscriptActionCommandName = .deleteSession,
        sessionID: String? = nil,
        deleted: Bool? = nil,
        deletedItems: [String] = [],
        retainedExternalExports: [String] = [],
        hasDeletedItemsField: Bool = true,
        hasRetainedExternalExportsField: Bool = true,
        warnings: [String] = [],
        code: TranscriptActionErrorCode? = nil,
        message: String? = nil,
        details: [String] = []
    ) {
        self.ok = ok
        self.requestID = requestID
        self.command = command
        self.sessionID = sessionID
        self.deleted = deleted
        self.deletedItems = deletedItems
        self.retainedExternalExports = retainedExternalExports
        self.hasDeletedItemsField = hasDeletedItemsField
        self.hasRetainedExternalExportsField = hasRetainedExternalExportsField
        self.warnings = warnings
        self.code = code
        self.message = message
        self.details = details
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        ok = try container.decode(Bool.self, forKey: .ok)
        requestID = try container.decode(String.self, forKey: .requestID)
        command = try container.decode(TranscriptActionCommandName.self, forKey: .command)
        sessionID = try container.decodeIfPresent(String.self, forKey: .sessionID)
        deleted = try container.decodeIfPresent(Bool.self, forKey: .deleted)
        let hasDeletedItems: Bool
        if container.contains(.deletedItems) {
            hasDeletedItems = !(try container.decodeNil(forKey: .deletedItems))
        } else {
            hasDeletedItems = false
        }
        let hasRetainedExternalExports: Bool
        if container.contains(.retainedExternalExports) {
            hasRetainedExternalExports = !(try container.decodeNil(forKey: .retainedExternalExports))
        } else {
            hasRetainedExternalExports = false
        }
        hasDeletedItemsField = hasDeletedItems
        hasRetainedExternalExportsField = hasRetainedExternalExports
        deletedItems = hasDeletedItems ? try container.decode([String].self, forKey: .deletedItems) : []
        retainedExternalExports = hasRetainedExternalExports
            ? try container.decode([String].self, forKey: .retainedExternalExports)
            : []
        warnings = try container.decodeIfPresent([String].self, forKey: .warnings) ?? []
        code = try container
            .decodeIfPresent(String.self, forKey: .code)
            .map(TranscriptActionErrorCode.init(rawValue:))
        message = try container.decodeIfPresent(String.self, forKey: .message)
        details = try decodeTranscriptActionDetails(from: container, forKey: .details)
    }
}

public struct TranscriptActionCommandFailure: Error, Equatable, LocalizedError, Sendable {
    public let command: TranscriptActionCommandName
    public let code: TranscriptActionErrorCode?
    public let message: String
    public let details: [String]

    public init(
        command: TranscriptActionCommandName,
        code: TranscriptActionErrorCode?,
        message: String,
        details: [String] = []
    ) {
        self.command = command
        self.code = code
        self.message = message
        self.details = details
    }

    public init(response: ExportTranscriptResponse) {
        self.init(
            command: response.command,
            code: response.code,
            message: response.message ?? "Transcript export failed.",
            details: response.details
        )
    }

    public init(response: DeleteSessionResponse) {
        self.init(
            command: response.command,
            code: response.code,
            message: response.message ?? "Session delete failed.",
            details: response.details
        )
    }

    public var errorDescription: String? {
        if let code {
            return "\(message) (\(code.rawValue))"
        }
        return message
    }
}

public struct TranscriptExportDestinationRequest: Equatable, Sendable {
    public let sessionID: String
    public let exportType: TranscriptExportType

    public init(sessionID: String, exportType: TranscriptExportType) {
        self.sessionID = sessionID
        self.exportType = exportType
    }
}

public protocol TranscriptActionCommandClient: Sendable {
    func exportTranscript(_ request: ExportTranscriptRequest) async throws -> ExportTranscriptResponse
    func deleteSession(_ request: DeleteSessionRequest) async throws -> DeleteSessionResponse
}

public protocol TranscriptClipboardWriting: Sendable {
    func writeTranscript(_ content: String) async
}

public protocol TranscriptExportDestinationSelecting: Sendable {
    func destination(for request: TranscriptExportDestinationRequest) async -> String?
}
