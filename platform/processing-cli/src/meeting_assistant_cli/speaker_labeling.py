from __future__ import annotations

import json
import os
import re
import uuid
from datetime import datetime
from pathlib import Path
from typing import Callable, Optional

from .sanitization import redact_sensitive_text, safe_exception_details, sanitize_failure_details
from .settings import default_workspace
from .workspace_contract import (
    ContractError,
    acquire_session_lock,
    artifact_file_path,
    load_session,
    prepare_managed_output_path,
    register_artifact,
    session_directory,
    utc_timestamp,
    verify_registered_artifacts,
)


LABEL_PATTERN = re.compile(r"^SPEAKER_\d{2}$")
SpeakerLabelAdapter = Callable[[dict, Optional[Path]], dict]


def _request_id() -> str:
    return f"local-{uuid.uuid4()}"


def _failure_response(
    code: str,
    message: str,
    *,
    request_id: str,
    details: dict[str, object] | None = None,
) -> dict:
    return {
        "ok": False,
        "request_id": request_id,
        "command": "generate_speaker_labels",
        "code": code,
        "message": redact_sensitive_text(message),
        "warnings": [],
        "details": sanitize_failure_details(details),
    }


def _success_response(
    *,
    request_id: str,
    session_id: str,
    transcript_id: str,
    artifact: dict,
    payload: dict,
    reused: bool = False,
) -> dict:
    response: dict[str, object] = {
        "ok": True,
        "request_id": request_id,
        "command": "generate_speaker_labels",
        "session_id": session_id,
        "transcript_id": transcript_id,
        "label_status": payload["label_status"],
        "speaker_labels_artifact_id": artifact["id"],
        "artifacts": [artifact],
        "warnings": [],
    }
    if payload.get("degradation_reason"):
        response["degradation_reason"] = payload["degradation_reason"]
    if payload.get("engine"):
        response["engine"] = payload["engine"]
    if reused:
        response["reused"] = True
        response["warnings"] = ["speaker_labels already exists; existing artifact was reused."]
    return response


def _append_processing_log(session_dir: Path, *, request_id: str, code: str, message: str) -> Path:
    log_path = prepare_managed_output_path(
        session_dir,
        Path("logs/processing.log"),
        "Processing log path conflicts with the session boundary.",
        create_parent=True,
    )
    safe_message = redact_sensitive_text(message)
    line = f"{utc_timestamp()} request_id={request_id} command=generate_speaker_labels code={code} message={safe_message}\n"
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


def _validate_transcript_payload(payload: dict) -> None:
    required = {"id", "session_id", "source_artifact_id", "status", "segments", "created_at"}
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


def _load_json(path: Path) -> dict:
    try:
        payload = json.loads(path.read_text(encoding="utf-8"))
    except (OSError, json.JSONDecodeError) as exc:
        raise ContractError("processing_failed", "JSON artifact could not be parsed.", path=str(path)) from exc
    if not isinstance(payload, dict):
        raise ContractError("processing_failed", "JSON artifact must be an object.", path=str(path))
    return payload


def _find_transcript(session_dir: Path, transcript_id: str) -> tuple[dict, dict, Path]:
    session = load_session(session_dir)
    for artifact in session.get("artifacts", []):
        if artifact.get("artifact_type") != "transcript_text":
            continue
        verify_registered_artifacts(session_dir, {"transcript_text"})
        path = artifact_file_path(session_dir, artifact)
        payload = _load_json(path)
        _validate_transcript_payload(payload)
        if payload.get("id") == transcript_id:
            return artifact, payload, path
    raise ContractError("artifact_missing", "Requested transcript was not found.", transcript_id=transcript_id)


def _normalized_audio_path(session_dir: Path) -> Path | None:
    session = load_session(session_dir)
    for artifact in session.get("artifacts", []):
        if artifact.get("artifact_type") != "normalized_audio":
            continue
        if artifact.get("capture_status") not in {"available", "degraded"}:
            continue
        verify_registered_artifacts(session_dir, {"normalized_audio"})
        path = artifact_file_path(session_dir, artifact)
        if path.is_file():
            return path
    return None


