#!/usr/bin/env bash
set -euo pipefail

component_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
root_dir="$(cd "$component_dir/../.." && pwd)"
cd "$root_dir"

timeout_seconds="${MA_NATIVE_LOCAL_APP_PROCESSING_SMOKE_TIMEOUT_SECONDS:-300}"
report_dir="${MA_NATIVE_LOCAL_APP_PROCESSING_SMOKE_REPORT_DIR:-$component_dir/build/local-direct-processing-smoke}"
report_file="$report_dir/local-direct-processing-smoke-report.json"
snapshot_file="$report_dir/local-direct-processing-ui-tree.txt"
runner_log="$report_dir/run-local-app.log"
workspace_dir="${MA_NATIVE_LOCAL_APP_PROCESSING_SMOKE_WORKSPACE:-$component_dir/build/local-direct-recording-smoke-direct/workspace}"
session_id="${MA_NATIVE_LOCAL_APP_PROCESSING_SMOKE_SESSION_ID:-session-app-ui-blocked}"
expected_terms="${MA_NATIVE_LOCAL_APP_PROCESSING_SMOKE_EXPECTED_TERMS:-}"
allow_preexisting_artifacts="${MA_NATIVE_LOCAL_APP_PROCESSING_SMOKE_ALLOW_PREEXISTING_ARTIFACTS:-0}"
ax_helper="$report_dir/local-app-ax-helper"

usage() {
  cat <<'USAGE'
Usage: platform/native-app/scripts/local-direct-processing-smoke.sh [run-local-app options]

Launch the local-direct Release MeetingAssistantNative.app with an existing
recorded workspace/session, press Start Processing through macOS Accessibility
AXIdentifier controls, and verify that real processing writes normalized audio,
transcript, and speaker-label artifacts.

This smoke consumes an existing recording; it does not start recording, does not
open System Settings, does not modify TCC or system permissions, and does not
require Developer ID/notarization.
USAGE
}

if [[ "${1:-}" == "--help" ]]; then
  usage
  exit 0
fi

for arg in "$@"; do
  case "$arg" in
    --workspace)
      echo "error: local-direct processing smoke owns --workspace; use MA_NATIVE_LOCAL_APP_PROCESSING_SMOKE_WORKSPACE instead." >&2
      exit 2
      ;;
    --ma-native-transcript-workspace* | --ma-native-transcript-session-id* | --)
      echo "error: local-direct processing smoke owns native transcript app args." >&2
      exit 2
      ;;
  esac
done

mkdir -p "$report_dir"
swiftc "$component_dir/scripts/local-app-ax.swift" -o "$ax_helper"

collect_pids() {
  /usr/bin/pgrep -x MeetingAssistantNative 2>/dev/null || true
}

pid_is_new() {
  local candidate="$1"
  local existing
  for existing in ${before_pids:-}; do
    if [[ "$candidate" == "$existing" ]]; then
      return 1
    fi
  done
  return 0
}

before_pids="$(collect_pids)"
runner_pid=""
app_pid=""

cleanup() {
  local exit_code=$?
  if [[ -n "$app_pid" ]]; then
    /bin/kill "$app_pid" >/dev/null 2>&1 || true
  fi
  if [[ -n "$runner_pid" ]]; then
    wait "$runner_pid" >/dev/null 2>&1 || true
  fi
  exit "$exit_code"
}
trap cleanup EXIT INT TERM

"$component_dir/scripts/run-local-app.sh" \
  --workspace "$workspace_dir" \
  "$@" \
  -- \
  "--ma-native-transcript-workspace=$workspace_dir" \
  "--ma-native-transcript-session-id=$session_id" >"$runner_log" 2>&1 &
runner_pid=$!

deadline=$((SECONDS + timeout_seconds))
while [[ $SECONDS -lt $deadline ]]; do
  current_pids="$(collect_pids)"
  for pid in $current_pids; do
    if pid_is_new "$pid"; then
      app_pid="$pid"
      break
    fi
  done
  if [[ -n "$app_pid" ]]; then
    break
  fi
  if ! kill -0 "$runner_pid" >/dev/null 2>&1; then
    echo "local-direct processing smoke failed: run-local-app exited before the app became visible." >&2
    cat "$runner_log" >&2 || true
    exit 1
  fi
  sleep 0.5
done

if [[ -z "$app_pid" ]]; then
  echo "local-direct processing smoke failed: timed out waiting for MeetingAssistantNative process." >&2
  cat "$runner_log" >&2 || true
  exit 1
fi

