import Foundation

public enum ProcessingCommandBridgeError: Error, Equatable, LocalizedError, Sendable {
    case invalidJSON(command: ProcessingCommandName, code: ProcessingCommandErrorCode)
    case launchFailed(command: ProcessingCommandName)
    case processFailed(command: ProcessingCommandName, exitCode: Int32, code: ProcessingCommandErrorCode)
    case unexpectedCommand(expected: ProcessingCommandName, actual: ProcessingCommandName)

    public var command: ProcessingCommandName {
        switch self {
        case .invalidJSON(let command, _), .launchFailed(let command), .processFailed(let command, _, _):
            return command
        case .unexpectedCommand(let expected, _):
            return expected
        }
    }

    public var code: ProcessingCommandErrorCode {
        switch self {
        case .invalidJSON(_, let code), .processFailed(_, _, let code):
            return code
        case .launchFailed, .unexpectedCommand:
            return .internalError
        }
    }

    public var safeMessage: String {
        switch self {
        case .invalidJSON:
            return "Processing command returned an invalid response."
        case .launchFailed:
            return "Processing command could not be launched."
        case .processFailed:
            return "Processing command failed before returning a contract response."
        case .unexpectedCommand:
            return "Processing command returned an unexpected response."
        }
    }

    public var errorDescription: String? {
        if case .processFailed(_, let exitCode, _) = self {
            return "\(safeMessage) Exit code: \(exitCode). Error code: \(code.rawValue)."
        }
        return "\(safeMessage) Error code: \(code.rawValue)."
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
                code: .internalError
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
                code: .internalError
            )
        }
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
                    code: Self.errorCode(forExitCode: result.exitCode)
                )
            }
            do {
                return try ProcessingCommandResponseDecoder.decodeTranscript(result.stdout)
            } catch ProcessingCommandBridgeError.invalidJSON(_, _) {
                throw ProcessingCommandBridgeError.invalidJSON(
                    command: .generateTranscript,
                    code: Self.errorCode(forExitCode: result.exitCode)
                )
            }
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
                    code: Self.errorCode(forExitCode: result.exitCode)
                )
            }
            do {
                return try ProcessingCommandResponseDecoder.decodeSpeakerLabels(result.stdout)
            } catch ProcessingCommandBridgeError.invalidJSON(_, _) {
                throw ProcessingCommandBridgeError.invalidJSON(
                    command: .generateSpeakerLabels,
                    code: Self.errorCode(forExitCode: result.exitCode)
                )
            }
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
            throw ProcessingCommandBridgeError.launchFailed(command: command)
        }
        let stdoutDrain = ProcessingCommandPipeDrain(
            pipe: stdout,
            label: "local.meeting-assistant.processing.stdout"
        )
        let stderrDrain = ProcessingCommandPipeDrain(
            pipe: stderr,
            label: "local.meeting-assistant.processing.stderr"
        )
        stdoutDrain.start()
        stderrDrain.start()
        process.waitUntilExit()

        return (
            stdoutDrain.wait(),
            stderrDrain.wait(),
            process.terminationStatus
        )
    }

    private static func errorCode(forExitCode exitCode: Int32) -> ProcessingCommandErrorCode {
        switch exitCode {
        case 2:
            return .invalidInput
        case 3:
            return .artifactMissing
        case 4:
            return .dependencyMissing
        case 5:
            return .processingFailed
        default:
            return .internalError
        }
    }
}

private final class ProcessingCommandPipeDrain: @unchecked Sendable {
    private let handle: FileHandle
    private let queue: DispatchQueue
    private var data = Data()

    init(pipe: Pipe, label: String) {
        handle = pipe.fileHandleForReading
        queue = DispatchQueue(label: label)
    }

    func start() {
        queue.async { [self] in
            data = handle.readDataToEndOfFile()
        }
    }

    func wait() -> Data {
        queue.sync {
            data
        }
    }
}
