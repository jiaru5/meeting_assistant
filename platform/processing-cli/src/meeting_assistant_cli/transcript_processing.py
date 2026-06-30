from __future__ import annotations

import json
import os
import uuid
from datetime import datetime
from pathlib import Path
from typing import Callable, Optional

from .audio_processing import run_audio_normalization
from .settings import default_workspace
from .transcription_runtime_config import SUPPORTED_TRANSCRIPTION_RUNTIME
from .whisper_cpp_adapter import validate_whisper_cpp_config, whisper_cpp_transcript_adapter
from .workspace_contract import (
    ContractError,
    ORIGINAL_MEDIA_ARTIFACT_TYPES,
    acquire_session_lock,
    artifact_file_path,
    load_session,
    prepare_managed_output_path,
    register_artifact,
    session_directory,
    utc_timestamp,
    verify_registered_artifacts,
    write_session,
)


TRANSCRIPTION_INPUT_TYPES = {"normalized_audio", "mixed_audio", "system_audio", "microphone_audio"}


TranscriptAdapter = Callable[[Path, Optional[str], Optional[str]], list[dict]]


def _request_id() -> str:
    return f"local-{uuid.uuid4()}"


def _failure_response(
    code: str,
    message: str,
    *,
    request_id: str,
    details: dict[str, object] | None = None,
) -> dict:
    response: dict[str, object] = {
        "ok": False,
        "request_id": request_id,
        "command": "generate_transcript",
        "code": code,
        "message": message,
        "warnings": [],
        "details": details or {},
    }
    return response


def _success_response(
    *,
    request_id: str,
    session_id: str,
    artifact: dict,
    reused: bool = False,
) -> dict:
    response: dict[str, object] = {
        "ok": True,
        "request_id": request_id,
        "command": "generate_transcript",
        "session_id": session_id,
        "artifacts": [artifact],
        "warnings": [],
    }
    transcript_path = Path(str(artifact["path"]))
    payload = json.loads(transcript_path.read_text(encoding="utf-8"))
    response["transcript_id"] = payload["id"]
    response["artifact_id"] = artifact["id"]
    response["segment_count"] = len(payload.get("segments", []))
    if reused:
        response["reused"] = True
        response["warnings"] = ["transcript_text already exists; existing transcript artifact was reused."]
    return response


def _append_processing_log(session_dir: Path, *, request_id: str, code: str, message: str) -> Path:
    log_path = prepare_managed_output_path(
        session_dir,
        Path("logs/processing.log"),
        "Processing log path conflicts with the session boundary.",
        create_parent=True,
    )
    line = f"{utc_timestamp()} request_id={request_id} command=generate_transcript code={code} message={message}\n"
    with log_path.open("a", encoding="utf-8") as handle:
        handle.write(line)
    return log_path


def _record_processing_failure(
    session_dir: Path,
    *,
    request_id: str,
    code: str,
    message: str,
    details: dict[str, object],
) -> tuple[str, str, dict[str, object]]:
    try:
        log_path = _append_processing_log(session_dir, request_id=request_id, code=code, message=message)
    except ContractError as exc:
        return exc.code, exc.message, dict(exc.details)
    details["log_path"] = str(log_path)
    return code, message, details


def _normalization_failure_code(code: str) -> str:
    if code in {"artifact_missing", "not_found"}:
        return "artifact_missing"
    if code in {"invalid_input", "path_conflict", "permission_denied"}:
        return code
    return "processing_failed"


def _find_artifact(session_dir: Path, artifact_id: str) -> dict:
    session = load_session(session_dir)
    for artifact in session.get("artifacts", []):
        if artifact.get("id") == artifact_id:
            return artifact
    raise ContractError("artifact_missing", "Requested source artifact was not found.", artifact_id=artifact_id)


def _available_artifact(session_dir: Path, artifact: dict) -> Path:
    if artifact.get("capture_status") not in {"available", "degraded"}:
        raise ContractError("artifact_missing", "Requested artifact is not available.", artifact_id=artifact.get("id"))
    path = artifact_file_path(session_dir, artifact)
    if not path.is_file():
        raise ContractError("artifact_missing", "Requested artifact file was not found.", artifact_id=artifact.get("id"))
    return path


def _normalized_audio_artifact(session_dir: Path) -> dict | None:
    session = load_session(session_dir)
    for artifact in session.get("artifacts", []):
        if artifact.get("artifact_type") != "normalized_audio":
            continue
        _available_artifact(session_dir, artifact)
        verify_registered_artifacts(session_dir, {"normalized_audio"})
        return artifact
    return None


