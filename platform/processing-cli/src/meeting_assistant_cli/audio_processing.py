from __future__ import annotations

import os
import shutil
import uuid
import wave
from datetime import datetime
from pathlib import Path
from typing import Callable, NamedTuple

from .settings import default_workspace
from .workspace_contract import (
    ContractError,
    ORIGINAL_MEDIA_ARTIFACT_TYPES,
    acquire_session_lock,
    artifact_file_path,
    load_session,
    prepare_managed_output_path,
    register_artifact,
    session_directory,
    sha256_file,
    utc_timestamp,
    verify_registered_artifacts,
    write_session,
)


AUDIO_SOURCE_PRIORITY = ("mixed_audio", "system_audio", "microphone_audio")
USABLE_CAPTURE_STATUSES = {"available", "degraded"}


class AudioSource(NamedTuple):
    artifact: dict
    path: Path


Normalizer = Callable[[Path, Path], None]


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
        "stage": "audio_normalization",
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
    source_artifact_id: str | None,
    reused: bool = False,
) -> dict:
    response: dict[str, object] = {
        "ok": True,
        "request_id": request_id,
        "stage": "audio_normalization",
        "session_id": session_id,
        "source_artifact_id": source_artifact_id,
        "artifacts": [artifact],
        "warnings": [],
    }
    if reused:
        response["reused"] = True
        response["warnings"] = ["normalized_audio already exists; existing derived artifact was reused."]
    return response


def _append_processing_log(session_dir: Path, *, request_id: str, code: str, message: str) -> Path:
    log_path = prepare_managed_output_path(
        session_dir,
        Path("logs/processing.log"),
        "Processing log path conflicts with the session boundary.",
        create_parent=True,
    )
    line = f"{utc_timestamp()} request_id={request_id} stage=audio_normalization code={code} message={message}\n"
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


def _usable_audio_source(session_dir: Path, artifact: dict) -> AudioSource | None:
    if artifact.get("artifact_type") not in AUDIO_SOURCE_PRIORITY:
        return None
    if artifact.get("capture_status") not in USABLE_CAPTURE_STATUSES:
        return None
    path = artifact_file_path(session_dir, artifact)
    if not path.is_file():
        raise ContractError(
            "artifact_missing",
            "Selected audio artifact file was not found.",
            artifact_id=artifact.get("id"),
            path=str(path),
        )
    return AudioSource(artifact=artifact, path=path)


def _available_audio_artifact_ids(session_dir: Path, artifacts: list[dict]) -> list[str]:
    ids: list[str] = []
    for artifact in artifacts:
        try:
            source = _usable_audio_source(session_dir, artifact)
        except ContractError:
            continue
        if source is not None:
            ids.append(str(artifact.get("id")))
    return ids


def select_audio_source(session_dir: Path, source_artifact_id: str | None = None) -> AudioSource:
    session = load_session(session_dir)
    artifacts = list(session.get("artifacts", []))
    default_source: AudioSource | None = None
    for artifact in artifacts:
        if artifact.get("artifact_type") == "mixed_audio":
            source = _usable_audio_source(session_dir, artifact)
            if source is not None:
                default_source = source
                break

    if source_artifact_id:
        if default_source is not None and default_source.artifact.get("id") != source_artifact_id:
            raise ContractError(
                "path_conflict",
                "mixed_audio is available; selecting another audio source requires mixed_audio to be unavailable.",
                source_artifact_id=source_artifact_id,
                default_artifact_id=default_source.artifact.get("id"),
            )
        for artifact in artifacts:
            if artifact.get("id") == source_artifact_id:
                source = _usable_audio_source(session_dir, artifact)
                if source is None:
                    raise ContractError(
                        "artifact_missing",
                        "Requested artifact is not a usable audio source.",
                        artifact_id=source_artifact_id,
                    )
                return source
        raise ContractError("artifact_missing", "Requested source artifact was not found.", artifact_id=source_artifact_id)

    if default_source is not None:
        return default_source

    raise ContractError(
        "artifact_missing",
        "Default audio source mixed_audio was not found; select an available audio artifact explicitly.",
        required_artifact_type="mixed_audio",
        available_audio_artifact_ids=_available_audio_artifact_ids(session_dir, artifacts),
    )


