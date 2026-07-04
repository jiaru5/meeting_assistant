import CryptoKit
import Foundation
import Testing
@testable import MeetingAssistantNative

@Suite("Native recording command client")
struct NativeRecordingCommandClientTests {
    @Test
    func permissionDeniedFailsClosedWithoutStartingAdapter() async throws {
        let workspace = try temporaryWorkspace()
        defer { try? FileManager.default.removeItem(at: workspace) }
        let adapter = ControlledNativeCaptureAdapter()
        let client = nativeClient(
            workspace: workspace,
            sessionID: "session-permission-denied",
            permissions: .denied,
            adapter: adapter
        )

        let response = try await client.startNativeRecording(startRequest(workspace: workspace))

        #expect(response.ok == false)
        #expect(response.command == .startNativeRecording)
        #expect(response.code == .permissionDenied)
        #expect(response.details.contains("Screen Recording permission is denied."))
        #expect(await adapter.startContexts.isEmpty)
        #expect(!FileManager.default.fileExists(atPath: sessionRoot(workspace, "session-permission-denied").path))
    }

    @Test
    func unknownPermissionFailsClosedWithoutStartingAdapter() async throws {
        let workspace = try temporaryWorkspace()
        defer { try? FileManager.default.removeItem(at: workspace) }
        let adapter = ControlledNativeCaptureAdapter()
        let client = nativeClient(
            workspace: workspace,
            sessionID: "session-permission-unknown",
            permissions: .unknown,
            adapter: adapter
        )

        let response = try await client.startNativeRecording(startRequest(workspace: workspace))

        #expect(response.ok == false)
        #expect(response.code == .permissionDenied)
        #expect(response.details.contains("Screen Recording permission status is unknown."))
        #expect(await adapter.startContexts.isEmpty)
    }

    @Test
    func macOSScreenRecordingPreflightDeniedFailsClosedWithoutStartingAdapter() async throws {
        let workspace = try temporaryWorkspace()
        defer { try? FileManager.default.removeItem(at: workspace) }
        let adapter = ControlledNativeCaptureAdapter()
        let checker = MacOSNativeCapturePermissionChecker(
            screenRecordingProbe: CoreGraphicsScreenRecordingPermissionProbe(preflight: { false }),
            microphoneStateProvider: { .granted }
        )
        let client = nativeClient(
            workspace: workspace,
            sessionID: "session-macos-screen-denied",
            permissionChecker: checker,
            adapter: adapter
        )

        let response = try await client.startNativeRecording(
            startRequest(workspace: workspace, captureMicrophoneAudio: false)
        )

        #expect(response.ok == false)
        #expect(response.command == .startNativeRecording)
        #expect(response.code == .permissionDenied)
        #expect(response.details == ["Screen Recording permission is denied."])
        #expect(await adapter.startContexts.isEmpty)
        #expect(!FileManager.default.fileExists(atPath: sessionRoot(workspace, "session-macos-screen-denied").path))
    }

