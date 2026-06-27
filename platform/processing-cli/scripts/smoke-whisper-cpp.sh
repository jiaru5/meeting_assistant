#!/usr/bin/env bash
set -euo pipefail

component_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$component_dir"

default_smoke_audio="$HOME/.local/share/ai-fixtures/asr/zh-en-tech/mixed-zh-en-tech.wav"
smoke_audio="${MEETING_ASSISTANT_WHISPER_SMOKE_AUDIO:-$default_smoke_audio}"

if [ -z "${MEETING_ASSISTANT_TRANSCRIPTION_RUNTIME:-}" ] || [ -z "${MEETING_ASSISTANT_TRANSCRIPTION_MODEL:-}" ]; then
  if [ "${MEETING_ASSISTANT_REQUIRE_WHISPER_CPP_SMOKE:-0}" = "1" ]; then
    echo "whisper.cpp smoke failed: MEETING_ASSISTANT_TRANSCRIPTION_RUNTIME and MEETING_ASSISTANT_TRANSCRIPTION_MODEL are required." >&2
    exit 1
  fi
  echo "whisper.cpp smoke not run: runtime/model env is not configured."
  exit 0
fi

if [ ! -f "$smoke_audio" ]; then
  if [ "${MEETING_ASSISTANT_REQUIRE_WHISPER_CPP_SMOKE:-0}" = "1" ]; then
    echo "whisper.cpp smoke failed: mixed Chinese-English WAV fixture is required at MEETING_ASSISTANT_WHISPER_SMOKE_AUDIO or $default_smoke_audio." >&2
    exit 1
  fi
  echo "whisper.cpp smoke not run: mixed-language audio fixture is not configured or missing at $default_smoke_audio."
  exit 0
fi

PYTHONPATH=src python3 - <<'PY'
import json
import shutil
import tempfile
import os
import re
import string
from pathlib import Path

from meeting_assistant_cli.transcript_processing import run_generate_transcript
from meeting_assistant_cli.workspace_contract import create_session, register_artifact, session_directory


def normalized_text(value: str) -> str:
    punctuation = string.punctuation.replace("+", "")
    table = str.maketrans({char: " " for char in punctuation})
    return " ".join(value.lower().translate(table).split())


def includes_term(transcript: str, term: str) -> bool:
    compact = transcript.replace(" ", "")
    compact_term = term.replace(" ", "")
    return term in transcript or compact_term in compact


with tempfile.TemporaryDirectory(prefix="meeting-assistant-whisper-smoke-") as tmp:
    model_name = Path(os.environ["MEETING_ASSISTANT_TRANSCRIPTION_MODEL"]).name.lower()
    if "large-v3" not in model_name:
        raise SystemExit(
            "whisper.cpp smoke failed: PV-MA-007 runtime smoke requires a large-v3 or large-v3-turbo multilingual model; "
            f"got {model_name!r}"
        )
    workspace = Path(tmp) / "workspace"
    create_session(workspace, source_type="imported_media", session_id="whisper-smoke", status="recorded")
    session_dir = session_directory(workspace, "whisper-smoke")
    audio_path = session_dir / "artifacts" / "mixed_audio.wav"
    shutil.copy2(Path(os.environ.get("MEETING_ASSISTANT_WHISPER_SMOKE_AUDIO", "~/.local/share/ai-fixtures/asr/zh-en-tech/mixed-zh-en-tech.wav")).expanduser(), audio_path)
    register_artifact(
        session_dir,
        artifact_type="mixed_audio",
        path=Path("artifacts/mixed_audio.wav"),
        file_format="wav",
        artifact_id="artifact-mixed_audio",
    )
    response = run_generate_transcript("whisper-smoke", workspace=workspace, language="zh", runtime="whisper_cpp")
    if not response.get("ok"):
        raise SystemExit(json.dumps(response, ensure_ascii=False, sort_keys=True))
    transcript_path = Path(str(response["artifacts"][0]["path"]))
    payload = json.loads(transcript_path.read_text(encoding="utf-8"))
    if not payload.get("segments"):
        raise SystemExit("whisper.cpp smoke failed: transcript has no segments")
    transcript = normalized_text(" ".join(str(segment.get("text", "")) for segment in payload["segments"]))
    if re.search(r"[\u4e00-\u9fff]", transcript) is None:
        raise SystemExit(
            "whisper.cpp smoke failed: transcript does not contain Chinese text "
            + json.dumps(transcript, ensure_ascii=False)
        )
    expected_terms = ["http", "llm", "clean architecture", "eda"]
    missing_terms = [term for term in expected_terms if not includes_term(transcript, term)]
    if missing_terms:
        raise SystemExit(
            "whisper.cpp smoke failed: missing mixed-language terms "
            + json.dumps(missing_terms, ensure_ascii=False)
            + " in transcript "
            + json.dumps(transcript, ensure_ascii=False)
        )

print("whisper.cpp smoke passed.")
PY