python3 - "$report_file" "$snapshot_file" "$runner_log" "$app_pid" "$workspace_dir" "$session_id" "$timeout_seconds" "$expected_terms" "$allow_preexisting_artifacts" "$ax_helper" <<'PY'
import json
import subprocess
import sys
import time
from pathlib import Path
from typing import Any, Optional, Tuple

report_path = Path(sys.argv[1])
snapshot_path = Path(sys.argv[2])
runner_log_path = Path(sys.argv[3])
app_pid = int(sys.argv[4])
workspace_dir = Path(sys.argv[5])
session_id = sys.argv[6]
timeout_seconds = int(sys.argv[7])
expected_terms_raw = sys.argv[8].strip()
allow_preexisting_artifacts = sys.argv[9].strip().lower() in {"1", "true", "yes"}
AX_HELPER = Path(sys.argv[10])

last_snapshot = ""
checked_markers: list[str] = []
pressed_controls: list[str] = []
blocker_type = "none"
blocker_detail = ""
success_marker = ""
preexisting_processing_artifacts: list[str] = []


SNAPSHOT_SCRIPT = r'''
on run argv
  set targetPid to item 1 of argv as integer
  tell application "System Events"
    set targetProcesses to processes whose unix id is targetPid
    if (count of targetProcesses) = 0 then error "MeetingAssistantNative process was not visible to System Events"
    tell item 1 of targetProcesses
      set frontmost to true
      repeat with attemptIndex from 1 to 20
        if (count of windows) > 0 then exit repeat
        delay 0.25
      end repeat
      if (count of windows) = 0 then error "MeetingAssistantNative window was not visible"
      set outputText to ""
      set allElements to entire contents of window 1
      repeat with elementRef in allElements
        try
          set outputText to outputText & " identifier=" & (value of attribute "AXIdentifier" of elementRef as text)
        end try
        try
          set outputText to outputText & " enabled=" & (value of attribute "AXEnabled" of elementRef as text)
        end try
        try
          set outputText to outputText & " role=" & (role of elementRef as text)
        end try
        try
          set outputText to outputText & " subrole=" & (subrole of elementRef as text)
        end try
        try
          set outputText to outputText & " name=" & (name of elementRef as text)
        end try
        try
          set outputText to outputText & " description=" & (description of elementRef as text)
        end try
        try
          set outputText to outputText & " value=" & (value of elementRef as text)
        end try
        set outputText to outputText & linefeed
      end repeat
      return outputText
    end tell
  end tell
end run
'''

PRESS_SCRIPT = r'''
on run argv
  set targetPid to item 1 of argv as integer
  set targetIdentifier to item 2 of argv as text
  tell application "System Events"
    set targetProcesses to processes whose unix id is targetPid
    if (count of targetProcesses) = 0 then error "MeetingAssistantNative process was not visible to System Events"
    tell item 1 of targetProcesses
      set frontmost to true
      repeat with attemptIndex from 1 to 20
        if (count of windows) > 0 then exit repeat
        delay 0.25
      end repeat
      if (count of windows) = 0 then error "MeetingAssistantNative window was not visible"
      set allElements to entire contents of window 1
      repeat with elementRef in allElements
        try
          if (value of attribute "AXIdentifier" of elementRef as text) is targetIdentifier then
            perform action "AXPress" of elementRef
            return "pressed " & targetIdentifier
          end if
        end try
      end repeat
      error "Missing AXIdentifier " & targetIdentifier
    end tell
  end tell
end run
'''


class SmokeFailure(Exception):
    def __init__(self, kind: str, detail: str) -> None:
        super().__init__(detail)
        self.kind = kind
        self.detail = detail


def run_osascript(script: str, args: list[str], timeout: int) -> str:
    try:
        completed = subprocess.run(
            ["/usr/bin/osascript", "-", *args],
            input=script,
            text=True,
            stdout=subprocess.PIPE,
            stderr=subprocess.PIPE,
            timeout=timeout,
            check=False,
        )
    except subprocess.TimeoutExpired as exc:
        raise SmokeFailure("accessibility_timeout", f"osascript timed out after {timeout}s") from exc
    if completed.returncode != 0:
        raise SmokeFailure(
            "accessibility_error",
            (completed.stderr or completed.stdout or "osascript failed").strip(),
        )
    return completed.stdout


def run_ax_helper(command: str, args: list[str], timeout: int) -> str:
    if not AX_HELPER.is_file():
        raise SmokeFailure("accessibility_error", f"missing AX helper: {AX_HELPER}")
    try:
        completed = subprocess.run(
            [str(AX_HELPER), command, str(timeout), str(app_pid), *args],
            text=True,
            stdout=subprocess.PIPE,
            stderr=subprocess.PIPE,
            timeout=timeout + 30,
            check=False,
        )
    except subprocess.TimeoutExpired as exc:
        raise SmokeFailure("accessibility_timeout", f"AX helper timed out after {timeout}s") from exc
    if completed.returncode != 0:
        raise SmokeFailure(
            "accessibility_error",
            (completed.stderr or completed.stdout or "AX helper failed").strip(),
        )
    return completed.stdout


