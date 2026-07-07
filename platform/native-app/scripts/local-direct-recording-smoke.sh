#!/usr/bin/env bash
set -euo pipefail

component_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
root_dir="$(cd "$component_dir/../.." && pwd)"
cd "$root_dir"

timeout_seconds="${MA_NATIVE_LOCAL_APP_RECORDING_SMOKE_TIMEOUT_SECONDS:-150}"
recording_seconds="${MA_NATIVE_LOCAL_APP_RECORDING_SMOKE_DURATION_SECONDS:-4}"
report_dir="${MA_NATIVE_LOCAL_APP_RECORDING_SMOKE_REPORT_DIR:-$component_dir/build/local-direct-recording-smoke}"
report_file="$report_dir/local-direct-recording-smoke-report.json"
snapshot_file="$report_dir/local-direct-recording-ui-tree.txt"
runner_log="$report_dir/run-local-app.log"
audio_path="${MA_NATIVE_LOCAL_APP_RECORDING_SMOKE_AUDIO:-${MEETING_ASSISTANT_WHISPER_SMOKE_AUDIO:-}}"
workspace_dir="${MA_NATIVE_LOCAL_APP_RECORDING_SMOKE_WORKSPACE:-}"
workspace_temp_dir=""

usage() {
  cat <<'USAGE'
Usage: platform/native-app/scripts/local-direct-recording-smoke.sh [run-local-app options]

Launch the local-direct Release MeetingAssistantNative.app, press Start Recording
and Stop Recording through macOS Accessibility AXIdentifier controls, and verify
that the app reports a saved recording with real capture artifacts.

This opt-in smoke may trigger the app's normal macOS permission request path when
permissions are not already granted. It does not open System Settings, does not
modify TCC or system permissions, and does not require Developer ID/notarization.
USAGE
}

if [[ "${1:-}" == "--help" ]]; then
  usage
  exit 0
fi

for arg in "$@"; do
  if [[ "$arg" == "--workspace" ]]; then
    echo "error: local-direct recording smoke owns --workspace; use MA_NATIVE_LOCAL_APP_RECORDING_SMOKE_WORKSPACE instead." >&2
    exit 2
  fi
done

mkdir -p "$report_dir"

if [[ -z "$workspace_dir" ]]; then
  workspace_temp_dir="$(mktemp -d)"
  workspace_dir="$workspace_temp_dir/workspace"
fi
mkdir -p "$workspace_dir"

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
  if [[ -n "$workspace_temp_dir" ]]; then
    rm -rf "$workspace_temp_dir"
  fi
  exit "$exit_code"
}
trap cleanup EXIT INT TERM

"$component_dir/scripts/run-local-app.sh" --workspace "$workspace_dir" "$@" >"$runner_log" 2>&1 &
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
    echo "local-direct recording smoke failed: run-local-app exited before the app became visible." >&2
    cat "$runner_log" >&2 || true
    exit 1
  fi
  sleep 0.5
done

if [[ -z "$app_pid" ]]; then
  echo "local-direct recording smoke failed: timed out waiting for MeetingAssistantNative process." >&2
  cat "$runner_log" >&2 || true
  exit 1
fi

python3 - "$report_file" "$snapshot_file" "$runner_log" "$app_pid" "$workspace_dir" "$timeout_seconds" "$recording_seconds" "$audio_path" <<'PY'
import json
import os
import subprocess
import sys
import time
from pathlib import Path
from typing import Optional, Tuple

report_path = Path(sys.argv[1])
snapshot_path = Path(sys.argv[2])
runner_log_path = Path(sys.argv[3])
app_pid = int(sys.argv[4])
workspace_dir = Path(sys.argv[5])
timeout_seconds = int(sys.argv[6])
recording_seconds = float(sys.argv[7])
audio_path = sys.argv[8].strip()

start_time = time.monotonic()
last_snapshot = ""
checked_markers: list[str] = []
pressed_controls: list[str] = []
blocker_type = "none"
blocker_detail = ""


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


def snapshot(timeout: int = 30) -> str:
    global last_snapshot
    text = run_osascript(SNAPSHOT_SCRIPT, [str(app_pid)], timeout)
    last_snapshot = text
    snapshot_path.write_text(text, encoding="utf-8")
    return text


def classify_snapshot(text: str) -> Tuple[Optional[str], Optional[str]]:
    lowered = text.lower()
    if "permission_denied" in lowered or "permissions are denied" in lowered:
        return "permission_denied", "recording permission was denied or unknown"
    if "capture_failed" in lowered or "recording failed." in text:
        return "capture_failed", "recording command failed"
    if "path_conflict" in lowered or "recording session already exists" in lowered:
        return "path_conflict", "recording session path already exists"
    if "dependency_missing" in lowered:
        return "dependency_missing", "required local dependency is missing"
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


