#!/usr/bin/env bash
set -euo pipefail

component_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
root_dir="$(cd "$component_dir/../.." && pwd)"
cd "$root_dir"

timeout_seconds="${MA_NATIVE_LOCAL_APP_SMOKE_TIMEOUT_SECONDS:-45}"
report_dir="${MA_NATIVE_LOCAL_APP_SMOKE_REPORT_DIR:-$component_dir/build/local-direct-smoke}"
report_file="$report_dir/local-direct-smoke-report.json"
ui_tree_file="$report_dir/local-direct-ui-tree.txt"
runner_log="$report_dir/run-local-app.log"
reuse_existing="${MA_NATIVE_LOCAL_APP_SMOKE_REUSE_EXISTING:-0}"
capture_system_audio="${MA_NATIVE_CAPTURE_SMOKE_SYSTEM_AUDIO:-true}"
capture_microphone_audio="${MA_NATIVE_CAPTURE_SMOKE_MICROPHONE_AUDIO:-false}"

usage() {
  cat <<'USAGE'
Usage: platform/native-app/scripts/local-direct-smoke.sh [run-local-app options]

Launch the local-direct Release MeetingAssistantNative.app with run-local-app.sh,
read the visible UI through macOS Accessibility, and verify that the designed
shell, preflight, recording, and processing controls are present.

This smoke does not click recording controls, does not open System Settings, and
does not modify TCC or system permissions. It only proves the normal local GUI
launch and visible readiness surface.
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

recording_setup_marker_for_request() {
  local capture_system="$1"
  local capture_microphone="$2"
  if is_truthy "$capture_system" && is_truthy "$capture_microphone"; then
    printf '%s\n' "Capture target: screen. System audio and microphone capture are requested through the recording command client."
  elif is_truthy "$capture_system"; then
    printf '%s\n' "Capture target: screen. System audio capture is requested; microphone capture is not requested for this run."
  elif is_truthy "$capture_microphone"; then
    printf '%s\n' "Capture target: screen. Microphone capture is requested; system audio capture is not requested for this run."
  else
    printf '%s\n' "Capture target: screen. Audio capture is not requested for this run; unavailable audio artifacts must stay missing with reasons."
  fi
}

if [[ "${1:-}" == "--help" ]]; then
  usage
  exit 0
fi

mkdir -p "$report_dir"
expected_recording_setup_marker="$(
  recording_setup_marker_for_request "$capture_system_audio" "$capture_microphone_audio"
)"

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
app_pid_owned=0

cleanup() {
  local exit_code=$?
  if [[ -n "$app_pid" && "$app_pid_owned" == "1" ]]; then
    /bin/kill "$app_pid" >/dev/null 2>&1 || true
  fi
  if [[ -n "$runner_pid" ]]; then
    wait "$runner_pid" >/dev/null 2>&1 || true
  fi
  exit "$exit_code"
}
trap cleanup EXIT INT TERM

"$component_dir/scripts/run-local-app.sh" "$@" >"$runner_log" 2>&1 &
runner_pid=$!

deadline=$((SECONDS + timeout_seconds))
while [[ $SECONDS -lt $deadline ]]; do
  current_pids="$(collect_pids)"
  for pid in $current_pids; do
    if pid_is_new "$pid"; then
      app_pid="$pid"
      app_pid_owned=1
      break
    fi
    if is_truthy "$reuse_existing"; then
      app_pid="$pid"
      app_pid_owned=0
      break
    fi
  done
  if [[ -n "$app_pid" ]]; then
    break
  fi
  if ! kill -0 "$runner_pid" >/dev/null 2>&1; then
    echo "local-direct smoke failed: run-local-app exited before the app became visible." >&2
    cat "$runner_log" >&2 || true
    exit 1
  fi
  sleep 0.5
done

if [[ -z "$app_pid" ]]; then
  echo "local-direct smoke failed: timed out waiting for MeetingAssistantNative process." >&2
  cat "$runner_log" >&2 || true
  exit 1
fi

