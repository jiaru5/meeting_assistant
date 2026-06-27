from __future__ import annotations

import os
import shutil
import uuid
from pathlib import Path

from .settings import default_workspace
from .workspace_contract import ContractError, load_session, session_directory


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
    if session_dir.is_symlink():
        raise ContractError("path_conflict", "Session directory must not be a symlink.", path=str(session_dir))
    workspace_sessions = (workspace.expanduser().resolve(strict=False) / "sessions").resolve(strict=False)
    try:
        session_dir.resolve(strict=True).relative_to(workspace_sessions)
    except FileNotFoundError as exc:
        raise ContractError("not_found", "Session directory was not found.", path=str(session_dir)) from exc
    except ValueError as exc:
        raise ContractError("path_conflict", "Session directory resolves outside the workspace.", path=str(session_dir)) from exc


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
        session_dir = session_directory(workspace_path, session_id)
        if not session_dir.exists():
            raise ContractError("not_found", "Session directory was not found.", session_id=session_id)
        if not session_dir.is_dir():
            raise ContractError("path_conflict", "Session path is not a directory.", session_id=session_id, path=str(session_dir))
        _ensure_real_session_root(workspace_path, session_dir)
        session = load_session(session_dir)
        deleted_items = _collect_managed_items(session_dir)
        retained_external_exports = _retained_external_exports(session_dir, session)
        shutil.rmtree(session_dir)
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
