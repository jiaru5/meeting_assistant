#!/usr/bin/env bash
set -euo pipefail

component_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$component_dir"

case "${MA_NATIVE_CAPTURE_SMOKE:-0}" in
  1|true|TRUE|yes|YES)
    ;;
  *)
    echo "native capture smoke skipped: set MA_NATIVE_CAPTURE_SMOKE=1 to run real ScreenCaptureKit capture." >&2
    echo "This opt-in smoke is not part of the default native-app test gate and may require macOS Screen Recording permission." >&2
    exit 2
    ;;
esac

if [[ "$(uname -s)" != "Darwin" ]]; then
  echo "native capture smoke failed: real ScreenCaptureKit capture requires macOS." >&2
  exit 2
fi

run_stamp="$(date -u +%Y%m%dT%H%M%SZ)"
workspace="${MA_NATIVE_CAPTURE_SMOKE_WORKSPACE:-$component_dir/build/native-capture-smoke/workspace-$run_stamp}"
session_id="${MA_NATIVE_CAPTURE_SMOKE_SESSION_ID:-session-native-capture-smoke-$run_stamp-$$}"
duration_seconds="${MA_NATIVE_CAPTURE_SMOKE_DURATION_SECONDS:-2}"
timeout_seconds="${MA_NATIVE_CAPTURE_SMOKE_TIMEOUT_SECONDS:-90}"
capture_system_audio="${MA_NATIVE_CAPTURE_SMOKE_SYSTEM_AUDIO:-false}"
capture_microphone_audio="${MA_NATIVE_CAPTURE_SMOKE_MICROPHONE_AUDIO:-false}"
title="${MA_NATIVE_CAPTURE_SMOKE_TITLE:-Native capture smoke $run_stamp}"
build_root="${MA_NATIVE_CAPTURE_SMOKE_BUILD_DIR:-$component_dir/build/native-capture-smoke/build-$run_stamp-$$}"

if ! [[ "$timeout_seconds" =~ ^[1-9][0-9]*$ ]] || ((timeout_seconds > 600)); then
  echo "native capture smoke failed: MA_NATIVE_CAPTURE_SMOKE_TIMEOUT_SECONDS must be an integer from 1 to 600." >&2
  exit 2
fi

mkdir -p "$(dirname "$workspace")" "$build_root"
tmp_dir="$(mktemp -d "$build_root/package.XXXXXX")"

if [[ "${MA_NATIVE_CAPTURE_SMOKE_KEEP_BUILD:-0}" =~ ^(1|true|TRUE|yes|YES)$ ]]; then
  trap 'printf "%s\n" "native capture smoke build package retained at '"$tmp_dir"'" >&2' EXIT
else
  trap 'rm -rf "$tmp_dir"' EXIT
fi

ln -s "$component_dir/Sources" "$tmp_dir/Sources"
mkdir -p "$tmp_dir/Smoke"

cat > "$tmp_dir/Package.swift" <<'SWIFT'
// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "MeetingAssistantNativeCaptureSmokePackage",
    platforms: [.macOS(.v14)],
    products: [
        .executable(name: "NativeCaptureSmoke", targets: ["NativeCaptureSmoke"]),
    ],
    targets: [
        .target(name: "MeetingAssistantNative"),
        .executableTarget(
            name: "NativeCaptureSmoke",
            dependencies: ["MeetingAssistantNative"],
            path: "Smoke"
        ),
    ]
)
SWIFT

cat > "$tmp_dir/Smoke/main.swift" <<'SWIFT'
import Darwin
import Foundation
import MeetingAssistantNative

struct SmokeConfiguration {
    let workspaceURL: URL
    let sessionID: String
    let durationSeconds: Double
    let captureSystemAudio: Bool
    let captureMicrophoneAudio: Bool
    let title: String
}

