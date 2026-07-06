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
    public let attemptsMixedAudioExtractionFromCombinedRecording: Bool

    public init(
        adapterID: String,
        framework: String,
        supportedCaptureTargets: [RecordingCaptureTarget],
        producedArtifactTypes: [NativeCaptureArtifactType],
        producesCombinedRecordingFile: Bool,
        producesSeparateAudioArtifacts: Bool,
        attemptsMixedAudioExtractionFromCombinedRecording: Bool
    ) {
        self.adapterID = adapterID
        self.framework = framework
        self.supportedCaptureTargets = supportedCaptureTargets
        self.producedArtifactTypes = producedArtifactTypes
        self.producesCombinedRecordingFile = producesCombinedRecordingFile
        self.producesSeparateAudioArtifacts = producesSeparateAudioArtifacts
        self.attemptsMixedAudioExtractionFromCombinedRecording = attemptsMixedAudioExtractionFromCombinedRecording
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
        producesSeparateAudioArtifacts: true,
        attemptsMixedAudioExtractionFromCombinedRecording: true
    )

    private let runtime: any AppleScreenCaptureKitRecordingRuntime
    private let audioExtractor: any AppleScreenCaptureKitMixedAudioExtracting
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
        self.audioExtractor = AVFoundationAppleScreenCaptureKitMixedAudioExtractor()
        self.temporaryDirectoryProvider = { FileManager.default.temporaryDirectory }
    }

    init(
        runtime: any AppleScreenCaptureKitRecordingRuntime,
        audioExtractor: any AppleScreenCaptureKitMixedAudioExtracting = AVFoundationAppleScreenCaptureKitMixedAudioExtractor(),
        temporaryDirectoryProvider: @escaping @Sendable () -> URL = {
            FileManager.default.temporaryDirectory
        }
    ) {
        self.runtime = runtime
        self.audioExtractor = audioExtractor
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
            let recordingFiles = try await runtime.stopRecording(recording.token)
            let recordingData = try recordingData(from: recordingFiles.combinedRecording.url)
            let mixedAudioArtifact = await mixedAudioArtifact(
                from: recordingFiles.combinedRecording.url,
                options: recording.options
            )
            let artifacts = artifactResults(
                combinedRecordingData: recordingData,
                combinedRecordingFormat: recordingFiles.combinedRecording.format,
                systemAudioFile: recordingFiles.systemAudio,
                microphoneAudioFile: recordingFiles.microphoneAudio,
                options: recording.options,
                mixedAudioArtifact: mixedAudioArtifact
            )
            cleanupTemporaryOutput(at: recording.outputURL)
            return NativeCaptureStopResult(artifacts: artifacts)
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
        systemAudioFile: AppleScreenCaptureKitRecordingFile?,
        microphoneAudioFile: AppleScreenCaptureKitRecordingFile?,
        options: AppleScreenCaptureKitRecordingOptions,
        mixedAudioArtifact: NativeCaptureArtifactResult
    ) -> [NativeCaptureArtifactResult] {
        [
            .available(
                .screenVideo,
                format: combinedRecordingFormat,
                data: combinedRecordingData
            ),
            audioArtifact(
                .systemAudio,
                recordingFile: systemAudioFile,
                wasRequested: options.captureSystemAudio,
                requestedReason: "ScreenCaptureKit did not provide a separate system_audio sample stream artifact for this native capture session."
            ),
            audioArtifact(
                .microphoneAudio,
                recordingFile: microphoneAudioFile,
                wasRequested: options.captureMicrophoneAudio,
                requestedReason: "ScreenCaptureKit did not provide a separate microphone_audio sample stream artifact for this native capture session."
            ),
            mixedAudioArtifact,
        ]
    }

    private func audioArtifact(
        _ artifactType: NativeCaptureArtifactType,
        recordingFile: AppleScreenCaptureKitRecordingFile?,
        wasRequested: Bool,
        requestedReason: String
    ) -> NativeCaptureArtifactResult {
        guard wasRequested else {
            return requestedAudioArtifact(
                artifactType,
                wasRequested: false,
                requestedReason: requestedReason
            )
        }
        guard let recordingFile else {
            return requestedAudioArtifact(
                artifactType,
                wasRequested: wasRequested,
                requestedReason: requestedReason
            )
        }
        do {
            return .available(
                artifactType,
                format: recordingFile.format,
                data: try recordingData(from: recordingFile.url)
            )
        } catch {
            return .degraded(
                artifactType,
                format: recordingFile.format,
                reason: "\(artifactType.rawValue) was produced by ScreenCaptureKit but could not be read: \(error.localizedDescription)"
            )
        }
    }

    private func mixedAudioArtifact(
        from combinedRecordingURL: URL,
        options: AppleScreenCaptureKitRecordingOptions
    ) async -> NativeCaptureArtifactResult {
        guard options.captureSystemAudio || options.captureMicrophoneAudio else {
            return .missing(
                .mixedAudio,
                reason: "mixed_audio was not requested for this native capture session."
            )
        }

        let mixedAudioURL = combinedRecordingURL
            .deletingLastPathComponent()
            .appendingPathComponent("mixed_audio.m4a", isDirectory: false)
        do {
            let extracted = try await audioExtractor.extractMixedAudio(
                from: combinedRecordingURL,
                to: mixedAudioURL
            )
            let data = try recordingData(from: extracted.url)
            return .available(
                .mixedAudio,
                format: extracted.format,
                data: data
            )
        } catch {
            return .degraded(
                .mixedAudio,
                format: "m4a",
                reason: "ScreenCaptureKit combined recording did not contain an exportable audio track for mixed_audio; no separate mixed_audio artifact was produced by this adapter."
            )
        }
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

struct AppleScreenCaptureKitMixedAudioFile: Equatable, Sendable {
    let url: URL
    let format: String
}

protocol AppleScreenCaptureKitMixedAudioExtracting: Sendable {
    func extractMixedAudio(
        from combinedRecordingURL: URL,
        to outputURL: URL
    ) async throws -> AppleScreenCaptureKitMixedAudioFile
}

enum AppleScreenCaptureKitMixedAudioExtractionError: Error, LocalizedError, Sendable {
    case noAudioTrack
    case exportSessionUnavailable
    case exportFailed

    var errorDescription: String? {
        switch self {
        case .noAudioTrack:
            return "ScreenCaptureKit combined recording contains no exportable audio track."
        case .exportSessionUnavailable:
            return "AVFoundation could not create an audio export session for the combined recording."
        case .exportFailed:
            return "AVFoundation audio export failed for the combined recording."
        }
    }
}

struct AVFoundationAppleScreenCaptureKitMixedAudioExtractor: AppleScreenCaptureKitMixedAudioExtracting {
    func extractMixedAudio(
        from combinedRecordingURL: URL,
        to outputURL: URL
    ) async throws -> AppleScreenCaptureKitMixedAudioFile {
        let asset = AVURLAsset(url: combinedRecordingURL)
        let audioTracks = try await asset.loadTracks(withMediaType: .audio)
        guard !audioTracks.isEmpty else {
            throw AppleScreenCaptureKitMixedAudioExtractionError.noAudioTrack
        }
        if FileManager.default.fileExists(atPath: outputURL.path) {
            try FileManager.default.removeItem(at: outputURL)
        }
        guard let exportSession = AVAssetExportSession(
            asset: asset,
            presetName: AVAssetExportPresetAppleM4A
        ) else {
            throw AppleScreenCaptureKitMixedAudioExtractionError.exportSessionUnavailable
        }
        exportSession.outputURL = outputURL
        exportSession.outputFileType = .m4a
        await withCheckedContinuation { continuation in
            exportSession.exportAsynchronously {
                continuation.resume()
            }
        }
        guard exportSession.status == .completed else {
            throw AppleScreenCaptureKitMixedAudioExtractionError.exportFailed
        }
        let data = try Data(contentsOf: outputURL)
        guard !data.isEmpty else {
            throw AppleScreenCaptureKitMixedAudioExtractionError.exportFailed
        }
        return AppleScreenCaptureKitMixedAudioFile(url: outputURL, format: "m4a")
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

struct AppleScreenCaptureKitRecordingFiles: Equatable, Sendable {
    let combinedRecording: AppleScreenCaptureKitRecordingFile
    let systemAudio: AppleScreenCaptureKitRecordingFile?
    let microphoneAudio: AppleScreenCaptureKitRecordingFile?

    init(
        combinedRecording: AppleScreenCaptureKitRecordingFile,
        systemAudio: AppleScreenCaptureKitRecordingFile? = nil,
        microphoneAudio: AppleScreenCaptureKitRecordingFile? = nil
    ) {
        self.combinedRecording = combinedRecording
        self.systemAudio = systemAudio
        self.microphoneAudio = microphoneAudio
    }
}

protocol AppleScreenCaptureKitRecordingRuntime: Sendable {
    func startRecording(
        context: NativeCaptureStartContext,
        outputURL: URL,
        options: AppleScreenCaptureKitRecordingOptions
    ) async throws -> AppleScreenCaptureKitRecordingToken

    func stopRecording(
        _ token: AppleScreenCaptureKitRecordingToken
    ) async throws -> AppleScreenCaptureKitRecordingFiles
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
    ) async throws -> AppleScreenCaptureKitRecordingFiles {
        throw AppleScreenCaptureKitRuntimeError.unavailable(reason)
    }
}

private enum AppleScreenCaptureKitRuntimeError: Error, LocalizedError {
    case unavailable(String)
    case noDisplayAvailable
    case unknownRecording(AppleScreenCaptureKitRecordingToken)
    case recordingOutputStartTimedOut
    case recordingOutputTimedOut
    case recordingOutputWaitAlreadyActive(String)

    var errorDescription: String? {
        switch self {
        case .unavailable(let reason):
            return reason
        case .noDisplayAvailable:
            return "No ScreenCaptureKit display is available for native capture."
        case .unknownRecording(let token):
            return "ScreenCaptureKit recording token is not active: \(token.rawValue)."
        case .recordingOutputStartTimedOut:
            return "ScreenCaptureKit recording output did not start before timeout."
        case .recordingOutputTimedOut:
            return "ScreenCaptureKit recording output did not finish writing before timeout."
        case .recordingOutputWaitAlreadyActive(let phase):
            return "ScreenCaptureKit recording output already has an active \(phase) waiter."
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
        let audioOutput = ScreenCaptureKitAudioOutput(
            directory: outputURL.deletingLastPathComponent(),
            options: options
        )
        do {
            try stream.addRecordingOutput(recordingOutput)
            try audioOutput.addRequestedOutputs(to: stream)
            try await stream.startCapture()
            try streamDelegate.throwIfFailed()
            try await recordingDelegate.waitForStart()
            try recordingDelegate.throwIfFailed()
        } catch {
            try? audioOutput.removeRequestedOutputs(from: stream)
            try? await stream.stopCapture()
            throw error
        }

        let token = AppleScreenCaptureKitRecordingToken(rawValue: context.sessionID)
        recordings[token] = ScreenCaptureKitRecordingSession(
            stream: stream,
            streamDelegate: streamDelegate,
            recordingOutput: recordingOutput,
            recordingDelegate: recordingDelegate,
            outputURL: outputURL,
            audioOutput: audioOutput
        )
        return token
    }

    func stopRecording(
        _ token: AppleScreenCaptureKitRecordingToken
    ) async throws -> AppleScreenCaptureKitRecordingFiles {
        guard let session = recordings.removeValue(forKey: token) else {
            throw AppleScreenCaptureKitRuntimeError.unknownRecording(token)
        }

        do {
            try session.stream.removeRecordingOutput(session.recordingOutput)
            try await session.recordingDelegate.waitForFinish()
            try session.streamDelegate.throwIfFailed()
            try session.recordingDelegate.throwIfFailed()
            try? session.audioOutput.removeRequestedOutputs(from: session.stream)
            try? await session.stream.stopCapture()
            let audioFiles = await session.audioOutput.finish()
            return AppleScreenCaptureKitRecordingFiles(
                combinedRecording: AppleScreenCaptureKitRecordingFile(url: session.outputURL, format: "mp4"),
                systemAudio: audioFiles.systemAudio,
                microphoneAudio: audioFiles.microphoneAudio
            )
        } catch {
            try? session.audioOutput.removeRequestedOutputs(from: session.stream)
            try? await session.stream.stopCapture()
            await session.audioOutput.cancel()
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
    let audioOutput: ScreenCaptureKitAudioOutput
}

@available(macOS 15.0, *)
private struct ScreenCaptureKitAudioOutputFiles: Sendable {
    let systemAudio: AppleScreenCaptureKitRecordingFile?
    let microphoneAudio: AppleScreenCaptureKitRecordingFile?
}

@available(macOS 15.0, *)
private final class ScreenCaptureKitAudioOutput: NSObject, SCStreamOutput, @unchecked Sendable {
    private let queue = DispatchQueue(label: "local.meeting-assistant.native.screencapturekit.audio-output")
    private let captureSystemAudio: Bool
    private let captureMicrophoneAudio: Bool
    private let systemAudioWriter: ScreenCaptureKitAudioTrackWriter?
    private let microphoneAudioWriter: ScreenCaptureKitAudioTrackWriter?
    private var isFinishing = false

    init(directory: URL, options: AppleScreenCaptureKitRecordingOptions) {
        self.captureSystemAudio = options.captureSystemAudio
        self.captureMicrophoneAudio = options.captureMicrophoneAudio
        self.systemAudioWriter = options.captureSystemAudio
            ? ScreenCaptureKitAudioTrackWriter(
                outputURL: directory.appendingPathComponent("system_audio.m4a", isDirectory: false)
            )
            : nil
        self.microphoneAudioWriter = options.captureMicrophoneAudio
            ? ScreenCaptureKitAudioTrackWriter(
                outputURL: directory.appendingPathComponent("microphone_audio.m4a", isDirectory: false)
            )
            : nil
        super.init()
    }

    func addRequestedOutputs(to stream: SCStream) throws {
        if captureSystemAudio {
            try stream.addStreamOutput(self, type: .audio, sampleHandlerQueue: queue)
        }
        if captureMicrophoneAudio {
            try stream.addStreamOutput(self, type: .microphone, sampleHandlerQueue: queue)
        }
    }

    func removeRequestedOutputs(from stream: SCStream) throws {
        var firstError: Error?
        if captureSystemAudio {
            do {
                try stream.removeStreamOutput(self, type: .audio)
            } catch {
                firstError = firstError ?? error
            }
        }
        if captureMicrophoneAudio {
            do {
                try stream.removeStreamOutput(self, type: .microphone)
            } catch {
                firstError = firstError ?? error
            }
        }
        if let firstError {
            throw firstError
        }
    }

    func stream(
        _ stream: SCStream,
        didOutputSampleBuffer sampleBuffer: CMSampleBuffer,
        of outputType: SCStreamOutputType
    ) {
        guard !isFinishing, CMSampleBufferDataIsReady(sampleBuffer) else {
            return
        }
        switch outputType {
        case .audio:
            systemAudioWriter?.append(sampleBuffer)
        case .microphone:
            microphoneAudioWriter?.append(sampleBuffer)
        default:
            return
        }
    }

    func finish() async -> ScreenCaptureKitAudioOutputFiles {
        let writers = queue.sync {
            isFinishing = true
            return (systemAudio: systemAudioWriter, microphoneAudio: microphoneAudioWriter)
        }
        let systemAudio = await writers.systemAudio?.finish()
        let microphoneAudio = await writers.microphoneAudio?.finish()
        return ScreenCaptureKitAudioOutputFiles(
            systemAudio: systemAudio,
            microphoneAudio: microphoneAudio
        )
    }

    func cancel() async {
        let writers = queue.sync {
            isFinishing = true
            return [systemAudioWriter, microphoneAudioWriter].compactMap { $0 }
        }
        for writer in writers {
            writer.cancel()
        }
    }
}

@available(macOS 15.0, *)
private final class ScreenCaptureKitAudioTrackWriter: @unchecked Sendable {
    private let outputURL: URL
    private var writer: AVAssetWriter?
    private var input: AVAssetWriterInput?
    private var didAppendSample = false
    private var failed = false

    init(outputURL: URL) {
        self.outputURL = outputURL
    }

    func append(_ sampleBuffer: CMSampleBuffer) {
        guard !failed, CMSampleBufferDataIsReady(sampleBuffer) else {
            return
        }
        do {
            if writer == nil {
                try startWriter(with: sampleBuffer)
            }
            guard
                let writer,
                let input,
                writer.status == .writing,
                input.isReadyForMoreMediaData
            else {
                failed = true
                return
            }
            guard input.append(sampleBuffer) else {
                failed = true
                return
            }
            didAppendSample = true
        } catch {
            failed = true
            cleanupOutput()
        }
    }

    func finish() async -> AppleScreenCaptureKitRecordingFile? {
        guard
            !failed,
            didAppendSample,
            let writer,
            let input,
            writer.status == .writing
        else {
            cleanupOutput()
            return nil
        }

        input.markAsFinished()
        await writer.finishWriting()
        guard writer.status == .completed, outputFileIsReadable() else {
            cleanupOutput()
            return nil
        }
        return AppleScreenCaptureKitRecordingFile(url: outputURL, format: "m4a")
    }

    func cancel() {
        writer?.cancelWriting()
        cleanupOutput()
    }

    private func startWriter(with sampleBuffer: CMSampleBuffer) throws {
        cleanupOutput()
        let writer = try AVAssetWriter(outputURL: outputURL, fileType: .m4a)
        let input = AVAssetWriterInput(
            mediaType: .audio,
            outputSettings: [
                AVFormatIDKey: kAudioFormatMPEG4AAC,
                AVSampleRateKey: 48_000,
                AVNumberOfChannelsKey: 2,
                AVEncoderBitRateKey: 128_000,
            ],
            sourceFormatHint: CMSampleBufferGetFormatDescription(sampleBuffer)
        )
        input.expectsMediaDataInRealTime = true
        guard writer.canAdd(input) else {
            throw ScreenCaptureKitAudioWriterError.inputRejected
        }
        writer.add(input)
        guard writer.startWriting() else {
            throw writer.error ?? ScreenCaptureKitAudioWriterError.writerStartFailed
        }
        let startTime = CMSampleBufferGetPresentationTimeStamp(sampleBuffer)
        guard startTime.isValid else {
            throw ScreenCaptureKitAudioWriterError.invalidStartTime
        }
        writer.startSession(atSourceTime: startTime)
        self.writer = writer
        self.input = input
    }

    private func outputFileIsReadable() -> Bool {
        guard FileManager.default.fileExists(atPath: outputURL.path) else {
            return false
        }
        return ((try? Data(contentsOf: outputURL))?.isEmpty == false)
    }

    private func cleanupOutput() {
        if FileManager.default.fileExists(atPath: outputURL.path) {
            try? FileManager.default.removeItem(at: outputURL)
        }
    }
}

@available(macOS 15.0, *)
private enum ScreenCaptureKitAudioWriterError: Error {
    case inputRejected
    case writerStartFailed
    case invalidStartTime
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
    private let eventState = ScreenCaptureKitRecordingEventState()

    func recordingOutputDidStartRecording(_ recordingOutput: SCRecordingOutput) {
        eventState.recordingDidStart()
    }

    func recordingOutput(
        _ recordingOutput: SCRecordingOutput,
        didFailWithError error: Error
    ) {
        eventState.recordingDidFail(error)
    }

    func recordingOutputDidFinishRecording(_ recordingOutput: SCRecordingOutput) {
        eventState.recordingDidFinish()
    }

    func waitForStart() async throws {
        try await eventState.waitForStart()
    }

    func waitForFinish() async throws {
        try await eventState.waitForFinish()
    }

    func throwIfFailed() throws {
        try eventState.throwIfFailed()
    }
}

final class ScreenCaptureKitRecordingEventState: @unchecked Sendable {
    private let lock = NSLock()
    private var failure: Error?
    private var didStart = false
    private var didFinish = false
    private var startContinuation: CheckedContinuation<Void, Error>?
    private var finishContinuation: CheckedContinuation<Void, Error>?

    func recordingDidStart() {
        let continuation = lock.withLock { () -> CheckedContinuation<Void, Error>? in
            didStart = true
            let continuation = startContinuation
            startContinuation = nil
            return continuation
        }
        continuation?.resume()
    }

    func recordingDidFail(_ error: Error) {
        let continuations = lock.withLock { () -> [CheckedContinuation<Void, Error>] in
            failure = error
            var continuations: [CheckedContinuation<Void, Error>] = []
            if let startContinuation {
                continuations.append(startContinuation)
                self.startContinuation = nil
            }
            if let finishContinuation {
                continuations.append(finishContinuation)
                self.finishContinuation = nil
            }
            return continuations
        }
        for continuation in continuations {
            continuation.resume(throwing: error)
        }
    }

    func recordingDidFinish() {
        let continuations = lock.withLock { () -> [CheckedContinuation<Void, Error>] in
            didStart = true
            didFinish = true
            var continuations: [CheckedContinuation<Void, Error>] = []
            if let startContinuation {
                continuations.append(startContinuation)
                self.startContinuation = nil
            }
            if let finishContinuation {
                continuations.append(finishContinuation)
                self.finishContinuation = nil
            }
            return continuations
        }
        for continuation in continuations {
            continuation.resume()
        }
    }

    func waitForStart(timeoutSeconds: TimeInterval = 10) async throws {
        try await withCheckedThrowingContinuation { continuation in
            let result: Result<Void, Error>? = lock.withLock {
                if let failure {
                    return .failure(failure)
                }
                if didStart || didFinish {
                    return .success(())
                }
                if startContinuation != nil {
                    return .failure(AppleScreenCaptureKitRuntimeError.recordingOutputWaitAlreadyActive("start"))
                }
                startContinuation = continuation
                return nil
            }
            if let result {
                continuation.resume(with: result)
                return
            }
            scheduleTimeout(
                seconds: timeoutSeconds,
                error: AppleScreenCaptureKitRuntimeError.recordingOutputStartTimedOut,
                phase: .start
            )
        }
    }

    func waitForFinish(timeoutSeconds: TimeInterval = 10) async throws {
        try await withCheckedThrowingContinuation { continuation in
            let result: Result<Void, Error>? = lock.withLock {
                if let failure {
                    return .failure(failure)
                }
                if didFinish {
                    return .success(())
                }
                if finishContinuation != nil {
                    return .failure(AppleScreenCaptureKitRuntimeError.recordingOutputWaitAlreadyActive("finish"))
                }
                finishContinuation = continuation
                return nil
            }
            if let result {
                continuation.resume(with: result)
                return
            }
            scheduleTimeout(
                seconds: timeoutSeconds,
                error: AppleScreenCaptureKitRuntimeError.recordingOutputTimedOut,
                phase: .finish
            )
        }
    }

    func throwIfFailed() throws {
        let error = lock.withLock { failure }
        if let error {
            throw error
        }
    }

    private enum WaitPhase {
        case start
        case finish
    }

    private func scheduleTimeout(
        seconds: TimeInterval,
        error: Error,
        phase: WaitPhase
    ) {
        let milliseconds = max(1, Int(seconds * 1_000))
        DispatchQueue.global().asyncAfter(deadline: .now() + .milliseconds(milliseconds)) {
            let continuations = self.lock.withLock { () -> [CheckedContinuation<Void, Error>] in
                if self.failure != nil {
                    return []
                }

                switch phase {
                case .start:
                    guard let startContinuation = self.startContinuation else {
                        return []
                    }
                    self.failure = error
                    self.startContinuation = nil
                    var continuations = [startContinuation]
                    if let finishContinuation = self.finishContinuation {
                        continuations.append(finishContinuation)
                        self.finishContinuation = nil
                    }
                    return continuations
                case .finish:
                    guard let finishContinuation = self.finishContinuation else {
                        return []
                    }
                    self.failure = error
                    self.finishContinuation = nil
                    return [finishContinuation]
                }
            }
            for continuation in continuations {
                continuation.resume(throwing: error)
            }
        }
    }
}