def _validate_segment_mapping_segments(payload: dict, transcript: dict) -> None:
    segment_ids = {str(segment["segment_id"]) for segment in transcript["segments"]}
    for mapping in payload["segment_mapping"]:
        if str(mapping.get("segment_id", "")) not in segment_ids:
            raise ContractError("processing_failed", "Speaker segment mapping references an unknown transcript segment.")


def _existing_speaker_labels(session_dir: Path, transcript: dict) -> tuple[dict, dict] | None:
    session = load_session(session_dir)
    for artifact in session.get("artifacts", []):
        if artifact.get("artifact_type") != "speaker_labels":
            continue
        verify_registered_artifacts(session_dir, {"speaker_labels"})
        payload = _load_json(artifact_file_path(session_dir, artifact))
        _validate_speaker_payload(payload, transcript_id=str(transcript["id"]))
        _validate_segment_mapping_segments(payload, transcript)
        return artifact, payload
    return None


def _fallback_payload(
    *,
    session_id: str,
    transcript_id: str,
    degradation_reason: str,
    clock: Callable[[], datetime] | None,
) -> dict:
    return {
        "session_id": session_id,
        "transcript_id": transcript_id,
        "label_status": "transcript_only",
        "degradation_reason": degradation_reason,
        "labels": [],
        "segment_mapping": [],
        "engine": {
            "type": "transcript_only_fallback",
            "available": False,
        },
        "created_at": utc_timestamp(clock),
    }


def _validate_speaker_payload(payload: dict, *, transcript_id: str) -> None:
    required = {"session_id", "transcript_id", "label_status", "labels", "segment_mapping", "created_at"}
    if required - set(payload):
        raise ContractError("processing_failed", "Speaker label payload is missing required fields.")
    if payload.get("transcript_id") != transcript_id:
        raise ContractError(
            "processing_failed",
            "speaker_labels already exists for a different transcript; replace policy is not defined in this slice.",
            transcript_id=transcript_id,
            existing_transcript_id=str(payload.get("transcript_id", "")),
        )
    label_status = payload.get("label_status")
    if label_status not in {"labeled", "transcript_only"}:
        raise ContractError("processing_failed", "Speaker label payload has an unsupported label status.")
    labels = payload.get("labels")
    segment_mapping = payload.get("segment_mapping")
    if not isinstance(labels, list) or not isinstance(segment_mapping, list):
        raise ContractError("processing_failed", "Speaker label payload has invalid label collections.")
    for label in labels:
        if not isinstance(label, dict):
            raise ContractError("processing_failed", "Speaker label entry must be an object.")
        value = str(label.get("label", ""))
        if not LABEL_PATTERN.match(value):
            raise ContractError("processing_failed", "Speaker label must use the SPEAKER_00 anonymous format.")
        if label.get("is_verified_identity") is not False:
            raise ContractError("processing_failed", "Speaker labels must not be marked as verified identities.")
    known_labels = {str(label.get("label")) for label in labels}
    for mapping in segment_mapping:
        if not isinstance(mapping, dict):
            raise ContractError("processing_failed", "Speaker segment mapping entry must be an object.")
        if str(mapping.get("label", "")) not in known_labels:
            raise ContractError("processing_failed", "Speaker segment mapping references an unknown label.")


def _payload_from_adapter(
    adapter_result: dict,
    *,
    transcript: dict,
    clock: Callable[[], datetime] | None,
) -> dict:
    payload = {
        "session_id": transcript["session_id"],
        "transcript_id": transcript["id"],
        "label_status": adapter_result.get("label_status", "labeled"),
        "labels": list(adapter_result.get("labels", [])),
        "segment_mapping": list(adapter_result.get("segment_mapping", [])),
        "engine": adapter_result.get("engine", {"type": "injected_adapter", "available": True}),
        "created_at": utc_timestamp(clock),
    }
    if adapter_result.get("degradation_reason"):
        payload["degradation_reason"] = redact_sensitive_text(adapter_result["degradation_reason"])
    _validate_speaker_payload(payload, transcript_id=str(transcript["id"]))
    _validate_segment_mapping_segments(payload, transcript)
    if payload["label_status"] == "labeled" and not payload["labels"]:
        raise ContractError("processing_failed", "Labeled speaker payload must include at least one anonymous label.")
    if payload["label_status"] == "transcript_only" and not payload.get("degradation_reason"):
        raise ContractError("processing_failed", "Transcript-only speaker payload must include a degradation reason.")
    return payload


