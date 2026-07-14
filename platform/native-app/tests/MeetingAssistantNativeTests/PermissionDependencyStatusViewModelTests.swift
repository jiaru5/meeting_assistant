import Foundation
import Testing
@testable import MeetingAssistantNative

private struct StubDependencyCheckRunner: DependencyCheckRunning {
    let result: Result<DependencyCheckResponse, Error>

    func checkDependencies(workspaceURL: URL?) async throws -> DependencyCheckResponse {
        try result.get()
    }
}

private enum StubError: Error {
    case failed
}

@Suite("Permission and dependency status")
struct PermissionDependencyStatusViewModelTests {
    @Test
    func decodesCheckDependenciesContractWithoutDependingOnDetails() throws {
        let json = """
        {
          "ok": false,
          "request_id": "local-test",
          "command": "check_dependencies",
          "code": "dependency_missing",
          "message": "Required dependency is missing",
          "checks": [
            {
              "id": "media_tool.ffmpeg",
              "status": "missing",
              "required": true,
              "message": "FFmpeg executable was not found",
              "details": { "path": "" }
            }
          ],
          "details": { "missing_required_checks": ["media_tool.ffmpeg"] },
          "warnings": []
        }
        """.data(using: .utf8)!

        let response = try DependencyCheckResponseDecoder.decode(json)

        #expect(response.ok == false)
        #expect(response.command == "check_dependencies")
        #expect(response.code == "dependency_missing")
        #expect(response.checks.first?.ok == nil)
        #expect(response.checks.first?.isPassing == false)
    }

    @Test
    func processingDependencyFailureDoesNotBlockCaptureState() {
        let state = PermissionDependencyStatusState.from(
            dependencyResponse(
                ok: false,
                checks: captureReadyChecks + [
                    check("media_tool.ffmpeg", status: "missing", required: true, ok: false),
                    check("speaker_labeling.runtime", status: "missing", required: false, ok: true),
                ],
                code: "dependency_missing"
            )
        )

        #expect(state.phase == .ready)
        #expect(state.canRunProcessing == false)
        #expect(state.canStartRecording == true)
        #expect(state.canStartRecording(captureMicrophoneAudio: true))
        #expect(state.missingRequiredCheckIDs == ["media_tool.ffmpeg"])
        #expect(state.summary == "Recording is ready; processing is blocked until required dependencies are available.")
    }

    @Test
    func structuredProcessingFailureWithoutCaptureCheckStillAllowsCapture() {
        let state = PermissionDependencyStatusState.from(
            dependencyResponse(
                ok: false,
                checks: captureReadyChecks + [
                    check("transcription.hardware", status: "unknown", required: true, ok: nil),
                ],
                code: "dependency_missing"
            )
        )

        #expect(state.phase == .ready)
        #expect(state.canRunProcessing == false)
        #expect(state.canStartRecording == true)
        #expect(state.missingRequiredCheckIDs == ["transcription.hardware"])
        #expect(state.summary == "Recording is ready; processing is blocked until required dependencies are available.")
    }

    @Test
    func commandFailureWithoutCaptureChecksFailsClosedForBothReadinesses() {
        let state = PermissionDependencyStatusState.from(
            dependencyResponse(
                ok: false,
                checks: grantedPermissionChecks,
                code: "dependency_missing"
            )
        )

        #expect(state.phase == .blocked)
        #expect(state.canRunProcessing == false)
        #expect(state.canStartRecording == false)
        #expect(state.summary == "Recording and processing are blocked by dependency check failure.")
    }

