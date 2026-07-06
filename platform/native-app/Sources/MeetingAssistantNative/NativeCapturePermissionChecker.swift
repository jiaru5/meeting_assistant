import AVFoundation
import CoreGraphics
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

public struct CoreGraphicsScreenRecordingPermissionProbe: Sendable {
    private let preflight: @Sendable () -> Bool
    private let requestAccess: @Sendable () -> Bool
    private let requestAccessWhenDenied: Bool

    public init(
        preflight: @escaping @Sendable () -> Bool = {
            CGPreflightScreenCaptureAccess()
        },
        requestAccessWhenDenied: Bool = false,
        requestAccess: @escaping @Sendable () -> Bool = {
            CGRequestScreenCaptureAccess()
        }
    ) {
        self.preflight = preflight
        self.requestAccess = requestAccess
        self.requestAccessWhenDenied = requestAccessWhenDenied
    }

    public func state() -> NativeCapturePermissionState {
        if preflight() {
            return .granted
        }
        guard requestAccessWhenDenied else {
            return .denied
        }
        if requestAccess() {
            return .granted
        }
        return preflight() ? .granted : .denied
    }
}

public struct AVFoundationMicrophonePermissionProbe: Sendable {
    public enum AuthorizationState: Equatable, Sendable {
        case authorized
        case denied
        case restricted
        case notDetermined
        case unknown
    }

    private let authorizationState: @Sendable () -> AuthorizationState
    private let requestAccess: @Sendable () async -> Bool
    private let requestAccessWhenUndetermined: Bool

    public init(
        authorizationState: @escaping @Sendable () -> AuthorizationState = {
            Self.currentAuthorizationState()
        },
        requestAccessWhenUndetermined: Bool = false,
        requestAccess: @escaping @Sendable () async -> Bool = {
            await Self.requestAudioAccess()
        }
    ) {
        self.authorizationState = authorizationState
        self.requestAccess = requestAccess
        self.requestAccessWhenUndetermined = requestAccessWhenUndetermined
    }

    public func state() async -> NativeCapturePermissionState {
        switch authorizationState() {
        case .authorized:
            return .granted
        case .denied, .restricted:
            return .denied
        case .notDetermined:
            guard requestAccessWhenUndetermined else {
                return .unknown
            }
            if await requestAccess() {
                return .granted
            }
            return authorizationState() == .authorized ? .granted : .denied
        case .unknown:
            return .unknown
        }
    }

    public static func currentAuthorizationState() -> AuthorizationState {
        switch AVCaptureDevice.authorizationStatus(for: .audio) {
        case .authorized:
            return .authorized
        case .denied:
            return .denied
        case .restricted:
            return .restricted
        case .notDetermined:
            return .notDetermined
        @unknown default:
            return .unknown
        }
    }

    public static func requestAudioAccess() async -> Bool {
        await withCheckedContinuation { continuation in
            AVCaptureDevice.requestAccess(for: .audio) { granted in
                continuation.resume(returning: granted)
            }
        }
    }
}

public struct MacOSNativeCapturePermissionChecker: NativeCapturePermissionChecking {
    private let screenRecordingProbe: CoreGraphicsScreenRecordingPermissionProbe
    private let microphoneStateProvider: @Sendable () async -> NativeCapturePermissionState

    public init(
        screenRecordingProbe: CoreGraphicsScreenRecordingPermissionProbe = CoreGraphicsScreenRecordingPermissionProbe(),
        microphoneStateProvider: @escaping @Sendable () -> NativeCapturePermissionState = {
            .unknown
        }
    ) {
        self.screenRecordingProbe = screenRecordingProbe
        self.microphoneStateProvider = {
            microphoneStateProvider()
        }
    }

    public init(
        screenRecordingProbe: CoreGraphicsScreenRecordingPermissionProbe = CoreGraphicsScreenRecordingPermissionProbe(),
        microphonePermissionProbe: AVFoundationMicrophonePermissionProbe
    ) {
        self.screenRecordingProbe = screenRecordingProbe
        self.microphoneStateProvider = {
            await microphonePermissionProbe.state()
        }
    }

    public func permissionSnapshot(
        for request: StartNativeRecordingRequest
    ) async -> NativeCapturePermissionSnapshot {
        let microphoneState: NativeCapturePermissionState = if request.captureMicrophoneAudio {
            await microphoneStateProvider()
        } else {
            .granted
        }
        return NativeCapturePermissionSnapshot(
            screenRecording: screenRecordingProbe.state(),
            microphone: microphoneState
        )
    }
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