def _select_transcription_input(
    session_id: str,
    session_dir: Path,
    *,
    workspace: Path,
    source_artifact_id: str | None,
    request_id: str,
    clock: Callable[[], datetime] | None,
) -> dict:
    if source_artifact_id is not None:
        requested = _find_artifact(session_dir, source_artifact_id)
        artifact_type = requested.get("artifact_type")
        if artifact_type == "normalized_audio":
            _available_artifact(session_dir, requested)
            verify_registered_artifacts(session_dir, {"normalized_audio"})
            return requested
        if artifact_type not in TRANSCRIPTION_INPUT_TYPES:
            raise ContractError("artifact_missing", "Requested artifact is not a usable transcription input.", artifact_id=source_artifact_id)
        normalized = run_audio_normalization(
            session_id,
            workspace=workspace,
            source_artifact_id=source_artifact_id,
            request_id=request_id,
            clock=clock,
        )
        if not normalized["ok"]:
            raise ContractError(
                _normalization_failure_code(str(normalized.get("code", "processing_failed"))),
                str(normalized.get("message", "Audio normalization failed.")),
                source_artifact_id=source_artifact_id,
            )
        return normalized["artifacts"][0]

    existing = _normalized_audio_artifact(session_dir)
    if existing is not None:
        return existing

    normalized = run_audio_normalization(session_id, workspace=workspace, request_id=request_id, clock=clock)
    if not normalized["ok"]:
        raise ContractError(
            _normalization_failure_code(str(normalized.get("code", "processing_failed"))),
            str(normalized.get("message", "Audio normalization failed.")),
        )
    return normalized["artifacts"][0]


def _fake_transcript_adapter(audio_path: Path, language: str | None, runtime: str | None) -> list[dict]:
    if runtime:
        validate_whisper_cpp_config(runtime)
        raise ContractError(
            "processing_failed",
            "Explicit transcription runtime selection cannot use the fake adapter.",
            runtime=runtime,
        )
    if not audio_path.is_file():
        raise ContractError("artifact_missing", "Transcription input audio file was not found.", path=str(audio_path))
    text = "Fake transcript generated from local audio."
    if language:
        text = f"{text} Language hint: {language}."
    return [
        {
            "segment_id": "segment-0001",
            "start_ms": 0,
            "end_ms": 1000,
            "text": text,
        }
    ]


def _normalized_segments(raw_segments: list[dict]) -> list[dict]:
    segments = sorted(raw_segments, key=lambda segment: (int(segment.get("start_ms", -1)), int(segment.get("end_ms", -1))))
    if not segments:
        raise ContractError("processing_failed", "Transcription adapter did not return any segments.")
    for index, segment in enumerate(segments, start=1):
        start_ms = segment.get("start_ms")
        end_ms = segment.get("end_ms")
        text = str(segment.get("text", "")).strip()
        if not isinstance(start_ms, int) or not isinstance(end_ms, int) or start_ms >= end_ms or not text:
            raise ContractError("processing_failed", "Transcription adapter returned invalid transcript segments.")
        segment.setdefault("segment_id", f"segment-{index:04d}")
        segment["text"] = text
    return segments


def _transcript_payload(
    *,
    session_id: str,
    source_artifact_id: str,
    segments: list[dict],
    language: str | None,
    clock: Callable[[], datetime] | None,
) -> dict:
    payload: dict[str, object] = {
        "id": f"transcript-{uuid.uuid4()}",
        "session_id": session_id,
        "source_artifact_id": source_artifact_id,
        "status": "succeeded",
        "segments": segments,
        "created_at": utc_timestamp(clock),
    }
    if language:
        payload["language"] = language
    return payload


def _validate_transcript_payload(payload: dict) -> None:
    required = {"id", "session_id", "source_artifact_id", "segments", "created_at"}
    if required - set(payload):
        raise ContractError("processing_failed", "Transcript payload is missing required fields.")
    segments = payload.get("segments")
    if not isinstance(segments, list) or not segments:
        raise ContractError("processing_failed", "Transcript payload is missing transcript segments.")
    previous: tuple[int, int] | None = None
    for segment in segments:
        start_ms = segment.get("start_ms") if isinstance(segment, dict) else None
        end_ms = segment.get("end_ms") if isinstance(segment, dict) else None
        text = str(segment.get("text", "")).strip() if isinstance(segment, dict) else ""
        if not isinstance(start_ms, int) or not isinstance(end_ms, int) or start_ms >= end_ms or not text:
            raise ContractError("processing_failed", "Transcript payload includes invalid transcript segments.")
        current = (start_ms, end_ms)
        if previous is not None and current < previous:
            raise ContractError("processing_failed", "Transcript payload segments are not sorted by time.")
        previous = current