    @Test
    func macOSMicrophoneUnknownFailsClosedOnlyWhenMicrophoneCaptureIsRequested() async throws {
        let blockedWorkspace = try temporaryWorkspace()
        let allowedWorkspace = try temporaryWorkspace()
        defer {
            try? FileManager.default.removeItem(at: blockedWorkspace)
            try? FileManager.default.removeItem(at: allowedWorkspace)
        }
        let blockedAdapter = ControlledNativeCaptureAdapter()
        let allowedAdapter = ControlledNativeCaptureAdapter()
        let checker = MacOSNativeCapturePermissionChecker(
            screenRecordingProbe: CoreGraphicsScreenRecordingPermissionProbe(preflight: { true }),
            microphoneStateProvider: { .unknown }
        )
        let blockedClient = nativeClient(
            workspace: blockedWorkspace,
            sessionID: "session-macos-mic-unknown",
            permissionChecker: checker,
            adapter: blockedAdapter
        )
        let allowedClient = nativeClient(
            workspace: allowedWorkspace,
            sessionID: "session-macos-mic-not-requested",
            permissionChecker: checker,
            adapter: allowedAdapter
        )

        let blocked = try await blockedClient.startNativeRecording(
            startRequest(workspace: blockedWorkspace, captureMicrophoneAudio: true)
        )

        #expect(blocked.ok == false)
        #expect(blocked.code == .permissionDenied)
        #expect(blocked.details == ["Microphone permission status is unknown."])
        #expect(await blockedAdapter.startContexts.isEmpty)

        let allowed = try await allowedClient.startNativeRecording(
            startRequest(workspace: allowedWorkspace, captureMicrophoneAudio: false)
        )

        #expect(allowed.ok == true)
        #expect(allowed.status == "recording")
        #expect(await allowedAdapter.startContexts.count == 1)
        #expect(FileManager.default.fileExists(
            atPath: sessionRoot(allowedWorkspace, "session-macos-mic-not-requested").path
        ))
    }

    @Test
    func successfulStartWritesRecordingSessionMetadata() async throws {
        let workspace = try temporaryWorkspace()
        defer { try? FileManager.default.removeItem(at: workspace) }
        let adapter = ControlledNativeCaptureAdapter()
        let client = nativeClient(
            workspace: workspace,
            sessionID: "session-start-metadata",
            adapter: adapter
        )

        let response = try await client.startNativeRecording(
            startRequest(workspace: workspace, title: "Architecture Review")
        )

        #expect(response.ok == true)
        #expect(response.status == "recording")
        #expect(response.sessionID == "session-start-metadata")
        #expect(await adapter.startContexts.count == 1)

        let session = try readSessionJSON(workspace: workspace, sessionID: "session-start-metadata")
        #expect(session["id"] as? String == "session-start-metadata")
        #expect(session["title"] as? String == "Architecture Review")
        #expect(session["source_type"] as? String == "native_recording")
        #expect(session["status"] as? String == "recording")
        #expect(session["started_at"] as? String == fixedTimestamp)
        #expect(session["created_at"] as? String == fixedTimestamp)
        #expect(session["updated_at"] as? String == fixedTimestamp)
        #expect(session["workspace_dir"] as? String == sessionRoot(workspace, "session-start-metadata").path)
        #expect((session["artifacts"] as? [[String: Any]])?.isEmpty == true)
    }

    @Test
    func startStoreFailureStopsAdapterBestEffort() async throws {
        let workspace = try temporaryWorkspace()
        defer { try? FileManager.default.removeItem(at: workspace) }
        let sessionID = "session-existing-root"
        try FileManager.default.createDirectory(
            at: sessionRoot(workspace, sessionID),
            withIntermediateDirectories: true
        )
        let adapter = ControlledNativeCaptureAdapter()
        let client = nativeClient(
            workspace: workspace,
            sessionID: sessionID,
            adapter: adapter
        )

        let response = try await client.startNativeRecording(startRequest(workspace: workspace))

        #expect(response.ok == false)
        #expect(response.code == .pathConflict)
        #expect(await adapter.startContexts.count == 1)
        #expect(await adapter.stopContexts.count == 1)
    }

    @Test
    func stopWritesFourTargetArtifactsWithChecksumAndDegradationReasons() async throws {
        let workspace = try temporaryWorkspace()
        defer { try? FileManager.default.removeItem(at: workspace) }
        let adapter = ControlledNativeCaptureAdapter(
            stopBehavior: .success(
                artifacts: [
                    .available(.screenVideo, format: "mov", data: data("screen-video")),
                    .available(.systemAudio, format: "m4a", data: data("system-audio")),
                    .missing(.microphoneAudio, reason: "microphone capture was disabled by the controlled fixture"),
                    .degraded(.mixedAudio, reason: "mixed audio degraded because microphone audio was unavailable"),
                ]
            )
        )
        let client = nativeClient(
            workspace: workspace,
            sessionID: "session-stop-artifacts",
            adapter: adapter
        )

        _ = try await client.startNativeRecording(startRequest(workspace: workspace))
        let response = try await client.stopRecording(StopRecordingRequest(sessionID: "session-stop-artifacts"))

        #expect(response.ok == true)
        #expect(response.status == "recorded")
        #expect(response.artifacts.map(\.artifactType) == [
            "screen_video",
            "system_audio",
            "microphone_audio",
            "mixed_audio",
        ])
        let screen = try #require(response.artifacts.first { $0.artifactType == "screen_video" })
        #expect(screen.captureStatus == "available")
        #expect(screen.path == "artifacts/screen_video.mov")
        #expect(screen.format == "mov")
        #expect(screen.createdAt == fixedTimestamp)
        let expectedScreenChecksum = try checksum(
            for: artifactURL(workspace, "session-stop-artifacts", "screen_video.mov")
        )
        #expect(screen.checksum == expectedScreenChecksum)

        let system = try #require(response.artifacts.first { $0.artifactType == "system_audio" })
        #expect(system.captureStatus == "available")
        let expectedSystemChecksum = try checksum(
            for: artifactURL(workspace, "session-stop-artifacts", "system_audio.m4a")
        )
        #expect(system.checksum == expectedSystemChecksum)

        let microphone = try #require(response.artifacts.first { $0.artifactType == "microphone_audio" })
        #expect(microphone.captureStatus == "missing")
        #expect(microphone.degradationReason == "microphone capture was disabled by the controlled fixture")
        #expect(microphone.checksum == nil)

        let mixed = try #require(response.artifacts.first { $0.artifactType == "mixed_audio" })
        #expect(mixed.captureStatus == "degraded")
        #expect(mixed.degradationReason == "mixed audio degraded because microphone audio was unavailable")

        let session = try readSessionJSON(workspace: workspace, sessionID: "session-stop-artifacts")
        #expect(session["status"] as? String == "recorded")
        #expect(session["ended_at"] as? String == fixedTimestamp)
        let artifacts = try #require(session["artifacts"] as? [[String: Any]])
        #expect(artifacts.count == 4)
        #expect(artifacts.compactMap { $0["checksum"] as? String }.count == 2)
        #expect(artifacts.compactMap { $0["degradation_reason"] as? String }.count == 2)
    }

    @Test
    func omittedStopArtifactsAreRegisteredMissingWithDegradationReasons() async throws {
        let workspace = try temporaryWorkspace()
        defer { try? FileManager.default.removeItem(at: workspace) }
        let adapter = ControlledNativeCaptureAdapter(
            stopBehavior: .success(
                artifacts: [
                    .available(.screenVideo, format: "mov", data: data("screen-video")),
                ]
            )
        )
        let client = nativeClient(
            workspace: workspace,
            sessionID: "session-omitted-artifacts",
            adapter: adapter
        )

        _ = try await client.startNativeRecording(startRequest(workspace: workspace))
        let response = try await client.stopRecording(StopRecordingRequest(sessionID: "session-omitted-artifacts"))

        #expect(response.ok == true)
        #expect(response.status == "recorded")
        #expect(response.artifacts.count == 4)
        let missingArtifacts = response.artifacts.filter { $0.captureStatus == "missing" }
        #expect(missingArtifacts.map(\.artifactType) == [
            "system_audio",
            "microphone_audio",
            "mixed_audio",
        ])
        #expect(missingArtifacts.allSatisfy {
            $0.degradationReason?.contains("Native capture adapter did not produce") == true
        })
        #expect(missingArtifacts.allSatisfy { $0.checksum == nil })

        let session = try readSessionJSON(workspace: workspace, sessionID: "session-omitted-artifacts")
        let artifacts = try #require(session["artifacts"] as? [[String: Any]])
        #expect(artifacts.count == 4)
        #expect(artifacts.compactMap { $0["checksum"] as? String }.count == 1)
        #expect(artifacts.compactMap { $0["degradation_reason"] as? String }.count == 3)
    }

    @Test
    func stopWithNoAvailableMediaReturnsCaptureFailedAndFailedSession() async throws {
        let workspace = try temporaryWorkspace()
        defer { try? FileManager.default.removeItem(at: workspace) }
        let adapter = ControlledNativeCaptureAdapter(
            stopBehavior: .success(
                artifacts: [
                    .failed(.screenVideo, reason: "screen capture failed"),
                    .missing(.systemAudio, reason: "system audio missing"),
                    .missing(.microphoneAudio, reason: "microphone audio missing"),
                    .failed(.mixedAudio, reason: "mixed audio failed"),
                ]
            )
        )
        let client = nativeClient(
            workspace: workspace,
            sessionID: "session-no-media",
            adapter: adapter
        )

        _ = try await client.startNativeRecording(startRequest(workspace: workspace))
        let response = try await client.stopRecording(StopRecordingRequest(sessionID: "session-no-media"))

        #expect(response.ok == false)
        #expect(response.status == "failed")
        #expect(response.code == .captureFailed)
        #expect(response.artifacts.count == 4)
        #expect(response.artifacts.allSatisfy { $0.captureStatus != "available" })
        #expect(response.artifacts.allSatisfy { $0.degradationReason != nil })

        let session = try readSessionJSON(workspace: workspace, sessionID: "session-no-media")
        #expect(session["status"] as? String == "failed")
        #expect((session["artifacts"] as? [[String: Any]])?.count == 4)
    }

    @Test
    func screenCaptureKitAdapterReportsConservativeCapabilities() {
        let adapter = AppleScreenCaptureKitNativeCaptureAdapter(
            runtime: FakeAppleScreenCaptureKitRuntime()
        )

        #expect(adapter.adapterIdentity == "apple_screencapturekit")
        #expect(adapter.capabilitySummary.adapterID == "apple_screencapturekit")
        #expect(adapter.capabilitySummary.framework == "ScreenCaptureKit")
        #expect(adapter.capabilitySummary.supportedCaptureTargets == [.screen])
        #expect(adapter.capabilitySummary.producedArtifactTypes == NativeCaptureArtifactType.allCases)
        #expect(adapter.capabilitySummary.producesCombinedRecordingFile == true)
        #expect(adapter.capabilitySummary.producesSeparateAudioArtifacts == false)
    }

    @Test
    func screenCaptureKitAdapterFailsClosedForUnsupportedCaptureTarget() async throws {
        let workspace = try temporaryWorkspace()
        defer { try? FileManager.default.removeItem(at: workspace) }
        let runtime = FakeAppleScreenCaptureKitRuntime()
        let adapter = AppleScreenCaptureKitNativeCaptureAdapter(runtime: runtime)
        let context = try RecordingSessionStore().makeStartContext(
            request: StartNativeRecordingRequest(
                captureTarget: .window,
                workspaceURL: workspace,
                captureSystemAudio: true,
                captureMicrophoneAudio: true
            ),
            sessionID: "session-sck-window-fail-closed",
            startedAt: fixedTimestamp
        )

        do {
            try await adapter.start(context)
            Issue.record("Expected unsupported ScreenCaptureKit target to fail closed.")
        } catch NativeCaptureAdapterFailure.startFailed(let message) {
            #expect(message.contains("supports only the screen capture target"))
        }

        #expect(await runtime.startCalls.isEmpty)
    }

    @Test
    func screenCaptureKitCombinedRecordingRegistersPartialAudioDegradation() async throws {
        let workspace = try temporaryWorkspace()
        defer { try? FileManager.default.removeItem(at: workspace) }
        let runtime = FakeAppleScreenCaptureKitRuntime(
            stopBehavior: .recordingData(data("combined-screen-audio-file"))
        )
        let adapter = AppleScreenCaptureKitNativeCaptureAdapter(runtime: runtime)
        let client = nativeClient(
            workspace: workspace,
            sessionID: "session-sck-combined",
            adapter: adapter
        )

        _ = try await client.startNativeRecording(startRequest(workspace: workspace))
        let response = try await client.stopRecording(StopRecordingRequest(sessionID: "session-sck-combined"))

        #expect(response.ok == true)
        #expect(response.status == "recorded")
        #expect(response.artifacts.map(\.artifactType) == [
            "screen_video",
            "system_audio",
            "microphone_audio",
            "mixed_audio",
        ])
        let screen = try #require(response.artifacts.first { $0.artifactType == "screen_video" })
        #expect(screen.captureStatus == "available")
        #expect(screen.format == "mp4")
        #expect(screen.path == "artifacts/screen_video.mp4")
        let expectedScreenChecksum = try checksum(
            for: artifactURL(workspace, "session-sck-combined", "screen_video.mp4")
        )
        #expect(screen.checksum == expectedScreenChecksum)

        let system = try #require(response.artifacts.first { $0.artifactType == "system_audio" })
        let microphone = try #require(response.artifacts.first { $0.artifactType == "microphone_audio" })
        let mixed = try #require(response.artifacts.first { $0.artifactType == "mixed_audio" })
        #expect(system.captureStatus == "degraded")
        #expect(microphone.captureStatus == "degraded")
        #expect(mixed.captureStatus == "degraded")
        #expect(system.degradationReason?.contains("combined screen_video file") == true)
        #expect(microphone.degradationReason?.contains("combined screen_video file") == true)
        #expect(mixed.degradationReason?.contains("combined recording file") == true)

        let session = try readSessionJSON(workspace: workspace, sessionID: "session-sck-combined")
        let artifacts = try #require(session["artifacts"] as? [[String: Any]])
        #expect(artifacts.count == 4)
        #expect(artifacts.compactMap { $0["checksum"] as? String }.count == 1)
        #expect(artifacts.compactMap { $0["degradation_reason"] as? String }.count == 3)
    }

    @Test
    func screenCaptureKitNoAvailableMediaFailsClosedThroughRecordingClient() async throws {
        let workspace = try temporaryWorkspace()
        defer { try? FileManager.default.removeItem(at: workspace) }
        let runtime = FakeAppleScreenCaptureKitRuntime(stopBehavior: .missingRecordingFile)
        let adapter = AppleScreenCaptureKitNativeCaptureAdapter(runtime: runtime)
        let client = nativeClient(
            workspace: workspace,
            sessionID: "session-sck-no-media",
            adapter: adapter
        )

        _ = try await client.startNativeRecording(startRequest(workspace: workspace))
        let response = try await client.stopRecording(StopRecordingRequest(sessionID: "session-sck-no-media"))

        #expect(response.ok == false)
        #expect(response.status == "failed")
        #expect(response.code == .captureFailed)
        #expect(response.artifacts.count == 4)
        #expect(response.artifacts.allSatisfy { $0.captureStatus == "failed" })
        #expect(response.details.allSatisfy { $0.contains("ScreenCaptureKit failed to finish native capture") })
        #expect(response.details.allSatisfy { !$0.contains("combined_recording.mp4") })

        let session = try readSessionJSON(workspace: workspace, sessionID: "session-sck-no-media")
        #expect(session["status"] as? String == "failed")
        #expect((session["artifacts"] as? [[String: Any]])?.count == 4)
    }

    @Test
    func interruptedPartialCaptureRecordsAvailableArtifactsAndFailsTheRest() async throws {
        let workspace = try temporaryWorkspace()
        defer { try? FileManager.default.removeItem(at: workspace) }
        let adapter = ControlledNativeCaptureAdapter(
            stopBehavior: .failure(
                message: "controlled native capture was interrupted",
                partialArtifacts: [
                    .available(.screenVideo, data: data("partial-screen-video")),
                ]
            )
        )
        let client = nativeClient(
            workspace: workspace,
            sessionID: "session-interrupted",
            adapter: adapter
        )

        _ = try await client.startNativeRecording(startRequest(workspace: workspace))
        let response = try await client.stopRecording(StopRecordingRequest(sessionID: "session-interrupted"))

        #expect(response.ok == true)
        #expect(response.status == "recorded")
        #expect(response.artifacts.filter { $0.captureStatus == "available" }.map(\.artifactType) == ["screen_video"])
        let failedArtifacts = response.artifacts.filter { $0.captureStatus == "failed" }
        #expect(failedArtifacts.map(\.artifactType) == ["system_audio", "microphone_audio", "mixed_audio"])
        #expect(failedArtifacts.allSatisfy {
            $0.degradationReason?.contains("controlled native capture was interrupted") == true
        })
    }

    @Test
    func repeatedStopReturnsFinalArtifactsWithoutDuplicatingOrCallingAdapterAgain() async throws {
        let workspace = try temporaryWorkspace()
        defer { try? FileManager.default.removeItem(at: workspace) }
        let adapter = ControlledNativeCaptureAdapter(
            stopBehavior: .success(
                artifacts: [
                    .available(.screenVideo, data: data("screen-video")),
                    .available(.mixedAudio, data: data("mixed-audio")),
                ]
            )
        )
        let client = nativeClient(
            workspace: workspace,
            sessionID: "session-idempotent-stop",
            adapter: adapter
        )

        _ = try await client.startNativeRecording(startRequest(workspace: workspace))
        let first = try await client.stopRecording(StopRecordingRequest(sessionID: "session-idempotent-stop"))
        let second = try await client.stopRecording(StopRecordingRequest(sessionID: "session-idempotent-stop"))

        #expect(first.ok == true)
        #expect(second.ok == true)
        #expect(second.artifacts == first.artifacts)
        #expect(await adapter.stopContexts.count == 1)
        let artifacts = try #require(
            readSessionJSON(workspace: workspace, sessionID: "session-idempotent-stop")["artifacts"] as? [[String: Any]]
        )
        #expect(artifacts.count == 4)
    }

    @Test
    func stopAfterClientRestartReturnsFinalArtifactsWithoutCallingAdapterAgain() async throws {
        let workspace = try temporaryWorkspace()
        defer { try? FileManager.default.removeItem(at: workspace) }
        let initialAdapter = ControlledNativeCaptureAdapter(
            stopBehavior: .success(
                artifacts: [
                    .available(.screenVideo, data: data("restart-screen-video")),
                    .available(.mixedAudio, data: data("restart-mixed-audio")),
                ]
            )
        )
        let initialClient = nativeClient(
            workspace: workspace,
            sessionID: "session-restart-final",
            adapter: initialAdapter
        )
        _ = try await initialClient.startNativeRecording(startRequest(workspace: workspace))
        let recorded = try await initialClient.stopRecording(
            StopRecordingRequest(sessionID: "session-restart-final")
        )
        let restartedAdapter = ControlledNativeCaptureAdapter()
        let restartedClient = nativeClient(
            workspace: workspace,
            sessionID: "unused-after-restart",
            recoveryWorkspace: workspace,
            adapter: restartedAdapter
        )

        let recovered = try await restartedClient.stopRecording(
            StopRecordingRequest(sessionID: "session-restart-final")
        )

        #expect(recorded.ok == true)
        #expect(recovered.ok == true)
        #expect(recovered.status == "recorded")
        #expect(recovered.artifacts == recorded.artifacts)
        #expect(await initialAdapter.stopContexts.count == 1)
        #expect(await restartedAdapter.stopContexts.isEmpty)
    }

    @Test
    func stopAfterClientRestartFailsClosedWhenAdapterLostRecordingState() async throws {
        let workspace = try temporaryWorkspace()
        defer { try? FileManager.default.removeItem(at: workspace) }
        let initialAdapter = ControlledNativeCaptureAdapter()
        let initialClient = nativeClient(
            workspace: workspace,
            sessionID: "session-restart-orphan",
            adapter: initialAdapter
        )
        _ = try await initialClient.startNativeRecording(startRequest(workspace: workspace))
        let screenURL = artifactURL(workspace, "session-restart-orphan", "screen_video.mov")
        try data("partial-screen-video").write(to: screenURL)
        let restartedAdapter = ControlledNativeCaptureAdapter()
        let restartedClient = nativeClient(
            workspace: workspace,
            sessionID: "unused-after-orphan-restart",
            recoveryWorkspace: workspace,
            adapter: restartedAdapter
        )

        let response = try await restartedClient.stopRecording(
            StopRecordingRequest(sessionID: "session-restart-orphan")
        )

        #expect(response.ok == false)
        #expect(response.code == .captureFailed)
        #expect(response.status == "failed")
        #expect(await restartedAdapter.stopContexts.count == 1)
        #expect(try Data(contentsOf: screenURL) == data("partial-screen-video"))
        #expect(response.details.contains { $0.contains("Native capture session was not started.") })
        let session = try readSessionJSON(workspace: workspace, sessionID: "session-restart-orphan")
        #expect(session["status"] as? String == "failed")
        let artifacts = try #require(session["artifacts"] as? [[String: Any]])
        #expect(artifacts.count == 4)
        #expect(artifacts.allSatisfy { $0["capture_status"] as? String == "failed" })
        #expect(artifacts.allSatisfy {
            ($0["degradation_reason"] as? String)?.contains("Native capture session was not started.") == true
        })
    }

    @Test
    func stopFinalizationPathConflictCanRetryWithoutCallingAdapterAgain() async throws {
        let workspace = try temporaryWorkspace()
        defer { try? FileManager.default.removeItem(at: workspace) }
        let adapter = ControlledNativeCaptureAdapter(
            stopBehavior: .success(
                artifacts: [
                    .available(.screenVideo, data: data("retry-screen-video")),
                    .available(.mixedAudio, data: data("retry-mixed-audio")),
                ]
            )
        )
        let client = nativeClient(
            workspace: workspace,
            sessionID: "session-stop-retry",
            adapter: adapter
        )
        _ = try await client.startNativeRecording(startRequest(workspace: workspace))
        let outsideURL = workspace.appendingPathComponent("outside-video.mov")
        try data("outside").write(to: outsideURL)
        let screenURL = artifactURL(workspace, "session-stop-retry", "screen_video.mov")
        try FileManager.default.createSymbolicLink(at: screenURL, withDestinationURL: outsideURL)

        let blocked = try await client.stopRecording(StopRecordingRequest(sessionID: "session-stop-retry"))

        #expect(blocked.ok == false)
        #expect(blocked.code == .pathConflict)
        #expect(await adapter.stopContexts.count == 1)
        let outsideData = try Data(contentsOf: outsideURL)
        #expect(outsideData == data("outside"))

        try FileManager.default.removeItem(at: screenURL)
        let retried = try await client.stopRecording(StopRecordingRequest(sessionID: "session-stop-retry"))

        #expect(retried.ok == true)
        #expect(retried.status == "recorded")
        #expect(await adapter.stopContexts.count == 1)
        let screen = try #require(retried.artifacts.first { $0.artifactType == "screen_video" })
        #expect(screen.captureStatus == "available")
        #expect(screen.checksum == (try checksum(for: screenURL)))
        let mixed = try #require(retried.artifacts.first { $0.artifactType == "mixed_audio" })
        #expect(mixed.captureStatus == "available")

        let session = try readSessionJSON(workspace: workspace, sessionID: "session-stop-retry")
        #expect(session["status"] as? String == "recorded")
        let artifacts = try #require(session["artifacts"] as? [[String: Any]])
        #expect(artifacts.count == 4)
    }

    @Test
    func sessionIDTraversalFailsClosedBeforeAdapterStart() async throws {
        let workspace = try temporaryWorkspace()
        defer { try? FileManager.default.removeItem(at: workspace) }
        let adapter = ControlledNativeCaptureAdapter()
        let client = nativeClient(
            workspace: workspace,
            sessionID: "../outside",
            adapter: adapter
        )

        let response = try await client.startNativeRecording(startRequest(workspace: workspace))

        #expect(response.ok == false)
        #expect(response.code == .pathConflict)
        #expect(await adapter.startContexts.isEmpty)
    }

    @Test
    func sessionMetadataSymlinkFailsClosedOnStop() async throws {
        let workspace = try temporaryWorkspace()
        defer { try? FileManager.default.removeItem(at: workspace) }
        let adapter = ControlledNativeCaptureAdapter(
            stopBehavior: .success(artifacts: [.available(.screenVideo, data: data("screen-video"))])
        )
        let client = nativeClient(
            workspace: workspace,
            sessionID: "session-metadata-symlink",
            adapter: adapter
        )
        _ = try await client.startNativeRecording(startRequest(workspace: workspace))
        let sessionURL = sessionRoot(workspace, "session-metadata-symlink").appendingPathComponent("session.json")
        let outsideURL = workspace.appendingPathComponent("outside-session.json")
        try data("outside").write(to: outsideURL)
        try FileManager.default.removeItem(at: sessionURL)
        try FileManager.default.createSymbolicLink(at: sessionURL, withDestinationURL: outsideURL)

        let response = try await client.stopRecording(StopRecordingRequest(sessionID: "session-metadata-symlink"))

        #expect(response.ok == false)
        #expect(response.code == .pathConflict)
        let outsideData = try Data(contentsOf: outsideURL)
        #expect(outsideData == data("outside"))
    }

    @Test
    func artifactSymlinkFailsClosedOnStop() async throws {
        let workspace = try temporaryWorkspace()
        defer { try? FileManager.default.removeItem(at: workspace) }
        let adapter = ControlledNativeCaptureAdapter(
            stopBehavior: .success(artifacts: [.available(.screenVideo, data: data("screen-video"))])
        )
        let client = nativeClient(
            workspace: workspace,
            sessionID: "session-artifact-symlink",
            adapter: adapter
        )
        _ = try await client.startNativeRecording(startRequest(workspace: workspace))
        let outsideURL = workspace.appendingPathComponent("outside-video.mov")
        try data("outside").write(to: outsideURL)
        try FileManager.default.createSymbolicLink(
            at: artifactURL(workspace, "session-artifact-symlink", "screen_video.mov"),
            withDestinationURL: outsideURL
        )

        let response = try await client.stopRecording(StopRecordingRequest(sessionID: "session-artifact-symlink"))

        #expect(response.ok == false)
        #expect(response.code == .pathConflict)
        let outsideData = try Data(contentsOf: outsideURL)
        #expect(outsideData == data("outside"))
    }

    @Test
    func artifactHardlinkFailsClosedOnStop() async throws {
        let workspace = try temporaryWorkspace()
        defer { try? FileManager.default.removeItem(at: workspace) }
        let adapter = ControlledNativeCaptureAdapter(
            stopBehavior: .success(artifacts: [.available(.screenVideo, data: data("screen-video"))])
        )
        let client = nativeClient(
            workspace: workspace,
            sessionID: "session-artifact-hardlink",
            adapter: adapter
        )
        _ = try await client.startNativeRecording(startRequest(workspace: workspace))
        let outsideURL = workspace.appendingPathComponent("outside-video.mov")
        try data("outside").write(to: outsideURL)
        try FileManager.default.linkItem(
            at: outsideURL,
            to: artifactURL(workspace, "session-artifact-hardlink", "screen_video.mov")
        )

        let response = try await client.stopRecording(StopRecordingRequest(sessionID: "session-artifact-hardlink"))

        #expect(response.ok == false)
        #expect(response.code == .pathConflict)
        let outsideData = try Data(contentsOf: outsideURL)
        #expect(outsideData == data("outside"))
    }

    @Test
    func adapterArtifactTraversalPathFailsClosedOnStop() async throws {
        let workspace = try temporaryWorkspace()
        defer { try? FileManager.default.removeItem(at: workspace) }
        let adapter = ControlledNativeCaptureAdapter(
            stopBehavior: .success(
                artifacts: [
                    .available(
                        .screenVideo,
                        relativePath: "artifacts/../outside-video.mov",
                        data: data("screen-video")
                    ),
                ]
            )
        )
        let client = nativeClient(
            workspace: workspace,
            sessionID: "session-artifact-traversal",
            adapter: adapter
        )
        _ = try await client.startNativeRecording(startRequest(workspace: workspace))
        let escapedURL = sessionRoot(workspace, "session-artifact-traversal")
            .appendingPathComponent("outside-video.mov")

        let response = try await client.stopRecording(StopRecordingRequest(sessionID: "session-artifact-traversal"))

        #expect(response.ok == false)
        #expect(response.code == .pathConflict)
        #expect(await adapter.stopContexts.count == 1)
        #expect(!FileManager.default.fileExists(atPath: escapedURL.path))
    }

    @Test
    func adapterArtifactAbsolutePathFailsClosedOnStop() async throws {
        let workspace = try temporaryWorkspace()
        defer { try? FileManager.default.removeItem(at: workspace) }
        let outsideURL = workspace.appendingPathComponent("outside-absolute-video.mov")
        try data("outside").write(to: outsideURL)
        let adapter = ControlledNativeCaptureAdapter(
            stopBehavior: .success(
                artifacts: [
                    .available(
                        .screenVideo,
                        relativePath: outsideURL.path,
                        data: data("screen-video")
                    ),
                ]
            )
        )
        let client = nativeClient(
            workspace: workspace,
            sessionID: "session-artifact-absolute",
            adapter: adapter
        )
        _ = try await client.startNativeRecording(startRequest(workspace: workspace))

        let response = try await client.stopRecording(StopRecordingRequest(sessionID: "session-artifact-absolute"))

        #expect(response.ok == false)
        #expect(response.code == .pathConflict)
        #expect(await adapter.stopContexts.count == 1)
        let outsideData = try Data(contentsOf: outsideURL)
        #expect(outsideData == data("outside"))
    }

    @Test
    func adapterArtifactUnsafeFormatFailsClosedOnStop() async throws {
        let workspace = try temporaryWorkspace()
        defer { try? FileManager.default.removeItem(at: workspace) }
        let adapter = ControlledNativeCaptureAdapter(
            stopBehavior: .success(
                artifacts: [
                    .available(
                        .screenVideo,
                        format: "mp4/../../outside",
                        data: data("screen-video")
                    ),
                ]
            )
        )
        let client = nativeClient(
            workspace: workspace,
            sessionID: "session-artifact-unsafe-format",
            adapter: adapter
        )
        _ = try await client.startNativeRecording(startRequest(workspace: workspace))
        let escapedURL = sessionRoot(workspace, "session-artifact-unsafe-format")
            .appendingPathComponent("outside")

        let response = try await client.stopRecording(
            StopRecordingRequest(sessionID: "session-artifact-unsafe-format")
        )

        #expect(response.ok == false)
        #expect(response.code == .pathConflict)
        #expect(await adapter.stopContexts.count == 1)
        #expect(!FileManager.default.fileExists(atPath: escapedURL.path))
    }

    @Test
    func duplicateAdapterArtifactTypeFailsClosedOnStop() async throws {
        let workspace = try temporaryWorkspace()
        defer { try? FileManager.default.removeItem(at: workspace) }
        let adapter = ControlledNativeCaptureAdapter(
            stopBehavior: .success(
                artifacts: [
                    .available(.screenVideo, data: data("first-screen-video")),
                    .available(
                        .screenVideo,
                        relativePath: "artifacts/screen_video_duplicate.mov",
                        data: data("second-screen-video")
                    ),
                ]
            )
        )
        let client = nativeClient(
            workspace: workspace,
            sessionID: "session-duplicate-artifact-type",
            adapter: adapter
        )
        _ = try await client.startNativeRecording(startRequest(workspace: workspace))

        let response = try await client.stopRecording(
            StopRecordingRequest(sessionID: "session-duplicate-artifact-type")
        )

        #expect(response.ok == false)
        #expect(response.code == .pathConflict)
        #expect(await adapter.stopContexts.count == 1)
        #expect(!FileManager.default.fileExists(
            atPath: artifactURL(workspace, "session-duplicate-artifact-type", "screen_video.mov").path
        ))
        #expect(!FileManager.default.fileExists(
            atPath: artifactURL(workspace, "session-duplicate-artifact-type", "screen_video_duplicate.mov").path
        ))
        let session = try readSessionJSON(workspace: workspace, sessionID: "session-duplicate-artifact-type")
        #expect(session["status"] as? String == "recording")
    }

    @Test
    func nonAvailableArtifactSymlinkFailsClosedOnStop() async throws {
        let workspace = try temporaryWorkspace()
        defer { try? FileManager.default.removeItem(at: workspace) }
        let adapter = ControlledNativeCaptureAdapter(
            stopBehavior: .success(
                artifacts: [
                    .missing(.microphoneAudio, reason: "microphone capture unavailable"),
                ]
            )
        )
        let client = nativeClient(
            workspace: workspace,
            sessionID: "session-missing-artifact-symlink",
            adapter: adapter
        )
        _ = try await client.startNativeRecording(startRequest(workspace: workspace))
        let outsideURL = workspace.appendingPathComponent("outside-microphone.m4a")
        try data("outside").write(to: outsideURL)
        try FileManager.default.createSymbolicLink(
            at: artifactURL(workspace, "session-missing-artifact-symlink", "microphone_audio.m4a"),
            withDestinationURL: outsideURL
        )

        let response = try await client.stopRecording(
            StopRecordingRequest(sessionID: "session-missing-artifact-symlink")
        )

        #expect(response.ok == false)
        #expect(response.code == .pathConflict)
        let outsideData = try Data(contentsOf: outsideURL)
        #expect(outsideData == data("outside"))
    }

    @Test
    func nonAvailableArtifactHardlinkFailsClosedOnStop() async throws {
        let workspace = try temporaryWorkspace()
        defer { try? FileManager.default.removeItem(at: workspace) }
        let adapter = ControlledNativeCaptureAdapter(
            stopBehavior: .success(
                artifacts: [
                    .degraded(.mixedAudio, reason: "mixed audio degraded"),
                ]
            )
        )
        let client = nativeClient(
            workspace: workspace,
            sessionID: "session-degraded-artifact-hardlink",
            adapter: adapter
        )
        _ = try await client.startNativeRecording(startRequest(workspace: workspace))
        let outsideURL = workspace.appendingPathComponent("outside-mixed.wav")
        try data("outside").write(to: outsideURL)
        try FileManager.default.linkItem(
            at: outsideURL,
            to: artifactURL(workspace, "session-degraded-artifact-hardlink", "mixed_audio.wav")
        )

        let response = try await client.stopRecording(
            StopRecordingRequest(sessionID: "session-degraded-artifact-hardlink")
        )

        #expect(response.ok == false)
        #expect(response.code == .pathConflict)
        let outsideData = try Data(contentsOf: outsideURL)
        #expect(outsideData == data("outside"))
    }

    @Test
    @MainActor
    func recordingViewExposesArtifactStatusAndDegradationLocators() {
        let artifacts = [
            RecordingCommandArtifact(
                id: "artifact-screen",
                sessionID: "session-view",
                artifactType: "screen_video",
                captureStatus: "available"
            ),
            RecordingCommandArtifact(
                id: "artifact-mic",
                sessionID: "session-view",
                artifactType: "microphone_audio",
                captureStatus: "missing",
                degradationReason: "microphone unavailable"
            ),
        ]
        let viewModel = RecordingControlViewModel(
            client: ControlledViewRecordingClient(),
            initialState: .recorded(sessionID: "session-view", artifacts: artifacts)
        )
        _ = RecordingControlView(viewModel: viewModel)

        #expect(RecordingAccessibilityID.artifactStatus("screen_video") == "ma.recording.artifact.screen_video.status")
        #expect(
            RecordingAccessibilityID.artifactDegradation("microphone_audio")
                == "ma.recording.artifact.microphone_audio.degradation"
        )
        #expect(viewModel.state.savedSummary == "Saved 1 recording artifact.")
    }
}

