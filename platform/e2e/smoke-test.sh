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
import stat
import sys
import tempfile
import wave
from pathlib import Path


ROOT = Path.cwd()
PYTHON = sys.executable
CLI_ENV_BASE = os.environ.copy()


def evidence_marker(stage: str) -> None:
    print(f"VS-MA-20 provider/e2e marker [non-contract]: import processing chain - {stage}", flush=True)


def sha256(path: Path) -> str:
    digest = hashlib.sha256()
    with path.open("rb") as handle:
        for chunk in iter(lambda: handle.read(1024 * 1024), b""):
            digest.update(chunk)
    return f"sha256:{digest.hexdigest()}"


def write_fixture_wav(path: Path) -> None:
    path.parent.mkdir(parents=True, exist_ok=True)
    frames = bytearray()
    for index in range(1600):
        sample = ((index % 64) - 32) * 128
        frames.extend(int(sample).to_bytes(2, "little", signed=True))
    with wave.open(str(path), "wb") as handle:
        handle.setnchannels(1)
        handle.setsampwidth(2)
        handle.setframerate(8000)
        handle.writeframes(bytes(frames))


def write_fake_executable(directory: Path, name: str) -> Path:
    path = directory / name
    path.write_text("#!/usr/bin/env sh\nexit 0\n", encoding="utf-8")
    path.chmod(path.stat().st_mode | stat.S_IXUSR)
    return path


def check_items_by_id(payload: dict, command: str) -> dict[str, dict]:
    checks = payload.get("checks")
    if not isinstance(checks, list):
        raise AssertionError(f"{command}: checks must be a list")
    result = {}
    for item in checks:
        if not isinstance(item, dict) or "id" not in item:
            raise AssertionError(f"{command}: each check must be an object with id")
        result[str(item["id"])] = item
    return result


def assert_single_json(stdout: str, command: str) -> dict:
    lines = [line for line in stdout.splitlines() if line.strip()]
    if len(lines) != 1:
        raise AssertionError(f"{command}: expected one JSON object on stdout, got {len(lines)} lines: {stdout!r}")
    payload = json.loads(lines[0])
    if not isinstance(payload, dict):
        raise AssertionError(f"{command}: response must be a JSON object")
    return payload


def assert_response_shape(payload: dict, command: str, *, ok: bool, code: str | None = None) -> None:
    for key in ("ok", "request_id", "command", "warnings"):
        if key not in payload:
            raise AssertionError(f"{command}: missing response key {key}")
    if payload["command"] != command:
        raise AssertionError(f"{command}: response command drifted to {payload['command']!r}")
    if payload["ok"] is not ok:
        raise AssertionError(f"{command}: expected ok={ok}, got {payload['ok']!r}")
    if not str(payload["request_id"]).startswith("local-"):
        raise AssertionError(f"{command}: request_id must be local-*")
    if not isinstance(payload["warnings"], list):
        raise AssertionError(f"{command}: warnings must be a list")
    if not ok:
        for key in ("code", "message", "details"):
            if key not in payload:
                raise AssertionError(f"{command}: missing failure key {key}")
        if code is not None and payload["code"] != code:
            raise AssertionError(f"{command}: expected code={code}, got {payload['code']!r}")
        if not payload["message"]:
            raise AssertionError(f"{command}: failure message must be explainable")


def run_cli(workspace: Path, args: list[str], *, expected_exit: int, command: str) -> dict:
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
    if completed.returncode != expected_exit:
        raise AssertionError(
            f"{command}: expected exit {expected_exit}, got {completed.returncode}\n"
            f"stdout={completed.stdout}\nstderr={completed.stderr}"
        )
    if "Traceback" in completed.stdout or "Traceback" in completed.stderr:
        raise AssertionError(f"{command}: response leaked a traceback")
    return assert_single_json(completed.stdout, command)


