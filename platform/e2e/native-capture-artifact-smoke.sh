#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
cd "$ROOT_DIR"

case "${MA_NATIVE_CAPTURE_SMOKE:-0}" in
  1|true|TRUE|yes|YES)
    ;;
  *)
    echo "native capture artifact e2e skipped: set MA_NATIVE_CAPTURE_SMOKE=1 to run real ScreenCaptureKit capture." >&2
    echo "This opt-in smoke is not part of the default full-stack gate and may require macOS Screen Recording permission." >&2
    exit 2
    ;;
esac

run_stamp="$(date -u +%Y%m%dT%H%M%SZ)"
smoke_root="$ROOT_DIR/platform/e2e/build/native-capture-artifact-smoke"
workspace="${MA_NATIVE_CAPTURE_SMOKE_WORKSPACE:-$smoke_root/workspace-$run_stamp-$$}"
build_dir="${MA_NATIVE_CAPTURE_SMOKE_BUILD_DIR:-$smoke_root/build-$run_stamp-$$}"
summary_dir="${MA_NATIVE_CAPTURE_ARTIFACT_SMOKE_SUMMARY_DIR:-$smoke_root/summaries}"
summary_path="${MA_NATIVE_CAPTURE_ARTIFACT_SMOKE_SUMMARY:-$summary_dir/native-capture-summary-$run_stamp-$$.json}"
attempts="${MA_NATIVE_CAPTURE_ARTIFACT_SMOKE_ATTEMPTS:-2}"
display_wake_seconds="${MA_NATIVE_CAPTURE_ARTIFACT_SMOKE_DISPLAY_WAKE_SECONDS:-120}"
display_wake_settle_seconds="${MA_NATIVE_CAPTURE_ARTIFACT_SMOKE_DISPLAY_WAKE_SETTLE_SECONDS:-3}"

if ! [[ "$attempts" =~ ^[1-9][0-9]*$ ]] || ((attempts > 5)); then
  echo "native capture artifact e2e failed: MA_NATIVE_CAPTURE_ARTIFACT_SMOKE_ATTEMPTS must be an integer from 1 to 5." >&2
  exit 2
fi

if ! [[ "$display_wake_seconds" =~ ^[0-9]+$ ]] || ((display_wake_seconds > 600)); then
  echo "native capture artifact e2e failed: MA_NATIVE_CAPTURE_ARTIFACT_SMOKE_DISPLAY_WAKE_SECONDS must be an integer from 0 to 600." >&2
  exit 2
fi

if ! [[ "$display_wake_settle_seconds" =~ ^[0-9]+$ ]] || ((display_wake_settle_seconds > 30)); then
  echo "native capture artifact e2e failed: MA_NATIVE_CAPTURE_ARTIFACT_SMOKE_DISPLAY_WAKE_SETTLE_SECONDS must be an integer from 0 to 30." >&2
  exit 2
fi

mkdir -p "$summary_dir" "$(dirname "$workspace")" "$build_dir"

export MA_NATIVE_CAPTURE_SMOKE_WORKSPACE="$workspace"
export MA_NATIVE_CAPTURE_SMOKE_BUILD_DIR="$build_dir"
export MA_NATIVE_CAPTURE_SMOKE_DURATION_SECONDS="${MA_NATIVE_CAPTURE_SMOKE_DURATION_SECONDS:-2}"
export MA_NATIVE_CAPTURE_SMOKE_SYSTEM_AUDIO="${MA_NATIVE_CAPTURE_SMOKE_SYSTEM_AUDIO:-false}"
export MA_NATIVE_CAPTURE_SMOKE_MICROPHONE_AUDIO="${MA_NATIVE_CAPTURE_SMOKE_MICROPHONE_AUDIO:-false}"

echo "native capture artifact e2e running: workspace=$workspace summary=$summary_path" >&2

display_wake_pid=""
cleanup_display_wake() {
  if [[ -n "$display_wake_pid" ]]; then
    kill "$display_wake_pid" 2>/dev/null || true
    wait "$display_wake_pid" 2>/dev/null || true
  fi
}
trap cleanup_display_wake EXIT

if ((display_wake_seconds > 0)) && command -v caffeinate >/dev/null 2>&1; then
  caffeinate -d -u -t "$display_wake_seconds" >/dev/null 2>&1 &
  display_wake_pid=$!
  echo "native capture artifact e2e display wake guard started: caffeinate -d -u -t $display_wake_seconds" >&2
  if ((display_wake_settle_seconds > 0)); then
    sleep "$display_wake_settle_seconds"
  fi
elif ((display_wake_seconds > 0)); then
  echo "native capture artifact e2e diagnostic: caffeinate not found; continuing without display wake guard." >&2
fi

