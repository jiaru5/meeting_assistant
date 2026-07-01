#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
cd "$ROOT_DIR"

PYTHONDONTWRITEBYTECODE=1 \
PYTHONPATH="$ROOT_DIR/platform/processing-cli/src${PYTHONPATH:+:$PYTHONPATH}" \
python3 - <<'PY'
from __future__ import annotations

import json
import os
import stat
import subprocess
import sys
import tempfile
import wave
from pathlib import Path

from meeting_assistant_cli.workspace_contract import (
    acquire_session_lock,
    create_session,
    load_session,
    register_artifact,
    session_directory,
    sha256_file,
)


ROOT = Path.cwd()
PYTHON = sys.executable
CLI_ENV_BASE = os.environ.copy()
TRANSCRIPTION_ENV_NAMES = (
    "MEETING_ASSISTANT_TRANSCRIPTION_RUNTIME",
    "MEETING_ASSISTANT_TRANSCRIPTION_MODEL",
    "MEETING_ASSISTANT_WHISPER_SMOKE_AUDIO",
)


def write_fixture_wav(path: Path, seed: int) -> None:
    path.parent.mkdir(parents=True, exist_ok=True)
    frames = bytearray()
    for index in range(2400):
        sample = (((index + seed) % 96) - 48) * 96
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


def assert_single_json(stdout: str, command: str) -> dict:
    lines = [line for line in stdout.splitlines() if line.strip()]
    if len(lines) != 1:
        raise AssertionError(f"{command}: expected one JSON object, got {len(lines)} lines: {stdout!r}")
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


def assert_json_does_not_contain(payload: object, forbidden: str, label: str) -> None:
    if forbidden and forbidden in json.dumps(payload, ensure_ascii=False, sort_keys=True):
        raise AssertionError(f"{label}: response must not contain transcript content")


def run_cli(workspace: Path, args: list[str], *, expected_exit: int, command: str) -> dict:
    env = CLI_ENV_BASE.copy()
    for env_name in TRANSCRIPTION_ENV_NAMES:
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


def run_isolated_dependency_smoke(workspace: Path, bin_dir: Path, model_path: Path) -> None:
    env = CLI_ENV_BASE.copy()
    for env_name in TRANSCRIPTION_ENV_NAMES:
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
    if checks["dependency_downloads.automatic"]["status"] != "not_attempted":
        raise AssertionError("check_dependencies: automatic dependency downloads must be not_attempted")
    if checks["dependency_downloads.automatic"]["ok"] is not True:
        raise AssertionError("check_dependencies: no-auto-download check must be ok")
    runtime_details = checks["transcription.runtime"].get("details", {})
    model_details = checks["transcription.model"].get("details", {})
    if not isinstance(runtime_details, dict) or not isinstance(model_details, dict):
        raise AssertionError("check_dependencies: runtime/model diagnostics must include details")
    runtime_path = Path(str(runtime_details.get("path", ""))).resolve(strict=False)
    if runtime_path != (bin_dir / "whisper-local").resolve(strict=False):
        raise AssertionError("check_dependencies: transcription runtime must come from the isolated fake env")
    model_check_path = Path(str(model_details.get("path", ""))).resolve(strict=False)
    if model_check_path != model_path.resolve(strict=False):
        raise AssertionError("check_dependencies: transcription model must come from the isolated fake env")
    if "MEETING_ASSISTANT_WHISPER_SMOKE_AUDIO" in env:
        raise AssertionError("check_dependencies: smoke audio env must be absent in this no-auto-download proof")


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


def assert_session_identity(session_dir: Path, *, session_id: str) -> dict:
    assert_managed_regular_file(session_dir / "session.json", "session.json")
    session = load_json(session_dir / "session.json")
    if session["id"] != session_id:
        raise AssertionError("session.json: session id drifted")
    if session["source_type"] != "native_recording":
        raise AssertionError("session.json: source_type must stay native_recording")
    if session["status"] != "recorded":
        raise AssertionError("session.json: status must stay recorded in this processing smoke")
    if session["workspace_dir"] != str(session_dir.resolve(strict=False)):
        raise AssertionError("session.json: workspace_dir must point to the session directory")
    return session


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
            raise AssertionError(f"{artifact_type}: available/degraded artifact must include checksum")
        if not str(artifact["checksum"]).startswith("sha256:"):
            raise AssertionError(f"{artifact_type}: checksum must use sha256 prefix")
        if sha256_file(artifact_path) != artifact["checksum"]:
            raise AssertionError(f"{artifact_type}: checksum mismatch")
    else:
        if not artifact.get("degradation_reason"):
            raise AssertionError(f"{artifact_type}: unavailable artifact must include degradation_reason")
    return artifact_path