def run_check_dependencies_smoke(workspace: Path, bin_dir: Path, model_path: Path) -> None:
    env = CLI_ENV_BASE.copy()
    for env_name in (
        "MEETING_ASSISTANT_TRANSCRIPTION_RUNTIME",
        "MEETING_ASSISTANT_TRANSCRIPTION_MODEL",
        "MEETING_ASSISTANT_WHISPER_SMOKE_AUDIO",
    ):
        env.pop(env_name, None)
    env.update(
        {
            "PATH": str(bin_dir),
            "MEETING_ASSISTANT_WORKSPACE": str(workspace),
            "MEETING_ASSISTANT_OS_NAME": "Darwin",
            "MEETING_ASSISTANT_MACOS_VERSION": "26.5.1",
            "MEETING_ASSISTANT_CPU_ARCH": "arm64",
            "MEETING_ASSISTANT_CHIP_NAME": "Apple M4",
            "MEETING_ASSISTANT_MEMORY_BYTES": str(16 * 1024 * 1024 * 1024),
            "MEETING_ASSISTANT_TRANSCRIPTION_RUNTIME": "whisper-local",
            "MEETING_ASSISTANT_TRANSCRIPTION_MODEL": str(model_path),
            "MEETING_ASSISTANT_SCREEN_RECORDING_PERMISSION": "unknown",
            "MEETING_ASSISTANT_MICROPHONE_PERMISSION": "granted",
            "PYTHONPATH": f"{ROOT / 'platform/processing-cli/src'}{os.pathsep}{env.get('PYTHONPATH', '')}",
        }
    )
    completed = subprocess.run(
        [
            PYTHON,
            "-m",
            "meeting_assistant_cli",
            "check_dependencies",
            "--workspace-dir",
            str(workspace),
            "--format",
            "json",
        ],
        cwd=ROOT,
        env=env,
        text=True,
        capture_output=True,
        check=False,
    )
    if completed.returncode != 0:
        raise AssertionError(
            f"check_dependencies: expected exit 0 in isolated fake env, got {completed.returncode}\n"
            f"stdout={completed.stdout}\nstderr={completed.stderr}"
        )
    if "Traceback" in completed.stdout or "Traceback" in completed.stderr:
        raise AssertionError("check_dependencies: response leaked a traceback")
    payload = assert_single_json(completed.stdout, "check_dependencies")
    assert_response_shape(payload, "check_dependencies", ok=True)
    checks = check_items_by_id(payload, "check_dependencies")
    expected_checks = {
        "platform.os",
        "developer_tools.swift",
        "media_tool.ffmpeg",
        "transcription.runtime",
        "transcription.model",
        "transcription.model.multilingual",
        "dependency_downloads.automatic",
    }
    missing = expected_checks - set(checks)
    if missing:
        raise AssertionError(f"check_dependencies: missing checks {sorted(missing)}")
    if checks["dependency_downloads.automatic"]["status"] != "not_attempted":
        raise AssertionError("check_dependencies: automatic dependency downloads must be not_attempted")
    if checks["dependency_downloads.automatic"]["ok"] is not True:
        raise AssertionError("check_dependencies: no-auto-download check must be ok")
    if checks["transcription.model.multilingual"]["status"] != "reported":
        raise AssertionError("check_dependencies: fake multilingual model preflight drifted")
    if workspace.exists() and not workspace.is_dir():
        raise AssertionError("check_dependencies: workspace path must not be replaced by a file")


def load_json(path: Path) -> dict:
    payload = json.loads(path.read_text(encoding="utf-8"))
    if not isinstance(payload, dict):
        raise AssertionError(f"{path}: expected JSON object")
    return payload


def assert_within(base: Path, candidate: Path, label: str) -> None:
    try:
        candidate.resolve(strict=False).relative_to(base.resolve(strict=False))
    except ValueError as exc:
        raise AssertionError(f"{label}: path {candidate} escapes {base}") from exc


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


def assert_artifact_schema(session_dir: Path, artifact: dict, artifact_type: str) -> Path:
    required = {"id", "session_id", "artifact_type", "path", "format", "capture_status", "created_at"}
    missing = required - set(artifact)
    if missing:
        raise AssertionError(f"{artifact_type}: artifact missing keys {sorted(missing)}")
    if artifact["artifact_type"] != artifact_type:
        raise AssertionError(f"{artifact_type}: got artifact_type={artifact['artifact_type']!r}")
    artifact_path = Path(str(artifact["path"]))
    assert_within(session_dir, artifact_path, f"{artifact_type} artifact")
    if artifact["capture_status"] in {"available", "degraded"}:
        assert_managed_regular_file(artifact_path, f"{artifact_type} artifact")
        if "checksum" not in artifact:
            raise AssertionError(f"{artifact_type}: available artifact must include checksum")
        if not str(artifact["checksum"]).startswith("sha256:"):
            raise AssertionError(f"{artifact_type}: checksum must use sha256 prefix")
        if sha256(artifact_path) != artifact["checksum"]:
            raise AssertionError(f"{artifact_type}: checksum mismatch")
    return artifact_path