    @Test
    func deniedPermissionBlocksRecordingEvenWhenDependenciesPass() {
        let state = PermissionDependencyStatusState.from(
            dependencyResponse(
                ok: true,
                checks: passingCaptureDependencyChecks + [
                    check(
                        "permission.screen_recording",
                        status: "denied",
                        required: false,
                        ok: false,
                        message: "Screen recording permission status is denied."
                    ),
                    check("permission.microphone", status: "granted", required: false, ok: true),
                    check("media_tool.ffmpeg", status: "available", required: true, ok: true),
                ]
            )
        )

        #expect(state.phase == .blocked)
        #expect(state.canRunProcessing == true)
        #expect(state.canStartRecording == false)
        #expect(state.canStartRecording(captureMicrophoneAudio: false) == false)
        #expect(state.canStartRecording(captureMicrophoneAudio: true) == false)
        #expect(state.permissions.first?.state == .denied)
        #expect(
            state.summary ==
                "Recording is blocked until the required macOS permissions and capture environment are ready."
        )
    }

    @Test
    func deniedRequiredCapturePermissionDoesNotBlockReadyProcessingDependencies() {
        let state = PermissionDependencyStatusState.from(
            dependencyResponse(
                ok: false,
                checks: passingCaptureDependencyChecks + [
                    check("permission.screen_recording", status: "denied", required: true, ok: false),
                    check("permission.microphone", status: "granted", required: true, ok: true),
                    check("media_tool.ffmpeg", status: "available", required: true, ok: true),
                    check("transcription.runtime", status: "available", required: true, ok: true),
                    check("transcription.model", status: "available", required: true, ok: true),
                ],
                code: "dependency_missing"
            )
        )

        #expect(state.phase == .blocked)
        #expect(state.canStartRecording == false)
        #expect(state.canRunProcessing)
        #expect(state.missingRequiredCheckIDs.isEmpty)
    }

    @Test
    func deniedMicrophoneOnlyBlocksCaptureWhenMicrophoneIntentIsEnabled() {
        let state = PermissionDependencyStatusState.from(
            dependencyResponse(
                ok: true,
                checks: passingCaptureDependencyChecks + [
                    check("permission.screen_recording", status: "granted", required: false, ok: true),
                    check("permission.microphone", status: "denied", required: false, ok: false),
                ]
            )
        )

        #expect(state.phase == .blocked)
        #expect(state.canStartRecording == false)
        #expect(state.canStartRecording(captureMicrophoneAudio: true) == false)
        #expect(state.canStartRecording(captureMicrophoneAudio: false))
        #expect(state.canRunProcessing)
        #expect(
            state.summary(captureMicrophoneAudio: true) ==
                "Recording is blocked until the required macOS permissions and capture environment are ready."
        )
        #expect(
            state.summary(captureMicrophoneAudio: false) ==
                "Permissions and required dependencies are ready."
        )
    }

    @Test
    func failedPlatformOrWorkspaceCheckBlocksCaptureButProcessingStateRemainsIndependent() {
        for checkID in [
            "platform.os",
            "platform.macos_version",
            "platform.cpu_arch",
            "workspace.writable",
        ] {
            let state = PermissionDependencyStatusState.from(
                dependencyResponse(
                    ok: false,
                    checks: grantedPermissionChecks
                        + passingCaptureDependencyChecks.filter { $0.id != checkID }
                        + [check(checkID, status: "unsupported", required: true, ok: false)],
                    code: "dependency_missing"
                )
            )

            #expect(state.phase == .blocked)
            #expect(state.canStartRecording == false)
            #expect(state.canStartRecording(captureMicrophoneAudio: false) == false)
            #expect(state.canRunProcessing == false)
        }
    }

    @Test
    func missingPlatformOrWorkspaceCheckFailsCaptureReadinessClosed() {
        for missingCheckID in [
            "platform.os",
            "platform.macos_version",
            "platform.cpu_arch",
            "workspace.writable",
        ] {
            let state = PermissionDependencyStatusState.from(
                dependencyResponse(
                    ok: true,
                    checks: grantedPermissionChecks
                        + passingCaptureDependencyChecks.filter { $0.id != missingCheckID }
                )
            )

            #expect(state.phase == .blocked)
            #expect(state.canStartRecording == false)
            #expect(state.canStartRecording(captureMicrophoneAudio: false) == false)
            #expect(state.canRunProcessing)
        }
    }

    @Test
    func unknownPermissionAllowsExplicitRecordingAttemptSoSystemPromptCanResolve() {
        let state = PermissionDependencyStatusState.from(
            dependencyResponse(
                ok: true,
                checks: passingCaptureDependencyChecks + [
                    check("permission.screen_recording", status: "unknown", required: false, ok: true),
                    check("permission.microphone", status: "granted", required: false, ok: true),
                    check("media_tool.ffmpeg", status: "available", required: true, ok: true),
                ]
            )
        )

        #expect(state.phase == .ready)
        #expect(state.canStartRecording == true)
        #expect(state.permissions.first?.state == .notConfirmed)
        #expect(state.hasUnconfirmedOrDeniedPermissions)
        #expect(
            state.summary ==
                "Recording can be started to confirm macOS permissions; denied permissions still fail closed."
        )
    }

    @Test
    func allRequiredChecksAndPermissionsReadyAllowRecordingState() {
        let state = PermissionDependencyStatusState.from(
            dependencyResponse(
                ok: true,
                checks: captureReadyChecks + [
                    check("developer_tools.swift", status: "available", required: true, ok: true),
                    check("media_tool.ffmpeg", status: "available", required: true, ok: true),
                    check("transcription.runtime", status: "available", required: true, ok: true),
                    check("transcription.model", status: "available", required: true, ok: true),
                    check("dependency_downloads.automatic", status: "not_attempted", required: true, ok: true),
                ]
            )
        )

        #expect(state.phase == .ready)
        #expect(state.canRunProcessing == true)
        #expect(state.canStartRecording == true)
        #expect(state.hasUnconfirmedOrDeniedPermissions == false)
        #expect(state.summary == "Permissions and required dependencies are ready.")
    }

    @Test
    func exposesStableAccessibilityIdentifiersForNativeStatusSurface() {
        #expect(PermissionDependencyAccessibilityID.heading == "ma.permissionDependency.heading")
        #expect(PermissionDependencyAccessibilityID.summary == "ma.permissionDependency.summary")
        #expect(PermissionDependencyAccessibilityID.checkButton == "ma.permissionDependency.checkButton")
        #expect(
            PermissionDependencyAccessibilityID.openMicrophoneSettingsButton ==
                "ma.permissionDependency.openMicrophoneSettingsButton"
        )
        #expect(PermissionDependencyAccessibilityID.appIdentity == "ma.permissionDependency.appIdentity")
        #expect(PermissionDependencyAccessibilityID.permissionsSection == "ma.permissionDependency.permissions")
        #expect(PermissionDependencyAccessibilityID.dependenciesSection == "ma.permissionDependency.dependencies")
    }

    @Test
    func mapsPermissionRepairDestinationsToSpecificButtonCopyAndSystemSettingsURI() {
        let systemSettingsScheme = "x-apple." + "systempreferences:com.apple.preference.security?"
        let screenRecording = NativePermissionRepairDestination(
            permissionID: "permission.screen_recording"
        )
        let microphone = NativePermissionRepairDestination(
            permissionID: "permission.microphone"
        )

        #expect(screenRecording == .screenRecording)
        #expect(screenRecording?.buttonTitle == "Open Screen Recording Settings")
        #expect(
            screenRecording?.systemSettingsURI ==
                systemSettingsScheme + "Privacy_ScreenCapture"
        )
        #expect(microphone == .microphone)
        #expect(microphone?.buttonTitle == "Open Microphone Settings")
        #expect(
            microphone?.systemSettingsURI ==
                systemSettingsScheme + "Privacy_Microphone"
        )
        #expect(NativePermissionRepairDestination(permissionID: "permission.camera") == nil)
    }

    @Test
    func exposesRepairDestinationOnlyForEachUnconfirmedOrDeniedPermission() {
        let screenDenied = PermissionDependencyStatusState.from(
            dependencyResponse(
                ok: true,
                checks: [
                    check("permission.screen_recording", status: "denied", required: false, ok: false),
                    check("permission.microphone", status: "granted", required: false, ok: true),
                ]
            )
        )
        let microphoneUnconfirmed = PermissionDependencyStatusState.from(
            dependencyResponse(
                ok: true,
                checks: [
                    check("permission.screen_recording", status: "granted", required: false, ok: true),
                    check("permission.microphone", status: "unknown", required: false, ok: true),
                ]
            )
        )

        #expect(screenDenied.permissionRepairDestinations == [.screenRecording])
        #expect(microphoneUnconfirmed.permissionRepairDestinations == [.microphone])
    }

    @Test
    func appPermissionIdentityBuildsExactRepairHint() {
        let identity = LocalAppPermissionIdentity(
            bundlePath: "/Users/jerry/Applications/MeetingAssistantNativeLocal.app",
            bundleIdentifier: "local.meeting-assistant.native.localdirect",
            codeSignatureHash: "ca3e033b67f6b4b8cabb9245cc9c7d9f0b7290db",
            designatedRequirement: "identifier \"local.meeting-assistant.native.localdirect\" and certificate root = H\"d2ebc4b501da40173af71fd03a33c9581d13b5dd\"",
            signingAuthority: "Meeting Assistant Local Code Signing"
        )

        #expect(identity.permissionRepairSummary.contains("/Users/jerry/Applications/MeetingAssistantNativeLocal.app"))
        #expect(identity.permissionRepairSummary.contains("local.meeting-assistant.native.localdirect"))
        #expect(identity.permissionRepairSummary.contains("designated requirement: identifier"))
        #expect(identity.permissionRepairSummary.contains("certificate root"))
        #expect(identity.permissionRepairSummary.contains("Meeting Assistant Local Code Signing"))
        #expect(identity.permissionRepairSummary.contains("ca3e033b67f6b4b8cabb9245cc9c7d9f0b7290db"))
        #expect(identity.staleIdentityRepairSummary.contains("designated requirement"))
        #expect(identity.staleIdentityRepairSummary.contains("remove stale ad-hoc"))
        #expect(identity.recordingPermissionFailureHint.contains("add this exact app again"))
    }

    @Test
    @MainActor
    func viewModelReportsRunnerFailureAsFailedState() async {
        let viewModel = PermissionDependencyStatusViewModel(
            runner: StubDependencyCheckRunner(result: .failure(StubError.failed))
        )

        await viewModel.refresh()

        #expect(viewModel.state.phase == .failed)
        #expect(viewModel.state.canStartRecording == false)
        #expect(viewModel.state.canStartRecording(captureMicrophoneAudio: false) == false)
    }

    @Test
    func processRunnerInvokesCheckDependenciesWithWorkspaceAndDecodesJSON() async throws {
        let fixture = try ProcessRunnerFixture()
        let response = try await fixture.runner.checkDependencies(workspaceURL: fixture.workspaceURL)

        #expect(response.ok)
        #expect(response.command == "check_dependencies")
        #expect(response.checks.first?.id == "permission.screen_recording")
        #expect(try fixture.recordedArguments() == [
            "check_dependencies",
            "--format",
            "json",
            "--workspace-dir",
            fixture.workspaceURL.path,
        ])
    }

    @Test
    func processRunnerDecodesStructuredNonzeroDependencyFailure() async throws {
        let fixture = try ProcessRunnerFixture(exitCode: 4, ok: false)
        let response = try await fixture.runner.checkDependencies(workspaceURL: nil)

        #expect(response.ok == false)
        #expect(response.code == "dependency_missing")
        #expect(response.checks.first?.status == "missing")
        #expect(try fixture.recordedArguments() == [
            "check_dependencies",
            "--format",
            "json",
        ])
    }
}

