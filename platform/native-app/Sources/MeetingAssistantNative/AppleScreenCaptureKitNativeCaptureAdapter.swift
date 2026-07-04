import AVFoundation
import CoreMedia
import Foundation
import ScreenCaptureKit

public struct AppleScreenCaptureKitNativeCaptureCapabilitySummary: Equatable, Sendable {
    public let adapterID: String
    public let framework: String
    public let supportedCaptureTargets: [RecordingCaptureTarget]
    public let producedArtifactTypes: [NativeCaptureArtifactType]
    public let producesCombinedRecordingFile: Bool
    public let producesSeparateAudioArtifacts: Bool

    public init(
        adapterID: String,
        framework: String,
        supportedCaptureTargets: [RecordingCaptureTarget],
        producedArtifactTypes: [NativeCaptureArtifactType],
        producesCombinedRecordingFile: Bool,
        producesSeparateAudioArtifacts: Bool
    ) {
        self.adapterID = adapterID
        self.framework = framework
        self.supportedCaptureTargets = supportedCaptureTargets
        self.producedArtifactTypes = producedArtifactTypes
        self.producesCombinedRecordingFile = producesCombinedRecordingFile
        self.producesSeparateAudioArtifacts = producesSeparateAudioArtifacts
    }
}

public actor AppleScreenCaptureKitNativeCaptureAdapter: NativeCaptureAdapter {
    public static let identity = "apple_screencapturekit"

    public nonisolated var adapterIdentity: String {
        Self.identity
    }

    public nonisolated var capabilitySummary: AppleScreenCaptureKitNativeCaptureCapabilitySummary {
        Self.capabilitySummary
    }

    public static let capabilitySummary = AppleScreenCaptureKitNativeCaptureCapabilitySummary(
        adapterID: identity,
        framework: "ScreenCaptureKit",
        supportedCaptureTargets: [.screen],
        producedArtifactTypes: NativeCaptureArtifactType.allCases,
        producesCombinedRecordingFile: true,
        producesSeparateAudioArtifacts: false
    )

    private let runtime: any AppleScreenCaptureKitRecordingRuntime
    private let temporaryDirectoryProvider: @Sendable () -> URL
    private var activeRecordings: [String: ActiveAppleScreenCaptureKitRecording] = [:]

    public init() {
        if #available(macOS 15.0, *) {
            self.runtime = DefaultAppleScreenCaptureKitRecordingRuntime()
        } else {
            self.runtime = UnavailableAppleScreenCaptureKitRecordingRuntime(
                reason: "ScreenCaptureKit recording output requires macOS 15.0 or newer."
            )
        }
        self.temporaryDirectoryProvider = { FileManager.default.temporaryDirectory }
    }

    init(
        runtime: any AppleScreenCaptureKitRecordingRuntime,
        temporaryDirectoryProvider: @escaping @Sendable () -> URL = {
            FileManager.default.temporaryDirectory
        }
    ) {
        self.runtime = runtime
        self.temporaryDirectoryProvider = temporaryDirectoryProvider
    }

    public func start(_ context: NativeCaptureStartContext) async throws {
        let target = context.request.captureTarget ?? .screen
        guard target == .screen else {
            throw NativeCaptureAdapterFailure.startFailed(
                "ScreenCaptureKit native adapter currently supports only the screen capture target."
            )
        }
        guard activeRecordings[context.sessionID] == nil else {
            throw NativeCaptureAdapterFailure.startFailed(
                "ScreenCaptureKit native adapter already has an active recording for \(context.sessionID)."
            )
        }

        let outputURL = try makeTemporaryOutputURL(sessionID: context.sessionID)
        let options = AppleScreenCaptureKitRecordingOptions(
            captureSystemAudio: context.request.captureSystemAudio,
            captureMicrophoneAudio: context.request.captureMicrophoneAudio
        )

        do {
            let token = try await runtime.startRecording(
                context: context,
                outputURL: outputURL,
                options: options
            )
            activeRecordings[context.sessionID] = ActiveAppleScreenCaptureKitRecording(
                token: token,
                outputURL: outputURL,
                options: options
            )
        } catch {
            cleanupTemporaryOutput(at: outputURL)
            throw NativeCaptureAdapterFailure.startFailed(
                "ScreenCaptureKit failed to start native capture: \(error.localizedDescription)"
            )
        }
    }

    public func stop(_ context: NativeCaptureStopContext) async throws -> NativeCaptureStopResult {
        guard let recording = activeRecordings.removeValue(forKey: context.sessionID) else {
            throw NativeCaptureAdapterFailure.stopFailed(
                message: "ScreenCaptureKit native capture session was not started.",
                partialArtifacts: noAvailableMediaArtifacts(
                    options: .requestedAudio,
                    reason: "ScreenCaptureKit native capture session was not started."
                )
            )
        }

        do {
            let recordingFile = try await runtime.stopRecording(recording.token)
            let recordingData = try recordingData(from: recordingFile.url)
            cleanupTemporaryOutput(at: recording.outputURL)
            return NativeCaptureStopResult(
                artifacts: artifactResults(
                    combinedRecordingData: recordingData,
                    combinedRecordingFormat: recordingFile.format,
                    options: recording.options
                )
            )
        } catch {
            cleanupTemporaryOutput(at: recording.outputURL)
            throw NativeCaptureAdapterFailure.stopFailed(
                message: "ScreenCaptureKit failed to finish native capture: \(error.localizedDescription)",
                partialArtifacts: noAvailableMediaArtifacts(
                    options: recording.options,
                    reason: "ScreenCaptureKit failed to finish native capture: \(error.localizedDescription)"
                )
            )
        }
    }

    private func makeTemporaryOutputURL(sessionID: String) throws -> URL {
        let directory = temporaryDirectoryProvider()
            .appendingPathComponent(
                "meeting-assistant-screencapturekit-\(sessionID)-\(UUID().uuidString)",
                isDirectory: true
            )
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        return directory.appendingPathComponent("combined_recording.mp4", isDirectory: false)
    }

    private func recordingData(from outputURL: URL) throws -> Data {
        guard FileManager.default.fileExists(atPath: outputURL.path) else {
            throw AppleScreenCaptureKitAdapterError.noRecordingFile(outputURL.path)
        }
        let data = try Data(contentsOf: outputURL)
        guard !data.isEmpty else {
            throw AppleScreenCaptureKitAdapterError.emptyRecordingFile(outputURL.path)
        }
        return data
    }

    private func cleanupTemporaryOutput(at outputURL: URL) {
        try? FileManager.default.removeItem(at: outputURL.deletingLastPathComponent())
    }

    private func artifactResults(
        combinedRecordingData: Data,
        combinedRecordingFormat: String,
        options: AppleScreenCaptureKitRecordingOptions
    ) -> [NativeCaptureArtifactResult] {
        [
            .available(
                .screenVideo,
                format: combinedRecordingFormat,
                data: combinedRecordingData
            ),
            requestedAudioArtifact(
                .systemAudio,
                wasRequested: options.captureSystemAudio,
                requestedReason: "ScreenCaptureKit SCRecordingOutput stores any captured system audio only inside the combined screen_video file; no separate system_audio artifact is produced by this adapter."
            ),
            requestedAudioArtifact(
                .microphoneAudio,
                wasRequested: options.captureMicrophoneAudio,
                requestedReason: "ScreenCaptureKit SCRecordingOutput stores any captured microphone audio only inside the combined screen_video file; no separate microphone_audio artifact is produced by this adapter."
            ),
            requestedAudioArtifact(
                .mixedAudio,
                wasRequested: options.captureSystemAudio || options.captureMicrophoneAudio,
                requestedReason: "ScreenCaptureKit SCRecordingOutput produced only a combined recording file; no separate mixed_audio artifact is produced by this adapter."
            ),
        ]
    }

    private func requestedAudioArtifact(
        _ artifactType: NativeCaptureArtifactType,
        wasRequested: Bool,
        requestedReason: String
    ) -> NativeCaptureArtifactResult {
        if wasRequested {
            return .degraded(artifactType, reason: requestedReason)
        }
        return .missing(
            artifactType,
            reason: "\(artifactType.rawValue) was not requested for this native capture session."
        )
    }

    private func noAvailableMediaArtifacts(
        options: AppleScreenCaptureKitRecordingOptions,
        reason: String
    ) -> [NativeCaptureArtifactResult] {
        NativeCaptureArtifactType.allCases.map { artifactType in
            .failed(
                artifactType,
                reason: "\(artifactType.rawValue) unavailable: \(reason)"
            )
        }
    }
}

