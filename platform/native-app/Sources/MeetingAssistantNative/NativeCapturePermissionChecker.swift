import Foundation

public enum NativeCapturePermissionState: String, Equatable, Sendable {
    case granted
    case denied
    case unknown
}

public struct NativeCapturePermissionSnapshot: Equatable, Sendable {
    public let screenRecording: NativeCapturePermissionState
    public let microphone: NativeCapturePermissionState

    public init(
        screenRecording: NativeCapturePermissionState,
        microphone: NativeCapturePermissionState
    ) {
        self.screenRecording = screenRecording
        self.microphone = microphone
    }

    public static let granted = NativeCapturePermissionSnapshot(
        screenRecording: .granted,
        microphone: .granted
    )

    public static let denied = NativeCapturePermissionSnapshot(
        screenRecording: .denied,
        microphone: .denied
    )

    public static let unknown = NativeCapturePermissionSnapshot(
        screenRecording: .unknown,
        microphone: .unknown
    )

    public func blockedReasons(for request: StartNativeRecordingRequest) -> [String] {
        var reasons: [String] = []
        appendBlockedReason(
            state: screenRecording,
            permissionName: "Screen Recording",
            into: &reasons
        )
        if request.captureMicrophoneAudio {
            appendBlockedReason(
                state: microphone,
                permissionName: "Microphone",
                into: &reasons
            )
        }
        return reasons
    }

    private func appendBlockedReason(
        state: NativeCapturePermissionState,
        permissionName: String,
        into reasons: inout [String]
    ) {
        switch state {
        case .granted:
            return
        case .denied:
            reasons.append("\(permissionName) permission is denied.")
        case .unknown:
            reasons.append("\(permissionName) permission status is unknown.")
        }
    }
}

public protocol NativeCapturePermissionChecking: Sendable {
    func permissionSnapshot(
        for request: StartNativeRecordingRequest
    ) async -> NativeCapturePermissionSnapshot
}

public struct StaticNativeCapturePermissionChecker: NativeCapturePermissionChecking {
    private let snapshot: NativeCapturePermissionSnapshot

    public init(snapshot: NativeCapturePermissionSnapshot = .unknown) {
        self.snapshot = snapshot
    }

    public func permissionSnapshot(
        for request: StartNativeRecordingRequest
    ) async -> NativeCapturePermissionSnapshot {
        snapshot
    }
}
