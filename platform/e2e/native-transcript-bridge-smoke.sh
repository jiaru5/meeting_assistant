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
import subprocess
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
    if not path.is_file() or sha256(path) != artifact["checksum"]:
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

guard CommandLine.arguments.count == 3 else {
    fail("usage: NativeTranscriptBridgeSmoke <workspace> <session-id>")
}

let workspaceURL = URL(fileURLWithPath: CommandLine.arguments[1], isDirectory: true)
let sessionID = CommandLine.arguments[2]
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
guard transcript.sessionID == sessionID else {
    fail("native workspace loader returned mismatched session")
}
guard transcript.segments.contains(where: { $0.text.contains("Fake transcript generated from local audio.") }) else {
    fail("native workspace loader did not expose processing transcript text")
}

let viewModel = TranscriptReviewViewModel(input: input)
guard viewModel.state.contentState == .available else {
    fail("native transcript view model did not enter available state")
}
guard viewModel.state.segments.count == transcript.segments.count else {
    fail("native transcript view model segment count drifted")
}
guard viewModel.state.segments.contains(where: { $0.text.contains("Fake transcript generated from local audio.") }) else {
    fail("native transcript view model did not expose transcript text")
}
guard let degradation = viewModel.state.degradationReason, !degradation.isEmpty else {
    fail("native transcript view model did not expose transcript-only degradation")
}

print("native transcript bridge smoke passed.")
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
    session = load_json(session_dir / "session.json")
    if session["id"] != session_id:
        raise AssertionError("import_media: session id drifted")
    assert_artifact_file(session_dir, artifact_by_type(session, "mixed_audio"), "mixed_audio")

    transcript_response = run_cli(
        workspace,
        ["generate_transcript", "--session-id", session_id, "--language", "zh"],
        "generate_transcript",
    )
    session = load_json(session_dir / "session.json")
    assert_artifact_file(session_dir, artifact_by_type(session, "normalized_audio"), "normalized_audio")
    transcript_artifact = artifact_by_type(session, "transcript_text")
    transcript_path = assert_artifact_file(session_dir, transcript_artifact, "transcript_text")
    transcript = load_json(transcript_path)
    if transcript["id"] != transcript_response["transcript_id"]:
        raise AssertionError("generate_transcript: transcript id drifted")
    if not transcript.get("segments"):
        raise AssertionError("generate_transcript: expected at least one segment")

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
    speaker_artifact = artifact_by_type(session, "speaker_labels")
    speaker_path = assert_artifact_file(session_dir, speaker_artifact, "speaker_labels")
    speaker_payload = load_json(speaker_path)
    if speaker_payload["session_id"] != session_id or not speaker_payload.get("degradation_reason"):
        raise AssertionError("generate_speaker_labels: speaker fallback payload drifted")
    if sha256(fixture) != fixture_checksum:
        raise AssertionError("processing pipeline changed the source fixture")

    swift_root = root / "swift-bridge"
    write_swift_bridge_package(swift_root)
    completed = subprocess.run(
        ["swift", "run", "NativeTranscriptBridgeSmoke", str(workspace), session_id],
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

print("processing-to-native transcript bridge e2e smoke passed.")
PY
