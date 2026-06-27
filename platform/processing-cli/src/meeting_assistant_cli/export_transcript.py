from __future__ import annotations

import json
import os
import uuid
from datetime import datetime
from pathlib import Path
from typing import Callable

from .settings import default_workspace
from .speaker_labeling import _load_json, _validate_transcript_payload
from .workspace_contract import (
    ContractError,
    acquire_session_lock,
    artifact_file_path,
    load_session,
    session_directory,
    utc_timestamp,
    verify_registered_artifacts,
    write_session,
)


SUPPORTED_EXPORT_TYPES = {"plain_text", "markdown", "json"}


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
        "command": "export_transcript",
        "code": code,
        "message": message,
        "warnings": [],
        "details": details or {},
    }


def _format_timestamp(milliseconds: int) -> str:
    seconds, ms = divmod(milliseconds, 1000)
    minutes, sec = divmod(seconds, 60)
    hours, minute = divmod(minutes, 60)
    if hours:
        return f"{hours:02d}:{minute:02d}:{sec:02d}.{ms:03d}"
    return f"{minute:02d}:{sec:02d}.{ms:03d}"


def _find_transcript(session_dir: Path) -> tuple[dict, dict, Path]:
    session = load_session(session_dir)
    for artifact in session.get("artifacts", []):
        if artifact.get("artifact_type") != "transcript_text":
            continue
        verify_registered_artifacts(session_dir, {"transcript_text"})
        path = artifact_file_path(session_dir, artifact)
        payload = _load_json(path)
        _validate_transcript_payload(payload)
        return artifact, payload, path
    raise ContractError("artifact_missing", "Transcript artifact was not found.")


def _render_content(transcript: dict, export_type: str) -> str:
    if export_type == "json":
        return json.dumps(transcript, ensure_ascii=False, indent=2, sort_keys=True) + "\n"

    lines = []
    for segment in transcript["segments"]:
        timestamp = f"{_format_timestamp(segment['start_ms'])}-{_format_timestamp(segment['end_ms'])}"
        text = str(segment["text"]).strip()
        if export_type == "markdown":
            lines.append(f"- [{timestamp}] {text}")
        else:
            lines.append(f"[{timestamp}] {text}")
    if export_type == "markdown":
        return "# Transcript\n\n" + "\n".join(lines) + "\n"
    return "\n".join(lines) + "\n"


def _prepare_target(target_path: Path) -> Path:
    if target_path.exists():
        raise ContractError("path_conflict", "Export target already exists; replace policy is not defined.", path=str(target_path))
    parent = target_path.parent.expanduser().resolve(strict=False)
    if not parent.exists() or not parent.is_dir():
        raise ContractError("invalid_input", "Export target parent directory does not exist.", path=str(target_path))
    return parent / target_path.name


def _record_export_package(
    session_dir: Path,
    *,
    export_package_id: str,
    export_type: str,
    target_path: Path | None,
    clock: Callable[[], datetime] | None,
) -> None:
    session = load_session(session_dir)
    exports = list(session.get("exports", []))
    payload: dict[str, object] = {
        "id": export_package_id,
        "session_id": session["id"],
        "export_type": export_type,
        "created_at": utc_timestamp(clock),
    }
    if target_path is not None:
        payload["path"] = str(target_path)
    exports.append(payload)
    session["exports"] = exports
    session["updated_at"] = utc_timestamp(clock)
    write_session(session_dir, session)


def run_export_transcript(
    session_id: str,
    export_type: str,
    *,
    target_path: Path | None = None,
    workspace: Path | None = None,
    request_id: str | None = None,
    clock: Callable[[], datetime] | None = None,
) -> dict:
    assigned_request_id = request_id or _request_id()
    workspace_path = (workspace or default_workspace()).expanduser()
    session_dir: Path | None = None
    temp_path: Path | None = None
    destination: Path | None = None
    destination_written = False
    export_package_id = f"export-{uuid.uuid4()}"

    try:
        if export_type not in SUPPORTED_EXPORT_TYPES:
            raise ContractError("invalid_input", "Unsupported transcript export type.", export_type=export_type)
        session_dir = session_directory(workspace_path, session_id)
        _, transcript, transcript_path = _find_transcript(session_dir)
        original_transcript_text = transcript_path.read_text(encoding="utf-8")
        content = _render_content(transcript, export_type)

        with acquire_session_lock(session_dir):
            if target_path is not None:
                destination = _prepare_target(target_path.expanduser())
                temp_path = destination.with_name(f".{destination.name}.tmp")
                if temp_path.exists():
                    raise ContractError("path_conflict", "Temporary export target already exists.", path=str(temp_path))
                temp_path.write_text(content, encoding="utf-8")
                os.replace(temp_path, destination)
                temp_path = None
                destination_written = True
            if transcript_path.read_text(encoding="utf-8") != original_transcript_text:
                raise ContractError("path_conflict", "Transcript changed during export; refusing to report success.")
            _record_export_package(
                session_dir,
                export_package_id=export_package_id,
                export_type=export_type,
                target_path=destination,
                clock=clock,
            )
            destination_written = False

        response: dict[str, object] = {
            "ok": True,
            "request_id": assigned_request_id,
            "command": "export_transcript",
            "session_id": session_id,
            "export_type": export_type,
            "export_package_id": export_package_id,
            "warnings": [],
        }
        if destination is None:
            response["content"] = content
        else:
            response["target_path"] = str(destination)
        return response
    except ContractError as exc:
        if temp_path is not None:
            temp_path.unlink(missing_ok=True)
        if destination is not None and destination_written:
            destination.unlink(missing_ok=True)
        return _failure_response(exc.code, exc.message, request_id=assigned_request_id, details=exc.details or None)
    except PermissionError as exc:
        if temp_path is not None:
            temp_path.unlink(missing_ok=True)
        return _failure_response(
            "permission_denied",
            "Transcript export target could not be written.",
            request_id=assigned_request_id,
            details={"error": exc.__class__.__name__},
        )
    except OSError as exc:
        if temp_path is not None:
            temp_path.unlink(missing_ok=True)
        return _failure_response(
            "internal_error",
            "Transcript export failed while writing the target file.",
            request_id=assigned_request_id,
            details={"error": exc.__class__.__name__},
        )


export_transcript = run_export_transcript
