#!/usr/bin/env bash
set -euo pipefail

component_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
root_dir="$(cd "$component_dir/../.." && pwd)"

default_app_path="$root_dir/.harness/release-build/native-app/DerivedData/Build/Products/Release/MeetingAssistantNative.app"
app_path="${MA_NATIVE_LOCAL_APP_PATH:-$default_app_path}"
workspace_path="${MEETING_ASSISTANT_WORKSPACE:-$HOME/Movies/MeetingAssistant}"
build_if_missing="${MA_NATIVE_LOCAL_APP_BUILD_IF_MISSING:-1}"
rebuild="${MA_NATIVE_LOCAL_APP_REBUILD:-0}"
dry_run="${MA_NATIVE_LOCAL_APP_DRY_RUN:-0}"
require_real_runtime="${MA_NATIVE_LOCAL_APP_REQUIRE_REAL_RUNTIME:-1}"
app_args=()

usage() {
  cat <<'USAGE'
Usage: platform/native-app/scripts/run-local-app.sh [options] [-- app-args...]

Build or reuse the local-direct Release MeetingAssistantNative.app and launch the
app executable with the current local runtime/workspace environment.

Options:
  --app PATH       Use an existing MeetingAssistantNative.app path.
  --workspace DIR Set MEETING_ASSISTANT_WORKSPACE for this run.
  --no-build      Require the app bundle to already exist.
  --rebuild       Rebuild the local-direct Release app before launching.
  --dry-run       Print the resolved launch configuration without starting app.
  --help          Show this help.

Environment:
  MEETING_ASSISTANT_TRANSCRIPTION_RUNTIME and MEETING_ASSISTANT_TRANSCRIPTION_MODEL
  are required by default so Start Processing uses the explicit local whisper.cpp
  runtime. Set MA_NATIVE_LOCAL_APP_REQUIRE_REAL_RUNTIME=0 for dependency-only runs.
USAGE
}

is_truthy() {
  case "${1:-0}" in
    1 | true | TRUE | yes | YES)
      return 0
      ;;
    *)
      return 1
      ;;
  esac
}

while [[ $# -gt 0 ]]; do
  case "$1" in
    --app)
      if [[ $# -lt 2 || -z "${2:-}" ]]; then
        echo "error: --app requires a path" >&2
        exit 2
      fi
      app_path="$2"
      shift 2
      ;;
    --workspace)
      if [[ $# -lt 2 || -z "${2:-}" ]]; then
        echo "error: --workspace requires a directory" >&2
        exit 2
      fi
      workspace_path="$2"
      shift 2
      ;;
    --no-build)
      build_if_missing="0"
      shift
      ;;
    --rebuild)
      rebuild="1"
      shift
      ;;
    --dry-run)
      dry_run="1"
      shift
      ;;
    --help)
      usage
      exit 0
      ;;
    --)
      shift
      app_args+=("$@")
      break
      ;;
    *)
      app_args+=("$1")
      shift
      ;;
  esac
done

resolve_path() {
  python3 - "$1" <<'PY'
from pathlib import Path
import sys
print(Path(sys.argv[1]).expanduser().resolve(strict=False))
PY
}

app_path="$(resolve_path "$app_path")"
workspace_path="$(resolve_path "$workspace_path")"

if is_truthy "$rebuild" || { [[ ! -d "$app_path" ]] && is_truthy "$build_if_missing"; }; then
  "$root_dir/scripts/release-bundle-create.py" \
    --distribution-mode local-direct \
    --builder "${MEETING_ASSISTANT_RELEASE_BUILDER:-local-direct-app-run}" \
    --source-repository "${MEETING_ASSISTANT_RELEASE_SOURCE_REPOSITORY:-local/meeting_assistant}"
fi

if [[ ! -d "$app_path" ]]; then
  echo "error: local-direct app bundle does not exist: $app_path" >&2
  echo "Run with --rebuild, or set MA_NATIVE_LOCAL_APP_PATH/--app to an existing MeetingAssistantNative.app." >&2
  exit 1
fi

app_binary="$app_path/Contents/MacOS/MeetingAssistantNative"
if [[ ! -x "$app_binary" ]]; then
  echo "error: app executable is missing or not executable: $app_binary" >&2
  exit 1
fi

if [[ -z "${MEETING_ASSISTANT_CLI_PATH:-}" ]]; then
  export MEETING_ASSISTANT_CLI_PATH="$root_dir/platform/e2e/ma-cli-local.sh"