def _existing_transcript(session_dir: Path, source_artifact_id: str | None, *, language: str | None = None) -> dict | None:
    session = load_session(session_dir)
    for artifact in session.get("artifacts", []):
        if artifact.get("artifact_type") != "transcript_text":
            continue
        verify_registered_artifacts(session_dir, {"transcript_text"})
        path = _available_artifact(session_dir, artifact)
        payload = json.loads(path.read_text(encoding="utf-8"))
        _validate_transcript_payload(payload)
        if source_artifact_id is not None and payload.get("source_artifact_id") != source_artifact_id:
            raise ContractError(
                "processing_failed",
                "transcript_text already exists for a different source artifact; replace policy is not defined in this slice.",
                source_artifact_id=source_artifact_id,
                existing_artifact_id=artifact.get("id"),
            )
        existing_language = payload.get("language")
        if existing_language != language:
            raise ContractError(
                "processing_failed",
                "transcript_text already exists for a different language hint; replace policy is not defined in this slice.",
                language=language or "",
                existing_language=str(existing_language or ""),
                existing_artifact_id=artifact.get("id"),
            )
        return artifact
    return None


def _matching_transcript(session_dir: Path, source_artifact_id: str, *, language: str | None = None) -> dict | None:
    session = load_session(session_dir)
    for artifact in session.get("artifacts", []):
        if artifact.get("artifact_type") != "transcript_text":
            continue
        verify_registered_artifacts(session_dir, {"transcript_text"})
        path = _available_artifact(session_dir, artifact)
        payload = json.loads(path.read_text(encoding="utf-8"))
        _validate_transcript_payload(payload)
        if payload.get("source_artifact_id") == source_artifact_id and payload.get("language") == language:
            return artifact
    return None


def _reject_existing_transcript_for_runtime(session_dir: Path, runtime: str) -> None:
    session = load_session(session_dir)
    for artifact in session.get("artifacts", []):
        if artifact.get("artifact_type") != "transcript_text":
            continue
        verify_registered_artifacts(session_dir, {"transcript_text"})
        path = _available_artifact(session_dir, artifact)
        payload = json.loads(path.read_text(encoding="utf-8"))
        _validate_transcript_payload(payload)
        raise ContractError(
            "processing_failed",
            "transcript_text already exists but runtime metadata is not available; replace policy is not defined in this slice.",
            runtime=runtime,
            existing_artifact_id=artifact.get("id"),
        )


def _remove_registered_artifact(session_dir: Path, artifact_id: str) -> None:
    session = load_session(session_dir)
    artifacts = [artifact for artifact in session.get("artifacts", []) if artifact.get("id") != artifact_id]
    if len(artifacts) == len(session.get("artifacts", [])):
        return
    session["artifacts"] = artifacts
    session["updated_at"] = utc_timestamp()
    write_session(session_dir, session)


