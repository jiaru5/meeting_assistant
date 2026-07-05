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
report_dir="${MA_NATIVE_CAPTURE_ARTIFACT_SMOKE_REPORT_DIR:-$smoke_root/reports}"
report_path="${MA_NATIVE_CAPTURE_ARTIFACT_SMOKE_REPORT:-$report_dir/native-capture-report-$run_stamp-$$.json}"
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

mkdir -p "$summary_dir" "$report_dir" "$(dirname "$workspace")" "$build_dir"

export MA_NATIVE_CAPTURE_SMOKE_WORKSPACE="$workspace"
export MA_NATIVE_CAPTURE_SMOKE_BUILD_DIR="$build_dir"
export MA_NATIVE_CAPTURE_SMOKE_DURATION_SECONDS="${MA_NATIVE_CAPTURE_SMOKE_DURATION_SECONDS:-2}"
export MA_NATIVE_CAPTURE_SMOKE_SYSTEM_AUDIO="${MA_NATIVE_CAPTURE_SMOKE_SYSTEM_AUDIO:-false}"
export MA_NATIVE_CAPTURE_SMOKE_MICROPHONE_AUDIO="${MA_NATIVE_CAPTURE_SMOKE_MICROPHONE_AUDIO:-false}"

echo "native capture artifact e2e running: workspace=$workspace summary=$summary_path report=$report_path" >&2

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
  if [[ -s "$summary_path" ]]; then
    set +e
    PYTHONDONTWRITEBYTECODE=1 \
    PYTHONPATH="$ROOT_DIR/platform/processing-cli/src${PYTHONPATH:+:$PYTHONPATH}" \
    MA_NATIVE_CAPTURE_ARTIFACT_SUMMARY="$summary_path" \
    MA_NATIVE_CAPTURE_ARTIFACT_REPORT="$report_path" \
    python3 "$ROOT_DIR/platform/e2e/native_capture_artifact_report.py" \
      --failure-report \
      --summary "$summary_path" \
      --report "$report_path" \
      --native-exit-code "$native_exit" \
      --attempts "$attempts" \
      --display-wake-seconds "$display_wake_seconds" \
      --display-wake-settle-seconds "$display_wake_settle_seconds" >&2
    report_exit=$?
    set -e
    if ((report_exit != 0)); then
      echo "native capture artifact e2e diagnostic: failed to write native failure report; preserving native exit code $native_exit." >&2
    fi
  fi
  exit "$native_exit"
fi

PYTHONDONTWRITEBYTECODE=1 \
PYTHONPATH="$ROOT_DIR/platform/processing-cli/src${PYTHONPATH:+:$PYTHONPATH}" \
MA_NATIVE_CAPTURE_ARTIFACT_SUMMARY="$summary_path" \
MA_NATIVE_CAPTURE_ARTIFACT_REPORT="$report_path" \
python3 "$ROOT_DIR/platform/e2e/native_capture_artifact_report.py" \
  --summary "$summary_path" \
  --report "$report_path"
