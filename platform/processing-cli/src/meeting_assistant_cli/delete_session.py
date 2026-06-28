from __future__ import annotations

import json
import os
import shutil
import uuid
from pathlib import Path
from typing import TextIO

from .settings import default_workspace
from .workspace_contract import ContractError, acquire_session_lock, load_session, session_directory, utc_timestamp


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
        "command": "delete_session",
        "code": code,
        "message": message,
        "warnings": [],
        "details": details or {},
    }


def _collect_managed_items(session_dir: Path) -> list[str]:
    items: list[str] = []
    for root, dirs, files in os.walk(session_dir, topdown=True, followlinks=False):
        root_path = Path(root)
        for name in files:
            if name == ".session.lock":
                continue
            items.append(str((root_path / name).relative_to(session_dir)))
        for name in dirs:
            items.append(str((root_path / name).relative_to(session_dir)))
    return sorted(items)


def _retained_external_exports(session_dir: Path, session: dict) -> list[str]:
    retained: list[str] = []
    session_root = session_dir.resolve(strict=False)
    for package in session.get("exports", []):
        if not isinstance(package, dict) or not package.get("path"):
            continue
        path = Path(str(package["path"])).expanduser().resolve(strict=False)
        try:
            path.relative_to(session_root)
        except ValueError:
            retained.append(str(path))
    return sorted(set(retained))


def _ensure_real_session_root(workspace: Path, session_dir: Path) -> None:
    workspace_root = workspace.expanduser().resolve(strict=False)
    workspace_sessions_raw = workspace_root / "sessions"
    if workspace_sessions_raw.is_symlink():
        raise ContractError("path_conflict", "Workspace sessions directory must not be a symlink.", path=str(workspace_sessions_raw))
    if session_dir.is_symlink():
        raise ContractError("path_conflict", "Session directory must not be a symlink.", path=str(session_dir))
    workspace_sessions = workspace_sessions_raw.resolve(strict=False)
    try:
        session_dir.resolve(strict=True).relative_to(workspace_sessions)
    except FileNotFoundError as exc:
        raise ContractError("not_found", "Session directory was not found.", path=str(session_dir)) from exc
    except ValueError as exc:
        raise ContractError("path_conflict", "Session directory resolves outside the workspace.", path=str(session_dir)) from exc


def _open_delete_event_log(workspace: Path) -> tuple[Path, TextIO]:
    workspace_root = workspace.expanduser().resolve(strict=False)
    event_dir_raw = workspace_root / "events"
    if event_dir_raw.is_symlink():
        raise ContractError("path_conflict", "Workspace events directory must not be a symlink.", path=str(event_dir_raw))
    event_dir_raw.mkdir(parents=True, exist_ok=True)
    if not event_dir_raw.is_dir():
        raise ContractError("path_conflict", "Workspace events path is not a directory.", path=str(event_dir_raw))

    event_dir = event_dir_raw.resolve(strict=True)
    try:
        event_dir.relative_to(workspace_root)
    except ValueError as exc:
        raise ContractError("path_conflict", "Workspace events directory resolves outside the workspace.", path=str(event_dir_raw)) from exc

    event_path = event_dir / "meeting_session.deleted.v1.jsonl"
    if event_path.is_symlink():
        raise ContractError("path_conflict", "Delete event log must not be a symlink.", path=str(event_path))
    if event_path.exists() and event_path.stat().st_nlink > 1:
        raise ContractError("path_conflict", "Delete event log must not be a hardlink.", path=str(event_path))
    try:
        event_path.resolve(strict=False).relative_to(workspace_root)
    except ValueError as exc:
        raise ContractError("path_conflict", "Delete event log resolves outside the workspace.", path=str(event_path)) from exc
    return event_path, event_path.open("a", encoding="utf-8")


def _write_delete_event(
    handle: TextIO,
    *,
    session_id: str,
    deleted_items: list[str],
    retained_external_exports: list[str],
) -> None:
    event = {
        "event_id": f"event-{uuid.uuid4()}",
        "event_name": "meeting_session.deleted.v1",
        "session_id": session_id,
        "occurred_at": utc_timestamp(),
        "result": {
            "deleted": True,
            "deleted_items": deleted_items,
            "retained_external_exports": retained_external_exports,
        },
    }
    handle.write(json.dumps(event, ensure_ascii=False, sort_keys=True) + "\n")
    handle.flush()


def run_delete_session(
    session_id: str,
    *,
    workspace: Path | None = None,
    confirm: bool,
    request_id: str | None = None,
) -> dict:
    assigned_request_id = request_id or _request_id()
    try:
        if confirm is not True:
            raise ContractError("invalid_input", "delete_session requires confirm=true.")
        workspace_path = (workspace or default_workspace()).expanduser()
        session_directory(workspace_path, session_id)
        workspace_root = workspace_path.expanduser().resolve(strict=False)
        session_dir = workspace_root / "sessions" / session_id
        if session_dir.is_symlink():
            raise ContractError("path_conflict", "Session directory must not be a symlink.", path=str(session_dir))
        if not session_dir.exists():
            raise ContractError("not_found", "Session directory was not found.", session_id=session_id)
        if not session_dir.is_dir():
            raise ContractError("path_conflict", "Session path is not a directory.", session_id=session_id, path=str(session_dir))
        _ensure_real_session_root(workspace_path, session_dir)
        with acquire_session_lock(session_dir):
            session = load_session(session_dir)
            deleted_items = _collect_managed_items(session_dir)
            retained_external_exports = _retained_external_exports(session_dir, session)
            _, event_log = _open_delete_event_log(workspace_path)
            try:
                shutil.rmtree(session_dir)
                _write_delete_event(
                    event_log,
                    session_id=session_id,
                    deleted_items=deleted_items,
                    retained_external_exports=retained_external_exports,
                )
            finally:
                event_log.close()
        return {
            "ok": True,
            "request_id": assigned_request_id,
            "command": "delete_session",
            "session_id": session_id,
            "deleted": True,
            "deleted_items": deleted_items,
            "retained_external_exports": retained_external_exports,
            "warnings": [],
        }
    except ContractError as exc:
        return _failure_response(exc.code, exc.message, request_id=assigned_request_id, details=exc.details or None)
    except PermissionError as exc:
        return _failure_response(
            "permission_denied",
            "Session could not be deleted due to file permissions.",
            request_id=assigned_request_id,
            details={"error": exc.__class__.__name__},
        )
    except OSError as exc:
        return _failure_response(
            "internal_error",
            "Session deletion failed.",
            request_id=assigned_request_id,
            details={"error": exc.__class__.__name__},
        )


delete_session = run_delete_session
