import Foundation

public actor NativeRecordingCommandClient: RecordingCommandClient {
    private let permissionChecker: any NativeCapturePermissionChecking
    private let captureAdapter: any NativeCaptureAdapter
    private let sessionStore: RecordingSessionStore
    private let sessionIDProvider: @Sendable () -> String
    private let timestampProvider: @Sendable () -> String
    private let requestIDProvider: @Sendable (RecordingCommandName) -> String
    private var activeSessions: [String: RecordingSessionReference] = [:]

    public init(
        permissionChecker: any NativeCapturePermissionChecking = StaticNativeCapturePermissionChecker(),
        captureAdapter: any NativeCaptureAdapter = ControlledNativeCaptureAdapter(),
        sessionStore: RecordingSessionStore = RecordingSessionStore(),
        sessionIDProvider: @escaping @Sendable () -> String = {
            "session-\(UUID().uuidString.lowercased())"
        },
        timestampProvider: @escaping @Sendable () -> String = {
            let formatter = ISO8601DateFormatter()
            formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
            return formatter.string(from: Date())
        },
        requestIDProvider: @escaping @Sendable (RecordingCommandName) -> String = { command in
            "local-native-\(command.rawValue)-\(UUID().uuidString.lowercased())"
        }
    ) {
        self.permissionChecker = permissionChecker
        self.captureAdapter = captureAdapter
        self.sessionStore = sessionStore
        self.sessionIDProvider = sessionIDProvider
        self.timestampProvider = timestampProvider
        self.requestIDProvider = requestIDProvider
    }

    public func startNativeRecording(
        _ request: StartNativeRecordingRequest
    ) async throws -> RecordingCommandResponse {
        let requestID = requestIDProvider(.startNativeRecording)
        let permissions = await permissionChecker.permissionSnapshot(for: request)
        let blockedReasons = permissions.blockedReasons(for: request)
        guard blockedReasons.isEmpty else {
            return RecordingCommandResponse.failure(
                requestID: requestID,
                command: .startNativeRecording,
                code: .permissionDenied,
                message: "Native capture permissions are denied or unknown.",
                details: blockedReasons
            )
        }

        let sessionID = sessionIDProvider()
        let startedAt = timestampProvider()
        do {
            let context = try sessionStore.makeStartContext(
                request: request,
                sessionID: sessionID,
                startedAt: startedAt
            )
            try await captureAdapter.start(context)
            let reference = try sessionStore.createRecordingSession(
                context: context,
                title: request.title
            )
            activeSessions[sessionID] = reference
            return .successfulStart(
                requestID: requestID,
                sessionID: sessionID,
                captureTarget: request.captureTarget ?? .screen
            )
        } catch let failure as NativeCaptureAdapterFailure {
            return RecordingCommandResponse.failure(
                requestID: requestID,
                command: .startNativeRecording,
                code: .captureFailed,
                message: failure.localizedDescription
            )
        } catch let error as RecordingSessionStoreError {
            return storeFailureResponse(
                error,
                requestID: requestID,
                command: .startNativeRecording,
                sessionID: nil
            )
        } catch {
            return RecordingCommandResponse.failure(
                requestID: requestID,
                command: .startNativeRecording,
                code: .captureFailed,
                message: error.localizedDescription
            )
        }
    }

    public func stopRecording(
        _ request: StopRecordingRequest
    ) async throws -> RecordingCommandResponse {
        let requestID = requestIDProvider(.stopRecording)
        guard let reference = activeSessions[request.sessionID] else {
            return RecordingCommandResponse.failure(
                requestID: requestID,
                command: .stopRecording,
                sessionID: request.sessionID,
                code: .notFound,
                message: "Recording session is not active."
            )
        }

        do {
            if let finalResponse = try sessionStore.finalResponseIfAvailable(
                reference: reference,
                requestID: requestID
            ) {
                return finalResponse
            }

            let endedAt = timestampProvider()
            let context = NativeCaptureStopContext(
                sessionID: request.sessionID,
                workspaceURL: reference.workspaceURL,
                sessionURL: reference.sessionURL,
                artifactsURL: reference.artifactsURL,
                endedAt: endedAt
            )
            do {
                let result = try await captureAdapter.stop(context)
                return try sessionStore.finalizeRecording(
                    reference: reference,
                    adapterArtifacts: result.artifacts,
                    endedAt: endedAt,
                    defaultFailureReason: nil,
                    requestID: requestID
                )
            } catch NativeCaptureAdapterFailure.stopFailed(let message, let partialArtifacts) {
                return try sessionStore.finalizeRecording(
                    reference: reference,
                    adapterArtifacts: partialArtifacts,
                    endedAt: endedAt,
                    defaultFailureReason: message,
                    requestID: requestID
                )
            } catch let failure as NativeCaptureAdapterFailure {
                return try sessionStore.finalizeRecording(
                    reference: reference,
                    adapterArtifacts: [],
                    endedAt: endedAt,
                    defaultFailureReason: failure.localizedDescription,
                    requestID: requestID
                )
            }
        } catch let error as RecordingSessionStoreError {
            return storeFailureResponse(
                error,
                requestID: requestID,
                command: .stopRecording,
                sessionID: request.sessionID
            )
        } catch {
            return RecordingCommandResponse.failure(
                requestID: requestID,
                command: .stopRecording,
                sessionID: request.sessionID,
                code: .captureFailed,
                message: error.localizedDescription
            )
        }
    }

    private func storeFailureResponse(
        _ error: RecordingSessionStoreError,
        requestID: String,
        command: RecordingCommandName,
        sessionID: String?
    ) -> RecordingCommandResponse {
        let code: RecordingCommandErrorCode
        switch error {
        case .sessionNotFound:
            code = .notFound
        case .unavailableArtifactData:
            code = .captureFailed
        case .invalidSessionID, .pathConflict, .invalidSessionMetadata:
            code = .pathConflict
        }

        return RecordingCommandResponse.failure(
            requestID: requestID,
            command: command,
            sessionID: sessionID,
            code: code,
            message: error.localizedDescription
        )
    }
}
