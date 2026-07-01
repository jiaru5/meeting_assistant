import Foundation

public actor ControlledNativeCaptureAdapter: NativeCaptureAdapter {
    public enum StartBehavior: Equatable, Sendable {
        case success
        case failure(message: String)
    }

    public enum StopBehavior: Equatable, Sendable {
        case success(artifacts: [NativeCaptureArtifactResult])
        case failure(message: String, partialArtifacts: [NativeCaptureArtifactResult])
    }

    public private(set) var startContexts: [NativeCaptureStartContext] = []
    public private(set) var stopContexts: [NativeCaptureStopContext] = []

    private let startBehavior: StartBehavior
    private let stopBehavior: StopBehavior
    private var startedSessionIDs: Set<String> = []

    public init(
        startBehavior: StartBehavior = .success,
        stopBehavior: StopBehavior = .success(artifacts: [])
    ) {
        self.startBehavior = startBehavior
        self.stopBehavior = stopBehavior
    }

    public func start(_ context: NativeCaptureStartContext) async throws {
        startContexts.append(context)
        switch startBehavior {
        case .success:
            startedSessionIDs.insert(context.sessionID)
        case .failure(let message):
            throw NativeCaptureAdapterFailure.startFailed(message)
        }
    }

    public func stop(_ context: NativeCaptureStopContext) async throws -> NativeCaptureStopResult {
        stopContexts.append(context)
        guard startedSessionIDs.contains(context.sessionID) else {
            throw NativeCaptureAdapterFailure.stopFailed(
                message: "Native capture session was not started.",
                partialArtifacts: []
            )
        }

        switch stopBehavior {
        case .success(let artifacts):
            startedSessionIDs.remove(context.sessionID)
            return NativeCaptureStopResult(artifacts: artifacts)
        case .failure(let message, let partialArtifacts):
            startedSessionIDs.remove(context.sessionID)
            throw NativeCaptureAdapterFailure.stopFailed(
                message: message,
                partialArtifacts: partialArtifacts
            )
        }
    }
}