def run_generate_transcript(
    session_id: str,
    *,
    workspace: Path | None = None,
    source_artifact_id: str | None = None,
    language: str | None = None,
    runtime: str | None = None,
    adapter: TranscriptAdapter | None = None,
    request_id: str | None = None,
    clock: Callable[[], datetime] | None = None,
) -> dict:
    assigned_request_id = request_id or _request_id()
    workspace_path = (workspace or default_workspace()).expanduser()
    session_dir: Path | None = None
    destination: Path | None = None
    temp_path: Path | None = None
    registered_artifact_id: str | None = None
    destination_written = False

    try:
        if runtime and runtime != SUPPORTED_TRANSCRIPTION_RUNTIME:
            validate_whisper_cpp_config(runtime)
        session_dir = session_directory(workspace_path, session_id)
        load_session(session_dir)
        if runtime:
            validate_whisper_cpp_config(runtime)
            _reject_existing_transcript_for_runtime(session_dir, runtime)
        if source_artifact_id is None:
            existing_default = _existing_transcript(session_dir, None, language=language)
            if existing_default is not None:
                return _success_response(
                    request_id=assigned_request_id,
                    session_id=session_id,
                    artifact=existing_default,
                    reused=True,
                )
        else:
            existing_requested_source = _matching_transcript(session_dir, source_artifact_id, language=language)
            if existing_requested_source is not None:
                return _success_response(
                    request_id=assigned_request_id,
                    session_id=session_id,
                    artifact=existing_requested_source,
                    reused=True,
                )
        source = _select_transcription_input(
            session_id,
            session_dir,
            workspace=workspace_path,
            source_artifact_id=source_artifact_id,
            request_id=assigned_request_id,
            clock=clock,
        )
        source_path = artifact_file_path(session_dir, source)

        with acquire_session_lock(session_dir):
            try:
                verify_registered_artifacts(session_dir, ORIGINAL_MEDIA_ARTIFACT_TYPES | {"normalized_audio"})
                if runtime:
                    _reject_existing_transcript_for_runtime(session_dir, runtime)
                existing = _existing_transcript(session_dir, str(source.get("id")), language=language)
                if existing is not None:
                    return _success_response(request_id=assigned_request_id, session_id=session_id, artifact=existing, reused=True)
                selected_adapter = adapter or (whisper_cpp_transcript_adapter if runtime else _fake_transcript_adapter)
                segments = _normalized_segments(selected_adapter(source_path, language, runtime))
                payload = _transcript_payload(
                    session_id=session_id,
                    source_artifact_id=str(source.get("id")),
                    segments=segments,
                    language=language,
                    clock=clock,
                )
                destination = prepare_managed_output_path(
                    session_dir,
                    Path("artifacts/transcript.json"),
                    "Transcript artifact path conflicts with the session boundary.",
                )
                temp_path = prepare_managed_output_path(
                    session_dir,
                    Path("artifacts/.transcript.json.tmp"),
                    "Transcript temporary artifact path conflicts with the session boundary.",
                )
                if destination.exists():
                    raise ContractError(
                        "path_conflict",
                        "Unregistered transcript.json already exists; refusing to overwrite it.",
                        path=str(destination),
                    )
                temp_path.write_text(json.dumps(payload, ensure_ascii=False, indent=2, sort_keys=True) + "\n", encoding="utf-8")
                os.replace(temp_path, destination)
                destination_written = True
                artifact = register_artifact(
                    session_dir,
                    artifact_type="transcript_text",
                    path=Path("artifacts/transcript.json"),
                    file_format="json",
                    artifact_id=f"artifact-{uuid.uuid4()}",
                    clock=clock,
                )
                registered_artifact_id = str(artifact["id"])
                verify_registered_artifacts(session_dir, ORIGINAL_MEDIA_ARTIFACT_TYPES | {"normalized_audio", "transcript_text"})
                destination_written = False
            except Exception:
                if registered_artifact_id is not None:
                    _remove_registered_artifact(session_dir, registered_artifact_id)
                    registered_artifact_id = None
                if temp_path is not None:
                    temp_path.unlink(missing_ok=True)
                if destination is not None and destination_written:
                    destination.unlink(missing_ok=True)
                    destination_written = False
                raise

        return _success_response(request_id=assigned_request_id, session_id=session_id, artifact=artifact)
    except ContractError as exc:
        details: dict[str, object] = dict(exc.details)
        code = exc.code
        message = exc.message
        if session_dir is not None and exc.code != "not_found":
            if registered_artifact_id is not None:
                _remove_registered_artifact(session_dir, registered_artifact_id)
            if temp_path is not None:
                temp_path.unlink(missing_ok=True)
            if destination is not None and destination_written:
                destination.unlink(missing_ok=True)
            code, message, details = _record_processing_failure(
                session_dir,
                request_id=assigned_request_id,
                code=code,
                message=message,
                details=details,
            )
        return _failure_response(code, message, request_id=assigned_request_id, details=details or None)
    except Exception as exc:
        message = f"Transcript generation failed: {exc}" if str(exc) else "Transcript generation failed."
        code = "processing_failed"
        details = {"error": exc.__class__.__name__, "error_message": str(exc)}
        if session_dir is not None:
            if registered_artifact_id is not None:
                _remove_registered_artifact(session_dir, registered_artifact_id)
            if temp_path is not None:
                temp_path.unlink(missing_ok=True)
            if destination is not None and destination_written:
                destination.unlink(missing_ok=True)
            code, message, details = _record_processing_failure(
                session_dir,
                request_id=assigned_request_id,
                code="processing_failed",
                message=message,
                details=details,
            )
        return _failure_response(code, message, request_id=assigned_request_id, details=details)


generate_transcript = run_generate_transcript