fi
if [[ ! -x "$MEETING_ASSISTANT_CLI_PATH" ]]; then
  echo "error: MEETING_ASSISTANT_CLI_PATH must point to an executable CLI bridge: $MEETING_ASSISTANT_CLI_PATH" >&2
  exit 1
fi

export MEETING_ASSISTANT_WORKSPACE="$workspace_path"
export MA_NATIVE_RECORDING_CLIENT="${MA_NATIVE_RECORDING_CLIENT:-apple_screencapturekit}"
export MA_NATIVE_PROCESSING_CLIENT="${MA_NATIVE_PROCESSING_CLIENT:-process}"
export MA_NATIVE_TRANSCRIPT_ACTION_CLIENT="${MA_NATIVE_TRANSCRIPT_ACTION_CLIENT:-process}"
export MA_NATIVE_TRANSCRIPT_ACTION_OS_CLIENT="${MA_NATIVE_TRANSCRIPT_ACTION_OS_CLIENT:-system}"

if is_truthy "$require_real_runtime"; then
  if [[ -z "${MEETING_ASSISTANT_TRANSCRIPTION_RUNTIME:-}" ]]; then
    echo "error: MEETING_ASSISTANT_TRANSCRIPTION_RUNTIME is required for local app real-runtime runs." >&2
    exit 1
  fi
  if [[ -z "${MEETING_ASSISTANT_TRANSCRIPTION_MODEL:-}" ]]; then
    echo "error: MEETING_ASSISTANT_TRANSCRIPTION_MODEL is required for local app real-runtime runs." >&2
    exit 1
  fi
  if [[ "$MEETING_ASSISTANT_TRANSCRIPTION_RUNTIME" == */* ]]; then
    runtime_path="$(resolve_path "$MEETING_ASSISTANT_TRANSCRIPTION_RUNTIME")"
    if [[ ! -x "$runtime_path" ]]; then
      echo "error: transcription runtime is not executable: $runtime_path" >&2
      exit 1
    fi
    export MEETING_ASSISTANT_TRANSCRIPTION_RUNTIME="$runtime_path"
  elif ! command -v "$MEETING_ASSISTANT_TRANSCRIPTION_RUNTIME" >/dev/null 2>&1; then
    echo "error: transcription runtime command is not on PATH: $MEETING_ASSISTANT_TRANSCRIPTION_RUNTIME" >&2
    exit 1
  fi
  model_path="$(resolve_path "$MEETING_ASSISTANT_TRANSCRIPTION_MODEL")"
  if [[ ! -f "$model_path" ]]; then
    echo "error: transcription model file does not exist: $model_path" >&2
    exit 1
  fi
  export MEETING_ASSISTANT_TRANSCRIPTION_MODEL="$model_path"
  export MA_NATIVE_PROCESSING_RUNTIME="${MA_NATIVE_PROCESSING_RUNTIME:-whisper_cpp}"
  export MA_NATIVE_PROCESSING_LANGUAGE="${MA_NATIVE_PROCESSING_LANGUAGE:-zh}"
fi

if [[ -z "${MEETING_ASSISTANT_FFMPEG_PATH:-}" ]] && command -v ffmpeg >/dev/null 2>&1; then
  export MEETING_ASSISTANT_FFMPEG_PATH="$(command -v ffmpeg)"
fi

unset MA_NATIVE_APP_XCTEST XCTestConfigurationFilePath XCTestBundlePath XCInjectBundleInto

echo "MeetingAssistantNative local app:"
echo "  app: $app_path"
echo "  cli: $MEETING_ASSISTANT_CLI_PATH"
echo "  workspace: $MEETING_ASSISTANT_WORKSPACE"
echo "  processing runtime: ${MA_NATIVE_PROCESSING_RUNTIME:-default}"
echo "  transcription runtime: ${MEETING_ASSISTANT_TRANSCRIPTION_RUNTIME:-not configured}"
echo "  transcription model: ${MEETING_ASSISTANT_TRANSCRIPTION_MODEL:-not configured}"

if is_truthy "$dry_run"; then
  echo "dry run: app not launched"
  exit 0
fi

if [[ ${#app_args[@]} -gt 0 ]]; then
  exec "$app_binary" "${app_args[@]}"
fi
exec "$app_binary"
