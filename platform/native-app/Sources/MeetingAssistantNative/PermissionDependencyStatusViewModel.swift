import Foundation
import Security
import SwiftUI

public enum PermissionDependencyPhase: String, Equatable, Sendable {
    case idle
    case checking
    case ready
    case blocked
    case failed
}

public enum NativePermissionState: String, Equatable, Sendable {
    case granted
    case denied
    case notConfirmed
}

public struct PermissionStatusItem: Equatable, Identifiable, Sendable {
    public let id: String
    public let title: String
    public let state: NativePermissionState
    public let message: String
}

public struct DependencyStatusItem: Equatable, Identifiable, Sendable {
    public let id: String
    public let title: String
    public let status: String
    public let required: Bool
    public let isPassing: Bool
    public let message: String
}

public struct LocalAppPermissionIdentity: Equatable, Sendable {
    public let bundlePath: String
    public let bundleIdentifier: String
    public let codeSignatureHash: String?

    public init(
        bundlePath: String,
        bundleIdentifier: String,
        codeSignatureHash: String? = nil
    ) {
        self.bundlePath = bundlePath
        self.bundleIdentifier = bundleIdentifier
        self.codeSignatureHash = codeSignatureHash
    }

    public static func current(bundle: Bundle = .main) -> LocalAppPermissionIdentity {
        LocalAppPermissionIdentity(
            bundlePath: bundle.bundlePath,
            bundleIdentifier: bundle.bundleIdentifier ?? "unknown",
            codeSignatureHash: currentCodeSignatureHash()
        )
    }

    public var permissionRepairSummary: String {
        let hashSummary = codeSignatureHash.map { ", CDHash: \($0)" } ?? ""
        return "Authorize this exact app in Screen Recording / Screen & System Audio Recording: \(bundlePath) (bundle id: \(bundleIdentifier)\(hashSummary))."
    }

    public var staleIdentityRepairSummary: String {
        "If System Settings already shows MeetingAssistantNative enabled but recording still fails, remove the stale entry and add this exact app again."
    }

    public var recordingPermissionFailureHint: String {
        "\(permissionRepairSummary) \(staleIdentityRepairSummary)"
    }

    private static func currentCodeSignatureHash() -> String? {
        var code: SecCode?
        guard SecCodeCopySelf(SecCSFlags(), &code) == errSecSuccess, let code else {
            return nil
        }
        var staticCode: SecStaticCode?
        guard SecCodeCopyStaticCode(code, SecCSFlags(), &staticCode) == errSecSuccess, let staticCode else {
            return nil
        }
        var information: CFDictionary?
        let flags = SecCSFlags(rawValue: kSecCSSigningInformation)
        guard SecCodeCopySigningInformation(staticCode, flags, &information) == errSecSuccess,
              let dictionary = information as? [String: Any],
              let unique = dictionary[kSecCodeInfoUnique as String] as? Data
        else {
            return nil
        }
        return unique.map { String(format: "%02x", $0) }.joined()
    }
}

public struct PermissionDependencyStatusState: Equatable, Sendable {
    public let phase: PermissionDependencyPhase
    public let summary: String
    public let permissions: [PermissionStatusItem]
    public let dependencies: [DependencyStatusItem]
    public let missingRequiredCheckIDs: [String]
    public let warnings: [String]
    public let canStartRecording: Bool
    public let canRunProcessing: Bool

    public var hasUnconfirmedOrDeniedPermissions: Bool {
        permissions.contains { $0.state != .granted }
    }

    public static let idle = PermissionDependencyStatusState(
        phase: .idle,
        summary: "Run checks before recording or processing.",
        permissions: Self.defaultPermissions(),
        dependencies: [],
        missingRequiredCheckIDs: [],
        warnings: [],
        canStartRecording: false,
        canRunProcessing: false
    )

    public static let checking = PermissionDependencyStatusState(
        phase: .checking,
        summary: "Checking permissions and local dependencies...",
        permissions: Self.defaultPermissions(),
        dependencies: [],
        missingRequiredCheckIDs: [],
        warnings: [],
        canStartRecording: false,
        canRunProcessing: false
    )

    public static func failed(_ message: String) -> PermissionDependencyStatusState {
        PermissionDependencyStatusState(
            phase: .failed,
            summary: message,
            permissions: Self.defaultPermissions(),
            dependencies: [],
            missingRequiredCheckIDs: [],
            warnings: [],
            canStartRecording: false,
            canRunProcessing: false
        )
    }

