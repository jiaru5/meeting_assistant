import Foundation
import SwiftUI

@main
struct MeetingAssistantNativeApp: App {
    private let configuration = NativeControlPlaneFixtureConfiguration.fromLaunchContext()

    var body: some Scene {
        WindowGroup("Meeting Assistant Native") {
            NativeControlPlaneRootView(configuration: configuration)
        }
        .defaultSize(width: 900, height: 760)
    }
}

private struct NativeControlPlaneRootView: View {
    @StateObject private var permissionViewModel: PermissionDependencyStatusViewModel
    @StateObject private var recordingViewModel: RecordingControlViewModel

    init(configuration: NativeControlPlaneFixtureConfiguration) {
        let readinessState = configuration.readinessState
        _permissionViewModel = StateObject(
            wrappedValue: PermissionDependencyStatusViewModel(
                runner: StaticDependencyCheckRunner(response: configuration.dependencyResponse),
                initialState: readinessState
            )
        )
        _recordingViewModel = StateObject(
            wrappedValue: RecordingControlViewModel(
                commandClient: FakeRecordingCommandClient(
                    script: configuration.recordingScript,
                    sessionID: configuration.sessionID
                ),
                readinessState: readinessState,
                title: "UI smoke recording",
                captureTarget: .screen
            )
        )
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            PermissionDependencyStatusView(viewModel: permissionViewModel)
                .frame(minHeight: 360, maxHeight: 420)

            Divider()

            RecordingControlView(viewModel: recordingViewModel)
        }
        .padding(20)
        .frame(minWidth: 760, minHeight: 640, alignment: .topLeading)
    }
}

private struct StaticDependencyCheckRunner: DependencyCheckRunning {
    let response: DependencyCheckResponse

    func checkDependencies(workspaceURL: URL?) async throws -> DependencyCheckResponse {
        response
    }
}

private struct NativeControlPlaneFixtureConfiguration {
    let dependencyResponse: DependencyCheckResponse
    let recordingScript: FakeRecordingCommandClient.Script
    let sessionID: String

    var readinessState: PermissionDependencyStatusState {
        PermissionDependencyStatusState.from(dependencyResponse)
    }

    static func fromLaunchContext(
        environment: [String: String] = ProcessInfo.processInfo.environment,
        arguments: [String] = CommandLine.arguments
    ) -> NativeControlPlaneFixtureConfiguration {
        let fixture = environment["MA_NATIVE_APP_SMOKE_FIXTURE"]
            ?? argumentValue(named: "--ma-native-fixture", in: arguments)
            ?? "blocked"

        switch fixture {
        case "ready":
            return NativeControlPlaneFixtureConfiguration(
                dependencyResponse: .readyFixture,
                recordingScript: .success,
                sessionID: "session-app-ui-smoke"
            )
        case "start-failure":
            return NativeControlPlaneFixtureConfiguration(
                dependencyResponse: .readyFixture,
                recordingScript: .startFailure(
                    code: "permission_denied",
                    message: "Screen Recording permission is missing."
                ),
                sessionID: "session-app-ui-start-failure"
            )
        case "stop-failure":
            return NativeControlPlaneFixtureConfiguration(
                dependencyResponse: .readyFixture,
                recordingScript: .stopFailure(
                    code: "capture_failed",
                    message: "Recording could not be saved."
                ),
                sessionID: "session-app-ui-stop-failure"
            )
        default:
            return NativeControlPlaneFixtureConfiguration(
                dependencyResponse: .blockedFixture,
                recordingScript: .success,
                sessionID: "session-app-ui-blocked"
            )
        }
    }

    private static func argumentValue(named name: String, in arguments: [String]) -> String? {
        let prefix = "\(name)="
        return arguments
            .first { $0.hasPrefix(prefix) }
            .map { String($0.dropFirst(prefix.count)) }
    }
}

private extension DependencyCheckResponse {
    static let blockedFixture = DependencyCheckResponse(
        ok: false,
        requestID: "local-app-blocked",
        code: "dependency_missing",
        message: "One or more required dependencies are missing or unsupported.",
        checks: [
            DependencyCheckItem(
                id: "permission.screen_recording",
                status: "denied",
                required: false,
                ok: false,
                message: "Screen Recording permission is denied. Open System Settings to grant access."
            ),
            DependencyCheckItem(
                id: "permission.microphone",
                status: "granted",
                required: false,
                ok: true,
                message: "Microphone permission is granted."
            ),
            DependencyCheckItem(
                id: "media_tool.ffmpeg",
                status: "missing",
                required: true,
                ok: false,
                message: "FFmpeg executable was not found."
            ),
        ]
    )

    static let readyFixture = DependencyCheckResponse(
        ok: true,
        requestID: "local-app-ready",
        checks: [
            DependencyCheckItem(
                id: "permission.screen_recording",
                status: "granted",
                required: false,
                ok: true,
                message: "Screen Recording permission is granted."
            ),
            DependencyCheckItem(
                id: "permission.microphone",
                status: "granted",
                required: false,
                ok: true,
                message: "Microphone permission is granted."
            ),
            DependencyCheckItem(
                id: "media_tool.ffmpeg",
                status: "available",
                required: true,
                ok: true,
                message: "FFmpeg executable is available."
            ),
            DependencyCheckItem(
                id: "dependency_downloads.automatic",
                status: "not_attempted",
                required: true,
                ok: true,
                message: "No automatic dependency download was attempted."
            ),
        ]
    )
}