def _existing_normalized_audio(session_dir: Path) -> dict | None:
    session = load_session(session_dir)
    for artifact in session.get("artifacts", []):
        if artifact.get("artifact_type") != "normalized_audio":
            continue
        if artifact.get("capture_status") not in USABLE_CAPTURE_STATUSES:
            continue
        verify_registered_artifacts(session_dir, {"normalized_audio"})
        path = artifact_file_path(session_dir, artifact)
        if not path.is_file():
            raise ContractError(
                "artifact_missing",
                "Registered normalized_audio file was not found.",
                artifact_id=artifact.get("id"),
                path=str(path),
            )
        return artifact
    return None


def _normalized_artifact_id(source_artifact_id: str) -> str:
    source_key = f"meeting-assistant:normalized_audio:{source_artifact_id}"
    return f"artifact-normalized_audio-{uuid.uuid5(uuid.NAMESPACE_URL, source_key)}"


def _ensure_existing_normalized_matches_source(session_dir: Path, existing: dict, source: AudioSource) -> None:
    normalized_path = artifact_file_path(session_dir, existing)
    normalized_checksum = existing.get("checksum") or sha256_file(normalized_path)
    source_checksum = source.artifact.get("checksum") or sha256_file(source.path)
    source_artifact_id = str(source.artifact.get("id"))
    expected_artifact_id = _normalized_artifact_id(source_artifact_id)
    available_audio_ids = _available_audio_artifact_ids(session_dir, list(load_session(session_dir).get("artifacts", [])))
    source_identity_mismatch = (
        existing.get("id") != expected_artifact_id
        and source.artifact.get("artifact_type") != "mixed_audio"
        and len(available_audio_ids) > 1
    )
    if normalized_checksum != source_checksum or source_identity_mismatch:
        raise ContractError(
            "path_conflict",
            "normalized_audio already exists for a different audio source; changing the source artifact requires an explicit replace policy.",
            source_artifact_id=source_artifact_id,
            existing_artifact_id=existing.get("id"),
        )


def _ensure_wav_pcm(path: Path) -> None:
    try:
        with wave.open(str(path), "rb") as handle:
            compression = handle.getcomptype()
    except (EOFError, wave.Error, OSError) as exc:
        raise ContractError(
            "processing_failed",
            "Audio normalization adapter requires WAV/PCM bytes in this slice.",
            path=str(path),
        ) from exc
    if compression != "NONE":
        raise ContractError(
            "processing_failed",
            "Audio normalization adapter requires PCM WAV bytes in this slice.",
            path=str(path),
            compression=compression,
        )


def _copy_normalizer(source: Path, destination: Path) -> None:
    _ensure_wav_pcm(source)
    shutil.copyfile(source, destination)


def _remove_registered_artifact(session_dir: Path, artifact_id: str) -> None:
    session = load_session(session_dir)
    artifacts = [artifact for artifact in session.get("artifacts", []) if artifact.get("id") != artifact_id]
    if len(artifacts) == len(session.get("artifacts", [])):
        return
    session["artifacts"] = artifacts
    session["updated_at"] = utc_timestamp()
    write_session(session_dir, session)