native_exit=1
last_attempt_summary=""
for attempt in $(seq 1 "$attempts"); do
  attempt_summary="${summary_path%.json}.attempt-${attempt}.json"
  last_attempt_summary="$attempt_summary"
  echo "native capture artifact e2e native attempt $attempt/$attempts" >&2
  set +e
  "$ROOT_DIR/platform/native-app/scripts/native-capture-smoke.sh" >"$attempt_summary"
  native_exit=$?
  set -e

  if ((native_exit == 0)); then
    cp "$attempt_summary" "$summary_path"
    break
  fi

  echo "native capture artifact e2e diagnostic: native capture attempt $attempt exited $native_exit" >&2
  if [[ -s "$attempt_summary" ]]; then
    cat "$attempt_summary" >&2
  fi
done

if ((native_exit != 0)); then
  echo "native capture artifact e2e failed: native capture smoke did not pass after $attempts attempt(s)" >&2
  if [[ -n "$last_attempt_summary" && -s "$last_attempt_summary" ]]; then
    cp "$last_attempt_summary" "$summary_path"
  fi
  exit "$native_exit"
fi

PYTHONDONTWRITEBYTECODE=1 \
PYTHONPATH="$ROOT_DIR/platform/processing-cli/src${PYTHONPATH:+:$PYTHONPATH}" \
MA_NATIVE_CAPTURE_ARTIFACT_SUMMARY="$summary_path" \
python3 - <<'PY'
from __future__ import annotations

import json
import os
import subprocess
import sys
from pathlib import Path

from meeting_assistant_cli.workspace_contract import (
    ORIGINAL_MEDIA_ARTIFACT_TYPES,
    ContractError,
    artifact_file_path,
    load_session,
    session_directory,
    sha256_file,
    verify_registered_artifacts,
)


ROOT = Path.cwd()
PYTHON = sys.executable
SUMMARY_PATH = Path(os.environ["MA_NATIVE_CAPTURE_ARTIFACT_SUMMARY"])
TRANSCRIPTION_ENV_NAMES = (
    "MEETING_ASSISTANT_TRANSCRIPTION_RUNTIME",
    "MEETING_ASSISTANT_TRANSCRIPTION_MODEL",
    "MEETING_ASSISTANT_WHISPER_SMOKE_AUDIO",
)


def fail(message: str) -> None:
    raise AssertionError(f"native capture artifact e2e: {message}")


def load_single_json(stdout: str, command: str) -> dict:
    lines = [line for line in stdout.splitlines() if line.strip()]
    if len(lines) != 1:
        fail(f"{command} expected one JSON object, got {len(lines)} lines: {stdout!r}")
    payload = json.loads(lines[0])
    if not isinstance(payload, dict):
        fail(f"{command} response must be a JSON object")
    return payload


def require_response(payload: dict, command: str, *, ok: bool, code: str | None = None) -> None:
    for key in ("ok", "request_id", "command", "warnings"):
        if key not in payload:
            fail(f"{command} missing response key {key}")
    if payload["command"] != command:
        fail(f"{command} response command drifted to {payload['command']!r}")
    if payload["ok"] is not ok:
        fail(f"{command} expected ok={ok}, got {payload['ok']!r}")
    if not isinstance(payload["warnings"], list):
        fail(f"{command} warnings must be a list")
    if not ok:
        for key in ("code", "message", "details"):
            if key not in payload:
                fail(f"{command} missing failure key {key}")
        if code is not None and payload["code"] != code:
            fail(f"{command} expected code={code}, got {payload['code']!r}")


def artifact_by_type(session: dict, artifact_type: str) -> dict:
    matches = [
        artifact
        for artifact in session.get("artifacts", [])
        if artifact.get("artifact_type") == artifact_type
    ]
    if len(matches) != 1:
        fail(f"expected exactly one {artifact_type} artifact, got {len(matches)}")
    return matches[0]


def assert_managed_relative_path(artifact: dict, artifact_type: str) -> None:
    path_text = str(artifact.get("path", ""))
    if not path_text:
        fail(f"{artifact_type} artifact path is empty")
    path = Path(path_text)
    if path.is_absolute():
        fail(f"{artifact_type} artifact path must be relative, got {path_text}")
    if not path_text.startswith("artifacts/") or ".." in path.parts:
        fail(f"{artifact_type} artifact path must stay under artifacts/, got {path_text}")


