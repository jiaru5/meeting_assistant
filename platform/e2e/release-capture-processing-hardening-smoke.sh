#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
cd "$ROOT_DIR"

stamp="$(date -u +%Y%m%dT%H%M%SZ)-$$"
build_dir="$ROOT_DIR/platform/e2e/build/capture-processing-hardening"
output_dir="$build_dir/output"
report_dir="$build_dir/reports"
output_path="${MA_CAPTURE_PROCESSING_HARDENING_OUTPUT:-$output_dir/capture-processing-hardening-$stamp.log}"
report_path="${MA_CAPTURE_PROCESSING_HARDENING_REPORT:-$report_dir/capture-processing-hardening-report-$stamp.json}"

mkdir -p "$(dirname "$output_path")" "$(dirname "$report_path")"

echo "capture processing hardening smoke running: output=$output_path report=$report_path"

set +e
./platform/e2e/capture-processing-smoke.sh >"$output_path" 2>&1
smoke_exit=$?
set -e

cat "$output_path"

set +e
python3 "$ROOT_DIR/platform/e2e/capture_processing_hardening_report.py" \
  --output "$output_path" \
  --report "$report_path" \
  --exit-code "$smoke_exit" \
  --release-scope
report_exit=$?
set -e

if ((smoke_exit != 0)); then
  echo "release capture processing hardening smoke failed: preserving capture-processing-smoke exit code $smoke_exit." >&2
  exit "$smoke_exit"
fi
if ((report_exit != 0)); then
  echo "release capture processing hardening smoke failed: structured report validation failed." >&2
  exit "$report_exit"
fi

echo "release capture processing hardening smoke passed."
