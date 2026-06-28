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
    func requiredDependencyFailureBlocksProcessingState() {
        let state = PermissionDependencyStatusState.from(
            dependencyResponse(
                ok: false,
                checks: grantedPermissionChecks + [
                    check("media_tool.ffmpeg", status: "missing", required: true, ok: false),
                    check("speaker_labeling.runtime", status: "missing", required: false, ok: true),
                ],
                code: "dependency_missing"
            )
        )

        #expect(state.phase == .blocked)
        #expect(state.canRunProcessing == false)
        #expect(state.canStartRecording == false)
        #expect(state.missingRequiredCheckIDs == ["media_tool.ffmpeg"])
        #expect(state.summary == "Processing is blocked until required dependencies are available.")
    }

    @Test
    func structuredCommandFailureWithoutSpecificMissingCheckStillBlocks() {
        let state = PermissionDependencyStatusState.from(
            dependencyResponse(
                ok: false,
                checks: grantedPermissionChecks + [
                    check("transcription.hardware", status: "unknown", required: true, ok: nil),
                ],
                code: "dependency_missing"
            )
        )

        #expect(state.phase == .blocked)
        #expect(state.canRunProcessing == false)
        #expect(state.canStartRecording == false)
        #expect(state.missingRequiredCheckIDs == ["transcription.hardware"])
        #expect(state.summary == "Processing is blocked until required dependencies are available.")
    }

    @Test
    func commandFailureWithoutCheckDetailsUsesBlockedSummary() {
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
                checks: [
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
        #expect(state.permissions.first?.state == .denied)
        #expect(state.summary == "Recording is blocked until macOS permissions are granted.")
    }

    @Test
    func unknownPermissionIsVisibleAndFailClosedForRecording() {
        let state = PermissionDependencyStatusState.from(
            dependencyResponse(
                ok: true,
                checks: [
                    check("permission.screen_recording", status: "unknown", required: false, ok: true),
                    check("permission.microphone", status: "granted", required: false, ok: true),
                    check("media_tool.ffmpeg", status: "available", required: true, ok: true),
                ]
            )
        )

        #expect(state.phase == .blocked)
        #expect(state.canStartRecording == false)
        #expect(state.permissions.first?.state == .notConfirmed)
    }

    @Test
    func allRequiredChecksAndPermissionsReadyAllowRecordingState() {
        let state = PermissionDependencyStatusState.from(
            dependencyResponse(
                ok: true,
                checks: grantedPermissionChecks + [
                    check("platform.os", status: "supported", required: true, ok: true),
                    check("platform.cpu_arch", status: "supported", required: true, ok: true),
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
        #expect(state.summary == "Permissions and required dependencies are ready.")
    }

    @Test
    func exposesStableAccessibilityIdentifiersForNativeStatusSurface() {
        #expect(PermissionDependencyAccessibilityID.heading == "ma.permissionDependency.heading")
        #expect(PermissionDependencyAccessibilityID.summary == "ma.permissionDependency.summary")
        #expect(PermissionDependencyAccessibilityID.checkButton == "ma.permissionDependency.checkButton")
        #expect(PermissionDependencyAccessibilityID.permissionsSection == "ma.permissionDependency.permissions")
        #expect(PermissionDependencyAccessibilityID.dependenciesSection == "ma.permissionDependency.dependencies")
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
