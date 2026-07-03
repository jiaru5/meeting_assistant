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

public enum TranscriptActionBridgeError: Error, Equatable, LocalizedError, Sendable {
    case invalidJSON(command: TranscriptActionCommandName, code: TranscriptActionErrorCode)
    case launchFailed(command: TranscriptActionCommandName)
    case processFailed(command: TranscriptActionCommandName, exitCode: Int32, code: TranscriptActionErrorCode)
    case unexpectedCommand(expected: TranscriptActionCommandName, actual: TranscriptActionCommandName)

    public var command: TranscriptActionCommandName {
        switch self {
        case .invalidJSON(let command, _), .launchFailed(let command), .processFailed(let command, _, _):
            return command
        case .unexpectedCommand(let expected, _):
            return expected
        }
    }

    public var code: TranscriptActionErrorCode {
        switch self {
        case .invalidJSON(_, let code), .processFailed(_, _, let code):
            return code
        case .launchFailed, .unexpectedCommand:
            return "internal_error"
        }
    }

    public var safeMessage: String {
        switch self {
        case .invalidJSON:
            return "Transcript action command returned an invalid response."
        case .launchFailed:
            return "Transcript action command could not be launched."
        case .processFailed:
            return "Transcript action command failed before returning a contract response."
        case .unexpectedCommand:
            return "Transcript action command returned an unexpected response."
        }
    }

    public var errorDescription: String? {
        if case .processFailed(_, let exitCode, _) = self {
            return "\(safeMessage) Exit code: \(exitCode). Error code: \(code.rawValue)."
        }
        return "\(safeMessage) Error code: \(code.rawValue)."
    }
}

public enum TranscriptActionResponseDecoder {
    public static func decodeExport(_ data: Data) throws -> ExportTranscriptResponse {
        do {
            let response = try JSONDecoder().decode(ExportTranscriptResponse.self, from: data)
            guard response.command == .exportTranscript else {
                throw TranscriptActionBridgeError.unexpectedCommand(
                    expected: .exportTranscript,
                    actual: response.command
                )
            }
            return response
        } catch let error as TranscriptActionBridgeError {
            throw error
        } catch {
            throw TranscriptActionBridgeError.invalidJSON(
                command: .exportTranscript,
                code: "internal_error"
            )
        }
    }

    public static func decodeDelete(_ data: Data) throws -> DeleteSessionResponse {
        do {
            let response = try JSONDecoder().decode(DeleteSessionResponse.self, from: data)
            guard response.command == .deleteSession else {
                throw TranscriptActionBridgeError.unexpectedCommand(
                    expected: .deleteSession,
                    actual: response.command
                )
            }
            return response
        } catch let error as TranscriptActionBridgeError {
            throw error
        } catch {
            throw TranscriptActionBridgeError.invalidJSON(
                command: .deleteSession,
                code: "internal_error"
            )
        }
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

public struct TranscriptActionProcessRunner: TranscriptActionCommandClient, Sendable {
    public let executablePath: String
    public let environment: [String: String]

    public init(
        executablePath: String? = nil,
        environment: [String: String] = ProcessInfo.processInfo.environment
    ) {
        self.executablePath = executablePath
            ?? environment["MEETING_ASSISTANT_CLI_PATH"]
            ?? "meeting-assistant-cli"
        self.environment = environment
    }

    public func exportTranscript(
        _ request: ExportTranscriptRequest
    ) async throws -> ExportTranscriptResponse {
        let executablePath = executablePath
        let environment = environment
        return try await Task.detached(priority: .userInitiated) {
            let arguments = Self.exportArguments(for: request)
            let result = try Self.runProcess(
                command: .exportTranscript,
                executablePath: executablePath,
                arguments: arguments,
                environment: environment
            )
            if result.stdout.isEmpty && result.exitCode != 0 {
                throw TranscriptActionBridgeError.processFailed(
                    command: .exportTranscript,
                    exitCode: result.exitCode,
                    code: Self.errorCode(forExitCode: result.exitCode)
                )
            }
            do {
                return try TranscriptActionResponseDecoder.decodeExport(result.stdout)
            } catch TranscriptActionBridgeError.invalidJSON(_, _) {
                throw TranscriptActionBridgeError.invalidJSON(
                    command: .exportTranscript,
                    code: Self.errorCode(forExitCode: result.exitCode)
                )
            }
        }.value
    }

    public func deleteSession(
        _ request: DeleteSessionRequest
    ) async throws -> DeleteSessionResponse {
        let executablePath = executablePath
        let environment = environment
        return try await Task.detached(priority: .userInitiated) {
            let arguments = Self.deleteArguments(for: request)
            let result = try Self.runProcess(
                command: .deleteSession,
                executablePath: executablePath,
                arguments: arguments,
                environment: environment
            )
            if result.stdout.isEmpty && result.exitCode != 0 {
                throw TranscriptActionBridgeError.processFailed(
                    command: .deleteSession,
                    exitCode: result.exitCode,
                    code: Self.errorCode(forExitCode: result.exitCode)
                )
            }
            do {
                return try TranscriptActionResponseDecoder.decodeDelete(result.stdout)
            } catch TranscriptActionBridgeError.invalidJSON(_, _) {
                throw TranscriptActionBridgeError.invalidJSON(
                    command: .deleteSession,
                    code: Self.errorCode(forExitCode: result.exitCode)
                )
            }
        }.value
    }

    private static func exportArguments(for request: ExportTranscriptRequest) -> [String] {
        var arguments = [
            TranscriptActionCommandName.exportTranscript.rawValue,
            "--session-id",
            request.sessionID,
            "--export-type",
            request.exportType.rawValue,
        ]
        if let targetPath = request.targetPath {
            arguments.append(contentsOf: ["--target-path", targetPath])
        }
        return arguments
    }

    private static func deleteArguments(for request: DeleteSessionRequest) -> [String] {
        var arguments = [
            TranscriptActionCommandName.deleteSession.rawValue,
            "--session-id",
            request.sessionID,
        ]
        if let workspaceDir = request.workspaceDir {
            arguments.append(contentsOf: ["--workspace-dir", workspaceDir])
        }
        arguments.append(contentsOf: ["--confirm", request.confirm ? "true" : "false"])
        return arguments
    }

    private static func runProcess(
        command: TranscriptActionCommandName,
        executablePath: String,
        arguments: [String],
        environment: [String: String]
    ) throws -> (stdout: Data, stderr: Data, exitCode: Int32) {
        let process = Process()
        let stdout = Pipe()
        let stderr = Pipe()

        if executablePath.contains("/") {
            process.executableURL = URL(fileURLWithPath: executablePath)
            process.arguments = arguments
        } else {
            process.executableURL = URL(fileURLWithPath: "/usr/bin/env")
            process.arguments = [executablePath] + arguments
        }
        process.environment = environment
        process.standardOutput = stdout
        process.standardError = stderr

        do {
            try process.run()
        } catch {
            throw TranscriptActionBridgeError.launchFailed(command: command)
        }
        process.waitUntilExit()

        return (
            stdout.fileHandleForReading.readDataToEndOfFile(),
            stderr.fileHandleForReading.readDataToEndOfFile(),
            process.terminationStatus
        )
    }

    private static func errorCode(forExitCode exitCode: Int32) -> TranscriptActionErrorCode {
        switch exitCode {
        case 2:
            return "invalid_input"
        case 3:
            return "path_conflict"
        case 4:
            return "permission_denied"
        default:
            return "internal_error"
        }
    }
}
