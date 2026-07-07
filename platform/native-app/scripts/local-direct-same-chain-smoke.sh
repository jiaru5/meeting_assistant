#!/usr/bin/env bash
set -euo pipefail

component_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
root_dir="$(cd "$component_dir/../.." && pwd)"
cd "$root_dir"

run_id="${MA_NATIVE_LOCAL_APP_SAME_CHAIN_SMOKE_RUN_ID:-$(date -u +%Y%m%dT%H%M%SZ)}"
report_root="${MA_NATIVE_LOCAL_APP_SAME_CHAIN_SMOKE_REPORT_ROOT:-$component_dir/build/local-direct-same-chain-smoke}"
report_dir="${MA_NATIVE_LOCAL_APP_SAME_CHAIN_SMOKE_REPORT_DIR:-$report_root/$run_id}"
report_file="$report_dir/local-direct-same-chain-smoke-report.json"
workspace_dir="${MA_NATIVE_LOCAL_APP_SAME_CHAIN_SMOKE_WORKSPACE:-$report_dir/workspace}"
session_id="${MA_NATIVE_LOCAL_APP_SAME_CHAIN_SMOKE_SESSION_ID:-session-app-ui-blocked}"
audio_path="${MA_NATIVE_LOCAL_APP_SAME_CHAIN_SMOKE_AUDIO:-${MEETING_ASSISTANT_WHISPER_SMOKE_AUDIO:-}}"
expected_terms="${MA_NATIVE_LOCAL_APP_SAME_CHAIN_SMOKE_EXPECTED_TERMS:-HTTP,LLM,clean architecture}"
recording_seconds="${MA_NATIVE_LOCAL_APP_SAME_CHAIN_SMOKE_RECORDING_SECONDS:-4}"

recording_report_dir="$report_dir/recording"
processing_report_dir="$report_dir/processing"
actions_report_dir="$report_dir/actions"
recording_report="$recording_report_dir/local-direct-recording-smoke-report.json"
processing_report="$processing_report_dir/local-direct-processing-smoke-report.json"
actions_report="$actions_report_dir/local-direct-actions-smoke-report.json"

usage() {
  cat <<'USAGE'
Usage: platform/native-app/scripts/local-direct-same-chain-smoke.sh [run-local-app options]

Run the local-direct installed Release MeetingAssistantNative.app through the
ordinary LaunchServices open path for the MVP same-chain flow:
recording Start/Stop -> processing -> transcript copy/export/delete.

This wrapper only composes existing local-direct smoke scripts. It does not open
System Settings, does not modify TCC or system permissions, and does not require
Developer ID/notarization. It may trigger the app's normal macOS recording
permission prompt if the exact app is not already authorized.

Each child smoke wraps scripts/run-local-app.sh and must keep the default
LaunchServices open path unless the caller explicitly passes different
run-local-app options.
USAGE
}

if [[ "${1:-}" == "--help" ]]; then
  usage
  exit 0
fi

for arg in "$@"; do
  case "$arg" in
    --workspace)
      echo "error: local-direct same-chain smoke owns --workspace; use MA_NATIVE_LOCAL_APP_SAME_CHAIN_SMOKE_WORKSPACE instead." >&2
      exit 2
      ;;
    --ma-native-transcript-workspace* | --ma-native-transcript-session-id* | --)
      echo "error: local-direct same-chain smoke owns native transcript app args." >&2
      exit 2
      ;;
  esac
done

if [[ -z "$audio_path" ]]; then
  echo "error: MA_NATIVE_LOCAL_APP_SAME_CHAIN_SMOKE_AUDIO or MEETING_ASSISTANT_WHISPER_SMOKE_AUDIO is required." >&2
  exit 2
fi
if [[ ! -f "$audio_path" ]]; then
  echo "error: same-chain audio fixture does not exist: $audio_path" >&2
  exit 2
fi