def run_audio_normalization(
    session_id: str,
    *,
    workspace: Path | None = None,
    source_artifact_id: str | None = None,
    normalizer: Normalizer | None = None,
    request_id: str | None = None,
    clock: Callable[[], datetime] | None = None,
) -> dict:
    assigned_request_id = request_id or _request_id()
    workspace_path = (workspace or default_workspace()).expanduser()
    session_dir: Path | None = None
    temp_path: Path | None = None
    destination: Path | None = None
    registered_artifact_id: str | None = None
    destination_written = False

    try:
        session_dir = session_directory(workspace_path, session_id)
        load_session(session_dir)
        with acquire_session_lock(session_dir):
            try:
                verify_registered_artifacts(session_dir, ORIGINAL_MEDIA_ARTIFACT_TYPES)
                existing = _existing_normalized_audio(session_dir)
                if existing is not None:
                    source = select_audio_source(session_dir, source_artifact_id)
                    _ensure_existing_normalized_matches_source(session_dir, existing, source)
                    return _success_response(
                        request_id=assigned_request_id,
                        session_id=session_id,
                        artifact=existing,
                        source_artifact_id=str(source.artifact.get("id")),
                        reused=True,
                    )

                source = select_audio_source(session_dir, source_artifact_id)

                destination = prepare_managed_output_path(
                    session_dir,
                    Path("artifacts/normalized_audio.wav"),
                    "normalized_audio output path conflicts with the session boundary.",
                )
                temp_path = prepare_managed_output_path(
                    session_dir,
                    Path("artifacts/.normalized_audio.wav.tmp"),
                    "normalized_audio temporary output path conflicts with the session boundary.",
                )
                if temp_path.exists():
                    temp_path.unlink()

                (normalizer or _copy_normalizer)(source.path, temp_path)
                if not temp_path.is_file():
                    raise ContractError(
                        "processing_failed",
                        "Audio normalization did not produce an output file.",
                        source_artifact_id=source.artifact.get("id"),
                    )
                _ensure_wav_pcm(temp_path)

                os.replace(temp_path, destination)
                temp_path = None
                destination_written = True
                artifact = register_artifact(
                    session_dir,
                    artifact_type="normalized_audio",
                    path=Path("artifacts/normalized_audio.wav"),
                    file_format="wav",
                    artifact_id=_normalized_artifact_id(str(source.artifact.get("id"))),
                    clock=clock,
                )
                registered_artifact_id = str(artifact["id"])
                verify_registered_artifacts(session_dir, ORIGINAL_MEDIA_ARTIFACT_TYPES)
                destination_written = False
            except Exception:
                if registered_artifact_id is not None:
                    _remove_registered_artifact(session_dir, registered_artifact_id)
                    registered_artifact_id = None
                if destination is not None and destination_written:
                    destination.unlink(missing_ok=True)
                    destination_written = False
                if temp_path is not None:
                    temp_path.unlink(missing_ok=True)
                    temp_path = None
                raise

        return _success_response(
            request_id=assigned_request_id,
            session_id=session_id,
            artifact=artifact,
            source_artifact_id=str(source.artifact.get("id")),
        )
    except ContractError as exc:
        details: dict[str, object] = dict(exc.details)
        if session_dir is not None and exc.code != "not_found":
            if registered_artifact_id is not None:
                _remove_registered_artifact(session_dir, registered_artifact_id)
            if destination is not None and destination_written:
                destination.unlink(missing_ok=True)
            response_code, response_message, details = _record_processing_failure(
                session_dir,
                request_id=assigned_request_id,
                code=exc.code,
                message=exc.message,
                details=details,
            )
        else:
            response_code = exc.code
            response_message = exc.message
        if temp_path is not None:
            temp_path.unlink(missing_ok=True)
        return _failure_response(response_code, response_message, request_id=assigned_request_id, details=details or None)
    except Exception as exc:
        if temp_path is not None:
            temp_path.unlink(missing_ok=True)
        message = f"Audio normalization failed: {exc}" if str(exc) else "Audio normalization failed."
        response_code = "processing_failed"
        response_message = message
        details = {"error": exc.__class__.__name__, "error_message": str(exc)}
        if session_dir is not None:
            if registered_artifact_id is not None:
                _remove_registered_artifact(session_dir, registered_artifact_id)
            if destination is not None and destination_written:
                destination.unlink(missing_ok=True)
            response_code, response_message, details = _record_processing_failure(
                session_dir,
                request_id=assigned_request_id,
                code="processing_failed",
                message=message,
                details=details,
            )
        return _failure_response(
            response_code,
            response_message,
            request_id=assigned_request_id,
            details=details,
        )


audio_normalization = run_audio_normalization
