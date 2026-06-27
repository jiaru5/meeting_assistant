from __future__ import annotations

import json
import os
import subprocess
import tempfile
from pathlib import Path

from .transcription_runtime_config import (
    SUPPORTED_TRANSCRIPTION_RUNTIME,
    TRANSCRIPTION_MODEL_ENV,
    TRANSCRIPTION_RUNTIME_ENV,
    model_name_suggests_english_only,
    resolve_model_path,
    resolve_runtime_executable,
)
from .workspace_contract import ContractError

MIXED_LANGUAGE_PROMPT = "HTTP LLM clean architecture EDA"


def validate_whisper_cpp_config(runtime: str) -> tuple[str, str]:
    if runtime != SUPPORTED_TRANSCRIPTION_RUNTIME:
        raise ContractError(
            "invalid_input",
            "Unsupported transcription runtime.",
            runtime=runtime,
            supported_runtime=SUPPORTED_TRANSCRIPTION_RUNTIME,
        )

    env_map = dict(os.environ)
    runtime_path = resolve_runtime_executable(env_map)
    model_path = resolve_model_path(env_map)
    missing = []
    if runtime_path is None:
        missing.append(TRANSCRIPTION_RUNTIME_ENV)
    if model_path is None:
        missing.append(TRANSCRIPTION_MODEL_ENV)
    if missing:
        raise ContractError(
            "dependency_missing",
            "whisper.cpp runtime or multilingual model path is not configured.",
            runtime=runtime,
            missing=missing,
        )
    if model_name_suggests_english_only(model_path):
        raise ContractError(
            "dependency_missing",
            "Configured Whisper model appears to be English-only and cannot cover Chinese-English mixed meeting audio.",
            runtime=runtime,
            model_name=Path(model_path).name,
        )
    return runtime_path, model_path


def whisper_cpp_transcript_adapter(audio_path: Path, language: str | None, runtime: str | None) -> list[dict]:
    if runtime is None:
        raise ContractError("invalid_input", "whisper.cpp adapter requires an explicit runtime.")
    if not audio_path.is_file():
        raise ContractError("artifact_missing", "Transcription input audio file was not found.", path=str(audio_path))

    runtime_path, model_path = validate_whisper_cpp_config(runtime)
    with tempfile.TemporaryDirectory(prefix="meeting-assistant-whisper-") as tmp:
        output_prefix = Path(tmp) / "transcript"
        command = [
            runtime_path,
            "-m",
            model_path,
            "-f",
            str(audio_path),
            "--output-json-full",
            "--output-file",
            str(output_prefix),
            "--no-prints",
            "--prompt",
            MIXED_LANGUAGE_PROMPT,
        ]
        if language:
            command.extend(["-l", language])

        try:
            result = subprocess.run(command, capture_output=True, text=True, timeout=600, check=False)
        except subprocess.TimeoutExpired as exc:
            raise ContractError("processing_failed", "whisper.cpp runtime timed out.", runtime=runtime) from exc
        except OSError as exc:
            raise ContractError(
                "processing_failed",
                "whisper.cpp runtime could not be started.",
                runtime=runtime,
                error=exc.__class__.__name__,
            ) from exc

        output_path = output_prefix.with_suffix(".json")
        if not output_path.is_file():
            raise ContractError(
                "processing_failed",
                "whisper.cpp runtime did not produce JSON output.",
                runtime=runtime,
                exit_code=result.returncode,
            )
        if result.returncode != 0:
            raise ContractError(
                "processing_failed",
                "whisper.cpp runtime failed.",
                runtime=runtime,
                exit_code=result.returncode,
            )

        try:
            payload = json.loads(output_path.read_bytes().decode("utf-8", errors="replace"))
        except (OSError, json.JSONDecodeError) as exc:
            raise ContractError(
                "processing_failed",
                "whisper.cpp JSON output could not be parsed.",
                runtime=runtime,
                error=exc.__class__.__name__,
            ) from exc
    return _segments_from_whisper_cpp_payload(payload)


def _segments_from_whisper_cpp_payload(payload: object) -> list[dict]:
    if not isinstance(payload, dict):
        raise ContractError("processing_failed", "whisper.cpp JSON output must be an object.")
    raw_segments = payload.get("transcription")
    if not isinstance(raw_segments, list) or not raw_segments:
        raise ContractError("processing_failed", "whisper.cpp JSON output did not include transcription segments.")

    segments: list[dict] = []
    for index, raw_segment in enumerate(raw_segments, start=1):
        if not isinstance(raw_segment, dict):
            raise ContractError("processing_failed", "whisper.cpp JSON output included an invalid segment.")
        offsets = raw_segment.get("offsets")
        if not isinstance(offsets, dict):
            raise ContractError("processing_failed", "whisper.cpp JSON segment did not include offsets.")
        start_ms = _coerce_milliseconds(offsets.get("from"))
        end_ms = _coerce_milliseconds(offsets.get("to"))
        text = str(raw_segment.get("text", "")).strip()
        if start_ms is None or end_ms is None or start_ms >= end_ms or not text:
            raise ContractError("processing_failed", "whisper.cpp JSON segment failed transcript contract validation.")
        segments.append(
            {
                "segment_id": f"segment-{index:04d}",
                "start_ms": start_ms,
                "end_ms": end_ms,
                "text": text,
            }
        )
    return segments


def _coerce_milliseconds(value: object) -> int | None:
    if isinstance(value, int):
        return value
    if isinstance(value, float):
        return int(round(value))
    if isinstance(value, str) and value.isdigit():
        return int(value)
    return None
