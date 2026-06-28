import Foundation

public struct DependencyCheckResponse: Decodable, Equatable, Sendable {
    public let ok: Bool
    public let requestID: String
    public let command: String
    public let code: String?
    public let message: String?
    public let checks: [DependencyCheckItem]
    public let warnings: [String]

    private enum CodingKeys: String, CodingKey {
        case ok
        case requestID = "request_id"
        case command
        case code
        case message
        case checks
        case warnings
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        ok = try container.decode(Bool.self, forKey: .ok)
        requestID = try container.decode(String.self, forKey: .requestID)
        command = try container.decode(String.self, forKey: .command)
        code = try container.decodeIfPresent(String.self, forKey: .code)
        message = try container.decodeIfPresent(String.self, forKey: .message)
        checks = try container.decodeIfPresent([DependencyCheckItem].self, forKey: .checks) ?? []
        warnings = try container.decodeIfPresent([String].self, forKey: .warnings) ?? []
    }

    init(
        ok: Bool,
        requestID: String,
        command: String = "check_dependencies",
        code: String? = nil,
        message: String? = nil,
        checks: [DependencyCheckItem],
        warnings: [String] = []
    ) {
        self.ok = ok
        self.requestID = requestID
        self.command = command
        self.code = code
        self.message = message
        self.checks = checks
        self.warnings = warnings
    }
}

public struct DependencyCheckItem: Decodable, Equatable, Identifiable, Sendable {
    public let id: String
    public let status: String
    public let required: Bool
    public let ok: Bool?
    public let message: String

    private enum CodingKeys: String, CodingKey {
        case id
        case status
        case required
        case ok
        case message
    }

    public var isPassing: Bool {
        if let ok {
            return ok
        }
        let normalizedStatus = status.lowercased()
        if Self.failureStatuses.contains(normalizedStatus) {
            return false
        }
        if required {
            return Self.requiredPassStatuses.contains(normalizedStatus)
        }
        return true
    }

    private static let failureStatuses: Set<String> = [
        "denied",
        "failed",
        "missing",
        "unsupported",
    ]

    private static let requiredPassStatuses: Set<String> = [
        "available",
        "constrained",
        "creatable",
        "granted",
        "not_attempted",
        "not_evaluated",
        "reported",
        "supported",
        "writable",
    ]

    init(id: String, status: String, required: Bool, ok: Bool? = nil, message: String) {
        self.id = id
        self.status = status
        self.required = required
        self.ok = ok
        self.message = message
    }
}

public enum DependencyCheckBridgeError: Error, Equatable, LocalizedError, Sendable {
    case invalidJSON(String)
    case launchFailed(String)
    case processFailed(exitCode: Int32, stderr: String)
    case unexpectedCommand(String)

    public var errorDescription: String? {
        switch self {
        case .invalidJSON(let snippet):
            return "check_dependencies did not return valid JSON: \(snippet)"
        case .launchFailed(let message):
            return "check_dependencies could not be launched: \(message)"
        case .processFailed(let exitCode, let stderr):
            return "check_dependencies exited with \(exitCode) and did not return JSON: \(stderr)"
        case .unexpectedCommand(let command):
            return "Expected check_dependencies response, got \(command)."
        }
    }
}

public enum DependencyCheckResponseDecoder {
    public static func decode(_ data: Data) throws -> DependencyCheckResponse {
        do {
            let response = try JSONDecoder().decode(DependencyCheckResponse.self, from: data)
            guard response.command == "check_dependencies" else {
                throw DependencyCheckBridgeError.unexpectedCommand(response.command)
            }
            return response
        } catch let error as DependencyCheckBridgeError {
            throw error
        } catch {
            throw DependencyCheckBridgeError.invalidJSON(snippet(from: data))
        }
    }

    private static func snippet(from data: Data) -> String {
        let prefix = Data(data.prefix(400))
        let value = String(data: prefix, encoding: .utf8) ?? "<non-utf8 output>"
        return value.trimmingCharacters(in: .whitespacesAndNewlines)
    }
}
