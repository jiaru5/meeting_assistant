#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
cd "$ROOT_DIR"

stamp="$(date -u +%Y%m%dT%H%M%SZ)-$$"
build_dir="$ROOT_DIR/platform/e2e/build/release-native-ui-hardening"
output_dir="$build_dir/output"
report_dir="$build_dir/reports"
real_capture_output="${MA_RELEASE_NATIVE_UI_REAL_CAPTURE_OUTPUT:-$output_dir/real-capture-app-bundle-$stamp.log}"
hardening_output="${MA_RELEASE_NATIVE_UI_HARDENING_OUTPUT:-$output_dir/vs-ma-21-hardening-app-bundle-$stamp.log}"
report_path="${MA_RELEASE_NATIVE_UI_HARDENING_REPORT:-$report_dir/release-native-ui-hardening-report-$stamp.json}"

mkdir -p "$(dirname "$real_capture_output")" "$(dirname "$hardening_output")" "$(dirname "$report_path")"

echo "release native UI hardening smoke running: real_capture_output=$real_capture_output hardening_output=$hardening_output report=$report_path"

set +e
MA_NATIVE_APP_REAL_CAPTURE_SMOKE=1 ./platform/native-app/scripts/test-app-bundle.sh >"$real_capture_output" 2>&1
real_capture_exit=$?
set -e

cat "$real_capture_output"

set +e
MA_NATIVE_APP_VSMA21_HARDENING_SMOKE=1 ./platform/native-app/scripts/test-app-bundle.sh >"$hardening_output" 2>&1
hardening_exit=$?
set -e

cat "$hardening_output"

set +e
python3 "$ROOT_DIR/platform/e2e/release_native_ui_hardening_report.py" \
  --real-capture-output "$real_capture_output" \
  --hardening-output "$hardening_output" \
  --report "$report_path" \
  --real-capture-exit-code "$real_capture_exit" \
  --hardening-exit-code "$hardening_exit" \
  --release-scope
report_exit=$?
set -e

if ((real_capture_exit != 0)); then
  echo "release native UI hardening smoke failed: preserving real capture app-bundle exit code $real_capture_exit." >&2
  exit "$real_capture_exit"
fi
if ((hardening_exit != 0)); then
  echo "release native UI hardening smoke failed: preserving VS-MA-21 hardening app-bundle exit code $hardening_exit." >&2
  exit "$hardening_exit"
fi
if ((report_exit != 0)); then
  echo "release native UI hardening smoke failed: structured report validation failed." >&2
  exit "$report_exit"
fi

echo "release native UI hardening smoke passed."