def _remove_registered_artifact(session_dir: Path, artifact_id: str) -> None:
    session = load_session(session_dir)
    artifacts = [artifact for artifact in session.get("artifacts", []) if artifact.get("id") != artifact_id]
    if len(artifacts) == len(session.get("artifacts", [])):
        return
    session["artifacts"] = artifacts
    session["updated_at"] = utc_timestamp()
    from .workspace_contract import write_session

    write_session(session_dir, session)


def run_generate_speaker_labels(
    session_id: str,
    transcript_id: str,
    *,
    allow_transcript_only_fallback: bool,
    workspace: Path | None = None,
    adapter: SpeakerLabelAdapter | None = None,
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
        session_dir = session_directory(workspace_path, session_id)
        _, transcript, _ = _find_transcript(session_dir, transcript_id)
        with acquire_session_lock(session_dir):
            existing = _existing_speaker_labels(session_dir, transcript)
            if existing is not None:
                artifact, payload = existing
                return _success_response(
                    request_id=assigned_request_id,
                    session_id=session_id,
                    transcript_id=transcript_id,
                    artifact=artifact,
                    payload=payload,
                    reused=True,
                )

            if adapter is None:
                if not allow_transcript_only_fallback:
                    raise ContractError(
                        "processing_failed",
                        "Speaker labeling engine is unavailable and transcript-only fallback is disabled.",
                    )
                payload = _fallback_payload(
                    session_id=session_id,
                    transcript_id=transcript_id,
                    degradation_reason="Speaker labeling engine is unavailable; transcript-only fallback was used.",
                    clock=clock,
                )
            else:
                try:
                    payload = _payload_from_adapter(
                        adapter(transcript, _normalized_audio_path(session_dir)),
                        transcript=transcript,
                        clock=clock,
                    )
                except Exception as exc:
                    if not allow_transcript_only_fallback:
                        raise
                    payload = _fallback_payload(
                        session_id=session_id,
                        transcript_id=transcript_id,
                        degradation_reason="Speaker labeling adapter failed; transcript-only fallback was used.",
                        clock=clock,
                    )

            destination = prepare_managed_output_path(
                session_dir,
                Path("artifacts/speaker_labels.json"),
                "Speaker labels artifact path conflicts with the session boundary.",
            )
            temp_path = prepare_managed_output_path(
                session_dir,
                Path("artifacts/.speaker_labels.json.tmp"),
                "Speaker labels temporary artifact path conflicts with the session boundary.",
            )
            if destination.exists():
                raise ContractError(
                    "path_conflict",
                    "Unregistered speaker_labels.json already exists; refusing to overwrite it.",
                    path=str(destination),
                )
            temp_path.write_text(json.dumps(payload, ensure_ascii=False, indent=2, sort_keys=True) + "\n", encoding="utf-8")
            os.replace(temp_path, destination)
            destination_written = True
            artifact = register_artifact(
                session_dir,
                artifact_type="speaker_labels",
                path=Path("artifacts/speaker_labels.json"),
                file_format="json",
                capture_status="available" if payload["label_status"] == "labeled" else "degraded",
                degradation_reason=str(payload.get("degradation_reason", "")) or None,
                artifact_id=f"artifact-{uuid.uuid4()}",
                clock=clock,
            )
            registered_artifact_id = str(artifact["id"])
            verify_registered_artifacts(session_dir, {"speaker_labels", "transcript_text"})
            destination_written = False

        return _success_response(
            request_id=assigned_request_id,
            session_id=session_id,
            transcript_id=transcript_id,
            artifact=artifact,
            payload=payload,
        )
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
        message = "Speaker labeling failed."
        code = "processing_failed"
        details = safe_exception_details(exc)
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


generate_speaker_labels = run_generate_speaker_labels
