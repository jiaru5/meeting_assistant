import AppKit
import SwiftUI

public enum PermissionDependencyAccessibilityID {
    public static let heading = "ma.permissionDependency.heading"
    public static let summary = "ma.permissionDependency.summary"
    public static let checkButton = "ma.permissionDependency.checkButton"
    public static let openPrivacySettingsButton = "ma.permissionDependency.openPrivacySettingsButton"
    public static let permissionsSection = "ma.permissionDependency.permissions"
    public static let dependenciesSection = "ma.permissionDependency.dependencies"
}

public struct PermissionDependencyStatusView: View {
    @ObservedObject private var viewModel: PermissionDependencyStatusViewModel
    private let openPrivacySettings: () -> Void

    public init(viewModel: PermissionDependencyStatusViewModel) {
        self.init(viewModel: viewModel, openPrivacySettings: SystemPrivacySettingsOpener.open)
    }

    public init(viewModel: PermissionDependencyStatusViewModel, openPrivacySettings: @escaping () -> Void) {
        self.viewModel = viewModel
        self.openPrivacySettings = openPrivacySettings
    }

    public var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                Text("Meeting Assistant Readiness")
                    .font(.title2)
                    .accessibilityAddTraits(.isHeader)
                    .accessibilityLabel("Meeting Assistant Readiness")
                    .accessibilityIdentifier(PermissionDependencyAccessibilityID.heading)

                Text(viewModel.state.summary)
                    .font(.body)
                    .accessibilityLabel(viewModel.state.summary)
                    .accessibilityIdentifier(PermissionDependencyAccessibilityID.summary)

                Button("Check permissions and dependencies") {
                    Task {
                        await viewModel.refresh()
                    }
                }
                .disabled(viewModel.state.phase == .checking)
                .accessibilityIdentifier(PermissionDependencyAccessibilityID.checkButton)

                if viewModel.state.hasUnconfirmedOrDeniedPermissions {
                    Button("Open Privacy Settings") {
                        openPrivacySettings()
                    }
                    .accessibilityIdentifier(PermissionDependencyAccessibilityID.openPrivacySettingsButton)
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
    static func open() {
        guard let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_ScreenCapture") else {
            return
        }
        NSWorkspace.shared.open(url)
    }
}
