#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
cd "$ROOT_DIR"

PYTHONDONTWRITEBYTECODE=1 \
PYTHONPATH="$ROOT_DIR/platform/processing-cli/src${PYTHONPATH:+:$PYTHONPATH}" \
python3 - <<'PY'
from __future__ import annotations

import hashlib
import json
import os
import shutil
import subprocess
import stat
import sys
import tempfile
import wave
from pathlib import Path


ROOT = Path.cwd()
PYTHON = sys.executable
CLI_ENV_BASE = os.environ.copy()


def sha256(path: Path) -> str:
    digest = hashlib.sha256()
    with path.open("rb") as handle:
        for chunk in iter(lambda: handle.read(1024 * 1024), b""):
            digest.update(chunk)
    return f"sha256:{digest.hexdigest()}"


def write_fixture_wav(path: Path) -> None:
    path.parent.mkdir(parents=True, exist_ok=True)
    frames = bytearray()
    for index in range(2400):
        sample = ((index % 96) - 48) * 96
        frames.extend(int(sample).to_bytes(2, "little", signed=True))
    with wave.open(str(path), "wb") as handle:
        handle.setnchannels(1)
        handle.setsampwidth(2)
        handle.setframerate(8000)
        handle.writeframes(bytes(frames))


def run_cli(workspace: Path, args: list[str], command: str) -> dict:
    env = CLI_ENV_BASE.copy()
    for env_name in (
        "MEETING_ASSISTANT_TRANSCRIPTION_RUNTIME",
        "MEETING_ASSISTANT_TRANSCRIPTION_MODEL",
        "MEETING_ASSISTANT_WHISPER_SMOKE_AUDIO",
    ):
        env.pop(env_name, None)
    env["MEETING_ASSISTANT_WORKSPACE"] = str(workspace)
    env["PYTHONPATH"] = f"{ROOT / 'platform/processing-cli/src'}{os.pathsep}{env.get('PYTHONPATH', '')}"
    completed = subprocess.run(
        [PYTHON, "-m", "meeting_assistant_cli", *args],
        cwd=ROOT,
        env=env,
        text=True,
        capture_output=True,
        check=False,
    )
    if "Traceback" in completed.stdout or "Traceback" in completed.stderr:
        raise AssertionError(f"{command}: response leaked a traceback")
    if completed.returncode != 0:
        raise AssertionError(
            f"{command}: expected exit 0, got {completed.returncode}\n"
            f"stdout={completed.stdout}\nstderr={completed.stderr}"
        )
    lines = [line for line in completed.stdout.splitlines() if line.strip()]
    if len(lines) != 1:
        raise AssertionError(f"{command}: expected one JSON object, got {len(lines)} lines")
    payload = json.loads(lines[0])
    if payload.get("ok") is not True or payload.get("command") != command:
        raise AssertionError(f"{command}: response contract drifted: {payload!r}")
    if not str(payload.get("request_id", "")).startswith("local-"):
        raise AssertionError(f"{command}: request_id must be local-*")
    if not isinstance(payload.get("warnings"), list):
        raise AssertionError(f"{command}: warnings must be a list")
    return payload


def load_json(path: Path) -> dict:
    payload = json.loads(path.read_text(encoding="utf-8"))
    if not isinstance(payload, dict):
        raise AssertionError(f"{path}: expected JSON object")
    return payload


def artifact_by_type(session: dict, artifact_type: str) -> dict:
    matches = [artifact for artifact in session.get("artifacts", []) if artifact.get("artifact_type") == artifact_type]
    if len(matches) != 1:
        raise AssertionError(f"expected exactly one {artifact_type} artifact, got {len(matches)}")
    return matches[0]


def assert_managed_regular_file(path: Path, label: str) -> None:
    if path.is_symlink():
        raise AssertionError(f"{label}: must not be a symlink")
    try:
        stat_result = path.stat()
    except FileNotFoundError as exc:
        raise AssertionError(f"{label}: file is missing") from exc
    if not stat.S_ISREG(stat_result.st_mode):
        raise AssertionError(f"{label}: must be a regular file")
    if stat_result.st_nlink != 1:
        raise AssertionError(f"{label}: must not be a hardlink")


