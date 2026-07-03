#!/usr/bin/env bash
set -euo pipefail

component_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
repo_root="$(cd "$component_dir/../.." && pwd)"
cd "$component_dir"

PYTHONPATH=src REPO_ROOT="$repo_root" python3 - <<'PY'
from __future__ import annotations

import os
import shutil
from pathlib import Path

from meeting_assistant_cli.transcription_runtime_config import (
    TRANSCRIPTION_MODEL_ENV,
    TRANSCRIPTION_RUNTIME_ENV,
    TRANSCRIPTION_SMOKE_AUDIO_ENV,
    model_name_suggests_english_only,
    resolve_model_path,
    resolve_runtime_executable,
)

env = dict(os.environ)
missing = [
    name
    for name in (
        TRANSCRIPTION_RUNTIME_ENV,
        TRANSCRIPTION_MODEL_ENV,
        TRANSCRIPTION_SMOKE_AUDIO_ENV,
    )
    if not env.get(name, "").strip()
]
if missing:
    raise SystemExit(
        "release provider smoke failed: required env is missing: " + ", ".join(missing)
    )

runtime_path = resolve_runtime_executable(env)
model_path = resolve_model_path(env)
audio_path = Path(env[TRANSCRIPTION_SMOKE_AUDIO_ENV]).expanduser()
if runtime_path is None:
    raise SystemExit("release provider smoke failed: runtime is missing or not executable")
if model_path is None:
    raise SystemExit("release provider smoke failed: model is missing or not readable")
if not audio_path.is_file():
    raise SystemExit("release provider smoke failed: mixed-language audio fixture is missing")
if model_name_suggests_english_only(model_path):
    raise SystemExit("release provider smoke failed: English-only model cannot provide release-scope evidence")

home_local = (Path.home() / ".local").resolve(strict=False)
repo_root = Path(os.environ["REPO_ROOT"]).resolve(strict=False)
disallowed_roots = [
    repo_root,
    Path.home() / "Downloads",
    Path.home() / "Desktop",
    Path.home() / "Library" / "Caches",
]
required_roots = {
    "runtime": home_local,
    "model": (home_local / "share" / "ai-models" / "whisper.cpp").resolve(strict=False),
    "audio": (home_local / "share" / "ai-fixtures" / "asr" / "zh-en-tech").resolve(strict=False),
}
paths = {
    "runtime": Path(runtime_path).expanduser().resolve(strict=False),
    "model": Path(model_path).expanduser().resolve(strict=False),
    "audio": audio_path.resolve(strict=False),
}

for label, path in paths.items():
    try:
        path.relative_to(required_roots[label])
    except ValueError as exc:
        raise SystemExit(
            f"release provider smoke failed: {label} must be under {required_roots[label]}, got {path}"
        ) from exc
    for disallowed in disallowed_roots:
        disallowed_resolved = disallowed.resolve(strict=False)
        try:
            path.relative_to(disallowed_resolved)
        except ValueError:
            continue
        raise SystemExit(
            f"release provider smoke failed: {label} must not be under {disallowed_resolved}"
        )

model_name = Path(model_path).name.lower()
if "large-v3" not in model_name:
    raise SystemExit(
        "release provider smoke failed: model name must indicate large-v3 or large-v3-turbo evidence"
    )

print("VS-MA-23 provider release smoke [non-contract]: required runtime/model/audio .local preflight passed.")
print("VS-MA-23 provider release smoke [non-contract]: no repo, Downloads, Desktop, or cache asset path is used.")
PY

set +e
smoke_output="$(MEETING_ASSISTANT_REQUIRE_WHISPER_CPP_SMOKE=1 ./scripts/smoke-whisper-cpp.sh 2>&1)"
smoke_status="$?"
set -e
printf '%s\n' "$smoke_output"
if [ "$smoke_status" -ne 0 ]; then
  exit "$smoke_status"
fi
case "$smoke_output" in
  *"whisper.cpp smoke passed."*) ;;
  *)
    echo "release provider smoke failed: required whisper.cpp smoke marker was missing." >&2
    exit 1
    ;;
esac

echo "VS-MA-23 provider release smoke [non-contract]: required whisper.cpp runtime smoke passed."
echo "VS-MA-23 provider release smoke [non-contract]: no-auto-download/no-auto-upload boundary remains unchanged."
echo "release provider smoke passed."
