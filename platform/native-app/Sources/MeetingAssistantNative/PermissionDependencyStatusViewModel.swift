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

public enum NativePermissionRepairDestination: String, CaseIterable, Equatable, Identifiable, Sendable {
    case screenRecording
    case microphone

    public var id: String {
        permissionID
    }

    public init?(permissionID: String) {
        switch permissionID {
        case "permission.screen_recording":
            self = .screenRecording
        case "permission.microphone":
            self = .microphone
        default:
            return nil
        }
    }

    public var permissionID: String {
        switch self {
        case .screenRecording:
            return "permission.screen_recording"
        case .microphone:
            return "permission.microphone"
        }
    }

    public var buttonTitle: String {
        switch self {
        case .screenRecording:
            return "Open Screen Recording Settings"
        case .microphone:
            return "Open Microphone Settings"
        }
    }
}

public struct LocalAppPermissionIdentity: Equatable, Sendable {
    public let bundlePath: String
    public let bundleIdentifier: String
    public let codeSignatureHash: String?
    public let designatedRequirement: String?
    public let signingAuthority: String?

    public init(
        bundlePath: String,
        bundleIdentifier: String,
        codeSignatureHash: String? = nil,
        designatedRequirement: String? = nil,
        signingAuthority: String? = nil
    ) {
        self.bundlePath = bundlePath
        self.bundleIdentifier = bundleIdentifier
        self.codeSignatureHash = codeSignatureHash
        self.designatedRequirement = designatedRequirement
        self.signingAuthority = signingAuthority
    }

    public static func current(bundle: Bundle = .main) -> LocalAppPermissionIdentity {
        let signingDetails = currentCodeSigningDetails()
        return LocalAppPermissionIdentity(
            bundlePath: bundle.bundlePath,
            bundleIdentifier: bundle.bundleIdentifier ?? "unknown",
            codeSignatureHash: signingDetails.cdHash,
            designatedRequirement: signingDetails.designatedRequirement,
            signingAuthority: signingDetails.signingAuthority
        )
    }

    public var permissionRepairSummary: String {
        var identityDetails = ["bundle id: \(bundleIdentifier)"]
        if let designatedRequirement, !designatedRequirement.isEmpty {
            identityDetails.append("designated requirement: \(designatedRequirement)")
        }
        if let signingAuthority, !signingAuthority.isEmpty {
            identityDetails.append("authority: \(signingAuthority)")
        }
        if let codeSignatureHash, !codeSignatureHash.isEmpty {
            identityDetails.append("current CDHash: \(codeSignatureHash)")
        }
        return "Authorize this exact app for the requested macOS Privacy permission: \(bundlePath) (\(identityDetails.joined(separator: ", ")))."
    }

    public var staleIdentityRepairSummary: String {
        "If System Settings already shows MeetingAssistantNative enabled but recording still fails, verify the exact app path and designated requirement, remove stale ad-hoc or old-path entries, then add this exact app again."
    }

    public var recordingPermissionFailureHint: String {
        "\(permissionRepairSummary) \(staleIdentityRepairSummary)"
    }

    private struct CodeSigningDetails {
        var cdHash: String?
        var designatedRequirement: String?
        var signingAuthority: String?
    }

