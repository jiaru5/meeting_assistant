from __future__ import annotations

import hashlib
import json
import os
import re
import uuid
from datetime import datetime, timezone
from pathlib import Path
from typing import Callable, Iterable


ALLOWED_SOURCE_TYPES = {"native_recording", "imported_media"}
ALLOWED_SESSION_STATUSES = {"created", "recording", "recorded", "processing", "transcribed", "failed", "deleted"}
ALLOWED_ARTIFACT_TYPES = {
    "screen_video",
    "system_audio",
    "microphone_audio",
    "mixed_audio",
    "normalized_audio",
    "transcript_text",
    "speaker_labels",
    "metadata",
}
ALLOWED_CAPTURE_STATUSES = {"available", "degraded", "missing", "failed"}
ORIGINAL_MEDIA_ARTIFACT_TYPES = {"screen_video", "system_audio", "microphone_audio", "mixed_audio"}
SESSION_ID_PATTERN = re.compile(r"^[A-Za-z0-9][A-Za-z0-9_.-]{0,127}$")


class ContractError(RuntimeError):
    def __init__(self, code: str, message: str, **details: object) -> None:
        super().__init__(message)
        self.code = code
        self.message = message
        self.details = details

    def as_response(self) -> dict:
        response: dict[str, object] = {"ok": False, "code": self.code, "message": self.message}
        if self.details:
            response["details"] = self.details
        return response


def utc_timestamp(clock: Callable[[], datetime] | None = None) -> str:
    now = clock() if clock else datetime.now(timezone.utc)
    if now.tzinfo is None:
        now = now.replace(tzinfo=timezone.utc)
    return now.astimezone(timezone.utc).isoformat().replace("+00:00", "Z")


def sha256_file(path: Path) -> str:
    digest = hashlib.sha256()
    with path.open("rb") as handle:
        for chunk in iter(lambda: handle.read(1024 * 1024), b""):
            digest.update(chunk)
    return f"sha256:{digest.hexdigest()}"


def _validate_session_id(session_id: str) -> None:
    if not SESSION_ID_PATTERN.match(session_id):
        raise ContractError("invalid_input", "Session id contains unsupported path characters.", session_id=session_id)


def _workspace_root(workspace: Path) -> Path:
    return workspace.expanduser().resolve(strict=False)


def _ensure_within(base: Path, candidate: Path, message: str = "Path escapes the session boundary.") -> Path:
    base_path = base.expanduser().resolve(strict=False)
    candidate_path = candidate.expanduser().resolve(strict=False)
    try:
        candidate_path.relative_to(base_path)
    except ValueError as exc:
        raise ContractError("path_conflict", message, base=str(base_path), path=str(candidate_path)) from exc
    return candidate_path


def session_directory(workspace: Path, session_id: str) -> Path:
    _validate_session_id(session_id)
    root = _workspace_root(workspace)
    return _ensure_within(root, root / "sessions" / session_id, "Session path escapes the workspace boundary.")


def session_json_path(session_dir: Path) -> Path:
    return session_dir / "session.json"


def write_session(session_dir: Path, payload: dict) -> None:
    _write_session(session_dir, payload)


def _write_session(session_dir: Path, payload: dict) -> None:
    session_path = session_json_path(session_dir)
    _ensure_within(session_dir, session_path)
    temp_path = session_path.with_name(f".{session_path.name}.tmp")
    temp_path.write_text(json.dumps(payload, ensure_ascii=False, indent=2, sort_keys=True) + "\n", encoding="utf-8")
    os.replace(temp_path, session_path)


def load_session(session_dir: Path) -> dict:
    session_path = session_json_path(session_dir)
    if not session_path.is_file():
        raise ContractError("not_found", "Session metadata file was not found.", path=str(session_path))
    return json.loads(session_path.read_text(encoding="utf-8"))


def create_session(
    workspace: Path,
    source_type: str,
    title: str | None = None,
    session_id: str | None = None,
    status: str = "created",
    clock: Callable[[], datetime] | None = None,
) -> dict:
    if source_type not in ALLOWED_SOURCE_TYPES:
        raise ContractError("invalid_input", "Unsupported meeting source type.", source_type=source_type)
    if status not in ALLOWED_SESSION_STATUSES:
        raise ContractError("invalid_input", "Unsupported meeting session status.", status=status)

    assigned_session_id = session_id or f"session-{uuid.uuid4()}"
    _validate_session_id(assigned_session_id)
    session_dir = session_directory(workspace, assigned_session_id)
    if session_dir.exists():
        raise ContractError("path_conflict", "Session directory already exists.", session_id=assigned_session_id)

    (session_dir / "artifacts").mkdir(parents=True)
    (session_dir / "logs").mkdir()

    now = utc_timestamp(clock)
    payload: dict[str, object] = {
        "id": assigned_session_id,
        "source_type": source_type,
        "status": status,
        "started_at": now,
        "workspace_dir": str(session_dir),
        "created_at": now,
        "updated_at": now,
        "artifacts": [],
    }
    if title:
        payload["title"] = title
    _write_session(session_dir, payload)
    return payload


