#!/usr/bin/env bash
set -euo pipefail

component_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
root_dir="$(cd "$component_dir/../.." && pwd)"
cd "$root_dir"

timeout_seconds="${MA_NATIVE_LOCAL_APP_SMOKE_TIMEOUT_SECONDS:-45}"
report_dir="${MA_NATIVE_LOCAL_APP_SMOKE_REPORT_DIR:-$component_dir/build/local-direct-smoke}"
report_file="$report_dir/local-direct-smoke-report.json"
app_state_report_file="$report_dir/local-direct-app-state-report.json"
window_report_file="$report_dir/local-direct-window-report.json"
runner_log="$report_dir/run-local-app.log"
reuse_existing="${MA_NATIVE_LOCAL_APP_SMOKE_REUSE_EXISTING:-0}"
capture_system_audio="${MA_NATIVE_CAPTURE_SMOKE_SYSTEM_AUDIO:-true}"
capture_microphone_audio="${MA_NATIVE_CAPTURE_SMOKE_MICROPHONE_AUDIO:-false}"

usage() {
  cat <<'USAGE'
Usage: platform/native-app/scripts/local-direct-smoke.sh [run-local-app options]

Launch the local-direct Release MeetingAssistantNative.app with run-local-app.sh,
verify that macOS reports a visible layer-0 app window, and verify the designed
shell, preflight, recording, and processing readiness through the app's local
smoke state report.

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
rm -f "$app_state_report_file" "$window_report_file"
export MA_NATIVE_LOCAL_APP_SMOKE_STATE_REPORT="$app_state_report_file"
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

# local-app-ax.swift uses CoreGraphics for ordinary app window visibility because
# this local SwiftUI/AppKit launch path can expose menus through Accessibility
# while returning the application object from AXWindows.
"$component_dir/scripts/local-app-ax.swift" window "$timeout_seconds" "$app_pid" >"$window_report_file"

python3 - "$report_file" "$app_state_report_file" "$window_report_file" "$runner_log" "$app_pid" \
  "$expected_recording_setup_marker" "$capture_system_audio" "$capture_microphone_audio" "$timeout_seconds" <<'PY'
import json
import os
import sys
import time
from pathlib import Path

report_path = Path(sys.argv[1])
app_state_report_path = Path(sys.argv[2])
window_report_path = Path(sys.argv[3])
runner_log = Path(sys.argv[4])
app_pid = int(sys.argv[5])
expected_recording_setup_marker = sys.argv[6]
capture_system_audio = sys.argv[7]
capture_microphone_audio = sys.argv[8]
timeout_seconds = float(sys.argv[9])


def is_truthy(value):
    return value in {"1", "true", "TRUE", "yes", "YES"}


required_projected_controls = {
    "ma.recording.startButton": True,
    "ma.recording.stopButton": False,
    "ma.processing.startButton": False,
    "ma.processing.retryButton": False,
}


def read_json(path):
    try:
        return json.loads(path.read_text(encoding="utf-8"))
    except FileNotFoundError:
        return None
    except json.JSONDecodeError:
        return None


def state_errors(state):
    errors = []
    if not state:
        return ["app state report missing or invalid"]
    if state.get("pid") != app_pid:
        errors.append(f"app state pid={state.get('pid')!r}, expected {app_pid!r}")
    shell = state.get("shell", {})
    preflight = state.get("preflight", {})
    recording = state.get("recording", {})
    processing = state.get("processing", {})
    if shell.get("title") != "Meeting Assistant":
        errors.append("Meeting Assistant shell title missing")
    if shell.get("recording_setup_text") != expected_recording_setup_marker:
        errors.append("recording setup marker mismatch")
    if preflight.get("phase") != "ready":
        errors.append(f"preflight phase={preflight.get('phase')!r}, expected 'ready'")
    if preflight.get("can_start_recording") is not True:
        errors.append("preflight can_start_recording is not true")
    if preflight.get("can_run_processing") is not True:
        errors.append("preflight can_run_processing is not true")
    if recording.get("phase") != "ready":
        errors.append(f"recording phase={recording.get('phase')!r}, expected 'ready'")
    if recording.get("status_text") != "Ready to start recording.":
        errors.append("recording ready status text missing")
    if processing.get("phase") != "blocked":
        errors.append(f"processing phase={processing.get('phase')!r}, expected 'blocked'")
    if processing.get("status_text") != "Choose a recorded meeting before generating a transcript.":
        errors.append("processing current-session guard status text missing")
    controls = {
        control.get("identifier"): control.get("enabled")
        for control in state.get("checked_controls", [])
    }
    for identifier, expected_enabled in required_projected_controls.items():
        if identifier not in controls:
            errors.append(f"{identifier} missing")
            continue
        if controls[identifier] is not expected_enabled:
            errors.append(
                f"{identifier} enabled={controls[identifier]!r}, expected {expected_enabled!r}"
            )
    return errors


deadline = time.monotonic() + timeout_seconds
state = None
errors = ["app state report missing"]
while time.monotonic() < deadline:
    state = read_json(app_state_report_path)
    errors = state_errors(state)
    if not errors:
        break
    time.sleep(0.5)
else:
    for error in errors:
        print(f"local-direct smoke failed: {error}", file=sys.stderr)
    print(f"app state report: {app_state_report_path}", file=sys.stderr)
    sys.exit(1)

window_report = read_json(window_report_path)
if not window_report:
    print(f"local-direct smoke failed: window report missing or invalid: {window_report_path}", file=sys.stderr)
    sys.exit(1)
if window_report.get("pid") != app_pid:
    print(
        f"local-direct smoke failed: window pid={window_report.get('pid')!r}, expected {app_pid!r}",
        file=sys.stderr,
    )
    sys.exit(1)
if window_report.get("is_onscreen") is not True or window_report.get("layer") != 0:
    print(f"local-direct smoke failed: window is not a visible layer-0 app window: {window_report}", file=sys.stderr)
    sys.exit(1)

report = {
    "report_schema": 1,
    "release_gate": "local-direct-ui-smoke",
    "app_pid": app_pid,
    "app_state_report": str(app_state_report_path),
    "window_report": str(window_report_path),
    "runner_log": str(runner_log),
    "checked_markers": [
        "Meeting Assistant",
        state["preflight"]["summary"],
        "Ready to start recording.",
        "Choose a recorded meeting before generating a transcript.",
        expected_recording_setup_marker,
    ],
    "checked_recording_setup_text": expected_recording_setup_marker,
    "checked_preflight_summary": state["preflight"]["summary"],
    "recording_request": {
        "capture_system_audio": is_truthy(capture_system_audio),
        "capture_microphone_audio": is_truthy(capture_microphone_audio),
    },
    "checked_controls": state["checked_controls"],
    "checked_control_evidence": "app_state_view_model_projection",
    "checked_visible_window": window_report,
    "verifies_app_state_report": True,
    "verifies_action_control_identifiers": False,
    "modifies_tcc_or_system_settings": False,
    "opens_system_settings": False,
    "starts_recording": False,
    "requires_developer_id_or_notarization": False,
    "workspace": state.get("launch_environment", {}).get("workspace", ""),
}
report_path.write_text(json.dumps(report, ensure_ascii=False, indent=2) + "\n", encoding="utf-8")
PY

echo "local-direct smoke passed."
echo "report: $report_file"