private let grantedPermissionChecks = [
    check("permission.screen_recording", status: "granted", required: false, ok: true),
    check("permission.microphone", status: "granted", required: false, ok: true),
]

private let passingCaptureDependencyChecks = [
    check("platform.os", status: "supported", required: true, ok: true),
    check("platform.macos_version", status: "supported", required: true, ok: true),
    check("platform.cpu_arch", status: "supported", required: true, ok: true),
    check("workspace.writable", status: "writable", required: true, ok: true),
]

private let captureReadyChecks = grantedPermissionChecks + passingCaptureDependencyChecks

private func dependencyResponse(
    ok: Bool,
    checks: [DependencyCheckItem],
    code: String? = nil
) -> DependencyCheckResponse {
    DependencyCheckResponse(
        ok: ok,
        requestID: "local-test",
        code: code,
        message: code == nil ? nil : "One or more required dependencies are missing or unsupported.",
        checks: checks
    )
}

private func check(
    _ id: String,
    status: String,
    required: Bool,
    ok: Bool?,
    message: String? = nil
) -> DependencyCheckItem {
    DependencyCheckItem(
        id: id,
        status: status,
        required: required,
        ok: ok,
        message: message ?? "\(id) is \(status)."
    )
}

private final class ProcessRunnerFixture {
    let rootURL: URL
    let scriptURL: URL
    let argsURL: URL
    let workspaceURL: URL
    let runner: ProcessingCLIDependencyCheckRunner