def _artifact_path(session_dir: Path, path: Path) -> Path:
    candidate = path if path.is_absolute() else session_dir / path
    return _ensure_within(session_dir, candidate, "Artifact path escapes the session boundary.")


def artifact_file_path(session_dir: Path, artifact: dict) -> Path:
    path = artifact.get("path")
    if not path:
        raise ContractError("artifact_missing", "Artifact metadata does not include a path.", artifact_id=artifact.get("id"))
    return _artifact_path(session_dir, Path(str(path)))


def _existing_original_artifact(session: dict, artifact_type: str) -> dict | None:
    if artifact_type not in ORIGINAL_MEDIA_ARTIFACT_TYPES:
        return None
    for artifact in session.get("artifacts", []):
        if artifact.get("artifact_type") == artifact_type and artifact.get("capture_status") in {"available", "degraded"}:
            return artifact
    return None


def register_artifact(
    session_dir: Path,
    artifact_type: str,
    path: Path,
    file_format: str,
    capture_status: str = "available",
    degradation_reason: str | None = None,
    duration_ms: int | None = None,
    artifact_id: str | None = None,
    clock: Callable[[], datetime] | None = None,
) -> dict:
    if artifact_type not in ALLOWED_ARTIFACT_TYPES:
        raise ContractError("invalid_input", "Unsupported artifact type.", artifact_type=artifact_type)
    if capture_status not in ALLOWED_CAPTURE_STATUSES:
        raise ContractError("invalid_input", "Unsupported artifact capture status.", capture_status=capture_status)
    if capture_status != "available" and not degradation_reason:
        raise ContractError(
            "invalid_input",
            "Unavailable or degraded artifacts must record a degradation reason.",
            capture_status=capture_status,
        )

    session = load_session(session_dir)
    artifact_path = _artifact_path(session_dir, path)
    if capture_status in {"available", "degraded"} and not artifact_path.is_file():
        raise ContractError("artifact_missing", "Available or degraded artifacts must point to an existing file.", path=str(artifact_path))

    existing = _existing_original_artifact(session, artifact_type)
    if existing is not None:
        raise ContractError(
            "path_conflict",
            "Original media artifacts are append-only and this type is already registered.",
            artifact_type=artifact_type,
            existing_artifact_id=existing.get("id"),
        )

    checksum = sha256_file(artifact_path) if artifact_path.is_file() else None
    for artifact in session.get("artifacts", []):
        if artifact.get("path") == str(artifact_path) and artifact.get("checksum") and artifact.get("checksum") != checksum:
            raise ContractError(
                "path_conflict",
                "Registered artifact checksum no longer matches the file.",
                artifact_id=artifact.get("id"),
                path=str(artifact_path),
            )

    now = utc_timestamp(clock)
    payload: dict[str, object] = {
        "id": artifact_id or f"artifact-{uuid.uuid4()}",
        "session_id": session["id"],
        "artifact_type": artifact_type,
        "path": str(artifact_path),
        "format": file_format,
        "capture_status": capture_status,
        "created_at": now,
    }
    if checksum:
        payload["checksum"] = checksum
    if degradation_reason:
        payload["degradation_reason"] = degradation_reason
    if duration_ms is not None:
        payload["duration_ms"] = duration_ms

    session.setdefault("artifacts", []).append(payload)
    session["updated_at"] = now
    _write_session(session_dir, session)
    return payload


def verify_registered_artifacts(session_dir: Path, artifact_types: Iterable[str] | None = None) -> bool:
    expected_types = set(artifact_types or ORIGINAL_MEDIA_ARTIFACT_TYPES)
    session = load_session(session_dir)
    for artifact in session.get("artifacts", []):
        if artifact.get("artifact_type") not in expected_types:
            continue
        checksum = artifact.get("checksum")
        if not checksum:
            continue
        artifact_path = _artifact_path(session_dir, Path(str(artifact.get("path", ""))))
        if not artifact_path.is_file():
            raise ContractError("artifact_missing", "Registered artifact file was not found.", artifact_id=artifact.get("id"))
        if sha256_file(artifact_path) != checksum:
            raise ContractError(
                "path_conflict",
                "Registered artifact checksum changed.",
                artifact_id=artifact.get("id"),
                path=str(artifact_path),
            )
    return True


class SessionLock:
    def __init__(self, session_dir: Path, lock_name: str = ".session.lock") -> None:
        self.session_dir = session_dir
        self.lock_path = _artifact_path(session_dir, Path(lock_name))
        self._fd: int | None = None

    def __enter__(self) -> "SessionLock":
        try:
            self._fd = os.open(self.lock_path, os.O_CREAT | os.O_EXCL | os.O_WRONLY)
            os.write(self._fd, f"pid={os.getpid()}\n".encode("utf-8"))
        except FileExistsError as exc:
            raise ContractError("path_conflict", "Session is already locked.", path=str(self.lock_path)) from exc
        return self

    def __exit__(self, exc_type: object, exc: object, traceback: object) -> None:
        if self._fd is not None:
            os.close(self._fd)
            self._fd = None
        try:
            self.lock_path.unlink()
        except FileNotFoundError:
            pass


def acquire_session_lock(session_dir: Path) -> SessionLock:
    return SessionLock(session_dir)