mkdir -p "$report_dir"
preexisting_app_pids="$(/usr/bin/pgrep -x MeetingAssistantNative 2>/dev/null || true)"
if [[ -n "$preexisting_app_pids" ]]; then
  echo "error: local-direct same-chain smoke requires no preexisting MeetingAssistantNative processes." >&2
  echo "$preexisting_app_pids" >&2
  echo "Close the app or terminate stale smoke runs, then retry." >&2
  exit 2
fi
if [[ -d "$workspace_dir/sessions/$session_id" ]]; then
  echo "error: same-chain workspace already contains $session_id; choose a fresh MA_NATIVE_LOCAL_APP_SAME_CHAIN_SMOKE_RUN_ID or workspace." >&2
  exit 2
fi
mkdir -p "$workspace_dir"

recording_exit=0
processing_exit=-1
actions_exit=-1

set +e
MA_NATIVE_LOCAL_APP_RECORDING_SMOKE_REPORT_DIR="$recording_report_dir" \
MA_NATIVE_LOCAL_APP_RECORDING_SMOKE_WORKSPACE="$workspace_dir" \
MA_NATIVE_LOCAL_APP_RECORDING_SMOKE_AUDIO="$audio_path" \
MA_NATIVE_LOCAL_APP_RECORDING_SMOKE_DURATION_SECONDS="$recording_seconds" \
"$component_dir/scripts/local-direct-recording-smoke.sh" "$@"
recording_exit=$?
set -e

if [[ "$recording_exit" -eq 0 ]]; then
  set +e
  MA_NATIVE_LOCAL_APP_PROCESSING_SMOKE_REPORT_DIR="$processing_report_dir" \
  MA_NATIVE_LOCAL_APP_PROCESSING_SMOKE_WORKSPACE="$workspace_dir" \
  MA_NATIVE_LOCAL_APP_PROCESSING_SMOKE_SESSION_ID="$session_id" \
  MA_NATIVE_LOCAL_APP_PROCESSING_SMOKE_EXPECTED_TERMS="$expected_terms" \
  "$component_dir/scripts/local-direct-processing-smoke.sh" "$@"
  processing_exit=$?
  set -e
fi

if [[ "$recording_exit" -eq 0 && "$processing_exit" -eq 0 ]]; then
  set +e
  MA_NATIVE_LOCAL_APP_ACTIONS_SMOKE_REPORT_DIR="$actions_report_dir" \
  MA_NATIVE_LOCAL_APP_ACTIONS_SMOKE_WORKSPACE="$workspace_dir" \
  MA_NATIVE_LOCAL_APP_ACTIONS_SMOKE_SESSION_ID="$session_id" \
  MA_NATIVE_LOCAL_APP_ACTIONS_SMOKE_EXPECTED_TERMS="$expected_terms" \
  "$component_dir/scripts/local-direct-actions-smoke.sh" "$@"
  actions_exit=$?
  set -e
fi

python3 - "$report_file" "$workspace_dir" "$session_id" "$expected_terms" "$audio_path" \
  "$recording_exit" "$processing_exit" "$actions_exit" \
  "$recording_report" "$processing_report" "$actions_report" <<'PY'
import json
import sys
from pathlib import Path
from typing import Any

report_path = Path(sys.argv[1])
workspace_dir = Path(sys.argv[2])
session_id = sys.argv[3]
expected_terms = [term.strip() for term in sys.argv[4].split(",") if term.strip()]
audio_path = sys.argv[5]
stage_exits = {
    "recording": int(sys.argv[6]),
    "processing": int(sys.argv[7]),
    "actions": int(sys.argv[8]),
}
stage_report_paths = {
    "recording": Path(sys.argv[9]),
    "processing": Path(sys.argv[10]),
    "actions": Path(sys.argv[11]),
}


def load_report(path: Path) -> dict[str, Any]:
    if not path.is_file():
        return {}
    return json.loads(path.read_text(encoding="utf-8"))


