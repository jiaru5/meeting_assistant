import AppKit
import SwiftUI

extension NativePermissionRepairDestination {
    public var systemSettingsURI: String {
        switch self {
        case .screenRecording:
            return "x-apple.systempreferences:com.apple.preference.security?Privacy_ScreenCapture"
        case .microphone:
            return "x-apple.systempreferences:com.apple.preference.security?Privacy_Microphone"
        }
    }

    public var accessibilityIdentifier: String {
        switch self {
        case .screenRecording:
            return PermissionDependencyAccessibilityID.openPrivacySettingsButton
        case .microphone:
            return PermissionDependencyAccessibilityID.openMicrophoneSettingsButton
        }
    }
}

public enum PermissionDependencyAccessibilityID {
    public static let heading = "ma.permissionDependency.heading"
    public static let summary = "ma.permissionDependency.summary"
    public static let checkButton = "ma.permissionDependency.checkButton"
    public static let openPrivacySettingsButton = "ma.permissionDependency.openPrivacySettingsButton"
    public static let openMicrophoneSettingsButton = "ma.permissionDependency.openMicrophoneSettingsButton"
    public static let appIdentity = "ma.permissionDependency.appIdentity"
    public static let permissionsSection = "ma.permissionDependency.permissions"
    public static let dependenciesSection = "ma.permissionDependency.dependencies"
}

public struct PermissionDependencyStatusView: View {
    @ObservedObject private var viewModel: PermissionDependencyStatusViewModel
    private let openPrivacySettings: () -> Void
    private let openMicrophoneSettings: () -> Void
    private let appIdentity: LocalAppPermissionIdentity
    private let captureMicrophoneAudio: Bool

    public init(
        viewModel: PermissionDependencyStatusViewModel,
        captureMicrophoneAudio: Bool = true
    ) {
        self.init(
            viewModel: viewModel,
            captureMicrophoneAudio: captureMicrophoneAudio,
            openPermissionSettings: SystemPrivacySettingsOpener.open
        )
    }

    public init(
        viewModel: PermissionDependencyStatusViewModel,
        captureMicrophoneAudio: Bool = true,
        appIdentity: LocalAppPermissionIdentity = .current(),
        openPrivacySettings: @escaping () -> Void
    ) {
        self.viewModel = viewModel
        self.captureMicrophoneAudio = captureMicrophoneAudio
        self.appIdentity = appIdentity
        self.openPrivacySettings = openPrivacySettings
        self.openMicrophoneSettings = {
            SystemPrivacySettingsOpener.open(.microphone)
        }
    }

    public init(
        viewModel: PermissionDependencyStatusViewModel,
        captureMicrophoneAudio: Bool = true,
        appIdentity: LocalAppPermissionIdentity = .current(),
        openPermissionSettings: @escaping (NativePermissionRepairDestination) -> Void
    ) {
        self.viewModel = viewModel
        self.captureMicrophoneAudio = captureMicrophoneAudio
        self.appIdentity = appIdentity
        self.openPrivacySettings = {
            openPermissionSettings(.screenRecording)
        }
        self.openMicrophoneSettings = {
            openPermissionSettings(.microphone)
        }
    }

    public var body: some View {
        let readinessSummary = viewModel.state.summary(
            captureMicrophoneAudio: captureMicrophoneAudio
        )
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                Text("Meeting Assistant Readiness")
                    .font(.title2)
                    .accessibilityAddTraits(.isHeader)
                    .accessibilityLabel("Meeting Assistant Readiness")
                    .accessibilityIdentifier(PermissionDependencyAccessibilityID.heading)

                Text(readinessSummary)
                    .font(.body)
                    .accessibilityLabel(readinessSummary)
                    .accessibilityIdentifier(PermissionDependencyAccessibilityID.summary)

                Button("Check permissions and dependencies") {
                    Task {
                        await viewModel.refresh()
                    }
                }
                .disabled(viewModel.state.phase == .checking)
                .accessibilityIdentifier(PermissionDependencyAccessibilityID.checkButton)

                if viewModel.state.hasUnconfirmedOrDeniedPermissions {
                    VStack(alignment: .leading, spacing: 4) {
                        Text(appIdentity.permissionRepairSummary)
                        Text(appIdentity.staleIdentityRepairSummary)
                    }
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .accessibilityElement(children: .combine)
                    .accessibilityLabel(appIdentity.recordingPermissionFailureHint)
                    .accessibilityIdentifier(PermissionDependencyAccessibilityID.appIdentity)

                    if viewModel.state.permissionRepairDestinations.contains(.screenRecording) {
                        Button("Open Screen Recording Settings") {
                            openPrivacySettings()
                        }
                        .accessibilityLabel(NativePermissionRepairDestination.screenRecording.buttonTitle)
                        .accessibilityIdentifier(PermissionDependencyAccessibilityID.openPrivacySettingsButton)
                    }

                    if viewModel.state.permissionRepairDestinations.contains(.microphone) {
                        Button("Open Microphone Settings") {
                            openMicrophoneSettings()
                        }
                        .accessibilityLabel(NativePermissionRepairDestination.microphone.buttonTitle)
                        .accessibilityIdentifier(PermissionDependencyAccessibilityID.openMicrophoneSettingsButton)
                    }
                }

                statusSection(
                    title: "Permissions",
                    identifier: PermissionDependencyAccessibilityID.permissionsSection
                ) {
                    ForEach(viewModel.state.permissions) { item in
                        statusRow(
                            title: item.title,
                            status: item.state.rawValue,
                            message: item.message,
                            identifier: "ma.permission.\(item.id).status"
                        )
                    }
                }

                statusSection(
                    title: "Dependencies",
                    identifier: PermissionDependencyAccessibilityID.dependenciesSection
                ) {
                    ForEach(viewModel.state.dependencies) { item in
                        statusRow(
                            title: item.title,
                            status: item.status,
                            message: item.message,
                            identifier: "ma.dependency.\(item.id).status"
                        )
                    }
                }
            }
            .padding()
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    private func statusSection<Content: View>(
        title: String,
        identifier: String,
        @ViewBuilder content: () -> Content
    ) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title)
                .font(.headline)
            content()
        }
        .accessibilityElement(children: .contain)
        .accessibilityLabel(title)
        .accessibilityIdentifier(identifier)
    }

    private func statusRow(
        title: String,
        status: String,
        message: String,
        identifier: String
    ) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                Text(title)
                    .font(.body)
                Spacer()
                Text(status)
                    .font(.caption)
                    .textCase(.uppercase)
            }
            Text(message)
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(title), \(status), \(message)")
        .accessibilityIdentifier(identifier)
    }
}

private enum SystemPrivacySettingsOpener {
    static func open(_ destination: NativePermissionRepairDestination) {
        guard let url = URL(string: destination.systemSettingsURI) else {
            return
        }
        NSWorkspace.shared.open(url)
    }
}