def assert_no_temp_leftovers(session_dir: Path) -> None:
    leftovers = [
        path
        for path in session_dir.rglob(".*.tmp")
        if path.exists() or path.is_symlink()
    ]
    if leftovers:
        raise AssertionError(f"temporary managed output leftovers remain: {[str(path) for path in leftovers]}")


def assert_native_readable_session_file(session_dir: Path) -> None:
    assert_managed_regular_file(session_dir / "session.json", "session.json")


def assert_artifact_file(session_dir: Path, artifact: dict, artifact_type: str) -> Path:
    required = {"id", "session_id", "artifact_type", "path", "format", "capture_status", "checksum", "created_at"}
    missing = required - set(artifact)
    if missing:
        raise AssertionError(f"{artifact_type}: missing artifact keys {sorted(missing)}")
    if artifact["artifact_type"] != artifact_type:
        raise AssertionError(f"{artifact_type}: artifact type drifted")
    path = Path(str(artifact["path"]))
    try:
        path.resolve(strict=False).relative_to(session_dir.resolve(strict=False))
    except ValueError as exc:
        raise AssertionError(f"{artifact_type}: artifact path escapes session dir") from exc
    assert_managed_regular_file(path, f"{artifact_type} artifact")
    if not str(artifact["checksum"]).startswith("sha256:"):
        raise AssertionError(f"{artifact_type}: checksum must use sha256 prefix")
    if sha256(path) != artifact["checksum"]:
        raise AssertionError(f"{artifact_type}: artifact file/checksum drifted")
    return path