    private static func currentCodeSigningDetails() -> CodeSigningDetails {
        var code: SecCode?
        guard SecCodeCopySelf(SecCSFlags(), &code) == errSecSuccess, let code else {
            return CodeSigningDetails()
        }
        var staticCode: SecStaticCode?
        guard SecCodeCopyStaticCode(code, SecCSFlags(), &staticCode) == errSecSuccess, let staticCode else {
            return CodeSigningDetails()
        }
        var information: CFDictionary?
        let flags = SecCSFlags(rawValue: kSecCSSigningInformation | kSecCSRequirementInformation)
        guard SecCodeCopySigningInformation(staticCode, flags, &information) == errSecSuccess,
              let dictionary = information as? [String: Any]
        else {
            return CodeSigningDetails()
        }

        var details = CodeSigningDetails()
        if let unique = dictionary[kSecCodeInfoUnique as String] as? Data {
            details.cdHash = unique.map { String(format: "%02x", $0) }.joined()
        }
        if let requirementValue = dictionary[kSecCodeInfoDesignatedRequirement as String] {
            let requirementObject = requirementValue as CFTypeRef
            if CFGetTypeID(requirementObject) == SecRequirementGetTypeID() {
                let requirement = requirementObject as! SecRequirement
                var requirementText: CFString?
                if SecRequirementCopyString(requirement, SecCSFlags(), &requirementText) == errSecSuccess {
                    details.designatedRequirement = requirementText as String?
                }
            }
        }
        if let certificates = dictionary[kSecCodeInfoCertificates as String] as? [SecCertificate] {
            let summaries = certificates.compactMap { certificate -> String? in
                SecCertificateCopySubjectSummary(certificate) as String?
            }
            if !summaries.isEmpty {
                details.signingAuthority = summaries.joined(separator: " -> ")
            }
        }
        return details
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

    public var permissionRepairDestinations: [NativePermissionRepairDestination] {
        permissions.compactMap { permission in
            guard permission.state != .granted else {
                return nil
            }
            return NativePermissionRepairDestination(permissionID: permission.id)
        }
    }

    public func canStartRecording(captureMicrophoneAudio: Bool) -> Bool {
        guard phase == .ready || phase == .blocked else {
            return false
        }
        return Self.captureChecksPass(
            permissions: permissions,
            dependencies: dependencies,
            captureMicrophoneAudio: captureMicrophoneAudio
        )
    }

    public func hasUnconfirmedCapturePermissions(captureMicrophoneAudio: Bool) -> Bool {
        let relevantPermissionIDs = Self.capturePermissionIDs(
            captureMicrophoneAudio: captureMicrophoneAudio
        )
        return permissions.contains {
            relevantPermissionIDs.contains($0.id) && $0.state == .notConfirmed
        }
    }

    public func summary(captureMicrophoneAudio: Bool) -> String {
        guard phase == .ready || phase == .blocked else {
            return summary
        }
        let relevantPermissionIDs = Self.capturePermissionIDs(
            captureMicrophoneAudio: captureMicrophoneAudio
        )
        let relevantPermissions = permissions.filter {
            relevantPermissionIDs.contains($0.id)
        }
        return Self.summary(
            canStartRecording: canStartRecording(
                captureMicrophoneAudio: captureMicrophoneAudio
            ),
            canRunProcessing: canRunProcessing,
            hasMissingRequiredDependencies: !missingRequiredCheckIDs.isEmpty,
            hasDeniedPermissions: relevantPermissions.contains { $0.state == .denied },
            hasUnconfirmedPermissions: relevantPermissions.contains { $0.state == .notConfirmed }
        )
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
        let missingRequired = dependencies
            .filter { $0.required && !$0.isPassing }
            .map(\.id)
        let deniedPermissions = permissions.filter { $0.state == .denied }
        let unconfirmedPermissions = permissions.filter { $0.state == .notConfirmed }
        let canRunProcessing = processingChecksPass(
            responseOK: response.ok,
            checks: response.checks
        )
        let canStartRecording = captureChecksPass(
            permissions: permissions,
            dependencies: dependencies,
            captureMicrophoneAudio: true
        )
        let phase: PermissionDependencyPhase = canStartRecording ? .ready : .blocked

        return PermissionDependencyStatusState(
            phase: phase,
            summary: summary(
                canStartRecording: canStartRecording,
                canRunProcessing: canRunProcessing,
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
        canStartRecording: Bool,
        canRunProcessing: Bool,
        hasMissingRequiredDependencies: Bool,
        hasDeniedPermissions: Bool,
        hasUnconfirmedPermissions: Bool
    ) -> String {
        if canStartRecording && !canRunProcessing {
            if hasUnconfirmedPermissions {
                return "Recording can be started to confirm macOS permissions; processing is blocked until required dependencies are available."
            }
            if hasMissingRequiredDependencies {
                return "Recording is ready; processing is blocked until required dependencies are available."
            }
            return "Recording is ready; processing is blocked by dependency check failure."
        }
        if !canStartRecording && canRunProcessing {
            return "Recording is blocked until the required macOS permissions and capture environment are ready."
        }
        if !canStartRecording && !canRunProcessing && !hasMissingRequiredDependencies && !hasDeniedPermissions {
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

    private static func captureChecksPass(
        permissions: [PermissionStatusItem],
        dependencies: [DependencyStatusItem],
        captureMicrophoneAudio: Bool
    ) -> Bool {
        let requiredCaptureDependencyIDs = [
            "platform.os",
            "platform.macos_version",
            "platform.cpu_arch",
            "workspace.writable",
        ]
        let captureDependenciesAreReady = requiredCaptureDependencyIDs.allSatisfy { id in
            dependencies.first(where: { $0.id == id })?.isPassing == true
        }
        guard captureDependenciesAreReady else {
            return false
        }

        let screenRecordingDenied = permissions.contains {
            $0.id == NativePermissionRepairDestination.screenRecording.permissionID && $0.state == .denied
        }
        guard !screenRecordingDenied else {
            return false
        }

        let microphoneDenied = permissions.contains {
            $0.id == NativePermissionRepairDestination.microphone.permissionID && $0.state == .denied
        }
        return !captureMicrophoneAudio || !microphoneDenied
    }

    private static func capturePermissionIDs(captureMicrophoneAudio: Bool) -> Set<String> {
        if captureMicrophoneAudio {
            return [
                NativePermissionRepairDestination.screenRecording.permissionID,
                NativePermissionRepairDestination.microphone.permissionID,
            ]
        }
        return [NativePermissionRepairDestination.screenRecording.permissionID]
    }

    private static func processingChecksPass(
        responseOK: Bool,
        checks: [DependencyCheckItem]
    ) -> Bool {
        let hasFailedRequiredDependency = checks.contains {
            !isPermissionCheck($0.id) && $0.required && !$0.isPassing
        }
        guard !hasFailedRequiredDependency else {
            return false
        }
        let hasExplicitPermissionFailure = checks.contains {
            isPermissionCheck($0.id) && !$0.isPassing
        }
        return responseOK || hasExplicitPermissionFailure
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