def artifact_by_type(session: dict, artifact_type: str) -> dict:
    matches = [artifact for artifact in session.get("artifacts", []) if artifact.get("artifact_type") == artifact_type]
    if len(matches) != 1:
        raise AssertionError(f"expected exactly one {artifact_type} artifact, got {len(matches)}")
    return matches[0]


with tempfile.TemporaryDirectory(prefix="meeting-assistant-p2c-") as tmp:
    root = Path(tmp)
    workspace = root / "workspace"
    check_workspace = root / "dependency-check-workspace"
    bin_dir = root / "fake-bin"
    model_path = bin_dir / "ggml-large-v3-turbo-q5_0.bin"
    fixture = root / "fixtures" / "p2c-import.wav"
    export_target = root / "exports" / "transcript.md"
    export_target.parent.mkdir(parents=True)
    bin_dir.mkdir()
    write_fake_executable(bin_dir, "swift")
    write_fake_executable(bin_dir, "ffmpeg")
    write_fake_executable(bin_dir, "whisper-local")
    model_path.write_bytes(b"fake local multilingual model")
    write_fixture_wav(fixture)
    fixture_checksum = sha256(fixture)

    run_check_dependencies_smoke(check_workspace, bin_dir, model_path)
    evidence_marker("no-auto-download dependency preflight verified")

    invalid_delete = run_cli(
        workspace,
        ["delete_session", "--session-id", "../outside", "--workspace-dir", str(workspace), "--confirm", "true"],
        expected_exit=2,
        command="delete_session",
    )
    assert_response_shape(invalid_delete, "delete_session", ok=False, code="invalid_input")
    if workspace.exists():
        raise AssertionError("delete_session invalid path traversal: workspace should not be created")
    evidence_marker("invalid delete exit-code path verified")

    import_response = run_cli(
        workspace,
        ["import_media", "--path", str(fixture), "--title", "P2-C deterministic fixture"],
        expected_exit=0,
        command="import_media",
    )
    assert_response_shape(import_response, "import_media", ok=True)
    if import_response["source_type"] != "imported_media":
        raise AssertionError("import_media: success response source_type drifted")
    session_id = str(import_response["session_id"])
    session_dir = workspace / "sessions" / session_id
    assert_native_readable_session_file(session_dir)
    session = load_json(session_dir / "session.json")
    if session["id"] != session_id or session["source_type"] != "imported_media":
        raise AssertionError("import_media: session metadata drifted")
    if session["workspace_dir"] != str(session_dir.resolve(strict=False)):
        raise AssertionError("import_media: workspace_dir must point to the session directory")
    mixed_artifact = assert_artifact_schema(session_dir, import_response["artifacts"][0], "mixed_audio")
    mixed_checksum = sha256(mixed_artifact)
    if sha256(fixture) != fixture_checksum:
        raise AssertionError("import_media: source fixture checksum changed")
    for derived_name in ("normalized_audio.wav", "transcript.json", "speaker_labels.json"):
        if (session_dir / "artifacts" / derived_name).exists():
            raise AssertionError(f"import_media: unexpected derived artifact {derived_name}")
    assert_no_temp_leftovers(session_dir)
    evidence_marker("import source/artifact checksum verified")

    transcript_response = run_cli(
        workspace,
        ["generate_transcript", "--session-id", session_id, "--language", "zh"],
        expected_exit=0,
        command="generate_transcript",
    )
    assert_response_shape(transcript_response, "generate_transcript", ok=True)
    if transcript_response["segment_count"] < 1:
        raise AssertionError("generate_transcript: expected at least one segment")
    session = load_json(session_dir / "session.json")
    assert_native_readable_session_file(session_dir)
    normalized_artifact = artifact_by_type(session, "normalized_audio")
    transcript_artifact = artifact_by_type(session, "transcript_text")
    normalized_path = assert_artifact_schema(session_dir, normalized_artifact, "normalized_audio")
    transcript_path = assert_artifact_schema(session_dir, transcript_artifact, "transcript_text")
    transcript = load_json(transcript_path)
    if transcript["id"] != transcript_response["transcript_id"]:
        raise AssertionError("generate_transcript: transcript_id mismatch")
    if transcript["session_id"] != session_id:
        raise AssertionError("generate_transcript: transcript session_id mismatch")
    if transcript["source_artifact_id"] != normalized_artifact["id"]:
        raise AssertionError("generate_transcript: transcript must source normalized_audio")
    previous = None
    for segment in transcript["segments"]:
        if not str(segment.get("segment_id", "")).startswith("segment-"):
            raise AssertionError("generate_transcript: segment_id must be stable and present")
        if segment["start_ms"] >= segment["end_ms"] or not str(segment["text"]).strip():
            raise AssertionError("generate_transcript: invalid segment")
        current = (segment["start_ms"], segment["end_ms"])
        if previous is not None and current < previous:
            raise AssertionError("generate_transcript: segments are not sorted")
        previous = current
    if "Fake transcript generated from local audio." not in transcript["segments"][0]["text"]:
        raise AssertionError("generate_transcript: expected deterministic fake adapter text")
    if sha256(fixture) != fixture_checksum or sha256(mixed_artifact) != mixed_checksum:
        raise AssertionError("generate_transcript: original media checksum changed")
    if normalized_path.read_bytes() != mixed_artifact.read_bytes():
        raise AssertionError("generate_transcript: fixture normalizer should copy WAV/PCM input")
    assert_no_temp_leftovers(session_dir)
    evidence_marker("transcript/normalized artifact verified")

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
        expected_exit=0,
        command="generate_speaker_labels",
    )
    assert_response_shape(speaker_response, "generate_speaker_labels", ok=True)
    if speaker_response["label_status"] != "transcript_only":
        raise AssertionError("generate_speaker_labels: fake/local smoke must use transcript-only fallback")
    session = load_json(session_dir / "session.json")
    assert_native_readable_session_file(session_dir)
    speaker_artifact = artifact_by_type(session, "speaker_labels")
    speaker_path = assert_artifact_schema(session_dir, speaker_artifact, "speaker_labels")
    speaker_payload = load_json(speaker_path)
    if speaker_payload["transcript_id"] != transcript["id"] or speaker_payload["labels"] != []:
        raise AssertionError("generate_speaker_labels: fallback payload drifted")
    if speaker_payload["segment_mapping"] != [] or not speaker_payload.get("degradation_reason"):
        raise AssertionError("generate_speaker_labels: fallback must be explicit")
    if "Fake transcript generated from local audio." in json.dumps(speaker_payload, ensure_ascii=False):
        raise AssertionError("generate_speaker_labels: speaker payload must not copy transcript text")
    if sha256(fixture) != fixture_checksum or sha256(mixed_artifact) != mixed_checksum:
        raise AssertionError("generate_speaker_labels: original media checksum changed")
    assert_no_temp_leftovers(session_dir)
    evidence_marker("speaker transcript-only fallback/no-auto-upload boundary verified")

    export_response = run_cli(
        workspace,
        [
            "export_transcript",
            "--session-id",
            session_id,
            "--export-type",
            "markdown",
            "--target-path",
            str(export_target),
        ],
        expected_exit=0,
        command="export_transcript",
    )
    assert_response_shape(export_response, "export_transcript", ok=True)
    if Path(str(export_response["target_path"])) != export_target.resolve(strict=False):
        raise AssertionError("export_transcript: target_path mismatch")
    try:
        export_target.resolve(strict=False).relative_to(workspace.resolve(strict=False))
        raise AssertionError("export_transcript: target_path should be workspace-external in this smoke")
    except ValueError:
        pass
    exported_text = export_target.read_text(encoding="utf-8")
    if not exported_text.startswith("# Transcript") or "Fake transcript generated from local audio." not in exported_text:
        raise AssertionError("export_transcript: markdown content drifted")
    session = load_json(session_dir / "session.json")
    assert_native_readable_session_file(session_dir)
    exports = session.get("exports", [])
    if len(exports) != 1 or exports[0]["path"] != str(export_target.resolve(strict=False)):
        raise AssertionError("export_transcript: session export summary missing")
    if sha256(fixture) != fixture_checksum or sha256(mixed_artifact) != mixed_checksum:
        raise AssertionError("export_transcript: original media checksum changed")
    assert_no_temp_leftovers(session_dir)

    existing_export_conflict = run_cli(
        workspace,
        [
            "export_transcript",
            "--session-id",
            session_id,
            "--export-type",
            "markdown",
            "--target-path",
            str(export_target),
        ],
        expected_exit=3,
        command="export_transcript",
    )
    assert_response_shape(existing_export_conflict, "export_transcript", ok=False, code="path_conflict")
    if export_target.read_text(encoding="utf-8") != exported_text:
        raise AssertionError("export_transcript existing target: target must not be overwritten")
    if not session_dir.exists():
        raise AssertionError("export_transcript existing target: session must remain")
    assert_no_temp_leftovers(session_dir)
    evidence_marker("export conflict/retention verified")

    declined_delete = run_cli(
        workspace,
        ["delete_session", "--session-id", session_id, "--workspace-dir", str(workspace), "--confirm", "false"],
        expected_exit=2,
        command="delete_session",
    )
    assert_response_shape(declined_delete, "delete_session", ok=False, code="invalid_input")
    if not session_dir.exists():
        raise AssertionError("delete_session confirm=false: session must remain")

    delete_response = run_cli(
        workspace,
        ["delete_session", "--session-id", session_id, "--workspace-dir", str(workspace), "--confirm", "true"],
        expected_exit=0,
        command="delete_session",
    )
    assert_response_shape(delete_response, "delete_session", ok=True)
    if delete_response["deleted"] is not True or session_dir.exists():
        raise AssertionError("delete_session: session directory must be deleted")
    if not export_target.is_file():
        raise AssertionError("delete_session: workspace-external export must be retained")
    if sha256(fixture) != fixture_checksum:
        raise AssertionError("delete_session: original import source checksum changed")
    for expected_item in (
        "session.json",
        "artifacts/mixed_audio.wav",
        "artifacts/normalized_audio.wav",
        "artifacts/transcript.json",
        "artifacts/speaker_labels.json",
    ):
        if expected_item not in delete_response["deleted_items"]:
            raise AssertionError(f"delete_session: missing deleted item summary {expected_item}")
    for deleted_item in delete_response["deleted_items"]:
        item_path = Path(str(deleted_item))
        if item_path.is_absolute() or ".." in item_path.parts:
            raise AssertionError(f"delete_session: deleted item must be relative and contained: {deleted_item}")
    if str(export_target.resolve(strict=False)) not in delete_response["retained_external_exports"]:
        raise AssertionError("delete_session: retained external export summary missing")

    event_path = workspace / "events" / "meeting_session.deleted.v1.jsonl"
    events = [json.loads(line) for line in event_path.read_text(encoding="utf-8").splitlines() if line.strip()]
    if len(events) != 1:
        raise AssertionError("delete_session: expected one workspace-level delete event")
    event = events[0]
    if event["event_name"] != "meeting_session.deleted.v1" or event["session_id"] != session_id:
        raise AssertionError("delete_session: delete event identity drifted")
    result = event["result"]
    if result["deleted"] is not True or str(export_target.resolve(strict=False)) not in result["retained_external_exports"]:
        raise AssertionError("delete_session: delete event summary drifted")
    event_json = json.dumps(event, ensure_ascii=False, sort_keys=True)
    if "Fake transcript generated from local audio." in event_json:
        raise AssertionError("delete_session: event must not include transcript content")
    for deleted_item in result["deleted_items"]:
        item_path = Path(str(deleted_item))
        if item_path.is_absolute() or ".." in item_path.parts:
            raise AssertionError(f"delete_session event: deleted item must be relative and contained: {deleted_item}")
    evidence_marker("delete retention/event verified")

print("p2-c processing local e2e smoke passed.")
PY