    init(exitCode: Int = 0, ok: Bool = true) throws {
        rootURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("meeting-assistant-native-tests-\(UUID().uuidString)", isDirectory: true)
        scriptURL = rootURL.appendingPathComponent("meeting-assistant-cli")
        argsURL = rootURL.appendingPathComponent("args.txt")
        workspaceURL = rootURL.appendingPathComponent("workspace", isDirectory: true)

        try FileManager.default.createDirectory(at: rootURL, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: workspaceURL, withIntermediateDirectories: true)
        try Self.script(exitCode: exitCode, ok: ok).write(to: scriptURL, atomically: true, encoding: .utf8)
        try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: scriptURL.path)

        runner = ProcessingCLIDependencyCheckRunner(
            executablePath: scriptURL.path,
            environment: [
                "MEETING_ASSISTANT_TEST_ARGS_FILE": argsURL.path,
            ]
        )
    }

    deinit {
        try? FileManager.default.removeItem(at: rootURL)
    }

    func recordedArguments() throws -> [String] {
        try String(contentsOf: argsURL, encoding: .utf8)
            .split(separator: "\n")
            .map(String.init)
    }

    private static func script(exitCode: Int, ok: Bool) -> String {
        let status = ok ? "granted" : "missing"
        let required = ok ? "false" : "true"
        let code = ok ? "null" : #""dependency_missing""#
        let message = ok ? "null" : #""One or more required dependencies are missing or unsupported.""#
        return """
        #!/bin/sh
        printf '%s\\n' "$@" > "$MEETING_ASSISTANT_TEST_ARGS_FILE"
        cat <<'JSON'
        {
          "ok": \(ok ? "true" : "false"),
          "request_id": "local-process-test",
          "command": "check_dependencies",
          "code": \(code),
          "message": \(message),
          "checks": [
            {
              "id": "\(ok ? "permission.screen_recording" : "media_tool.ffmpeg")",
              "status": "\(status)",
              "required": \(required),
              "ok": \(ok ? "true" : "false"),
              "message": "fixture check"
            }
          ],
          "warnings": []
        }
        JSON
        exit \(exitCode)
        """
    }
}