struct AppleScreenCaptureKitRecordingOptions: Equatable, Sendable {
    let captureSystemAudio: Bool
    let captureMicrophoneAudio: Bool

    static let requestedAudio = AppleScreenCaptureKitRecordingOptions(
        captureSystemAudio: true,
        captureMicrophoneAudio: true
    )
}

struct AppleScreenCaptureKitRecordingToken: Hashable, Sendable {
    let rawValue: String
}

struct AppleScreenCaptureKitRecordingFile: Equatable, Sendable {
    let url: URL
    let format: String
}

protocol AppleScreenCaptureKitRecordingRuntime: Sendable {
    func startRecording(
        context: NativeCaptureStartContext,
        outputURL: URL,
        options: AppleScreenCaptureKitRecordingOptions
    ) async throws -> AppleScreenCaptureKitRecordingToken

    func stopRecording(
        _ token: AppleScreenCaptureKitRecordingToken
    ) async throws -> AppleScreenCaptureKitRecordingFile
}

private struct ActiveAppleScreenCaptureKitRecording: Sendable {
    let token: AppleScreenCaptureKitRecordingToken
    let outputURL: URL
    let options: AppleScreenCaptureKitRecordingOptions
}

private enum AppleScreenCaptureKitAdapterError: Error, LocalizedError {
    case noRecordingFile(String)
    case emptyRecordingFile(String)

