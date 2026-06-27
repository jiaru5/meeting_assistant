from __future__ import annotations

import os
import re
import shutil
from pathlib import Path
from typing import Mapping


SUPPORTED_TRANSCRIPTION_RUNTIME = "whisper_cpp"
TRANSCRIPTION_RUNTIME_ENV = "MEETING_ASSISTANT_TRANSCRIPTION_RUNTIME"
TRANSCRIPTION_MODEL_ENV = "MEETING_ASSISTANT_TRANSCRIPTION_MODEL"
TRANSCRIPTION_SMOKE_AUDIO_ENV = "MEETING_ASSISTANT_WHISPER_SMOKE_AUDIO"
RECOMMENDED_RUNTIME_PATH = "~/.local/bin/whisper-cli"
RECOMMENDED_RUNTIME_ROOT = "~/.local/opt/whisper.cpp"
RECOMMENDED_MODEL_ROOT = "~/.local/share/ai-models/whisper.cpp"
RECOMMENDED_SMOKE_AUDIO_PATH = "~/.local/share/ai-fixtures/asr/zh-en-tech/mixed-zh-en-tech.wav"


def env_value(env: Mapping[str, str], name: str) -> str:
    return env.get(name, "").strip()


def resolve_runtime_executable(env: Mapping[str, str]) -> str | None:
    value = env_value(env, TRANSCRIPTION_RUNTIME_ENV)
    if not value:
        return None

    path = Path(value).expanduser()
    if path.is_file() and os.access(path, os.X_OK):
        return str(path)

    return shutil.which(value, path=env.get("PATH"))


def resolve_model_path(env: Mapping[str, str]) -> str | None:
    value = env_value(env, TRANSCRIPTION_MODEL_ENV)
    if not value:
        return None

    path = Path(value).expanduser()
    if path.is_file() and os.access(path, os.R_OK):
        return str(path)
    return None


def model_name_suggests_english_only(path: str) -> bool:
    name = Path(path).name.lower()
    return re.search(r"(^|[._-])en([._-]|$)", name) is not None