struct SmokeSummary: Encodable {
    let ok: Bool
    let script: String
    let adapter: String
    let workspace: String
    let sessionID: String?
    let durationSeconds: Double
    let captureSystemAudio: Bool
    let captureMicrophoneAudio: Bool
    let failureStage: String?
    let message: String?
    let startResponse: ResponseSummary?
    let stopResponse: ResponseSummary?
    let sessionJSON: String?
    let screenVideoPath: String?
    let screenVideoBytes: Int?
    let screenVideoChecksum: String?
    let artifactStatuses: [String: String]
    let artifactDegradationReasons: [String: String]
    let validationErrors: [String]
    let notes: [String]
}

struct FatalSmokeSummary: Encodable {
    let ok: Bool
    let script: String
    let adapter: String
    let failureStage: String
    let message: String
}

struct ResponseSummary: Encodable {
    let ok: Bool
    let requestID: String
    let command: String
    let sessionID: String?
    let status: String?
    let captureTarget: String?
    let code: String?
    let message: String?
    let details: [String]
    let artifacts: [ArtifactSummary]

    init(_ response: RecordingCommandResponse) {
        ok = response.ok
        requestID = response.requestID
        command = response.command.rawValue
        sessionID = response.sessionID
        status = response.status
        captureTarget = response.captureTarget?.rawValue
        code = response.code?.rawValue
        message = response.message
        details = response.details
        artifacts = response.artifacts.map(ArtifactSummary.init)
    }
}

struct ArtifactSummary: Encodable {
    let artifactType: String
    let captureStatus: String
    let format: String?
    let path: String?
    let checksum: String?
    let degradationReason: String?

    init(_ artifact: RecordingCommandArtifact) {
        artifactType = artifact.artifactType
        captureStatus = artifact.captureStatus
        format = artifact.format
        path = artifact.path
        checksum = artifact.checksum
        degradationReason = artifact.degradationReason
    }
}

struct ValidationOutcome {
    let sessionJSON: String
    let screenVideoPath: String?
    let screenVideoBytes: Int?
    let screenVideoChecksum: String?
    let artifactStatuses: [String: String]
    let artifactDegradationReasons: [String: String]
    let errors: [String]
}

struct SessionMetadata: Decodable {
    let id: String
    let sourceType: String
    let status: String
    let endedAt: String?
    let artifacts: [SessionArtifactMetadata]

    private enum CodingKeys: String, CodingKey {
        case id
        case sourceType = "source_type"
        case status
        case endedAt = "ended_at"
        case artifacts
    }
}

struct SessionArtifactMetadata: Decodable {
    let artifactType: String
    let path: String
    let captureStatus: String
    let checksum: String?
    let degradationReason: String?

    private enum CodingKeys: String, CodingKey {
        case artifactType = "artifact_type"
        case path
        case captureStatus = "capture_status"
        case checksum
        case degradationReason = "degradation_reason"
    }
}

enum SmokeInputError: Error, LocalizedError {
    case missingEnvironment(String)
    case invalidBoolean(name: String, value: String)
    case invalidDuration(String)
    case invalidSessionID(String)

    var errorDescription: String? {
        switch self {
        case .missingEnvironment(let name):
            return "Missing required environment variable \(name)."
        case .invalidBoolean(let name, let value):
            return "\(name) must be 0/1, true/false, or yes/no; got \(value)."
        case .invalidDuration(let value):
            return "MA_NATIVE_CAPTURE_SMOKE_DURATION_SECONDS must be greater than 0 and at most 30; got \(value)."
        case .invalidSessionID(let value):
            return "MA_NATIVE_CAPTURE_SMOKE_SESSION_ID contains unsupported path characters: \(value)."
        }
    }
}

@main
struct NativeCaptureSmoke {
    static func main() async {
        do {
            let configuration = try configurationFromEnvironment()
            let summary = await runSmoke(configuration)
            emitJSON(summary)
            exit(summary.ok ? 0 : 1)
        } catch {
            emitJSON(
                FatalSmokeSummary(
                    ok: false,
                    script: "native-capture-smoke",
                    adapter: AppleScreenCaptureKitNativeCaptureAdapter.identity,
                    failureStage: "fatal",
                    message: error.localizedDescription
                )
            )
            exit(1)
        }
    }