def write_swift_bridge_package(swift_root: Path) -> None:
    sources_root = swift_root / "Sources"
    bridge_root = sources_root / "NativeTranscriptBridgeSmoke"
    sources_root.mkdir(parents=True)
    bridge_root.mkdir()
    (sources_root / "MeetingAssistantNative").symlink_to(
        ROOT / "platform/native-app/Sources/MeetingAssistantNative",
        target_is_directory=True,
    )
    (swift_root / "Package.swift").write_text(
        """// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "MeetingAssistantNativeBridgeSmoke",
    platforms: [.macOS(.v14)],
    targets: [
        .target(
            name: "MeetingAssistantNative",
            path: "Sources/MeetingAssistantNative"
        ),
        .executableTarget(
            name: "NativeTranscriptBridgeSmoke",
            dependencies: ["MeetingAssistantNative"],
            path: "Sources/NativeTranscriptBridgeSmoke"
        ),
    ]
)
""",
        encoding="utf-8",
    )
    (bridge_root / "main.swift").write_text(
        """import Foundation
import MeetingAssistantNative

func fail(_ message: String) -> Never {
    fputs("\\(message)\\n", stderr)
    exit(1)
}

guard CommandLine.arguments.count == 5 else {
    fail("usage: NativeTranscriptBridgeSmoke <workspace> <session-id> <transcript-id> <repo-root>")
}

let workspaceURL = URL(fileURLWithPath: CommandLine.arguments[1], isDirectory: true)
let sessionID = CommandLine.arguments[2]
let repoRootURL = URL(fileURLWithPath: CommandLine.arguments[4], isDirectory: true)

func assertSourceContains(_ url: URL, _ requiredSnippets: [String], label: String) {
    let source: String
    do {
        source = try String(contentsOf: url, encoding: .utf8)
    } catch {
        fail("\\(label): could not read source at \\(url.path): \\(error)")
    }
    for snippet in requiredSnippets where !source.contains(snippet) {
        fail("\\(label): missing source snippet: \\(snippet)")
    }
}

func assertDesignedShellContract(repoRootURL: URL) {
    let routeIDs = MeetingWorkspaceRoute.allCases.map(\\.rawValue)
    guard routeIDs == ["meetings", "newRecording", "meetingDetail", "diagnostics"] else {
        fail("task-based meeting route order drifted: \\(routeIDs)")
    }
    guard MeetingWorkspaceRoute.meetings.title == "Meetings",
          MeetingWorkspaceRoute.newRecording.title == "New recording",
          MeetingWorkspaceRoute.meetingDetail.title == "Meeting detail",
          MeetingWorkspaceRoute.diagnostics.title == "Settings & diagnostics" else {
        fail("task-based meeting route title drifted")
    }
    guard DesignedNativeShellAccessibilityID.root == "ma.shell.root" else {
        fail("designed native shell root locator drifted")
    }
    guard MeetingTaskAccessibilityID.navigation == "ma.shell.navigation" else {
        fail("task-based meeting navigation locator drifted")
    }
    guard MeetingTaskAccessibilityID.meetingsHeading == "ma.meetings.heading",
          MeetingTaskAccessibilityID.newRecordingHeading == "ma.newRecording.heading",
          MeetingTaskAccessibilityID.detailHeading == "ma.meetingDetail.heading" else {
        fail("task-based meeting heading locators drifted")
    }
    guard MeetingTaskAccessibilityID.recoveryStatus == "ma.meetingDetail.recoveryStatus" else {
        fail("task-based meeting recovery locator drifted")
    }
    guard MeetingTaskAccessibilityID.meetingRow("session-bridge") == "ma.meetings.row.session-bridge" else {
        fail("task-based meeting row locator drifted")
    }

    let appSourceURL = repoRootURL.appendingPathComponent("platform/native-app/App/MeetingAssistantNativeApp.swift")
    let appSource: String
    do {
        appSource = try String(contentsOf: appSourceURL, encoding: .utf8)
    } catch {
        fail("designed native shell app root: could not read source at \\(appSourceURL.path): \\(error)")
    }
    for snippet in [
        "@StateObject private var workspaceCoordinator: MeetingWorkspaceCoordinator",
        "_workspaceCoordinator = StateObject(",
        "wrappedValue: MeetingWorkspaceCoordinator(",
        "DesignedNativeShellView(",
        "coordinator: workspaceCoordinator",
        "permissionViewModel: permissionViewModel",
        "recordingViewModel: recordingViewModel",
        "processingViewModel: processingViewModel",
        "transcriptViewModel: transcriptViewModel",
        "transcriptActionViewModel: transcriptActionViewModel",
    ] where !appSource.contains(snippet) {
        fail("designed native shell app root: missing source snippet: \\(snippet)")
    }
    if appSource.contains("PermissionDependencyStatusView(viewModel: permissionViewModel)") {
        fail("designed native shell app root must not mount primitive debug UI directly")
    }

    let shellSourceURL = repoRootURL.appendingPathComponent("platform/native-app/Sources/MeetingAssistantNative/DesignedNativeShellView.swift")
    assertSourceContains(
        shellSourceURL,
        [
            "Text(\\\"Meeting Assistant\\\")",
            "Text(\\\"Local meeting capture\\\")",
            ".accessibilityIdentifier(DesignedNativeShellAccessibilityID.root)",
            ".accessibilityIdentifier(MeetingTaskAccessibilityID.navigation)",
            "private var routeContent: some View",
            "case .meetings:",
            "case .newRecording:",
            "case .meetingDetail:",
            "case .diagnostics:",
            "PermissionDependencyStatusView(",
            "captureMicrophoneAudio: coordinator.recordingDraft.captureMicrophoneAudio",
            ".accessibilityIdentifier(MeetingTaskAccessibilityID.newRecordingButton)",
            ".accessibilityIdentifier(MeetingTaskAccessibilityID.detailHeading)",
            ".accessibilityIdentifier(MeetingTaskAccessibilityID.recoveryStatus)",
        ],
        label: "designed native shell source"
    )
}

assertDesignedShellContract(repoRootURL: repoRootURL)

let input: TranscriptReviewInput
do {
    input = try TranscriptReviewWorkspaceLoader.load(
        workspaceURL: workspaceURL,
        sessionID: sessionID
    )
} catch {
    fail("native workspace loader failed: \\(error)")
}

guard let transcript = input.transcript else {
    fail("native workspace loader returned missing transcript")
}
guard transcript.id == CommandLine.arguments[3] else {
    fail("native workspace loader returned mismatched transcript id")
}
guard transcript.sessionID == sessionID else {
    fail("native workspace loader returned mismatched session")
}
guard transcript.segments.count == 1 else {
    fail("native workspace loader segment count drifted")
}
guard let firstSegment = transcript.segments.first else {
    fail("native workspace loader returned no first segment")
}
guard firstSegment.segmentID == "segment-0001" else {
    fail("native workspace loader segment id drifted")
}
guard firstSegment.startMS == 0 && firstSegment.endMS == 1000 else {
    fail("native workspace loader timestamp drifted")
}
guard transcript.segments.contains(where: { $0.text.contains("Fake transcript generated from local audio.") }) else {
    fail("native workspace loader did not expose processing transcript text")
}
guard input.speakerLabels?.sessionID == sessionID else {
    fail("native workspace loader returned mismatched speaker label session")
}
guard input.speakerLabels?.labels.isEmpty == true && input.speakerLabels?.segmentMapping.isEmpty == true else {
    fail("native workspace loader should expose transcript-only speaker fallback without labels")
}

let viewModel = TranscriptReviewViewModel(input: input)
guard viewModel.state.contentState == .available else {
    fail("native transcript view model did not enter available state")
}
guard viewModel.state.segments.count == transcript.segments.count else {
    fail("native transcript view model segment count drifted")
}
guard viewModel.state.segments.map(\\.id) == transcript.segments.map(\\.segmentID) else {
    fail("native transcript view model segment id/order drifted")
}
guard let firstVisibleSegment = viewModel.state.segments.first,
      firstVisibleSegment.timestampLabel == "00:00-00:01" else {
    fail("native transcript view model timestamp label drifted")
}
guard viewModel.state.segments.contains(where: { $0.text.contains("Fake transcript generated from local audio.") }) else {
    fail("native transcript view model did not expose transcript text")
}
guard viewModel.state.segments.allSatisfy({ $0.speakerDisplayLabel == nil }) else {
    fail("native transcript view model should show no verified speaker labels in fallback")
}
guard let degradation = viewModel.state.degradationReason, !degradation.isEmpty else {
    fail("native transcript view model did not expose transcript-only degradation")
}

print("native transcript bridge smoke passed.")
print("designed native shell bridge smoke passed.")
""",
        encoding="utf-8",
    )