def assert_original_artifact_contract(session_dir: Path, session: dict, summary: dict) -> None:
    expected_types = set(ORIGINAL_MEDIA_ARTIFACT_TYPES)
    actual_types = {
        str(artifact.get("artifact_type"))
        for artifact in session.get("artifacts", [])
        if artifact.get("artifact_type") in expected_types
    }
    if actual_types != expected_types:
        fail(f"original artifact types mismatch: expected {sorted(expected_types)}, got {sorted(actual_types)}")

    verify_registered_artifacts(session_dir, expected_types)

    screen = artifact_by_type(session, "screen_video")
    assert_managed_relative_path(screen, "screen_video")
    if screen.get("capture_status") != "available":
        fail(f"screen_video must be available, got {screen.get('capture_status')!r}")
    screen_path = artifact_file_path(session_dir, screen)
    if not screen_path.is_file():
        fail(f"screen_video file is missing at {screen_path}")
    if screen_path.stat().st_size <= 0:
        fail("screen_video file must be non-empty")
    checksum = screen.get("checksum")
    if not isinstance(checksum, str) or not checksum.startswith("sha256:"):
        fail("screen_video checksum must be a sha256 value")
    if sha256_file(screen_path) != checksum:
        fail("screen_video checksum does not match file bytes")
    if summary.get("screen_video_checksum") != checksum:
        fail("ScreenCaptureKit summary checksum differs from processing contract checksum")

    expected_status = {
        "system_audio": "degraded" if summary.get("capture_system_audio") else "missing",
        "microphone_audio": "degraded" if summary.get("capture_microphone_audio") else "missing",
        "mixed_audio": "degraded"
        if summary.get("capture_system_audio") or summary.get("capture_microphone_audio")
        else "missing",
    }
    for artifact_type, status in expected_status.items():
        artifact = artifact_by_type(session, artifact_type)
        assert_managed_relative_path(artifact, artifact_type)
        if artifact.get("capture_status") != status:
            fail(f"{artifact_type} expected {status}, got {artifact.get('capture_status')!r}")
        if artifact.get("checksum"):
            fail(f"{artifact_type} {status} artifact must not include checksum")
        if not artifact.get("degradation_reason"):
            fail(f"{artifact_type} {status} artifact must include degradation_reason")


def run_generate_transcript_fail_closed(workspace: Path, session_id: str) -> None:
    env = os.environ.copy()
    for env_name in TRANSCRIPTION_ENV_NAMES:
        env.pop(env_name, None)
    env["MEETING_ASSISTANT_WORKSPACE"] = str(workspace)
    env["PYTHONPATH"] = f"{ROOT / 'platform/processing-cli/src'}{os.pathsep}{env.get('PYTHONPATH', '')}"

    completed = subprocess.run(
        [PYTHON, "-m", "meeting_assistant_cli", "generate_transcript", "--session-id", session_id],
        cwd=ROOT,
        env=env,
        text=True,
        capture_output=True,
        check=False,
    )
    if completed.returncode != 3:
        fail(
            "generate_transcript should fail closed with artifact_missing when real capture produced no usable audio; "
            f"exit={completed.returncode} stdout={completed.stdout!r} stderr={completed.stderr!r}"
        )
    if "Traceback" in completed.stdout or "Traceback" in completed.stderr:
        fail("generate_transcript failure must not leak a traceback")
    payload = load_single_json(completed.stdout, "generate_transcript")
    require_response(payload, "generate_transcript", ok=False, code="artifact_missing")


def assert_no_derived_artifact_pollution(session: dict) -> None:
    forbidden = {"normalized_audio", "transcript_text", "speaker_labels"}
    actual = {
        str(artifact.get("artifact_type"))
        for artifact in session.get("artifacts", [])
        if artifact.get("artifact_type") in forbidden
    }
    if actual:
        fail(f"fail-closed processing path must not register derived artifacts, got {sorted(actual)}")


def main() -> None:
    summary = json.loads(SUMMARY_PATH.read_text(encoding="utf-8"))
    if not isinstance(summary, dict):
        fail("native capture summary must be a JSON object")
    if summary.get("ok") is not True:
        fail(f"native capture summary did not pass: {summary}")

    workspace = Path(str(summary["workspace"]))
    session_id = str(summary["session_id"])
    session_dir = session_directory(workspace, session_id)
    session = load_session(session_dir)

    if session.get("id") != session_id:
        fail("session id drifted between native summary and session.json")
    if session.get("source_type") != "native_recording":
        fail("session source_type must be native_recording")
    if session.get("status") != "recorded":
        fail("session status must be recorded before processing consumption")
    if not session.get("ended_at"):
        fail("recorded native session must include ended_at")

    assert_original_artifact_contract(session_dir, session, summary)
    run_generate_transcript_fail_closed(workspace, session_id)
    assert_no_derived_artifact_pollution(load_session(session_dir))

    print(
        "VS-MA-14/15 real native capture artifact e2e marker [non-contract]: "
        "processing workspace contract consumed native session and no-audio transcript path failed closed."
    )
    print("real native capture artifact e2e smoke passed.")


try:
    main()
except ContractError as exc:
    fail(f"processing workspace contract rejected native session: code={exc.code} message={exc.message}")
PY
