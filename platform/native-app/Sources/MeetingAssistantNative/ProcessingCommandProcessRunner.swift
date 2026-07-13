import Darwin
import Foundation

public enum ProcessingCommandBridgeError: Error, Equatable, LocalizedError, Sendable {
    case invalidJSON(command: ProcessingCommandName, code: ProcessingCommandErrorCode)
    case launchFailed(command: ProcessingCommandName)
    case processFailed(command: ProcessingCommandName, exitCode: Int32, code: ProcessingCommandErrorCode)
    case timedOut(command: ProcessingCommandName)
    case unexpectedCommand(expected: ProcessingCommandName, actual: ProcessingCommandName)

    public var command: ProcessingCommandName {
        switch self {
        case .invalidJSON(let command, _), .launchFailed(let command), .processFailed(let command, _, _),
                .timedOut(let command):
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
        case .timedOut:
            return .processingFailed
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
        case .timedOut:
            return "Processing command timed out and was stopped."
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
    public static let defaultTimeoutSeconds: TimeInterval = 600

    public let executablePath: String
    public let environment: [String: String]
    public let timeoutSeconds: TimeInterval

    public init(
        executablePath: String? = nil,
        environment: [String: String] = ProcessInfo.processInfo.environment,
        timeoutSeconds: TimeInterval = Self.defaultTimeoutSeconds
    ) {
        self.executablePath = executablePath
            ?? environment["MEETING_ASSISTANT_CLI_PATH"]
            ?? "meeting-assistant-cli"
        self.environment = environment
        self.timeoutSeconds = Self.normalizedTimeoutSeconds(timeoutSeconds)
    }

    public func generateTranscript(
        _ request: GenerateTranscriptRequest
    ) async throws -> GenerateTranscriptResponse {
        let executablePath = executablePath
        let environment = environment
        let timeoutSeconds = timeoutSeconds
        return try await Task.detached(priority: .userInitiated) {
            let arguments = Self.transcriptArguments(for: request)
            let result = try Self.runProcess(
                command: .generateTranscript,
                executablePath: executablePath,
                arguments: arguments,
                environment: environment,
                timeoutSeconds: timeoutSeconds
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
        let timeoutSeconds = timeoutSeconds
        return try await Task.detached(priority: .userInitiated) {
            let arguments = Self.speakerLabelsArguments(for: request)
            let result = try Self.runProcess(
                command: .generateSpeakerLabels,
                executablePath: executablePath,
                arguments: arguments,
                environment: environment,
                timeoutSeconds: timeoutSeconds
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
        environment: [String: String],
        timeoutSeconds: TimeInterval
    ) throws -> (stdout: Data, stderr: Data, exitCode: Int32) {
        do {
            let result = try NativeCommandProcess.run(
                executablePath: executablePath,
                arguments: arguments,
                environment: environment,
                timeoutSeconds: timeoutSeconds,
                label: "local.meeting-assistant.processing"
            )
            return (result.stdout, result.stderr, result.exitCode)
        } catch NativeCommandProcessError.timedOut {
            throw ProcessingCommandBridgeError.timedOut(command: command)
        } catch {
            throw ProcessingCommandBridgeError.launchFailed(command: command)
        }
    }

    private static func normalizedTimeoutSeconds(_ timeoutSeconds: TimeInterval) -> TimeInterval {
        guard timeoutSeconds.isFinite, timeoutSeconds > 0 else {
            return defaultTimeoutSeconds
        }
        return timeoutSeconds
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

enum NativeCommandProcessError: Error {
    case launchFailed
    case timedOut
}

struct NativeCommandProcessResult {
    let stdout: Data
    let stderr: Data
    let exitCode: Int32
}

enum NativeCommandProcess {
    private static let terminationGraceSeconds: TimeInterval = 0.25
    private static let drainGrace: DispatchTimeInterval = .milliseconds(500)

    static func run(
        executablePath: String,
        arguments: [String],
        environment: [String: String],
        timeoutSeconds: TimeInterval,
        label: String
    ) throws -> NativeCommandProcessResult {
        var stdoutDescriptors = [Int32](repeating: -1, count: 2)
        var stderrDescriptors = [Int32](repeating: -1, count: 2)
        guard Darwin.pipe(&stdoutDescriptors) == 0 else {
            throw NativeCommandProcessError.launchFailed
        }
        guard Darwin.pipe(&stderrDescriptors) == 0 else {
            closeDescriptors(stdoutDescriptors)
            throw NativeCommandProcessError.launchFailed
        }

        var ownedDescriptors = stdoutDescriptors + stderrDescriptors
        defer { closeDescriptors(ownedDescriptors) }

        var fileActions: posix_spawn_file_actions_t?
        guard posix_spawn_file_actions_init(&fileActions) == 0 else {
            throw NativeCommandProcessError.launchFailed
        }
        defer { posix_spawn_file_actions_destroy(&fileActions) }
        let fileActionResults = [
            posix_spawn_file_actions_adddup2(&fileActions, stdoutDescriptors[1], STDOUT_FILENO),
            posix_spawn_file_actions_adddup2(&fileActions, stderrDescriptors[1], STDERR_FILENO),
            posix_spawn_file_actions_addclose(&fileActions, stdoutDescriptors[0]),
            posix_spawn_file_actions_addclose(&fileActions, stdoutDescriptors[1]),
            posix_spawn_file_actions_addclose(&fileActions, stderrDescriptors[0]),
            posix_spawn_file_actions_addclose(&fileActions, stderrDescriptors[1]),
        ]
        guard fileActionResults.allSatisfy({ $0 == 0 }) else {
            throw NativeCommandProcessError.launchFailed
        }

        var attributes: posix_spawnattr_t?
        guard posix_spawnattr_init(&attributes) == 0 else {
            throw NativeCommandProcessError.launchFailed
        }
        defer { posix_spawnattr_destroy(&attributes) }
        guard posix_spawnattr_setpgroup(&attributes, 0) == 0,
              posix_spawnattr_setflags(&attributes, Int16(POSIX_SPAWN_SETPGROUP)) == 0 else {
            throw NativeCommandProcessError.launchFailed
        }

        let launchPath: String
        let launchArguments: [String]
        if executablePath.contains("/") {
            launchPath = executablePath
            launchArguments = [executablePath] + arguments
        } else {
            launchPath = "/usr/bin/env"
            launchArguments = ["env", executablePath] + arguments
        }
        guard let argv = NativeCommandCStringVector(launchArguments),
              let envp = NativeCommandCStringVector(environment.map { "\($0.key)=\($0.value)" }) else {
            throw NativeCommandProcessError.launchFailed
        }

        var processIdentifier: pid_t = 0
        let spawnResult = launchPath.withCString { path in
            argv.withUnsafePointer { argvPointer in
                envp.withUnsafePointer { environmentPointer in
                    posix_spawn(
                        &processIdentifier,
                        path,
                        &fileActions,
                        &attributes,
                        argvPointer,
                        environmentPointer
                    )
                }
            }
        }
        guard spawnResult == 0, processIdentifier > 0 else {
            throw NativeCommandProcessError.launchFailed
        }

        Darwin.close(stdoutDescriptors[1])
        Darwin.close(stderrDescriptors[1])
        ownedDescriptors.removeAll { $0 == stdoutDescriptors[1] || $0 == stderrDescriptors[1] }

        let stdoutDrain = NativeCommandPipeDrain(
            fileDescriptor: stdoutDescriptors[0],
            label: "\(label).stdout"
        )
        let stderrDrain = NativeCommandPipeDrain(
            fileDescriptor: stderrDescriptors[0],
            label: "\(label).stderr"
        )
        ownedDescriptors.removeAll { $0 == stdoutDescriptors[0] || $0 == stderrDescriptors[0] }
        stdoutDrain.start()
        stderrDrain.start()

        switch observeProcessExit(processIdentifier, timeoutSeconds: timeoutSeconds) {
        case .exited:
            break
        case .timedOut:
            terminateProcessGroup(processIdentifier)
            stdoutDrain.stop()
            stderrDrain.stop()
            _ = stdoutDrain.finish(timeout: drainGrace)
            _ = stderrDrain.finish(timeout: drainGrace)
            throw NativeCommandProcessError.timedOut
        case .failed:
            terminateProcessGroup(processIdentifier)
            stdoutDrain.stop()
            stderrDrain.stop()
            _ = stdoutDrain.finish(timeout: drainGrace)
            _ = stderrDrain.finish(timeout: drainGrace)
            throw NativeCommandProcessError.launchFailed
        }

        // The direct command is a zombie until waitpid below, so its process-group
        // identifier cannot be reused while any inherited-pipe descendants are killed.
        _ = Darwin.kill(-processIdentifier, SIGKILL)
        var status: Int32 = 0
        guard waitForProcess(processIdentifier, status: &status, blocking: true) else {
            stdoutDrain.stop()
            stderrDrain.stop()
            throw NativeCommandProcessError.launchFailed
        }
        waitForProcessGroupToDisappear(processIdentifier)

        return NativeCommandProcessResult(
            stdout: stdoutDrain.finish(timeout: drainGrace),
            stderr: stderrDrain.finish(timeout: drainGrace),
            exitCode: exitCode(fromWaitStatus: status)
        )
    }

    private static func terminateProcessGroup(
        _ processIdentifier: pid_t
    ) {
        _ = Darwin.kill(-processIdentifier, SIGTERM)
        let exitedAfterTerm = observeProcessExit(
            processIdentifier,
            timeoutSeconds: terminationGraceSeconds
        ) == .exited
        _ = Darwin.kill(-processIdentifier, SIGKILL)
        if !exitedAfterTerm {
            _ = observeProcessExit(
                processIdentifier,
                timeoutSeconds: terminationGraceSeconds
            )
        }

        var status: Int32 = 0
        if !waitForProcess(processIdentifier, status: &status, blocking: false) {
            DispatchQueue.global(qos: .utility).async {
                var deferredStatus: Int32 = 0
                while Darwin.waitpid(processIdentifier, &deferredStatus, 0) == -1 && errno == EINTR {}
            }
        }
        waitForProcessGroupToDisappear(processIdentifier)
    }

    private enum ProcessExitObservation: Equatable {
        case exited
        case timedOut
        case failed
    }

    private static func observeProcessExit(
        _ processIdentifier: pid_t,
        timeoutSeconds: TimeInterval
    ) -> ProcessExitObservation {
        let deadline = DispatchTime.now() + timeoutSeconds
        repeat {
            var information = siginfo_t()
            let result = Darwin.waitid(
                P_PID,
                id_t(processIdentifier),
                &information,
                WEXITED | WNOHANG | WNOWAIT
            )
            if result == 0, information.si_pid == processIdentifier {
                return .exited
            }
            if result == -1, errno != EINTR {
                return .failed
            }
            if DispatchTime.now() >= deadline {
                return .timedOut
            }
            usleep(10_000)
        } while true
    }

    private static func waitForProcess(
        _ processIdentifier: pid_t,
        status: inout Int32,
        blocking: Bool
    ) -> Bool {
        let options = blocking ? 0 : WNOHANG
        let deadline = DispatchTime.now() + terminationGraceSeconds
        repeat {
            let result = Darwin.waitpid(processIdentifier, &status, options)
            if result == processIdentifier {
                return true
            }
            if result == -1, errno != EINTR {
                return false
            }
            if blocking {
                continue
            }
            usleep(10_000)
        } while DispatchTime.now() < deadline
        return false
    }

    private static func waitForProcessGroupToDisappear(_ processIdentifier: pid_t) {
        let deadline = DispatchTime.now() + terminationGraceSeconds
        while Darwin.kill(-processIdentifier, 0) == 0 || errno == EPERM {
            guard DispatchTime.now() < deadline else {
                return
            }
            usleep(10_000)
        }
    }

    private static func exitCode(fromWaitStatus status: Int32) -> Int32 {
        let signal = status & 0x7f
        if signal == 0 {
            return (status >> 8) & 0xff
        }
        return 128 + signal
    }

    private static func closeDescriptors(_ descriptors: [Int32]) {
        for descriptor in descriptors where descriptor >= 0 {
            Darwin.close(descriptor)
        }
    }
}

private final class NativeCommandCStringVector {
    private var pointers: [UnsafeMutablePointer<CChar>?]

    init?(_ strings: [String]) {
        pointers = []
        pointers.reserveCapacity(strings.count + 1)
        for string in strings {
            guard let pointer = strdup(string) else {
                for existingPointer in pointers {
                    free(existingPointer)
                }
                return nil
            }
            pointers.append(pointer)
        }
        pointers.append(nil)
    }

    deinit {
        for pointer in pointers {
            free(pointer)
        }
    }

    func withUnsafePointer<Result>(
        _ body: (UnsafePointer<UnsafeMutablePointer<CChar>?>) -> Result
    ) -> Result {
        pointers.withUnsafeBufferPointer { buffer in
            body(buffer.baseAddress!)
        }
    }
}

private final class NativeCommandPipeDrain: @unchecked Sendable {
    private let fileDescriptor: Int32
    private let queue: DispatchQueue
    private let finished = DispatchSemaphore(value: 0)
    private let lock = NSLock()
    private var data = Data()
    private var isStopped = false

    init(fileDescriptor: Int32, label: String) {
        self.fileDescriptor = fileDescriptor
        queue = DispatchQueue(label: label)
        let flags = Darwin.fcntl(fileDescriptor, F_GETFL)
        if flags >= 0 {
            _ = Darwin.fcntl(fileDescriptor, F_SETFL, flags | O_NONBLOCK)
        }
    }

    func start() {
        queue.async { [self] in
            defer {
                Darwin.close(fileDescriptor)
                finished.signal()
            }
            var buffer = [UInt8](repeating: 0, count: 64 * 1024)
            while !stoppedSnapshot() {
                let count = buffer.withUnsafeMutableBytes { bytes in
                    Darwin.read(fileDescriptor, bytes.baseAddress, bytes.count)
                }
                if count > 0 {
                    lock.lock()
                    data.append(buffer, count: count)
                    lock.unlock()
                } else if count == 0 {
                    return
                } else if errno == EINTR {
                    continue
                } else if errno == EAGAIN || errno == EWOULDBLOCK {
                    var descriptor = pollfd(fd: fileDescriptor, events: Int16(POLLIN | POLLHUP), revents: 0)
                    _ = Darwin.poll(&descriptor, 1, 50)
                } else {
                    return
                }
            }
        }
    }

    func finish(timeout: DispatchTimeInterval) -> Data {
        if finished.wait(timeout: .now() + timeout) != .success {
            stop()
            _ = finished.wait(timeout: .now() + .milliseconds(100))
        }
        lock.lock()
        defer { lock.unlock() }
        return data
    }

    func stop() {
        lock.lock()
        isStopped = true
        lock.unlock()
    }

    private func stoppedSnapshot() -> Bool {
        lock.lock()
        defer { lock.unlock() }
        return isStopped
    }
}