    private static func runSmoke(_ configuration: SmokeConfiguration) async -> SmokeSummary {
        if #unavailable(macOS 15.0) {
            return baseSummary(
                configuration,
                ok: false,
                failureStage: "runtime",
                message: "ScreenCaptureKit recording output requires macOS 15.0 or newer."
            )
        }

        var notes = [
            "This script is an opt-in local smoke and is not part of the default native-app gate.",
            "The smoke validates real ScreenCaptureKit screen_video output plus existing session.json artifact registration only.",
        ]
        if configuration.captureSystemAudio {
            notes.append("System audio remains unproven as an independent artifact; mixed_audio may be extracted from the combined recording when an exportable audio track exists.")
        }
        if configuration.captureMicrophoneAudio {
            notes.append("Microphone capture requires the current permission checker to prove microphone permission; unknown permission fails closed, and independent microphone_audio remains unproven.")
        }

        let client = NativeRecordingCommandClient(
            permissionChecker: MacOSNativeCapturePermissionChecker(
                screenRecordingProbe: CoreGraphicsScreenRecordingPermissionProbe(
                    requestAccessWhenDenied: true
                )
            ),
            captureAdapter: AppleScreenCaptureKitNativeCaptureAdapter(),
            sessionStore: RecordingSessionStore(),
            sessionIDProvider: { configuration.sessionID },
            timestampProvider: {
                let formatter = ISO8601DateFormatter()
                formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
                return formatter.string(from: Date())
            },
            requestIDProvider: { command in
                "native-capture-smoke-\(command.rawValue)"
            }
        )

        let startResponse: RecordingCommandResponse
        do {
            startResponse = try await client.startNativeRecording(
                StartNativeRecordingRequest(
                    title: configuration.title,
                    captureTarget: .screen,
                    workspaceURL: configuration.workspaceURL,
                    captureSystemAudio: configuration.captureSystemAudio,
                    captureMicrophoneAudio: configuration.captureMicrophoneAudio
                )
            )
        } catch {
            return baseSummary(
                configuration,
                ok: false,
                failureStage: "start_exception",
                message: error.localizedDescription,
                startResponse: nil,
                notes: notes
            )
        }

        guard startResponse.ok, let startedSessionID = startResponse.sessionID else {
            return baseSummary(
                configuration,
                ok: false,
                failureStage: "start",
                message: startResponse.message ?? "Native capture did not start.",
                startResponse: ResponseSummary(startResponse),
                notes: notes
            )
        }

        let nanoseconds = UInt64(configuration.durationSeconds * 1_000_000_000)
        try? await Task.sleep(nanoseconds: nanoseconds)

        let stopResponse: RecordingCommandResponse
        do {
            stopResponse = try await client.stopRecording(StopRecordingRequest(sessionID: startedSessionID))
        } catch {
            return baseSummary(
                configuration,
                ok: false,
                failureStage: "stop_exception",
                message: error.localizedDescription,
                startResponse: ResponseSummary(startResponse),
                notes: notes
            )
        }

        let validation = validateSession(
            workspaceURL: configuration.workspaceURL,
            sessionID: startedSessionID,
            captureSystemAudio: configuration.captureSystemAudio,
            captureMicrophoneAudio: configuration.captureMicrophoneAudio
        )
        let ok = stopResponse.ok && validation.errors.isEmpty
        let failureStage: String?
        let message: String?
        if stopResponse.ok, validation.errors.isEmpty {
            failureStage = nil
            message = nil
        } else if !stopResponse.ok {
            failureStage = "stop"
            message = stopResponse.message ?? "Native capture stop did not produce an available media artifact."
        } else {
            failureStage = "validation"
            message = validation.errors.joined(separator: "; ")
        }

