import Foundation

public enum ProcessingCommandBridgeError: Error, Equatable, LocalizedError, Sendable {
    case invalidJSON(command: ProcessingCommandName, snippet: String)
    case launchFailed(command: ProcessingCommandName, message: String)
    case processFailed(command: ProcessingCommandName, exitCode: Int32, stderr: String)
    case unexpectedCommand(expected: ProcessingCommandName, actual: ProcessingCommandName)

    public var errorDescription: String? {
        switch self {
        case .invalidJSON(let command, let snippet):
            return "\(command.rawValue) did not return valid JSON: \(snippet)"
        case .launchFailed(let command, let message):
            return "\(command.rawValue) could not be launched: \(message)"
        case .processFailed(let command, let exitCode, let stderr):
            return "\(command.rawValue) exited with \(exitCode) and did not return JSON: \(stderr)"
        case .unexpectedCommand(let expected, let actual):
            return "Expected \(expected.rawValue) response, got \(actual.rawValue)."
        }
    }
}

public enum ProcessingCommandResponseDecoder {
    public static func decodeTranscript(_ data: Data) throws -> GenerateTranscriptResponse {
        do {
            let response = try JSONDecoder().decode(GenerateTranscriptResponse.self, from: data)
            guard response.command == .generateTranscript else {
                throw ProcessingCommandBridgeError.unexpectedCommand(
                    expected: .generateTranscript,
                    actual: response.command
                )
            }
            return response
        } catch let error as ProcessingCommandBridgeError {
            throw error
        } catch {
            throw ProcessingCommandBridgeError.invalidJSON(
                command: .generateTranscript,
                snippet: snippet(from: data)
            )
        }
    }

    public static func decodeSpeakerLabels(_ data: Data) throws -> GenerateSpeakerLabelsResponse {
        do {
            let response = try JSONDecoder().decode(GenerateSpeakerLabelsResponse.self, from: data)
            guard response.command == .generateSpeakerLabels else {
                throw ProcessingCommandBridgeError.unexpectedCommand(
                    expected: .generateSpeakerLabels,
                    actual: response.command
                )
            }
            return response
        } catch let error as ProcessingCommandBridgeError {
            throw error
        } catch {
            throw ProcessingCommandBridgeError.invalidJSON(
                command: .generateSpeakerLabels,
                snippet: snippet(from: data)
            )
        }
    }

    private static func snippet(from data: Data) -> String {
        let prefix = Data(data.prefix(400))
        let value = String(data: prefix, encoding: .utf8) ?? "<non-utf8 output>"
        return value.trimmingCharacters(in: .whitespacesAndNewlines)
    }
}

public struct ProcessingCommandProcessRunner: ProcessingCommandClient, Sendable {
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

    public func generateTranscript(
        _ request: GenerateTranscriptRequest
    ) async throws -> GenerateTranscriptResponse {
        let executablePath = executablePath
        let environment = environment
        return try await Task.detached(priority: .userInitiated) {
            let arguments = Self.transcriptArguments(for: request)
            let result = try Self.runProcess(
                command: .generateTranscript,
                executablePath: executablePath,
                arguments: arguments,
                environment: environment
            )
            if result.stdout.isEmpty && result.exitCode != 0 {
                throw ProcessingCommandBridgeError.processFailed(
                    command: .generateTranscript,
                    exitCode: result.exitCode,
                    stderr: Self.snippet(from: result.stderr)
                )
            }
            return try ProcessingCommandResponseDecoder.decodeTranscript(result.stdout)
        }.value
    }

    public func generateSpeakerLabels(
        _ request: GenerateSpeakerLabelsRequest
    ) async throws -> GenerateSpeakerLabelsResponse {
        let executablePath = executablePath
        let environment = environment
        return try await Task.detached(priority: .userInitiated) {
            let arguments = Self.speakerLabelsArguments(for: request)
            let result = try Self.runProcess(
                command: .generateSpeakerLabels,
                executablePath: executablePath,
                arguments: arguments,
                environment: environment
            )
            if result.stdout.isEmpty && result.exitCode != 0 {
                throw ProcessingCommandBridgeError.processFailed(
                    command: .generateSpeakerLabels,
                    exitCode: result.exitCode,
                    stderr: Self.snippet(from: result.stderr)
                )
            }
            return try ProcessingCommandResponseDecoder.decodeSpeakerLabels(result.stdout)
        }.value
    }

    private static func transcriptArguments(for request: GenerateTranscriptRequest) -> [String] {
        var arguments = [
            ProcessingCommandName.generateTranscript.rawValue,
            "--session-id",
            request.sessionID,
        ]
        if let sourceArtifactID = request.sourceArtifactID {
            arguments.append(contentsOf: ["--source-artifact-id", sourceArtifactID])
        }
        if let language = request.language {
            arguments.append(contentsOf: ["--language", language])
        }
        if let runtime = request.runtime {
            arguments.append(contentsOf: ["--runtime", runtime.rawValue])
        }
        return arguments
    }

    private static func speakerLabelsArguments(for request: GenerateSpeakerLabelsRequest) -> [String] {
        [
            ProcessingCommandName.generateSpeakerLabels.rawValue,
            "--session-id",
            request.sessionID,
            "--transcript-id",
            request.transcriptID,
            "--allow-transcript-only-fallback",
            request.allowTranscriptOnlyFallback ? "true" : "false",
        ]
    }

    private static func runProcess(
        command: ProcessingCommandName,
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
            throw ProcessingCommandBridgeError.launchFailed(
                command: command,
                message: error.localizedDescription
            )
        }
        process.waitUntilExit()

        return (
            stdout.fileHandleForReading.readDataToEndOfFile(),
            stderr.fileHandleForReading.readDataToEndOfFile(),
            process.terminationStatus
        )
    }

    private static func snippet(from data: Data) -> String {
        let prefix = Data(data.prefix(400))
        return (String(data: prefix, encoding: .utf8) ?? "<non-utf8 output>")
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }
}