private let fixedTimestamp = "2026-07-01T00:00:00Z"

private func nativeClient(
    workspace: URL,
    sessionID: String,
    permissions: NativeCapturePermissionSnapshot = .granted,
    recoveryWorkspace: URL? = nil,
    adapter: any NativeCaptureAdapter
) -> NativeRecordingCommandClient {
    nativeClient(
        workspace: workspace,
        sessionID: sessionID,
        permissionChecker: StaticNativeCapturePermissionChecker(snapshot: permissions),
        recoveryWorkspace: recoveryWorkspace,
        adapter: adapter
    )
}

private func nativeClient(
    workspace: URL,
    sessionID: String,
    permissionChecker: any NativeCapturePermissionChecking,
    recoveryWorkspace: URL? = nil,
    adapter: any NativeCaptureAdapter
) -> NativeRecordingCommandClient {
    let recoveryWorkspaceURL = recoveryWorkspace ?? workspace
    return NativeRecordingCommandClient(
        permissionChecker: permissionChecker,
        captureAdapter: adapter,
        sessionIDProvider: { sessionID },
        timestampProvider: { fixedTimestamp },
        requestIDProvider: { command in "request-\(command.rawValue)" },
        recoveryWorkspaceURLProvider: { recoveryWorkspaceURL }
    )
}

