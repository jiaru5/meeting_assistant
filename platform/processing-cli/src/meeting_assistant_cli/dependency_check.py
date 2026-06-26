from __future__ import annotations

import os
import platform
import shutil
import tempfile
import uuid
from pathlib import Path
from typing import Mapping


MIN_MACOS_VERSION = "26.5.1"
DEFAULT_WORKSPACE = Path("~/Movies/MeetingAssistant").expanduser()
ALLOWED_SOURCE_CATEGORIES = (
    "Apple official Xcode or Command Line Tools",
    "official or well-maintained open-source project releases",
    "user-provided existing local model paths",
    "sources approved by future ADR",
)


def default_workspace() -> Path:
    return DEFAULT_WORKSPACE


def _version_tuple(value: str) -> tuple[int, ...]:
    parts: list[int] = []
    for part in value.split("."):
        if not part.isdigit():
            break
        parts.append(int(part))
    return tuple(parts)


def _check(check_id: str, status: str, required: bool, ok: bool, message: str, **details: object) -> dict:
    item = {
        "id": check_id,
        "status": status,
        "required": required,
        "ok": ok,
        "message": message,
    }
    if details:
        item["details"] = details
    return item


def _env(env: Mapping[str, str], name: str, default: str = "") -> str:
    return env.get(name, default).strip()


def _which(name: str, env: Mapping[str, str]) -> str | None:
    value = _env(env, name)
    if value:
        path = Path(value).expanduser()
        if path.is_file() and os.access(path, os.X_OK):
            return str(path)
        found = shutil.which(value, path=env.get("PATH"))
        return found
    return None


def _which_executable(executable: str, env: Mapping[str, str]) -> str | None:
    return shutil.which(executable, path=env.get("PATH"))


def _workspace_check(workspace: Path) -> dict:
    try:
        if workspace.exists():
            if not workspace.is_dir():
                return _check(
                    "workspace.writable",
                    "failed",
                    True,
                    False,
                    "Workspace path exists but is not a directory.",
                    path=str(workspace),
                )
            test_dir = workspace
            status = "writable"
            message = "Workspace exists and accepts a temporary write."
        else:
            test_dir = workspace.parent
            status = "creatable"
            message = "Workspace does not exist yet; parent directory accepts a temporary write."
        with tempfile.NamedTemporaryFile(prefix=".meeting-assistant-check-", dir=test_dir, delete=True) as handle:
            handle.write(b"ok")
        return _check(
            "workspace.writable",
            status,
            True,
            True,
            message,
            path=str(workspace),
        )
    except OSError as exc:
        return _check(
            "workspace.writable",
            "failed",
            True,
            False,
            "Workspace is not writable.",
            path=str(workspace),
            error=exc.__class__.__name__,
        )


def _permission_check(check_id: str, label: str, env: Mapping[str, str], env_name: str) -> dict:
    status = _env(env, env_name, "unknown").lower()
    if status not in {"granted", "denied", "unknown"}:
        status = "unknown"
    ok = status != "denied"
    message = f"{label} permission status is {status}."
    if status == "unknown":
        message = f"{label} permission status cannot be fully detected by the CLI yet."
    return _check(check_id, status, False, ok, message)