def artifact_by_type(session: dict, artifact_type: str) -> dict:
    matches = [artifact for artifact in session.get("artifacts", []) if artifact.get("artifact_type") == artifact_type]
    if len(matches) != 1:
        raise AssertionError(f"expected exactly one {artifact_type} artifact, got {len(matches)}")
    return matches[0]


def capture_artifact_checksums(session: dict) -> dict[str, str]:
    checksums = {}
    for artifact in session.get("artifacts", []):
        if artifact.get("artifact_type") in {"screen_video", "system_audio", "microphone_audio", "mixed_audio"}:
            checksum = artifact.get("checksum")
            if checksum:
                checksums[str(artifact["artifact_type"])] = str(checksum)
    return checksums


def assert_capture_checksums_unchanged(session_dir: Path, expected: dict[str, str]) -> None:
    session = load_session(session_dir)
    for artifact_type, checksum in expected.items():
        artifact = artifact_by_type(session, artifact_type)
        artifact_path = Path(str(artifact["path"]))
        if sha256_file(artifact_path) != checksum:
            raise AssertionError(f"{artifact_type}: original capture artifact checksum changed")


def create_capture_session(
    workspace: Path,
    session_id: str,
    *,
    mixed_status: str = "available",
    system_status: str = "available",
    microphone_status: str = "available",
    mixed_seed: int = 11,
    system_seed: int = 31,
    microphone_seed: int = 53,
) -> Path:
    create_session(
        workspace,
        source_type="native_recording",
        title=f"Capture fixture {session_id}",
        session_id=session_id,
        status="recorded",
    )
    session_dir = session_directory(workspace, session_id)
    screen_path = session_dir / "artifacts" / "screen_video.mov"
    screen_path.write_bytes(b"fake native screen video container\n")
    register_artifact(
        session_dir,
        artifact_type="screen_video",
        path=Path("artifacts/screen_video.mov"),
        file_format="mov",
        artifact_id="artifact-screen_video",
    )

    audio_specs = (
        ("system_audio", "system_audio.wav", system_status, system_seed),
        ("microphone_audio", "microphone_audio.wav", microphone_status, microphone_seed),
        ("mixed_audio", "mixed_audio.wav", mixed_status, mixed_seed),
    )
    for artifact_type, file_name, capture_status, seed in audio_specs:
        artifact_path = session_dir / "artifacts" / file_name
        if capture_status in {"available", "degraded"}:
            write_fixture_wav(artifact_path, seed)
        register_artifact(
            session_dir,
            artifact_type=artifact_type,
            path=Path("artifacts") / file_name,
            file_format="wav",
            capture_status=capture_status,
            degradation_reason=(
                f"{artifact_type} was unavailable in the native capture fixture."
                if capture_status != "available"
                else None
            ),
            artifact_id=f"artifact-{artifact_type}",
        )
    return session_dir


def assert_speaker_fallback(
    session_dir: Path,
    speaker_response: dict,
    transcript: dict,
    transcript_text: str,
) -> None:
    if speaker_response["label_status"] != "transcript_only":
        raise AssertionError("generate_speaker_labels: expected transcript-only fallback")
    if not speaker_response.get("degradation_reason"):
        raise AssertionError("generate_speaker_labels: degradation_reason must be present")
    session = load_json(session_dir / "session.json")
    speaker_artifact = artifact_by_type(session, "speaker_labels")
    speaker_path = assert_artifact_schema(session_dir, speaker_artifact, "speaker_labels")
    if speaker_artifact["capture_status"] != "degraded":
        raise AssertionError("speaker_labels artifact must be degraded for transcript-only fallback")
    if not speaker_artifact.get("degradation_reason"):
        raise AssertionError("speaker_labels artifact degradation_reason must be present")
    speaker_payload = load_json(speaker_path)
    if speaker_payload["transcript_id"] != transcript["id"]:
        raise AssertionError("speaker_labels payload transcript_id drifted")
    if speaker_payload["labels"] != [] or speaker_payload["segment_mapping"] != []:
        raise AssertionError("speaker fallback must not claim speaker mappings")
    if transcript_text in json.dumps(speaker_payload, ensure_ascii=False):
        raise AssertionError("speaker fallback payload must not contain transcript text")
    for label in speaker_payload["labels"]:
        if label.get("is_verified_identity") is not False:
            raise AssertionError("speaker labels must not claim verified identity")