def snapshot(timeout: int = 30) -> str:
    global last_snapshot
    text = run_ax_helper("snapshot", [], timeout)
    last_snapshot = text
    snapshot_path.write_text(text, encoding="utf-8")
    return text


def classify_snapshot(text: str) -> Tuple[Optional[str], Optional[str]]:
    lowered = text.lower()
    if "dependency_missing" in lowered or "required processing dependency is missing" in lowered:
        return "dependency_missing", "required local processing dependency is missing"
    if "path_conflict" in lowered or "processing path conflict" in lowered:
        return "path_conflict", "processing path conflict"
    if "artifact_missing" in lowered or "required processing artifact is missing" in lowered:
        return "artifact_missing", "required processing artifact is missing"
    if "processing failed." in text or "processing_failed" in lowered:
        return "processing_failed", "processing command failed"
    if "processing is blocked" in lowered:
        return "dependency_missing", "processing remained blocked by readiness"
    return None, None


def wait_for_marker(marker: str, timeout: int) -> str:
    deadline = time.monotonic() + timeout
    last_error = None
    while time.monotonic() < deadline:
        try:
            text = snapshot()
        except SmokeFailure as exc:
            last_error = exc
            time.sleep(1)
            continue
        failure_kind, failure_detail = classify_snapshot(text)
        if failure_kind:
            raise SmokeFailure(failure_kind, failure_detail or failure_kind)
        if marker in text:
            checked_markers.append(marker)
            return text
        time.sleep(1)
    if last_error is not None:
        raise last_error
    raise SmokeFailure("ui_marker_timeout", f"timed out waiting for {marker}")


def wait_for_success(timeout: int) -> str:
    global success_marker
    markers = [
        "Processing complete.",
        "Processing completed with transcript-only speaker labels.",
    ]
    deadline = time.monotonic() + timeout
    last_error = None
    while time.monotonic() < deadline:
        try:
            text = snapshot()
        except SmokeFailure as exc:
            last_error = exc
            time.sleep(1)
            continue
        failure_kind, failure_detail = classify_snapshot(text)
        if failure_kind:
            raise SmokeFailure(failure_kind, failure_detail or failure_kind)
        for marker in markers:
            if marker in text:
                success_marker = marker
                checked_markers.append(marker)
                return text
        time.sleep(1)
    if last_error is not None:
        raise last_error
    raise SmokeFailure("ui_marker_timeout", "timed out waiting for processing completion")


def press(identifier: str) -> None:
    run_ax_helper("press", [identifier], timeout=20)
    pressed_controls.append(identifier)


def load_json(path: Path) -> Any:
    return json.loads(path.read_text(encoding="utf-8"))


def session_root() -> Path:
    return workspace_dir / "sessions" / session_id


def session_json_path() -> Path:
    return session_root() / "session.json"


def workspace_files() -> list[str]:
    if not workspace_dir.exists():
        return []
    return sorted(
        str(path.relative_to(workspace_dir))
        for path in workspace_dir.rglob("*")
        if path.is_file()
    )


def runner_configuration() -> dict[str, str]:
    if not runner_log_path.exists():
        return {}
    config: dict[str, str] = {}
    for line in runner_log_path.read_text(encoding="utf-8", errors="replace").splitlines():
        stripped = line.strip()
        if ": " not in stripped:
            continue
        key, value = stripped.split(": ", 1)
        normalized_key = key.lower().replace(" ", "_")
        if normalized_key in {
            "app",
            "cli",
            "workspace",
            "launch_mode",
            "capture_system_audio",
            "capture_microphone_audio",
            "processing_runtime",
            "transcription_runtime",
            "transcription_model",
        }:
            config[normalized_key] = value
    return config