def workspace_files() -> list[str]:
    if not workspace_dir.exists():
        return []
    return sorted(
        str(path.relative_to(workspace_dir))
        for path in workspace_dir.rglob("*")
        if path.is_file()
    )


stage_reports = {
    name: load_report(path)
    for name, path in stage_report_paths.items()
}
stage_passed = {
    name: stage_exits[name] == 0 and bool(stage_reports[name].get("passed"))
    for name in ("recording", "processing", "actions")
}
app_identities = [
    stage_reports[name].get("app_identity", {})
    for name in ("recording", "processing", "actions")
    if stage_reports[name].get("app_identity")
]
identity_keys = [
    (
        identity.get("path"),
        identity.get("CFBundleIdentifier"),
        identity.get("codesign", {}).get("CDHash"),
    )
    for identity in app_identities
]
same_app_identity = bool(identity_keys) and len(set(identity_keys)) == 1
launch_modes = sorted(
    {
        stage_reports[name].get("runner_configuration", {}).get("launch_mode")
        for name in ("recording", "processing", "actions")
        if stage_reports[name].get("runner_configuration", {}).get("launch_mode")
    }
)
passed = all(stage_passed.values()) and same_app_identity and launch_modes == ["open"]

report = {
    "report_schema": 1,
    "release_gate": "local-direct-same-chain-smoke",
    "passed": passed,
    "blocker_type": "none" if passed else "same_chain_stage_failed",
    "blocker_detail": "" if passed else "One or more local-direct same-chain stages failed or did not use the same open-launched app identity.",
    "workspace": str(workspace_dir),
    "session_id": session_id,
    "audio_fixture": audio_path,
    "expected_terms": expected_terms,
    "stage_exit_codes": stage_exits,
    "stage_passed": stage_passed,
    "stage_reports": {
        name: str(path)
        for name, path in stage_report_paths.items()
    },
    "same_app_identity": same_app_identity,
    "app_identity": app_identities[0] if app_identities else {},
    "launch_modes": launch_modes,
    "recording_markers": stage_reports["recording"].get("checked_markers", []),
    "processing_artifacts": stage_reports["processing"].get("processing_artifacts", {}),
    "actions_markers": stage_reports["actions"].get("checked_markers", []),
    "export_path": stage_reports["actions"].get("export_path", ""),
    "export_exists": stage_reports["actions"].get("export_exists", False),
    "delete_event_path": stage_reports["actions"].get("delete_event_path", ""),
    "session_root_exists_after_delete": stage_reports["actions"].get("session_root_exists_after_delete"),
    "workspace_files": workspace_files()[:120],
    "same_chain_boundary": "Runs local-direct recording, processing and transcript actions against the same installed app identity and workspace.",
    "requires_clean_app_processes": True,
    "starts_recording": True,
    "starts_processing": True,
    "uses_system_pasteboard": True,
    "uses_save_panel": True,
    "opens_system_settings": False,
    "modifies_tcc_or_system_settings": False,
    "may_request_macos_permissions": True,
    "requires_developer_id_or_notarization": False,
    "not_release_readiness": True,
}
report_path.write_text(json.dumps(report, ensure_ascii=False, indent=2) + "\n", encoding="utf-8")
PY

if [[ "$recording_exit" -ne 0 || "$processing_exit" -ne 0 || "$actions_exit" -ne 0 ]]; then
  echo "local-direct same-chain smoke failed." >&2
  echo "report: $report_file" >&2
  exit 1
fi

if ! python3 - "$report_file" <<'PY'
import json
import sys
from pathlib import Path

report = json.loads(Path(sys.argv[1]).read_text(encoding="utf-8"))
raise SystemExit(0 if report.get("passed") is True else 1)
PY
then
  echo "local-direct same-chain smoke failed summary validation." >&2
  echo "report: $report_file" >&2
  exit 1
fi

echo "local-direct same-chain smoke passed."
echo "report: $report_file"