    var errorDescription: String? {
        switch self {
        case .noRecordingFile:
            return "ScreenCaptureKit recording file was not produced."
        case .emptyRecordingFile:
            return "ScreenCaptureKit recording file was empty."
        }
    }
}

private struct UnavailableAppleScreenCaptureKitRecordingRuntime: AppleScreenCaptureKitRecordingRuntime {
    let reason: String

    func startRecording(
        context: NativeCaptureStartContext,
        outputURL: URL,
        options: AppleScreenCaptureKitRecordingOptions
    ) async throws -> AppleScreenCaptureKitRecordingToken {
        throw AppleScreenCaptureKitRuntimeError.unavailable(reason)
    }

    func stopRecording(
        _ token: AppleScreenCaptureKitRecordingToken
    ) async throws -> AppleScreenCaptureKitRecordingFile {
        throw AppleScreenCaptureKitRuntimeError.unavailable(reason)
    }
}

private enum AppleScreenCaptureKitRuntimeError: Error, LocalizedError {
    case unavailable(String)
    case noDisplayAvailable
    case unknownRecording(AppleScreenCaptureKitRecordingToken)
    case recordingOutputTimedOut

    var errorDescription: String? {
        switch self {
        case .unavailable(let reason):
            return reason
        case .noDisplayAvailable:
            return "No ScreenCaptureKit display is available for native capture."
        case .unknownRecording(let token):
            return "ScreenCaptureKit recording token is not active: \(token.rawValue)."
        case .recordingOutputTimedOut:
            return "ScreenCaptureKit recording output did not finish writing before timeout."
        }
    }
}