        return SmokeSummary(
            ok: ok,
            script: "native-capture-smoke",
            adapter: AppleScreenCaptureKitNativeCaptureAdapter.identity,
            workspace: configuration.workspaceURL.path,
            sessionID: startedSessionID,
            durationSeconds: configuration.durationSeconds,
            captureSystemAudio: configuration.captureSystemAudio,
            captureMicrophoneAudio: configuration.captureMicrophoneAudio,
            failureStage: failureStage,
            message: message,
            startResponse: ResponseSummary(startResponse),
            stopResponse: ResponseSummary(stopResponse),
            sessionJSON: validation.sessionJSON,
            screenVideoPath: validation.screenVideoPath,
            screenVideoBytes: validation.screenVideoBytes,
            screenVideoChecksum: validation.screenVideoChecksum,
            artifactStatuses: validation.artifactStatuses,
            artifactDegradationReasons: validation.artifactDegradationReasons,
            validationErrors: validation.errors,
            notes: notes
        )
    }

    private static func baseSummary(
        _ configuration: SmokeConfiguration,
        ok: Bool,
        failureStage: String,
        message: String,
        startResponse: ResponseSummary? = nil,
        notes: [String] = []
    ) -> SmokeSummary {
        SmokeSummary(
            ok: ok,
            script: "native-capture-smoke",
            adapter: AppleScreenCaptureKitNativeCaptureAdapter.identity,
            workspace: configuration.workspaceURL.path,
            sessionID: configuration.sessionID,
            durationSeconds: configuration.durationSeconds,
            captureSystemAudio: configuration.captureSystemAudio,
            captureMicrophoneAudio: configuration.captureMicrophoneAudio,
            failureStage: failureStage,
            message: message,
            startResponse: startResponse,
            stopResponse: nil,
            sessionJSON: nil,
            screenVideoPath: nil,
            screenVideoBytes: nil,
            screenVideoChecksum: nil,
            artifactStatuses: [:],
            artifactDegradationReasons: [:],
            validationErrors: [],
            notes: notes
        )
    }

    private static func configurationFromEnvironment() throws -> SmokeConfiguration {
        let environment = ProcessInfo.processInfo.environment
        guard let workspace = environment["MA_NATIVE_CAPTURE_SMOKE_WORKSPACE"], !workspace.isEmpty else {
            throw SmokeInputError.missingEnvironment("MA_NATIVE_CAPTURE_SMOKE_WORKSPACE")
        }
        let sessionID = environment["MA_NATIVE_CAPTURE_SMOKE_SESSION_ID"] ?? "session-native-capture-smoke"
        guard isValidSessionID(sessionID) else {
            throw SmokeInputError.invalidSessionID(sessionID)
        }
        let durationValue = environment["MA_NATIVE_CAPTURE_SMOKE_DURATION_SECONDS"] ?? "2"
        guard let duration = Double(durationValue), duration > 0, duration <= 30 else {
            throw SmokeInputError.invalidDuration(durationValue)
        }

        return SmokeConfiguration(
            workspaceURL: URL(fileURLWithPath: workspace, isDirectory: true),
            sessionID: sessionID,
            durationSeconds: duration,
            captureSystemAudio: try boolEnvironment(
                environment,
                name: "MA_NATIVE_CAPTURE_SMOKE_SYSTEM_AUDIO",
                defaultValue: false
            ),
            captureMicrophoneAudio: try boolEnvironment(
                environment,
                name: "MA_NATIVE_CAPTURE_SMOKE_MICROPHONE_AUDIO",
                defaultValue: false
            ),
            title: environment["MA_NATIVE_CAPTURE_SMOKE_TITLE"] ?? "Native capture smoke"
        )
    }

    private static func validateSession(
        workspaceURL: URL,
        sessionID: String,
        captureSystemAudio: Bool,
        captureMicrophoneAudio: Bool
    ) -> ValidationOutcome {
        let sessionURL = workspaceURL
            .appendingPathComponent("sessions", isDirectory: true)
            .appendingPathComponent(sessionID, isDirectory: true)
            .standardizedFileURL
        let sessionJSON = sessionURL.appendingPathComponent("session.json", isDirectory: false)
        var errors: [String] = []
        var artifactStatuses: [String: String] = [:]
        var screenVideoPath: String?
        var screenVideoBytes: Int?
        var screenVideoChecksum: String?
        var artifactDegradationReasons: [String: String] = [:]

        guard FileManager.default.fileExists(atPath: sessionJSON.path) else {
            return ValidationOutcome(
                sessionJSON: sessionJSON.path,
                screenVideoPath: nil,
                screenVideoBytes: nil,
                screenVideoChecksum: nil,
                artifactStatuses: [:],
                artifactDegradationReasons: [:],
                errors: ["session.json was not written at \(sessionJSON.path)"]
            )
        }

        do {
            let data = try Data(contentsOf: sessionJSON)
            let session = try JSONDecoder().decode(SessionMetadata.self, from: data)
            if session.id != sessionID {
                errors.append("session.json id mismatch: expected \(sessionID), got \(session.id)")
            }
            if session.sourceType != "native_recording" {
                errors.append("session.json source_type must be native_recording")
            }
            if session.status != "recorded" {
                errors.append("session.json status must be recorded")
            }
            if session.endedAt == nil {
                errors.append("session.json ended_at must be present")
            }

            let expectedTypes = ["screen_video", "system_audio", "microphone_audio", "mixed_audio"]
            for expectedType in expectedTypes where !session.artifacts.contains(where: { $0.artifactType == expectedType }) {
                errors.append("session.json missing artifact type \(expectedType)")
            }
            for artifact in session.artifacts {
                artifactStatuses[artifact.artifactType] = artifact.captureStatus
                if let degradationReason = artifact.degradationReason {
                    artifactDegradationReasons[artifact.artifactType] = degradationReason
                }
                if artifact.captureStatus != "available",
                   (artifact.degradationReason ?? "").isEmpty {
                    errors.append("\(artifact.artifactType) \(artifact.captureStatus) artifact must include degradation_reason")
                }
            }

            if let screenVideo = session.artifacts.first(where: { $0.artifactType == "screen_video" }) {
                if screenVideo.captureStatus != "available" {
                    errors.append("screen_video capture_status must be available")
                }
                if screenVideo.path.isEmpty || screenVideo.path.hasPrefix("/") || !screenVideo.path.hasPrefix("artifacts/") || screenVideo.path.contains("..") {
                    errors.append("screen_video path must stay under artifacts/")
                } else {
                    let artifactURL = sessionURL.appendingPathComponent(screenVideo.path, isDirectory: false).standardizedFileURL
                    let artifactsRoot = sessionURL.appendingPathComponent("artifacts", isDirectory: true).standardizedFileURL
                    if !isWithin(artifactURL, root: artifactsRoot) {
                        errors.append("screen_video path escapes artifacts boundary")
                    }
                    if !FileManager.default.fileExists(atPath: artifactURL.path) {
                        errors.append("screen_video file was not written at \(artifactURL.path)")
                    } else {
                        let values = try artifactURL.resourceValues(forKeys: [.isRegularFileKey, .fileSizeKey])
                        if values.isRegularFile != true {
                            errors.append("screen_video file must be a regular file")
                        }
                        if let size = values.fileSize, size > 0 {
                            screenVideoBytes = size
                        } else {
                            errors.append("screen_video file must be non-empty")
                        }
                        screenVideoPath = artifactURL.path
                    }
                }
                if let checksum = screenVideo.checksum, checksum.hasPrefix("sha256:") {
                    screenVideoChecksum = checksum
                } else {
                    errors.append("screen_video checksum must be a sha256: value")
                }
            } else {
                errors.append("session.json missing screen_video artifact")
            }

            validateUnavailableAudioArtifact(
                type: "system_audio",
                expectedStatus: captureSystemAudio ? "degraded" : "missing",
                artifacts: session.artifacts,
                errors: &errors
            )
            validateUnavailableAudioArtifact(
                type: "microphone_audio",
                expectedStatus: captureMicrophoneAudio ? "degraded" : "missing",
                artifacts: session.artifacts,
                errors: &errors
            )
            validateMixedAudioArtifact(
                type: "mixed_audio",
                expectedStatus: (captureSystemAudio || captureMicrophoneAudio) ? "degraded" : "missing",
                allowAvailable: captureSystemAudio || captureMicrophoneAudio,
                sessionURL: sessionURL,
                artifacts: session.artifacts,
                errors: &errors
            )
        } catch {
            errors.append("session.json validation failed: \(error.localizedDescription)")
        }

        return ValidationOutcome(
            sessionJSON: sessionJSON.path,
            screenVideoPath: screenVideoPath,
            screenVideoBytes: screenVideoBytes,
            screenVideoChecksum: screenVideoChecksum,
            artifactStatuses: artifactStatuses,
            artifactDegradationReasons: artifactDegradationReasons,
            errors: errors
        )
    }

    private static func validateUnavailableAudioArtifact(
        type: String,
        expectedStatus: String,
        artifacts: [SessionArtifactMetadata],
        errors: inout [String]
    ) {
        guard let artifact = artifacts.first(where: { $0.artifactType == type }) else {
            errors.append("session.json missing artifact type \(type)")
            return
        }
        if artifact.captureStatus != expectedStatus {
            errors.append("\(type) capture_status must be \(expectedStatus); got \(artifact.captureStatus)")
        }
        if artifact.checksum != nil {
            errors.append("\(type) \(expectedStatus) artifact must not include a checksum")
        }
        if artifact.path.isEmpty || artifact.path.hasPrefix("/") || !artifact.path.hasPrefix("artifacts/") || artifact.path.contains("..") {
            errors.append("\(type) path must stay under artifacts/")
        }
        if (artifact.degradationReason ?? "").isEmpty {
            errors.append("\(type) \(expectedStatus) artifact must include degradation_reason")
        }
    }

    private static func validateMixedAudioArtifact(
        type: String,
        expectedStatus: String,
        allowAvailable: Bool,
        sessionURL: URL,
        artifacts: [SessionArtifactMetadata],
        errors: inout [String]
    ) {
        guard let artifact = artifacts.first(where: { $0.artifactType == type }) else {
            errors.append("session.json missing artifact type \(type)")
            return
        }
        if allowAvailable, artifact.captureStatus == "available" {
            if artifact.checksum?.hasPrefix("sha256:") != true {
                errors.append("\(type) available artifact must include a sha256: checksum")
            }
            if artifact.path.isEmpty || artifact.path.hasPrefix("/") || !artifact.path.hasPrefix("artifacts/") || artifact.path.contains("..") {
                errors.append("\(type) path must stay under artifacts/")
                return
            }
            let artifactURL = sessionURL.appendingPathComponent(artifact.path, isDirectory: false).standardizedFileURL
            let artifactsRoot = sessionURL.appendingPathComponent("artifacts", isDirectory: true).standardizedFileURL
            if !isWithin(artifactURL, root: artifactsRoot) {
                errors.append("\(type) path escapes artifacts boundary")
                return
            }
            guard FileManager.default.fileExists(atPath: artifactURL.path) else {
                errors.append("\(type) file was not written at \(artifactURL.path)")
                return
            }
            do {
                let values = try artifactURL.resourceValues(forKeys: [.isRegularFileKey, .fileSizeKey])
                if values.isRegularFile != true {
                    errors.append("\(type) file must be a regular file")
                }
                if values.fileSize ?? 0 <= 0 {
                    errors.append("\(type) file must be non-empty")
                }
            } catch {
                errors.append("\(type) file validation failed: \(error.localizedDescription)")
            }
            return
        }
        validateUnavailableAudioArtifact(
            type: type,
            expectedStatus: expectedStatus,
            artifacts: artifacts,
            errors: &errors
        )
    }

    private static func boolEnvironment(
        _ environment: [String: String],
        name: String,
        defaultValue: Bool
    ) throws -> Bool {
        guard let value = environment[name], !value.isEmpty else {
            return defaultValue
        }
        switch value {
        case "1", "true", "TRUE", "yes", "YES":
            return true
        case "0", "false", "FALSE", "no", "NO":
            return false
        default:
            throw SmokeInputError.invalidBoolean(name: name, value: value)
        }
    }

    private static func isValidSessionID(_ value: String) -> Bool {
        guard value.count <= 128, let first = value.unicodeScalars.first, isASCIILetterOrDigit(first) else {
            return false
        }
        return value.unicodeScalars.allSatisfy { scalar in
            isASCIILetterOrDigit(scalar) || scalar.value == 95 || scalar.value == 46 || scalar.value == 45
        }
    }

    private static func isASCIILetterOrDigit(_ scalar: UnicodeScalar) -> Bool {
        switch scalar.value {
        case 48...57, 65...90, 97...122:
            return true
        default:
            return false
        }
    }

    private static func isWithin(_ candidate: URL, root: URL) -> Bool {
        let rootPath = root.standardizedFileURL.path
        let candidatePath = candidate.standardizedFileURL.path
        return candidatePath == rootPath || candidatePath.hasPrefix("\(rootPath)/")
    }

    private static func emitJSON<T: Encodable>(_ value: T) {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
        encoder.keyEncodingStrategy = .convertToSnakeCase
        if let data = try? encoder.encode(value), let text = String(data: data, encoding: .utf8) {
            print(text)
        } else {
            print("{\"ok\":false,\"script\":\"native-capture-smoke\",\"failure_stage\":\"encoding\",\"message\":\"failed to encode smoke summary\"}")
        }
    }
}
SWIFT

