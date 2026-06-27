from __future__ import annotations

import shutil
import uuid
from datetime import datetime
from pathlib import Path
from typing import Callable

from .settings import default_workspace
from .workspace_contract import ContractError, acquire_session_lock, create_session, register_artifact, session_directory


SUPPORTED_IMPORTS = {
    ".wav": ("mixed_audio", "wav"),
    ".m4a": ("mixed_audio", "m4a"),
    ".mp3": ("mixed_audio", "mp3"),
    ".mp4": ("screen_video", "mp4"),
    ".mov": ("screen_video", "mov"),
}


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
        "command": "import_media",
        "code": code,
        "message": message,
        "warnings": [],
    }
    if details:
        response["details"] = details
    return response


def _validate_source(source_path: Path) -> tuple[Path, str, str]:
    try:
        resolved = source_path.expanduser().resolve(strict=True)
    except FileNotFoundError as exc:
        raise ContractError("invalid_input", "Media file was not found.", path=str(source_path)) from exc
    except OSError as exc:
        raise ContractError("invalid_input", "Media path cannot be resolved.", path=str(source_path)) from exc

    if not resolved.is_file():
        raise ContractError("invalid_input", "Media path must point to a file.", path=str(resolved))

    suffix = resolved.suffix.lower()
    if suffix not in SUPPORTED_IMPORTS:
        raise ContractError(
            "invalid_input",
            "Media file format is not supported by import_media.",
            path=str(resolved),
            supported_formats=sorted(SUPPORTED_IMPORTS),
        )

    artifact_type, file_format = SUPPORTED_IMPORTS[suffix]
    return resolved, artifact_type, file_format


def run_import_media(
    source_path: Path,
    *,
    title: str | None = None,
    workspace: Path | None = None,
    request_id: str | None = None,
    clock: Callable[[], datetime] | None = None,
) -> dict:
    assigned_request_id = request_id or _request_id()
    session_dir: Path | None = None
    try:
        source, artifact_type, file_format = _validate_source(source_path)
        workspace_path = (workspace or default_workspace()).expanduser()
        session = create_session(workspace_path, source_type="imported_media", title=title, clock=clock)
        session_dir = session_directory(workspace_path, str(session["id"]))
        destination = session_dir / "artifacts" / f"{artifact_type}.{file_format}"

        with acquire_session_lock(session_dir):
            shutil.copy2(source, destination)
            artifact = register_artifact(
                session_dir,
                artifact_type=artifact_type,
                path=Path("artifacts") / destination.name,
                file_format=file_format,
                clock=clock,
            )

        return {
            "ok": True,
            "request_id": assigned_request_id,
            "command": "import_media",
            "session_id": session["id"],
            "artifacts": [artifact],
            "warnings": [],
        }
    except ContractError as exc:
        if session_dir is not None:
            shutil.rmtree(session_dir, ignore_errors=True)
        return _failure_response(exc.code, exc.message, request_id=assigned_request_id, details=exc.details)
    except PermissionError as exc:
        if session_dir is not None:
            shutil.rmtree(session_dir, ignore_errors=True)
        return _failure_response(
            "permission_denied",
            "Media file or workspace could not be accessed.",
            request_id=assigned_request_id,
            details={"error": exc.__class__.__name__},
        )
    except OSError as exc:
        if session_dir is not None:
            shutil.rmtree(session_dir, ignore_errors=True)
        return _failure_response(
            "internal_error",
            "Media import failed while copying the source file.",
            request_id=assigned_request_id,
            details={"error": exc.__class__.__name__},
        )


import_media = run_import_media