def exercise_default_capture_pipeline(workspace: Path, root: Path) -> None:
    session_id = "capture-default"
    session_dir = create_capture_session(workspace, session_id)
    session = assert_session_identity(session_dir, session_id=session_id)
    for artifact_type in ("screen_video", "system_audio", "microphone_audio", "mixed_audio"):
        assert_artifact_schema(session_dir, artifact_by_type(session, artifact_type), artifact_type)
    original_checksums = capture_artifact_checksums(session)
    mixed_path = Path(str(artifact_by_type(session, "mixed_audio")["path"]))
    mixed_bytes = mixed_path.read_bytes()

    transcript_response = run_cli(
        workspace,
        ["generate_transcript", "--session-id", session_id, "--language", "zh"],
        expected_exit=0,
        command="generate_transcript",
    )
    assert_response_shape(transcript_response, "generate_transcript", ok=True)
    session = assert_session_identity(session_dir, session_id=session_id)
    normalized_artifact = artifact_by_type(session, "normalized_audio")
    transcript_artifact = artifact_by_type(session, "transcript_text")
    normalized_path = assert_artifact_schema(session_dir, normalized_artifact, "normalized_audio")
    transcript_path = assert_artifact_schema(session_dir, transcript_artifact, "transcript_text")
    if normalized_path.read_bytes() != mixed_bytes:
        raise AssertionError("generate_transcript: default source must be mixed_audio")
    transcript = load_json(transcript_path)
    if transcript["id"] != transcript_response["transcript_id"]:
        raise AssertionError("generate_transcript: transcript_id mismatch")
    if transcript["source_artifact_id"] != normalized_artifact["id"]:
        raise AssertionError("generate_transcript: transcript must source normalized_audio")
    if transcript["session_id"] != session_id or transcript["status"] != "succeeded":
        raise AssertionError("generate_transcript: transcript identity/status drifted")
    transcript_text = str(transcript["segments"][0]["text"])
    if "Fake transcript generated from local audio." not in transcript_text:
        raise AssertionError("generate_transcript: expected deterministic fake adapter text")
    assert_capture_checksums_unchanged(session_dir, original_checksums)
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
        expected_exit=0,
        command="generate_speaker_labels",
    )
    assert_response_shape(speaker_response, "generate_speaker_labels", ok=True)
    assert_session_identity(session_dir, session_id=session_id)
    assert_speaker_fallback(session_dir, speaker_response, transcript, transcript_text)
    assert_capture_checksums_unchanged(session_dir, original_checksums)
    assert_no_temp_leftovers(session_dir)

    export_target = root / "exports" / "capture-default.md"
    export_target.parent.mkdir(parents=True)
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
        raise AssertionError("export_transcript: target_path should be workspace-external")
    except ValueError:
        pass
    exported_text = export_target.read_text(encoding="utf-8")
    if not exported_text.startswith("# Transcript") or transcript_text not in exported_text:
        raise AssertionError("export_transcript: markdown content drifted")
    assert_capture_checksums_unchanged(session_dir, original_checksums)

    conflict_response = run_cli(
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
    assert_response_shape(conflict_response, "export_transcript", ok=False, code="path_conflict")
    assert_json_does_not_contain(conflict_response, transcript_text, "export_transcript existing target")
    if export_target.read_text(encoding="utf-8") != exported_text:
        raise AssertionError("export_transcript existing target: target must not be overwritten")
    if not session_dir.exists():
        raise AssertionError("export_transcript existing target: session must remain")

    declined_delete = run_cli(
        workspace,
        ["delete_session", "--session-id", session_id, "--workspace-dir", str(workspace), "--confirm", "false"],
        expected_exit=2,
        command="delete_session",
    )
    assert_response_shape(declined_delete, "delete_session", ok=False, code="invalid_input")
    assert_json_does_not_contain(declined_delete, transcript_text, "delete_session confirm=false")
    if not session_dir.exists():
        raise AssertionError("delete_session confirm=false: session must remain")

    delete_response = run_cli(
        workspace,
        ["delete_session", "--session-id", session_id, "--workspace-dir", str(workspace), "--confirm", "true"],
        expected_exit=0,
        command="delete_session",
    )
    assert_response_shape(delete_response, "delete_session", ok=True)
    assert_json_does_not_contain(delete_response, transcript_text, "delete_session summary")
    if delete_response["deleted"] is not True or session_dir.exists():
        raise AssertionError("delete_session: session directory must be deleted")
    if not export_target.is_file() or export_target.read_text(encoding="utf-8") != exported_text:
        raise AssertionError("delete_session: workspace-external export must be retained")
    for deleted_item in delete_response["deleted_items"]:
        item_path = Path(str(deleted_item))
        if item_path.is_absolute() or ".." in item_path.parts:
            raise AssertionError(f"delete_session: deleted item must be relative and contained: {deleted_item}")
    for expected_item in (
        "session.json",
        "artifacts/screen_video.mov",
        "artifacts/system_audio.wav",
        "artifacts/microphone_audio.wav",
        "artifacts/mixed_audio.wav",
        "artifacts/normalized_audio.wav",
        "artifacts/transcript.json",
        "artifacts/speaker_labels.json",
    ):
        if expected_item not in delete_response["deleted_items"]:
            raise AssertionError(f"delete_session: missing deleted item summary {expected_item}")
    if str(export_target.resolve(strict=False)) not in delete_response["retained_external_exports"]:
        raise AssertionError("delete_session: retained external export summary missing")

    event_path = workspace / "events" / "meeting_session.deleted.v1.jsonl"
    events = [json.loads(line) for line in event_path.read_text(encoding="utf-8").splitlines() if line.strip()]
    if len(events) != 1:
        raise AssertionError("delete_session: expected one workspace-level delete event")
    event = events[0]
    if event["event_name"] != "meeting_session.deleted.v1" or event["session_id"] != session_id:
        raise AssertionError("delete_session: delete event identity drifted")
    event_json = json.dumps(event, ensure_ascii=False, sort_keys=True)
    if transcript_text in event_json:
        raise AssertionError("delete_session: event must not include transcript content")
    for deleted_item in event["result"]["deleted_items"]:
        item_path = Path(str(deleted_item))
        if item_path.is_absolute() or ".." in item_path.parts:
            raise AssertionError(f"delete_session event: deleted item must be relative and contained: {deleted_item}")


def exercise_fallback_capture_pipeline(
    workspace: Path,
    *,
    session_id: str,
    source_artifact_type: str,
    unavailable_peer_type: str,
) -> None:
    statuses = {
        "mixed_audio": "missing",
        "system_audio": "missing",
        "microphone_audio": "missing",
    }
    statuses[source_artifact_type] = "available"
    statuses[unavailable_peer_type] = "missing"
    session_dir = create_capture_session(
        workspace,
        session_id,
        mixed_status=statuses["mixed_audio"],
        system_status=statuses["system_audio"],
        microphone_status=statuses["microphone_audio"],
    )
    session = assert_session_identity(session_dir, session_id=session_id)
    mixed_artifact = artifact_by_type(session, "mixed_audio")
    if mixed_artifact["capture_status"] != "missing" or not mixed_artifact.get("degradation_reason"):
        raise AssertionError("fallback fixture: mixed_audio must be missing with degradation_reason")
    unavailable_peer = artifact_by_type(session, unavailable_peer_type)
    if unavailable_peer["capture_status"] != "missing" or not unavailable_peer.get("degradation_reason"):
        raise AssertionError(f"fallback fixture: {unavailable_peer_type} must be missing with degradation_reason")
    source_artifact = artifact_by_type(session, source_artifact_type)
    source_path = assert_artifact_schema(session_dir, source_artifact, source_artifact_type)
    source_bytes = source_path.read_bytes()
    original_checksums = capture_artifact_checksums(session)

    transcript_response = run_cli(
        workspace,
        [
            "generate_transcript",
            "--session-id",
            session_id,
            "--source-artifact-id",
            str(source_artifact["id"]),
        ],
        expected_exit=0,
        command="generate_transcript",
    )
    assert_response_shape(transcript_response, "generate_transcript", ok=True)
    session = assert_session_identity(session_dir, session_id=session_id)
    normalized_artifact = artifact_by_type(session, "normalized_audio")
    transcript_artifact = artifact_by_type(session, "transcript_text")
    normalized_path = assert_artifact_schema(session_dir, normalized_artifact, "normalized_audio")
    transcript_path = assert_artifact_schema(session_dir, transcript_artifact, "transcript_text")
    if normalized_path.read_bytes() != source_bytes:
        raise AssertionError(f"fallback fixture: normalized audio must come from {source_artifact_type}")
    transcript = load_json(transcript_path)
    if transcript["source_artifact_id"] != normalized_artifact["id"]:
        raise AssertionError("fallback fixture: transcript must source normalized_audio")
    assert_capture_checksums_unchanged(session_dir, original_checksums)
    assert_no_temp_leftovers(session_dir)


def exercise_path_boundary_rollback(workspace: Path, root: Path) -> None:
    session_id = "capture-rollback"
    session_dir = create_capture_session(
        workspace,
        session_id,
        system_status="missing",
        microphone_status="missing",
    )
    session = assert_session_identity(session_dir, session_id=session_id)
    original_checksums = capture_artifact_checksums(session)
    outside = root / "outside-normalized.wav"
    write_fixture_wav(outside, 89)
    outside_checksum = sha256_file(outside)
    normalized_path = session_dir / "artifacts" / "normalized_audio.wav"
    normalized_path.symlink_to(outside)

    response = run_cli(
        workspace,
        ["generate_transcript", "--session-id", session_id],
        expected_exit=3,
        command="generate_transcript",
    )
    assert_response_shape(response, "generate_transcript", ok=False, code="path_conflict")
    session = assert_session_identity(session_dir, session_id=session_id)
    artifact_types = {artifact["artifact_type"] for artifact in session.get("artifacts", [])}
    if "normalized_audio" in artifact_types or "transcript_text" in artifact_types:
        raise AssertionError("path boundary rollback: derived artifacts must not be registered")
    if (session_dir / "artifacts" / "transcript.json").exists():
        raise AssertionError("path boundary rollback: transcript.json must not be written")
    if sha256_file(outside) != outside_checksum:
        raise AssertionError("path boundary rollback: external target must not be written")
    if not normalized_path.is_symlink():
        raise AssertionError("path boundary rollback: conflicting symlink should remain for diagnosis")
    assert_capture_checksums_unchanged(session_dir, original_checksums)
    assert_no_temp_leftovers(session_dir)


def exercise_lock_conflict(workspace: Path) -> None:
    session_id = "capture-lock-conflict"
    session_dir = create_capture_session(workspace, session_id)
    original_checksums = capture_artifact_checksums(assert_session_identity(session_dir, session_id=session_id))

    with acquire_session_lock(session_dir):
        response = run_cli(
            workspace,
            ["generate_transcript", "--session-id", session_id],
            expected_exit=3,
            command="generate_transcript",
        )

    assert_response_shape(response, "generate_transcript", ok=False, code="path_conflict")
    session = assert_session_identity(session_dir, session_id=session_id)
    artifact_types = {artifact["artifact_type"] for artifact in session.get("artifacts", [])}
    if "normalized_audio" in artifact_types or "transcript_text" in artifact_types:
        raise AssertionError("lock conflict: derived artifacts must not be registered")
    if (session_dir / "artifacts" / "transcript.json").exists():
        raise AssertionError("lock conflict: transcript.json must not be written")
    assert_capture_checksums_unchanged(session_dir, original_checksums)
    assert_no_temp_leftovers(session_dir)


def exercise_temp_hardlink_rollback(workspace: Path, root: Path) -> None:
    session_id = "capture-temp-hardlink"
    session_dir = create_capture_session(
        workspace,
        session_id,
        system_status="missing",
        microphone_status="missing",
    )
    original_checksums = capture_artifact_checksums(assert_session_identity(session_dir, session_id=session_id))
    outside = root / "outside-temp-normalized.wav"
    write_fixture_wav(outside, 97)
    outside_checksum = sha256_file(outside)
    temp_path = session_dir / "artifacts" / ".normalized_audio.wav.tmp"
    os.link(outside, temp_path)

    response = run_cli(
        workspace,
        ["generate_transcript", "--session-id", session_id],
        expected_exit=3,
        command="generate_transcript",
    )

    assert_response_shape(response, "generate_transcript", ok=False, code="path_conflict")
    session = assert_session_identity(session_dir, session_id=session_id)
    artifact_types = {artifact["artifact_type"] for artifact in session.get("artifacts", [])}
    if "normalized_audio" in artifact_types or "transcript_text" in artifact_types:
        raise AssertionError("temp hardlink rollback: derived artifacts must not be registered")
    if (session_dir / "artifacts" / "normalized_audio.wav").exists() or (session_dir / "artifacts" / "transcript.json").exists():
        raise AssertionError("temp hardlink rollback: managed derived outputs must not be written")
    if sha256_file(outside) != outside_checksum:
        raise AssertionError("temp hardlink rollback: external hardlink target must not be written")
    if not temp_path.exists() or temp_path.stat().st_nlink < 2:
        raise AssertionError("temp hardlink rollback: conflicting hardlink should remain for diagnosis")
    assert_capture_checksums_unchanged(session_dir, original_checksums)


def exercise_checksum_drift(workspace: Path) -> None:
    session_id = "capture-checksum-drift"
    session_dir = create_capture_session(workspace, session_id)
    session = assert_session_identity(session_dir, session_id=session_id)
    original_checksums = capture_artifact_checksums(session)
    mixed_path = Path(str(artifact_by_type(session, "mixed_audio")["path"]))
    mixed_path.write_bytes(b"mutated capture bytes")

    response = run_cli(
        workspace,
        ["generate_transcript", "--session-id", session_id],
        expected_exit=3,
        command="generate_transcript",
    )

    assert_response_shape(response, "generate_transcript", ok=False, code="path_conflict")
    session = assert_session_identity(session_dir, session_id=session_id)
    artifact_types = {artifact["artifact_type"] for artifact in session.get("artifacts", [])}
    if "normalized_audio" in artifact_types or "transcript_text" in artifact_types:
        raise AssertionError("checksum drift: derived artifacts must not be registered")
    if (session_dir / "artifacts" / "normalized_audio.wav").exists() or (session_dir / "artifacts" / "transcript.json").exists():
        raise AssertionError("checksum drift: derived outputs must not be written")
    unchanged_types = {key: value for key, value in original_checksums.items() if key != "mixed_audio"}
    assert_capture_checksums_unchanged(session_dir, unchanged_types)


with tempfile.TemporaryDirectory(prefix="meeting-assistant-capture-processing-") as tmp:
    root = Path(tmp)
    workspace = root / "workspace"
    check_workspace = root / "dependency-check-workspace"
    bin_dir = root / "fake-bin"
    model_path = bin_dir / "ggml-large-v3-turbo-q5_0.bin"
    bin_dir.mkdir()
    write_fake_executable(bin_dir, "swift")
    write_fake_executable(bin_dir, "ffmpeg")
    write_fake_executable(bin_dir, "whisper-local")
    model_path.write_bytes(b"fake local multilingual model")

    run_isolated_dependency_smoke(check_workspace, bin_dir, model_path)
    exercise_default_capture_pipeline(workspace, root)
    exercise_fallback_capture_pipeline(
        workspace,
        session_id="capture-fallback-system",
        source_artifact_type="system_audio",
        unavailable_peer_type="microphone_audio",
    )
    exercise_fallback_capture_pipeline(
        workspace,
        session_id="capture-fallback-microphone",
        source_artifact_type="microphone_audio",
        unavailable_peer_type="system_audio",
    )
    exercise_path_boundary_rollback(workspace, root)
    exercise_lock_conflict(workspace)
    exercise_temp_hardlink_rollback(workspace, root)
    exercise_checksum_drift(workspace)

print("capture-style processing e2e smoke passed.")
PY