def app_identity(config: dict[str, str]) -> dict[str, object]:
    app_path = config.get("app", "")
    if not app_path:
        return {}
    app = Path(app_path)
    info_plist = app / "Contents" / "Info.plist"
    identity: dict[str, object] = {"path": app_path}
    if info_plist.exists():
        for key in ("CFBundleIdentifier", "CFBundleName", "CFBundleShortVersionString"):
            completed = subprocess.run(
                ["/usr/bin/defaults", "read", str(info_plist), key],
                text=True,
                stdout=subprocess.PIPE,
                stderr=subprocess.DEVNULL,
                check=False,
            )
            if completed.returncode == 0:
                identity[key] = completed.stdout.strip()
    completed = subprocess.run(
        ["/usr/bin/codesign", "-dv", "--verbose=4", app_path],
        text=True,
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
        check=False,
    )
    if completed.returncode == 0:
        fields: dict[str, str] = {}
        for line in (completed.stderr or completed.stdout).splitlines():
            if "=" in line:
                key, value = line.split("=", 1)
                key = key.strip()
                if key in {"Identifier", "Format", "Signature", "TeamIdentifier", "CDHash"}:
                    fields[key] = value.strip()
        identity["codesign"] = fields
    return identity


def session_artifacts() -> list[dict[str, Any]]:
    path = session_json_path()
    if not path.exists():
        raise SmokeFailure("recorded_session_missing", f"session.json is missing: {path}")
    session = load_json(path)
    if session.get("id") != session_id:
        raise SmokeFailure("recorded_session_invalid", "session id does not match requested smoke session")
    artifacts = session.get("artifacts")
    if not isinstance(artifacts, list):
        raise SmokeFailure("recorded_session_invalid", "session artifacts must be a list")
    return [artifact for artifact in artifacts if isinstance(artifact, dict)]


def artifact_path(artifact: dict[str, Any]) -> Path:
    raw_path = artifact.get("path")
    if not isinstance(raw_path, str) or not raw_path:
        raise SmokeFailure("artifact_missing", f"{artifact.get('artifact_type', '<unknown>')} artifact path is missing")
    path = Path(raw_path)
    if not path.is_absolute():
        path = session_root() / path
    resolved = path.resolve(strict=False)
    resolved_root = session_root().resolve(strict=False)
    if not (resolved == resolved_root or resolved_root in resolved.parents):
        raise SmokeFailure("path_conflict", f"artifact path escapes the session root: {raw_path}")
    return resolved


def artifact_by_type(artifacts: list[dict[str, Any]], artifact_type: str) -> dict[str, Any]:
    for artifact in artifacts:
        if artifact.get("artifact_type") == artifact_type:
            return artifact
    raise SmokeFailure("artifact_missing", f"{artifact_type} artifact is missing from session.json")


def preexisting_artifact_types() -> list[str]:
    try:
        artifacts = session_artifacts()
    except SmokeFailure:
        return []
    return [
        str(artifact.get("artifact_type"))
        for artifact in artifacts
        if artifact.get("artifact_type") in {"normalized_audio", "transcript_text", "speaker_labels"}
    ]


def validate_recorded_input() -> None:
    artifacts = session_artifacts()
    mixed_audio = artifact_by_type(artifacts, "mixed_audio")
    if mixed_audio.get("capture_status") != "available":
        raise SmokeFailure("artifact_missing", "mixed_audio artifact is not available")
    if not artifact_path(mixed_audio).is_file():
        raise SmokeFailure("artifact_missing", "mixed_audio file is missing")

    global preexisting_processing_artifacts
    preexisting_processing_artifacts = preexisting_artifact_types()
    if preexisting_processing_artifacts and not allow_preexisting_artifacts:
        raise SmokeFailure(
            "path_conflict",
            "processing artifacts already exist; rerun recording smoke with a clean workspace "
            "or set MA_NATIVE_LOCAL_APP_PROCESSING_SMOKE_ALLOW_PREEXISTING_ARTIFACTS=1",
        )