ui_tree="$(osascript - "$timeout_seconds" "$app_pid" <<'OSA'
on run argv
  set timeoutSeconds to item 1 of argv as integer
  set targetPid to item 2 of argv as integer
  tell application "System Events"
    set targetProcesses to processes whose unix id is targetPid
    if (count of targetProcesses) = 0 then error "MeetingAssistantNative process was not visible to System Events"
    tell item 1 of targetProcesses
      set frontmost to true
      repeat with attemptIndex from 1 to timeoutSeconds
        if (count of windows) > 0 then exit repeat
        delay 1
      end repeat
      if (count of windows) = 0 then error "MeetingAssistantNative window was not visible"
      set outputText to ""
      set allElements to entire contents of window 1
      repeat with elementRef in allElements
        try
          set outputText to outputText & " role=" & (role of elementRef as text)
        end try
        try
          set outputText to outputText & " identifier=" & (value of attribute "AXIdentifier" of elementRef as text)
        end try
        try
          set outputText to outputText & " enabled=" & (value of attribute "AXEnabled" of elementRef as text)
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
OSA
)"

printf '%s\n' "$ui_tree" > "$ui_tree_file"

required_markers=(
  "Meeting Assistant"
  "Preflight: Ready"
  "Recording: Ready"
  "Processing: Ready"
  "Recording readiness is ready."
  "Processing is ready to run."
  "$expected_recording_setup_marker"
)

missing_markers=()
for marker in "${required_markers[@]}"; do
  if [[ "$ui_tree" != *"$marker"* ]]; then
    missing_markers+=("$marker")
  fi
done

if [[ ${#missing_markers[@]} -gt 0 ]]; then
  echo "local-direct smoke failed: missing UI markers: ${missing_markers[*]}" >&2
  echo "UI tree: $ui_tree_file" >&2
  exit 1
fi

python3 - "$report_file" "$ui_tree_file" "$runner_log" "$app_pid" \
  "$expected_recording_setup_marker" "$capture_system_audio" "$capture_microphone_audio" <<'PY'
import json
import os
import re
import sys
from pathlib import Path

report_path = Path(sys.argv[1])
ui_tree_path = Path(sys.argv[2])
runner_log = Path(sys.argv[3])
app_pid = int(sys.argv[4])
expected_recording_setup_marker = sys.argv[5]
capture_system_audio = sys.argv[6]
capture_microphone_audio = sys.argv[7]
ui_tree = ui_tree_path.read_text(encoding="utf-8")


def is_truthy(value):
    return value in {"1", "true", "TRUE", "yes", "YES"}


required_controls = {
    "ma.recording.startButton": True,
    "ma.recording.stopButton": False,
    "ma.processing.startButton": True,
    "ma.processing.retryButton": False,
}
controls = {}
for line in ui_tree.splitlines():
    identifier_match = re.search(r"\bidentifier=([^ ]+)", line)
    if not identifier_match:
        continue
    enabled_match = re.search(r"\benabled=(true|false)", line)
    controls[identifier_match.group(1)] = {
        "enabled": enabled_match.group(1) == "true" if enabled_match else None,
    }

control_errors = []
for identifier, expected_enabled in required_controls.items():
    control = controls.get(identifier)
    if control is None:
        control_errors.append(f"{identifier} missing")
        continue
    actual_enabled = control["enabled"]
    if actual_enabled is not expected_enabled:
        control_errors.append(
            f"{identifier} enabled={actual_enabled!r}, expected {expected_enabled!r}"
        )
if control_errors:
    for error in control_errors:
        print(f"local-direct smoke failed: {error}", file=sys.stderr)
    print(f"UI tree: {ui_tree_path}", file=sys.stderr)
    sys.exit(1)

report = {
    "report_schema": 1,
    "release_gate": "local-direct-ui-smoke",
    "app_pid": app_pid,
    "ui_tree": str(ui_tree_path),
    "runner_log": str(runner_log),
    "checked_markers": [
        "Meeting Assistant",
        "Preflight: Ready",
        "Recording: Ready",
        "Processing: Ready",
        "Recording readiness is ready.",
        "Processing is ready to run.",
        expected_recording_setup_marker,
    ],
    "checked_recording_setup_text": expected_recording_setup_marker,
    "recording_request": {
        "capture_system_audio": is_truthy(capture_system_audio),
        "capture_microphone_audio": is_truthy(capture_microphone_audio),
    },
    "checked_controls": [
        {
            "identifier": identifier,
            "enabled": controls[identifier]["enabled"],
        }
        for identifier in required_controls
    ],
    "verifies_action_control_identifiers": True,
    "modifies_tcc_or_system_settings": False,
    "opens_system_settings": False,
    "starts_recording": False,
    "requires_developer_id_or_notarization": False,
    "workspace": os.environ.get("MEETING_ASSISTANT_WORKSPACE", ""),
}
report_path.write_text(json.dumps(report, ensure_ascii=False, indent=2) + "\n", encoding="utf-8")
PY

echo "local-direct smoke passed."
echo "report: $report_file"