with tempfile.TemporaryDirectory(prefix="meeting-assistant-native-bridge-") as tmp:
    root = Path(tmp)
    workspace = root / "workspace"
    fixture = root / "fixtures" / "native-bridge.wav"
    write_fixture_wav(fixture)
    fixture_checksum = sha256(fixture)

    import_response = run_cli(
        workspace,
        ["import_media", "--path", str(fixture), "--title", "Native transcript bridge smoke"],
        "import_media",
    )
    session_id = str(import_response["session_id"])
    session_dir = workspace / "sessions" / session_id
    assert_native_readable_session_file(session_dir)
    session = load_json(session_dir / "session.json")
    if session["id"] != session_id:
        raise AssertionError("import_media: session id drifted")
    assert_artifact_file(session_dir, artifact_by_type(session, "mixed_audio"), "mixed_audio")
    assert_no_temp_leftovers(session_dir)

    transcript_response = run_cli(
        workspace,
        ["generate_transcript", "--session-id", session_id, "--language", "zh"],
        "generate_transcript",
    )
    session = load_json(session_dir / "session.json")
    assert_native_readable_session_file(session_dir)
    assert_artifact_file(session_dir, artifact_by_type(session, "normalized_audio"), "normalized_audio")
    transcript_artifact = artifact_by_type(session, "transcript_text")
    transcript_path = assert_artifact_file(session_dir, transcript_artifact, "transcript_text")
    transcript = load_json(transcript_path)
    if transcript["id"] != transcript_response["transcript_id"]:
        raise AssertionError("generate_transcript: transcript id drifted")
    if transcript["session_id"] != session_id:
        raise AssertionError("generate_transcript: transcript session id drifted")
    segments = transcript.get("segments")
    if not segments:
        raise AssertionError("generate_transcript: expected at least one segment")
    if [segment["segment_id"] for segment in segments] != sorted(segment["segment_id"] for segment in segments):
        raise AssertionError("generate_transcript: segment ids should be deterministic for the fake adapter")
    previous = None
    for segment in segments:
        if segment["start_ms"] >= segment["end_ms"]:
            raise AssertionError("generate_transcript: invalid segment timestamp")
        current = (segment["start_ms"], segment["end_ms"])
        if previous is not None and current < previous:
            raise AssertionError("generate_transcript: segments are not sorted")
        previous = current
    assert_no_temp_leftovers(session_dir)

    speaker_response = run_cli(
        workspace,
        [
            "generate_speaker_labels",
            "--session-id",
            session_id,
            "--transcript-id",
            str(transcript["id"]),
            "--allow-transcript-only-fallback",
            "true",
        ],
        "generate_speaker_labels",
    )
    if speaker_response["label_status"] != "transcript_only":
        raise AssertionError("generate_speaker_labels: expected transcript-only fallback")
    session = load_json(session_dir / "session.json")
    assert_native_readable_session_file(session_dir)
    speaker_artifact = artifact_by_type(session, "speaker_labels")
    speaker_path = assert_artifact_file(session_dir, speaker_artifact, "speaker_labels")
    speaker_payload = load_json(speaker_path)
    if speaker_payload["session_id"] != session_id or not speaker_payload.get("degradation_reason"):
        raise AssertionError("generate_speaker_labels: speaker fallback payload drifted")
    if speaker_payload["labels"] != [] or speaker_payload["segment_mapping"] != []:
        raise AssertionError("generate_speaker_labels: transcript-only fallback should not claim speaker mappings")
    if sha256(fixture) != fixture_checksum:
        raise AssertionError("processing pipeline changed the source fixture")
    assert_no_temp_leftovers(session_dir)

    processing_artifact_checksums = {
        "session.json": sha256(session_dir / "session.json"),
        "transcript.json": sha256(transcript_path),
        "speaker_labels.json": sha256(speaker_path),
    }

    swift_root = root / "swift-bridge"
    write_swift_bridge_package(swift_root)
    if not shutil.which("swift"):
        raise AssertionError("native Swift bridge cannot run: swift executable was not found; install Xcode or Command Line Tools")
    completed = subprocess.run(
        ["swift", "run", "NativeTranscriptBridgeSmoke", str(workspace), session_id, str(transcript["id"]), str(ROOT)],
        cwd=swift_root,
        text=True,
        capture_output=True,
        check=False,
    )
    if completed.returncode != 0:
        raise AssertionError(
            f"native Swift bridge failed with exit {completed.returncode}\n"
            f"stdout={completed.stdout}\nstderr={completed.stderr}"
        )
    if "native transcript bridge smoke passed." not in completed.stdout:
        raise AssertionError(f"native Swift bridge success marker missing: {completed.stdout!r}")
    if "designed native shell bridge smoke passed." not in completed.stdout:
        raise AssertionError(f"designed native shell bridge success marker missing: {completed.stdout!r}")
    after_bridge_checksums = {
        "session.json": sha256(session_dir / "session.json"),
        "transcript.json": sha256(transcript_path),
        "speaker_labels.json": sha256(speaker_path),
    }
    if after_bridge_checksums != processing_artifact_checksums:
        raise AssertionError("native Swift bridge changed processing artifacts")

print("processing-to-native transcript bridge e2e smoke passed.")
print("designed native shell bridge smoke passed.")
PY