private func startRequest(
    workspace: URL,
    title: String? = nil,
    captureSystemAudio: Bool = true,
    captureMicrophoneAudio: Bool = true
) -> StartNativeRecordingRequest {
    StartNativeRecordingRequest(
        title: title,
        captureTarget: .screen,
        workspaceURL: workspace,
        captureSystemAudio: captureSystemAudio,
        captureMicrophoneAudio: captureMicrophoneAudio
    )
}

private func temporaryWorkspace() throws -> URL {
    let url = FileManager.default.temporaryDirectory
        .appendingPathComponent("ma-native-recording-\(UUID().uuidString)", isDirectory: true)
    try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
    return url
}

private func sessionRoot(_ workspace: URL, _ sessionID: String) -> URL {
    workspace
        .appendingPathComponent("sessions", isDirectory: true)
        .appendingPathComponent(sessionID, isDirectory: true)
}

private func artifactURL(_ workspace: URL, _ sessionID: String, _ filename: String) -> URL {
    sessionRoot(workspace, sessionID)
        .appendingPathComponent("artifacts", isDirectory: true)
        .appendingPathComponent(filename, isDirectory: false)
}

private func readSessionJSON(workspace: URL, sessionID: String) throws -> [String: Any] {
    let url = sessionRoot(workspace, sessionID).appendingPathComponent("session.json")
    let payload = try JSONSerialization.jsonObject(with: Data(contentsOf: url))
    guard let session = payload as? [String: Any] else {
        throw NativeRecordingCommandClientTestError.invalidSessionJSON
    }
    return session
}