def validate_processing_artifacts() -> dict[str, Any]:
    artifacts = session_artifacts()
    normalized = artifact_by_type(artifacts, "normalized_audio")
    transcript_artifact = artifact_by_type(artifacts, "transcript_text")
    speaker_artifact = artifact_by_type(artifacts, "speaker_labels")

    for expected_type, artifact in {
        "normalized_audio": normalized,
        "transcript_text": transcript_artifact,
        "speaker_labels": speaker_artifact,
    }.items():
        if artifact.get("capture_status") not in {"available", "degraded"}:
            raise SmokeFailure("processing_failed", f"{expected_type} artifact is not available or degraded")
        if not artifact_path(artifact).is_file():
            raise SmokeFailure("artifact_missing", f"{expected_type} file is missing")

    transcript_path = artifact_path(transcript_artifact)
    transcript = load_json(transcript_path)
    if transcript.get("session_id") != session_id or transcript.get("status") != "succeeded":
        raise SmokeFailure("processing_failed", "transcript.json session or status is invalid")
    segments = transcript.get("segments")
    if not isinstance(segments, list) or not segments:
        raise SmokeFailure("processing_failed", "transcript.json must contain at least one segment")
    transcript_text = " ".join(
        str(segment.get("text", ""))
        for segment in segments
        if isinstance(segment, dict)
    )
    if not transcript_text.strip():
        raise SmokeFailure("processing_failed", "transcript text is empty")

    expected_terms = [
        term.strip()
        for term in expected_terms_raw.split(",")
        if term.strip()
    ]
    lower_text = transcript_text.lower()
    missing_terms = [term for term in expected_terms if term.lower() not in lower_text]
    if missing_terms:
        raise SmokeFailure("processing_failed", f"missing expected transcript terms: {', '.join(missing_terms)}")

    speaker_path = artifact_path(speaker_artifact)
    speaker_labels = load_json(speaker_path)
    if speaker_labels.get("session_id") != session_id:
        raise SmokeFailure("processing_failed", "speaker_labels.json session is invalid")
    label_status = speaker_labels.get("label_status")
    if not isinstance(label_status, str) or not label_status:
        raise SmokeFailure("processing_failed", "speaker_labels.json label_status is missing")
    if label_status == "transcript_only" and not speaker_labels.get("degradation_reason"):
        raise SmokeFailure("processing_failed", "transcript-only speaker labels must include a degradation reason")

    return {
        "normalized_audio": {
            "id": normalized.get("id"),
            "status": normalized.get("capture_status"),
            "path": str(artifact_path(normalized)),
        },
        "transcript_text": {
            "id": transcript_artifact.get("id"),
            "status": transcript_artifact.get("capture_status"),
            "path": str(transcript_path),
            "transcript_id": transcript.get("id"),
            "segment_count": len(segments),
            "expected_terms_checked": expected_terms,
            "expected_terms_found": expected_terms,
        },
        "speaker_labels": {
            "id": speaker_artifact.get("id"),
            "status": speaker_artifact.get("capture_status"),
            "path": str(speaker_path),
            "label_status": label_status,
            "degradation_reason": speaker_labels.get("degradation_reason"),
        },
    }


def write_report(passed: bool, processing_artifacts: Optional[dict[str, Any]] = None) -> None:
    config = runner_configuration()
    launch_mode = config.get("launch_mode", "")
    report = {
        "report_schema": 1,
        "release_gate": "local-direct-processing-smoke",
        "passed": passed,
        "blocker_type": blocker_type,
        "blocker_detail": blocker_detail,
        "app_pid": app_pid,
        "workspace": str(workspace_dir),
        "session_id": session_id,
        "runner_configuration": config,
        "app_identity": app_identity(config),
        "ui_tree": str(snapshot_path),
        "runner_log": str(runner_log_path),
        "checked_markers": checked_markers,
        "pressed_controls": pressed_controls,
        "success_marker": success_marker,
        "preexisting_processing_artifacts": preexisting_processing_artifacts,
        "processing_artifacts": processing_artifacts or {},
        "workspace_files": workspace_files()[:120],
        "workspace_precondition": (
            "Requires an existing recorded session from local-direct-recording-smoke or an equivalent "
            "native recording workspace; use a clean workspace for fresh processing evidence."
        ),
        "recording_input_boundary": "This smoke consumes existing recording artifacts and does not start recording.",
        "starts_recording": False,
        "starts_processing": True,
        "opens_system_settings": False,
        "modifies_tcc_or_system_settings": False,
        "may_request_macos_permissions": False,
        "launch_attribution_boundary": (
            "direct launch is executable diagnostic evidence only; the default local user path remains LaunchServices open."
            if launch_mode == "direct"
            else "LaunchServices open is the default local user path."
        ),
        "requires_developer_id_or_notarization": False,
        "not_release_readiness": True,
    }
    report_path.write_text(json.dumps(report, ensure_ascii=False, indent=2) + "\n", encoding="utf-8")


try:
    validate_recorded_input()
    wait_for_marker("Processing is ready to run.", min(timeout_seconds, 90))
    press("ma.processing.startButton")
    wait_for_success(timeout_seconds)
    processing_artifacts = validate_processing_artifacts()
    write_report(True, processing_artifacts=processing_artifacts)
except SmokeFailure as exc:
    blocker_type = exc.kind
    blocker_detail = exc.detail
    try:
        snapshot(timeout=15)
    except SmokeFailure:
        pass
    write_report(False)
    print(f"local-direct processing smoke failed: {blocker_type}: {blocker_detail}", file=sys.stderr)
    print(f"report: {report_path}", file=sys.stderr)
    sys.exit(1)

print("local-direct processing smoke passed.")
print(f"report: {report_path}")
PY