def press(identifier: str) -> None:
    run_osascript(PRESS_SCRIPT, [str(app_pid), identifier], timeout=20)
    pressed_controls.append(identifier)


def start_audio_playback() -> Optional[subprocess.Popen]:
    if not audio_path:
        return None
    candidate = Path(audio_path).expanduser()
    if not candidate.is_file():
        raise SmokeFailure("audio_fixture_missing", f"audio fixture is missing: {candidate}")
    return subprocess.Popen(
        ["/usr/bin/afplay", str(candidate)],
        stdout=subprocess.DEVNULL,
        stderr=subprocess.DEVNULL,
    )


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


def permission_failure_details(text: str) -> list[str]:
    details: list[str] = []
    for marker in (
        "Screen Recording permission is denied.",
        "Screen Recording permission status is unknown.",
        "Microphone permission is denied.",
        "Microphone permission status is unknown.",
    ):
        if marker in text:
            details.append(marker)
    return details


def write_report(passed: bool) -> None:
    config = runner_configuration()
    launch_mode = config.get("launch_mode", "")
    permission_denied = blocker_type == "permission_denied"
    report = {
        "report_schema": 1,
        "release_gate": "local-direct-recording-smoke",
        "passed": passed,
        "blocker_type": blocker_type,
        "blocker_detail": blocker_detail,
        "app_pid": app_pid,
        "workspace": str(workspace_dir),
        "runner_configuration": config,
        "app_identity": app_identity(config),
        "ui_tree": str(snapshot_path),
        "runner_log": str(runner_log_path),
        "recording_request": {
            "capture_system_audio": config.get("capture_system_audio"),
            "capture_microphone_audio": config.get("capture_microphone_audio"),
        },
        "permission_failure_details": permission_failure_details(last_snapshot),
        "checked_markers": checked_markers,
        "pressed_controls": pressed_controls,
        "recording_duration_seconds": recording_seconds,
        "audio_playback_requested": bool(audio_path),
        "workspace_files": workspace_files()[:80],
        "workspace_precondition": "Use an empty smoke workspace or leave MA_NATIVE_LOCAL_APP_RECORDING_SMOKE_WORKSPACE unset for a temporary workspace.",
        "starts_recording": True,
        "opens_system_settings": False,
        "modifies_tcc_or_system_settings": False,
        "may_request_macos_permissions": True,
        "tcc_remediation": "Grant Screen & System Audio Recording and Microphone permissions to the exact app_identity.path, then relaunch and retry.",
        "tcc_identity_mismatch_hint": "If System Settings shows MeetingAssistantNative enabled but this report still says permission_denied, remove the stale entry and add the exact app_identity.path again.",
        "direct_launch_diagnostic_hint": (
            "If LaunchServices open is denied but the exact app appears authorized, rerun with "
            "MA_NATIVE_LOCAL_APP_LAUNCH_MODE=direct to distinguish local capture functionality "
            "from LaunchServices/TCC attribution."
            if permission_denied and launch_mode != "direct"
            else ""
        ),
        "launch_attribution_boundary": (
            "direct launch is executable diagnostic evidence only; the default local user path remains LaunchServices open."
            if launch_mode == "direct"
            else "LaunchServices open is the default local user path."
        ),
        "requires_developer_id_or_notarization": False,
        "not_release_readiness": True,
    }
    report_path.write_text(json.dumps(report, ensure_ascii=False, indent=2) + "\n", encoding="utf-8")


playback: Optional[subprocess.Popen] = None
try:
    wait_for_marker("Recording readiness is ready.", min(timeout_seconds, 60))
    press("ma.recording.startButton")
    wait_for_marker("Recording in progress.", min(timeout_seconds, 60))
    playback = start_audio_playback()
    time.sleep(recording_seconds)
    press("ma.recording.stopButton")
    saved_snapshot = wait_for_marker("Recording saved.", timeout_seconds)
    for marker in ("screen_video: available", "mixed_audio: available"):
        if marker not in saved_snapshot:
            raise SmokeFailure("artifact_marker_missing", f"missing artifact marker: {marker}")
        checked_markers.append(marker)
    write_report(True)
except SmokeFailure as exc:
    blocker_type = exc.kind
    blocker_detail = exc.detail
    try:
        snapshot(timeout=15)
    except SmokeFailure:
        pass
    write_report(False)
    print(f"local-direct recording smoke failed: {blocker_type}: {blocker_detail}", file=sys.stderr)
    print(f"report: {report_path}", file=sys.stderr)
    sys.exit(1)
finally:
    if playback is not None and playback.poll() is None:
        playback.terminate()
        try:
            playback.wait(timeout=3)
        except subprocess.TimeoutExpired:
            playback.kill()
            playback.wait(timeout=3)

print("local-direct recording smoke passed.")
print(f"report: {report_path}")
PY