private func data(_ value: String) -> Data {
    Data(value.utf8)
}

private func checksum(for url: URL) throws -> String {
    let digest = SHA256.hash(data: try Data(contentsOf: url))
    let hex = digest.map { String(format: "%02x", $0) }.joined()
    return "sha256:\(hex)"
}

private enum NativeRecordingCommandClientTestError: Error {
    case invalidSessionJSON
}

private actor FakeAppleScreenCaptureKitRuntime: AppleScreenCaptureKitRecordingRuntime {
    enum StartBehavior: Equatable {
        case success
        case failure(String)
    }

    enum StopBehavior: Equatable {
        case recordingData(Data)
        case missingRecordingFile
        case emptyRecordingFile
        case failure(String)
    }

    struct StartCall: Equatable {
        let sessionID: String
        let outputURL: URL
        let options: AppleScreenCaptureKitRecordingOptions
    }

    private let startBehavior: StartBehavior
    private let stopBehavior: StopBehavior
    private var outputURLs: [AppleScreenCaptureKitRecordingToken: URL] = [:]
    private(set) var startCalls: [StartCall] = []

    init(
        startBehavior: StartBehavior = .success,
        stopBehavior: StopBehavior = .recordingData(data("screen"))
    ) {
        self.startBehavior = startBehavior
        self.stopBehavior = stopBehavior
    }

    func startRecording(
        context: NativeCaptureStartContext,
        outputURL: URL,
        options: AppleScreenCaptureKitRecordingOptions
    ) async throws -> AppleScreenCaptureKitRecordingToken {
        startCalls.append(
            StartCall(
                sessionID: context.sessionID,
                outputURL: outputURL,
                options: options
            )
        )
        if case .failure(let message) = startBehavior {
            throw FakeAppleScreenCaptureKitRuntimeError(message: message)
        }

        let token = AppleScreenCaptureKitRecordingToken(rawValue: context.sessionID)
        outputURLs[token] = outputURL
        return token
    }

    func stopRecording(
        _ token: AppleScreenCaptureKitRecordingToken
    ) async throws -> AppleScreenCaptureKitRecordingFile {
        guard let outputURL = outputURLs.removeValue(forKey: token) else {
            throw FakeAppleScreenCaptureKitRuntimeError(message: "unknown fake recording token")
        }

        switch stopBehavior {
        case .recordingData(let data):
            try data.write(to: outputURL)
        case .missingRecordingFile:
            break
        case .emptyRecordingFile:
            try Data().write(to: outputURL)
        case .failure(let message):
            throw FakeAppleScreenCaptureKitRuntimeError(message: message)
        }

        return AppleScreenCaptureKitRecordingFile(url: outputURL, format: "mp4")
    }
}

private struct FakeAppleScreenCaptureKitRuntimeError: Error, LocalizedError, Equatable {
    let message: String

    var errorDescription: String? {
        message
    }
}

private actor ControlledViewRecordingClient: RecordingCommandClient {
    func startNativeRecording(_ request: StartNativeRecordingRequest) async throws -> RecordingCommandResponse {
        .successfulStart(sessionID: "session-view")
    }

    func stopRecording(_ request: StopRecordingRequest) async throws -> RecordingCommandResponse {
        .successfulStop(sessionID: request.sessionID)
    }
}