def run_dependency_check(workspace: Path | None = None, env: Mapping[str, str] | None = None) -> dict:
    env_map = dict(os.environ if env is None else env)
    configured_workspace = _env(env_map, "MEETING_ASSISTANT_WORKSPACE")
    workspace_path = (workspace or (Path(configured_workspace) if configured_workspace else DEFAULT_WORKSPACE)).expanduser()

    os_name = _env(env_map, "MEETING_ASSISTANT_OS_NAME", platform.system())
    macos_version = _env(env_map, "MEETING_ASSISTANT_MACOS_VERSION", platform.mac_ver()[0])
    arch = _env(env_map, "MEETING_ASSISTANT_CPU_ARCH", platform.machine())

    checks: list[dict] = []
    checks.append(
        _check(
            "platform.os",
            "supported" if os_name == "Darwin" else "unsupported",
            True,
            os_name == "Darwin",
            "Target platform is macOS." if os_name == "Darwin" else "Phase 1 target platform is macOS.",
            detected=os_name,
        )
    )
    version_ok = bool(macos_version) and _version_tuple(macos_version) >= _version_tuple(MIN_MACOS_VERSION)
    checks.append(
        _check(
            "platform.macos_version",
            "supported" if version_ok else "unsupported",
            True,
            version_ok,
            f"macOS version must be at least {MIN_MACOS_VERSION}.",
            detected=macos_version or "unknown",
            minimum=MIN_MACOS_VERSION,
        )
    )
    checks.append(
        _check(
            "platform.cpu_arch",
            "supported" if arch == "arm64" else "unsupported",
            True,
            arch == "arm64",
            "Phase 1 target CPU architecture is Apple Silicon arm64.",
            detected=arch,
        )
    )

    swift_path = _which("MEETING_ASSISTANT_SWIFT_PATH", env_map) or _which_executable("swift", env_map)
    checks.append(
        _check(
            "developer_tools.swift",
            "available" if swift_path else "missing",
            True,
            bool(swift_path),
            "Swift toolchain is available." if swift_path else "Swift toolchain was not found.",
            path=swift_path or "",
        )
    )

    ffmpeg_path = _which("MEETING_ASSISTANT_FFMPEG_PATH", env_map) or _which_executable("ffmpeg", env_map)
    checks.append(
        _check(
            "media_tool.ffmpeg",
            "available" if ffmpeg_path else "missing",
            True,
            bool(ffmpeg_path),
            "FFmpeg executable is available." if ffmpeg_path else "FFmpeg executable was not found.",
            path=ffmpeg_path or "",
        )
    )

    transcription_runtime = _which("MEETING_ASSISTANT_TRANSCRIPTION_RUNTIME", env_map)
    checks.append(
        _check(
            "transcription.runtime",
            "available" if transcription_runtime else "missing",
            True,
            bool(transcription_runtime),
            "Transcription runtime is available."
            if transcription_runtime
            else "Transcription runtime path or executable is not configured.",
            path=transcription_runtime or "",
        )
    )

    speaker_runtime = _which("MEETING_ASSISTANT_SPEAKER_LABELING_RUNTIME", env_map)
    checks.append(
        _check(
            "speaker_labeling.runtime",
            "available" if speaker_runtime else "missing",
            False,
            True,
            "Speaker labeling runtime is available."
            if speaker_runtime
            else "Speaker labeling runtime is missing; transcript-only fallback remains allowed.",
            path=speaker_runtime or "",
            fallback="transcript_only",
        )
    )

    checks.append(_workspace_check(workspace_path))
    checks.append(
        _permission_check(
            "permission.screen_recording",
            "Screen recording",
            env_map,
            "MEETING_ASSISTANT_SCREEN_RECORDING_PERMISSION",
        )
    )
    checks.append(_permission_check("permission.microphone", "Microphone", env_map, "MEETING_ASSISTANT_MICROPHONE_PERMISSION"))
    checks.append(
        _check(
            "dependency_sources.allowed",
            "reported",
            True,
            True,
            "Allowed dependency source categories are documented.",
            categories=list(ALLOWED_SOURCE_CATEGORIES),
        )
    )
    checks.append(
        _check(
            "dependency_downloads.automatic",
            "not_attempted",
            True,
            True,
            "The dependency check did not download models, binaries or drivers.",
        )
    )

    missing_required = [item for item in checks if item["required"] and not item["ok"]]
    warnings = [
        item["message"]
        for item in checks
        if not item["required"] and item["status"] in {"missing", "unknown", "denied"}
    ]
    response = {
        "ok": not missing_required,
        "request_id": f"local-{uuid.uuid4()}",
        "command": "check_dependencies",
        "checks": checks,
        "warnings": warnings,
    }
    if missing_required:
        response["code"] = "dependency_missing"
        response["message"] = "One or more required dependencies are missing or unsupported."
    return response