@available(macOS 15.0, *)
private actor DefaultAppleScreenCaptureKitRecordingRuntime: AppleScreenCaptureKitRecordingRuntime {
    private var recordings: [AppleScreenCaptureKitRecordingToken: ScreenCaptureKitRecordingSession] = [:]

    func startRecording(
        context: NativeCaptureStartContext,
        outputURL: URL,
        options: AppleScreenCaptureKitRecordingOptions
    ) async throws -> AppleScreenCaptureKitRecordingToken {
        let content = try await SCShareableContent.current
        guard let display = content.displays.first else {
            throw AppleScreenCaptureKitRuntimeError.noDisplayAvailable
        }

        let filter = SCContentFilter(display: display, excludingWindows: [])
        let configuration = SCStreamConfiguration()
        configuration.width = display.width
        configuration.height = display.height
        configuration.minimumFrameInterval = CMTime(value: 1, timescale: 30)
        configuration.queueDepth = 8
        configuration.showsCursor = true
        configuration.capturesAudio = options.captureSystemAudio
        configuration.captureMicrophone = options.captureMicrophoneAudio
        configuration.excludesCurrentProcessAudio = true
        configuration.sampleRate = 48_000
        configuration.channelCount = 2

        let streamDelegate = ScreenCaptureKitStreamDelegate()
        let stream = SCStream(filter: filter, configuration: configuration, delegate: streamDelegate)
        let recordingConfiguration = SCRecordingOutputConfiguration()
        recordingConfiguration.outputURL = outputURL
        recordingConfiguration.outputFileType = .mp4
        recordingConfiguration.videoCodecType = .h264

        let recordingDelegate = ScreenCaptureKitRecordingOutputDelegate()
        let recordingOutput = SCRecordingOutput(
            configuration: recordingConfiguration,
            delegate: recordingDelegate
        )
        try stream.addRecordingOutput(recordingOutput)
        try await stream.startCapture()
        try streamDelegate.throwIfFailed()
        try recordingDelegate.throwIfFailed()

        let token = AppleScreenCaptureKitRecordingToken(rawValue: context.sessionID)
        recordings[token] = ScreenCaptureKitRecordingSession(
            stream: stream,
            streamDelegate: streamDelegate,
            recordingOutput: recordingOutput,
            recordingDelegate: recordingDelegate,
            outputURL: outputURL
        )
        return token
    }

    func stopRecording(
        _ token: AppleScreenCaptureKitRecordingToken
    ) async throws -> AppleScreenCaptureKitRecordingFile {
        guard let session = recordings.removeValue(forKey: token) else {
            throw AppleScreenCaptureKitRuntimeError.unknownRecording(token)
        }

        do {
            try session.stream.removeRecordingOutput(session.recordingOutput)
            try await session.stream.stopCapture()
            try await session.recordingDelegate.waitForFinish()
            try session.streamDelegate.throwIfFailed()
            try session.recordingDelegate.throwIfFailed()
            return AppleScreenCaptureKitRecordingFile(url: session.outputURL, format: "mp4")
        } catch {
            try? await session.stream.stopCapture()
            throw error
        }
    }
}

@available(macOS 15.0, *)
private struct ScreenCaptureKitRecordingSession {
    let stream: SCStream
    let streamDelegate: ScreenCaptureKitStreamDelegate
    let recordingOutput: SCRecordingOutput
    let recordingDelegate: ScreenCaptureKitRecordingOutputDelegate
    let outputURL: URL
}

@available(macOS 15.0, *)
private final class ScreenCaptureKitStreamDelegate: NSObject, SCStreamDelegate, @unchecked Sendable {
    private let lock = NSLock()
    private var failure: Error?

    func stream(_ stream: SCStream, didStopWithError error: Error) {
        lock.withLock {
            failure = error
        }
    }

    func throwIfFailed() throws {
        let error = lock.withLock { failure }
        if let error {
            throw error
        }
    }
}

@available(macOS 15.0, *)
private final class ScreenCaptureKitRecordingOutputDelegate: NSObject, SCRecordingOutputDelegate, @unchecked Sendable {
    private let lock = NSLock()
    private var failure: Error?
    private var didFinish = false
    private var finishContinuation: CheckedContinuation<Void, Error>?

    func recordingOutput(
        _ recordingOutput: SCRecordingOutput,
        didFailWithError error: Error
    ) {
        let continuation = lock.withLock {
            failure = error
            let continuation = finishContinuation
            finishContinuation = nil
            return continuation
        }
        continuation?.resume(throwing: error)
    }

    func recordingOutputDidFinishRecording(_ recordingOutput: SCRecordingOutput) {
        let continuation = lock.withLock {
            didFinish = true
            let continuation = finishContinuation
            finishContinuation = nil
            return continuation
        }
        continuation?.resume()
    }

    func waitForFinish() async throws {
        try await withCheckedThrowingContinuation { continuation in
            let result: Result<Void, Error>? = lock.withLock {
                if let failure {
                    return Result<Void, Error>.failure(failure)
                }
                if didFinish {
                    return Result<Void, Error>.success(())
                }
                finishContinuation = continuation
                return nil
            }
            if let result {
                continuation.resume(with: result)
                return
            }
            DispatchQueue.global().asyncAfter(deadline: .now() + 10) { [weak self] in
                let continuation = self?.lock.withLock { () -> CheckedContinuation<Void, Error>? in
                    guard let continuation = self?.finishContinuation else {
                        return nil
                    }
                    self?.failure = AppleScreenCaptureKitRuntimeError.recordingOutputTimedOut
                    self?.finishContinuation = nil
                    return continuation
                }
                continuation?.resume(throwing: AppleScreenCaptureKitRuntimeError.recordingOutputTimedOut)
            }
        }
    }

    func throwIfFailed() throws {
        let error = lock.withLock { failure }
        if let error {
            throw error
        }
    }
}
