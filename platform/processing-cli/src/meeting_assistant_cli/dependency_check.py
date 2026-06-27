from __future__ import annotations

import os
import platform
import shutil
import subprocess
import tempfile
import uuid
from pathlib import Path
from typing import Mapping

from .settings import default_workspace
from .transcription_runtime_config import (
    RECOMMENDED_MODEL_ROOT,
    RECOMMENDED_RUNTIME_PATH,
    RECOMMENDED_RUNTIME_ROOT,
    RECOMMENDED_SMOKE_AUDIO_PATH,
    TRANSCRIPTION_MODEL_ENV,
    TRANSCRIPTION_RUNTIME_ENV,
    model_name_suggests_english_only,
    resolve_model_path,
    resolve_runtime_executable,
)


MIN_MACOS_VERSION = "26.5.1"
GIB = 1024 * 1024 * 1024
ALLOWED_SOURCE_CATEGORIES = (
    "Apple official Xcode or Command Line Tools",
    "official or well-maintained open-source project releases",
    "user-provided existing local multilingual Whisper model paths",
    "sources approved by future ADR",
)


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


def _sysctl_value(name: str) -> str:
    try:
        result = subprocess.run(["/usr/sbin/sysctl", "-n", name], capture_output=True, text=True, timeout=2, check=False)
    except (OSError, subprocess.TimeoutExpired):
        return ""
    if result.returncode != 0:
        return ""
    return result.stdout.strip()


def _memory_bytes(env: Mapping[str, str]) -> int | None:
    value = _env(env, "MEETING_ASSISTANT_MEMORY_BYTES") or _sysctl_value("hw.memsize")
    if not value.isdigit():
        return None
    return int(value)


def _chip_name(env: Mapping[str, str]) -> str:
    return _env(env, "MEETING_ASSISTANT_CHIP_NAME") or _sysctl_value("machdep.cpu.brand_string") or "unknown"


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


def _model_grade(model_path: str | None) -> str:
    if model_path is None:
        return "unknown"
    name = Path(model_path).name.lower()
    if "large-v3-turbo" in name:
        return "large-v3-turbo"
    if "large-v3" in name:
        return "large-v3"
    return "other"


def _transcription_hardware_check(arch: str, env: Mapping[str, str], model_path: str | None) -> dict:
    memory_bytes = _memory_bytes(env)
    memory_gb = round(memory_bytes / GIB, 1) if memory_bytes is not None else None
    chip_name = _chip_name(env)
    model_grade = _model_grade(model_path)
    details = {
        "cpu_arch": arch,
        "chip": chip_name,
        "memory_gb": memory_gb if memory_gb is not None else "unknown",
        "model_grade": model_grade,
        "recommended_model_grade": "large-v3 or large-v3-turbo multilingual",
    }

    if model_path is None or model_grade == "unknown":
        return _check(
            "transcription.hardware",
            "not_evaluated",
            True,
            True,
            "Hardware preflight requires a configured transcription model to evaluate the selected model grade.",
            **details,
        )

    if model_grade == "other":
        return _check(
            "transcription.hardware",
            "reported",
            True,
            True,
            "Hardware preflight is reported; product-quality evidence still requires a large-v3 or large-v3-turbo multilingual model.",
            **details,
        )

    if memory_bytes is None:
        return _check(
            "transcription.hardware",
            "unknown",
            True,
            False,
            "Hardware memory could not be detected for the selected transcription model grade.",
            **details,
        )

    if arch == "arm64" and memory_bytes >= 16 * GIB:
        return _check(
            "transcription.hardware",
            "supported",
            True,
            True,
            "Apple Silicon with at least 16 GB unified memory is suitable for the recommended multilingual Whisper model grade preflight.",
            **details,
        )

    if arch == "arm64" and memory_bytes >= 8 * GIB:
        return _check(
            "transcription.hardware",
            "constrained",
            True,
            True,
            "Apple Silicon memory is constrained for the recommended multilingual Whisper model grade; prefer turbo or quantized models for smoke.",
            **details,
        )

    return _check(
        "transcription.hardware",
        "unsupported",
        True,
        False,
        "Hardware does not meet the recommended multilingual Whisper model grade preflight.",
        **details,
    )


def run_dependency_check(workspace: Path | None = None, env: Mapping[str, str] | None = None) -> dict:
    env_map = dict(os.environ if env is None else env)
    workspace_path = (workspace or default_workspace(env_map)).expanduser()

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

    transcription_runtime = resolve_runtime_executable(env_map)
    checks.append(
        _check(
            "transcription.runtime",
            "available" if transcription_runtime else "missing",
            True,
            bool(transcription_runtime),
            "whisper.cpp transcription runtime is available."
            if transcription_runtime
            else "whisper.cpp runtime path or executable is not configured.",
            env=TRANSCRIPTION_RUNTIME_ENV,
            path=transcription_runtime or "",
            recommended_path=RECOMMENDED_RUNTIME_PATH,
            recommended_root=RECOMMENDED_RUNTIME_ROOT,
        )
    )
    transcription_model = resolve_model_path(env_map)
    checks.append(
        _check(
            "transcription.model",
            "available" if transcription_model else "missing",
            True,
            bool(transcription_model),
            "Multilingual Whisper-compatible transcription model is available."
            if transcription_model
            else "Transcription model path is not configured or is not readable.",
            env=TRANSCRIPTION_MODEL_ENV,
            path=transcription_model or "",
            recommended_root=RECOMMENDED_MODEL_ROOT,
        )
    )
    checks.append(_transcription_hardware_check(arch, env_map, transcription_model))
    english_only_model = bool(transcription_model and model_name_suggests_english_only(transcription_model))
    checks.append(
        _check(
            "transcription.model.multilingual",
            "unsupported" if english_only_model else "reported",
            True,
            not english_only_model,
            "English-only .en Whisper models cannot cover Chinese-English mixed meeting audio."
            if english_only_model
            else "Real runtime smoke must use a multilingual model for Chinese-English mixed meeting audio.",
            model_name=Path(transcription_model).name if transcription_model else "",
            examples=["HTTP", "LLM", "clean architecture", "EDA"],
            recommended_smoke_audio=RECOMMENDED_SMOKE_AUDIO_PATH,
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
        response["details"] = {"missing_required_checks": [item["id"] for item in missing_required]}
    return response
