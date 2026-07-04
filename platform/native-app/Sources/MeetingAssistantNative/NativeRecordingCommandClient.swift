import Foundation

public actor NativeRecordingCommandClient: RecordingCommandClient {
    private let permissionChecker: any NativeCapturePermissionChecking
    private let captureAdapter: any NativeCaptureAdapter
    private let sessionStore: RecordingSessionStore
    private let sessionIDProvider: @Sendable () -> String
    private let timestampProvider: @Sendable () -> String
    private let requestIDProvider: @Sendable (RecordingCommandName) -> String
    private let recoveryWorkspaceURLProvider: @Sendable () -> URL
    private var activeSessions: [String: RecordingSessionReference] = [:]
    private var pendingStopFinalizations: [String: PendingNativeStopFinalization] = [:]

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
        },
        recoveryWorkspaceURLProvider: @escaping @Sendable () -> URL = {
            RecordingSessionStore.defaultWorkspaceURL
        }
    ) {
        self.permissionChecker = permissionChecker
        self.captureAdapter = captureAdapter
        self.sessionStore = sessionStore
        self.sessionIDProvider = sessionIDProvider
        self.timestampProvider = timestampProvider
        self.requestIDProvider = requestIDProvider
        self.recoveryWorkspaceURLProvider = recoveryWorkspaceURLProvider
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
            let reference: RecordingSessionReference
            do {
                reference = try sessionStore.createRecordingSession(
                    context: context,
                    title: request.title
                )
            } catch {
                await stopCaptureAfterStartFailure(context: context)
                throw error
            }
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
        let reference: RecordingSessionReference
        do {
            reference = try recordingSessionReferenceForStop(sessionID: request.sessionID)
        } catch let error as RecordingSessionStoreError {
            return storeFailureResponse(
                error,
                requestID: requestID,
                command: .stopRecording,
                sessionID: request.sessionID
            )
        }

        do {
            if let finalResponse = try sessionStore.finalResponseIfAvailable(
                reference: reference,
                requestID: requestID
            ) {
                pendingStopFinalizations.removeValue(forKey: request.sessionID)
                return finalResponse
            }

            if let pending = pendingStopFinalizations[request.sessionID] {
                return try finalizePendingStop(
                    pending,
                    reference: reference,
                    requestID: requestID
                )
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
                let pending = PendingNativeStopFinalization(
                    adapterArtifacts: result.artifacts,
                    endedAt: endedAt,
                    defaultFailureReason: nil
                )
                pendingStopFinalizations[request.sessionID] = pending
                return try finalizePendingStop(
                    pending,
                    reference: reference,
                    requestID: requestID
                )
            } catch NativeCaptureAdapterFailure.stopFailed(let message, let partialArtifacts) {
                let pending = PendingNativeStopFinalization(
                    adapterArtifacts: partialArtifacts,
                    endedAt: endedAt,
                    defaultFailureReason: message
                )
                pendingStopFinalizations[request.sessionID] = pending
                return try finalizePendingStop(
                    pending,
                    reference: reference,
                    requestID: requestID
                )
            } catch let failure as NativeCaptureAdapterFailure {
                let pending = PendingNativeStopFinalization(
                    adapterArtifacts: [],
                    endedAt: endedAt,
                    defaultFailureReason: failure.localizedDescription
                )
                pendingStopFinalizations[request.sessionID] = pending
                return try finalizePendingStop(
                    pending,
                    reference: reference,
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

    private func recordingSessionReferenceForStop(sessionID: String) throws -> RecordingSessionReference {
        if let reference = activeSessions[sessionID] {
            return reference
        }

        let reference = try sessionStore.existingSessionReference(
            sessionID: sessionID,
            workspaceURL: recoveryWorkspaceURLProvider()
        )
        activeSessions[sessionID] = reference
        return reference
    }

    private func stopCaptureAfterStartFailure(context: NativeCaptureStartContext) async {
        let endedAt = timestampProvider()
        let stopContext = NativeCaptureStopContext(
            sessionID: context.sessionID,
            workspaceURL: context.workspaceURL,
            sessionURL: context.sessionURL,
            artifactsURL: context.artifactsURL,
            endedAt: endedAt
        )
        _ = try? await captureAdapter.stop(stopContext)
    }

    private func finalizePendingStop(
        _ pending: PendingNativeStopFinalization,
        reference: RecordingSessionReference,
        requestID: String
    ) throws -> RecordingCommandResponse {
        let response = try sessionStore.finalizeRecording(
            reference: reference,
            adapterArtifacts: pending.adapterArtifacts,
            endedAt: pending.endedAt,
            defaultFailureReason: pending.defaultFailureReason,
            requestID: requestID
        )
        pendingStopFinalizations.removeValue(forKey: reference.sessionID)
        return response
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

private struct PendingNativeStopFinalization: Sendable {
    let adapterArtifacts: [NativeCaptureArtifactResult]
    let endedAt: String
    let defaultFailureReason: String?
}