export MA_NATIVE_CAPTURE_SMOKE_WORKSPACE="$workspace"
export MA_NATIVE_CAPTURE_SMOKE_SESSION_ID="$session_id"
export MA_NATIVE_CAPTURE_SMOKE_DURATION_SECONDS="$duration_seconds"
export MA_NATIVE_CAPTURE_SMOKE_SYSTEM_AUDIO="$capture_system_audio"
export MA_NATIVE_CAPTURE_SMOKE_MICROPHONE_AUDIO="$capture_microphone_audio"
export MA_NATIVE_CAPTURE_SMOKE_TITLE="$title"

run_native_capture_smoke() {
  local executable_path="$1"
  local timeout="$2"
  local child_pid
  local elapsed
  local state

  "$executable_path" &
  child_pid=$!

  while :; do
    state="$(ps -p "$child_pid" -o state= 2>/dev/null || true)"
    state="${state//[[:space:]]/}"
    if [[ -z "$state" || "$state" == Z* ]]; then
      break
    fi

    elapsed=$((SECONDS - run_start_seconds))
    if ((elapsed >= timeout)); then
      echo "native capture smoke failed: NativeCaptureSmoke timed out after ${timeout}s." >&2
      kill "$child_pid" 2>/dev/null || true
      sleep 2
      if kill -0 "$child_pid" 2>/dev/null; then
        kill -9 "$child_pid" 2>/dev/null || true
      fi
      wait "$child_pid" 2>/dev/null || true
      printf '{"adapter":"apple_screencapturekit","failure_stage":"timeout","message":"NativeCaptureSmoke timed out after %s seconds.","ok":false,"script":"native-capture-smoke"}\n' "$timeout"
      return 124
    fi

    sleep 1
  done

  wait "$child_pid"
}

printf '%s\n' "native capture smoke running: workspace=$workspace session_id=$session_id duration=${duration_seconds}s timeout=${timeout_seconds}s" >&2
(
  cd "$tmp_dir"
  swift build --product NativeCaptureSmoke >&2
  bin_path="$(swift build --show-bin-path)"
  run_start_seconds=$SECONDS
  run_native_capture_smoke "$bin_path/NativeCaptureSmoke" "$timeout_seconds"
)
