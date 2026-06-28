import Foundation

public protocol DependencyCheckRunning: Sendable {
    func checkDependencies(workspaceURL: URL?) async throws -> DependencyCheckResponse
}

public struct ProcessingCLIDependencyCheckRunner: DependencyCheckRunning, Sendable {
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

    public func checkDependencies(workspaceURL: URL? = nil) async throws -> DependencyCheckResponse {
        let executablePath = executablePath
        let environment = environment
        return try await Task.detached(priority: .userInitiated) {
            let result = try Self.runProcess(
                executablePath: executablePath,
                workspaceURL: workspaceURL,
                environment: environment
            )
            if result.stdout.isEmpty && result.exitCode != 0 {
                throw DependencyCheckBridgeError.processFailed(
                    exitCode: result.exitCode,
                    stderr: Self.snippet(from: result.stderr)
                )
            }
            return try DependencyCheckResponseDecoder.decode(result.stdout)
        }.value
    }

    private static func runProcess(
        executablePath: String,
        workspaceURL: URL?,
        environment: [String: String]
    ) throws -> (stdout: Data, stderr: Data, exitCode: Int32) {
        let process = Process()
        let stdout = Pipe()
        let stderr = Pipe()
        var arguments = ["check_dependencies", "--format", "json"]
        if let workspaceURL {
            arguments.append(contentsOf: ["--workspace-dir", workspaceURL.path])
        }

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
            throw DependencyCheckBridgeError.launchFailed(error.localizedDescription)
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