    public static func from(_ response: DependencyCheckResponse) -> PermissionDependencyStatusState {
        let permissions = [
            permissionStatus(
                for: "permission.screen_recording",
                title: "Screen Recording",
                checks: response.checks
            ),
            permissionStatus(
                for: "permission.microphone",
                title: "Microphone",
                checks: response.checks
            ),
        ]
        let dependencies = response.checks
            .filter { !isPermissionCheck($0.id) }
            .map(DependencyStatusItem.from)
        let missingRequired = response.checks
            .filter { $0.required && !$0.isPassing }
            .map(\.id)
        let deniedPermissions = permissions.filter { $0.state == .denied }
        let unconfirmedPermissions = permissions.filter { $0.state == .notConfirmed }
        let canRunProcessing = response.ok
        let canStartRecording = canRunProcessing && deniedPermissions.isEmpty
        let phase: PermissionDependencyPhase = canStartRecording ? .ready : .blocked

        return PermissionDependencyStatusState(
            phase: phase,
            summary: summary(
                responseOK: response.ok,
                hasMissingRequiredDependencies: !missingRequired.isEmpty,
                hasDeniedPermissions: !deniedPermissions.isEmpty,
                hasUnconfirmedPermissions: !unconfirmedPermissions.isEmpty
            ),
            permissions: permissions,
            dependencies: dependencies,
            missingRequiredCheckIDs: missingRequired,
            warnings: response.warnings,
            canStartRecording: canStartRecording,
            canRunProcessing: canRunProcessing
        )
    }

    private static func defaultPermissions() -> [PermissionStatusItem] {
        [
            PermissionStatusItem(
                id: "permission.screen_recording",
                title: "Screen Recording",
                state: .notConfirmed,
                message: "Screen Recording permission has not been checked."
            ),
            PermissionStatusItem(
                id: "permission.microphone",
                title: "Microphone",
                state: .notConfirmed,
                message: "Microphone permission has not been checked."
            ),
        ]
    }

    private static func permissionStatus(
        for id: String,
        title: String,
        checks: [DependencyCheckItem]
    ) -> PermissionStatusItem {
        guard let check = checks.first(where: { $0.id == id }) else {
            return PermissionStatusItem(
                id: id,
                title: title,
                state: .notConfirmed,
                message: "\(title) permission status is not available yet."
            )
        }

        let state: NativePermissionState
        switch check.status.lowercased() {
        case "granted":
            state = .granted
        case "denied":
            state = .denied
        default:
            state = .notConfirmed
        }

        return PermissionStatusItem(
            id: id,
            title: title,
            state: state,
            message: check.message
        )
    }

    private static func summary(
        responseOK: Bool,
        hasMissingRequiredDependencies: Bool,
        hasDeniedPermissions: Bool,
        hasUnconfirmedPermissions: Bool
    ) -> String {
        if !responseOK && !hasMissingRequiredDependencies && !hasDeniedPermissions {
            return "Recording and processing are blocked by dependency check failure."
        }
        switch (hasMissingRequiredDependencies, hasDeniedPermissions, hasUnconfirmedPermissions) {
        case (false, false, false):
            return "Permissions and required dependencies are ready."
        case (false, false, true):
            return "Recording can be started to confirm macOS permissions; denied permissions still fail closed."
        case (true, true, _):
            return "Recording and processing are blocked by missing permissions and dependencies."
        case (false, true, _):
            return "Recording is blocked until macOS permissions are granted."
        case (true, false, true):
            return "Processing is blocked until required dependencies are available; recording permissions still need confirmation."
        case (true, false, false):
            return "Processing is blocked until required dependencies are available."
        }
    }

    private static func isPermissionCheck(_ id: String) -> Bool {
        id.hasPrefix("permission.")
    }
}

extension DependencyStatusItem {
    static func from(_ check: DependencyCheckItem) -> DependencyStatusItem {
        DependencyStatusItem(
            id: check.id,
            title: title(for: check.id),
            status: check.status,
            required: check.required,
            isPassing: check.isPassing,
            message: check.message
        )
    }

    private static func title(for id: String) -> String {
        switch id {
        case "platform.os":
            return "macOS"
        case "platform.macos_version":
            return "macOS Version"
        case "platform.cpu_arch":
            return "CPU Architecture"
        case "developer_tools.swift":
            return "Swift Toolchain"
        case "media_tool.ffmpeg":
            return "Media Tool"
        case "transcription.runtime":
            return "Transcription Runtime"
        case "transcription.model":
            return "Transcription Model"
        case "transcription.hardware":
            return "Transcription Hardware"
        case "transcription.model.multilingual":
            return "Multilingual Model"
        case "speaker_labeling.runtime":
            return "Speaker Labeling Runtime"
        case "workspace.writable":
            return "Workspace"
        case "dependency_sources.allowed":
            return "Allowed Sources"
        case "dependency_downloads.automatic":
            return "Automatic Downloads"
        default:
            return id
        }
    }
}

@MainActor
public final class PermissionDependencyStatusViewModel: ObservableObject {
    @Published public private(set) var state: PermissionDependencyStatusState

    private let runner: any DependencyCheckRunning

    public init(
        runner: any DependencyCheckRunning = ProcessingCLIDependencyCheckRunner(),
        initialState: PermissionDependencyStatusState = .idle
    ) {
        self.runner = runner
        self.state = initialState
    }

    public func refresh(workspaceURL: URL? = nil) async {
        state = .checking
        do {
            let response = try await runner.checkDependencies(workspaceURL: workspaceURL)
            state = .from(response)
        } catch {
            state = .failed(error.localizedDescription)
        }
    }
}
