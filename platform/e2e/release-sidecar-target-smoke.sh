#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
cd "$ROOT_DIR"

stamp="$(date -u +%Y%m%dT%H%M%SZ)-$$"
build_dir="$ROOT_DIR/platform/e2e/build/release-sidecar-target-smoke"
output_dir="$build_dir/output"
report_dir="$build_dir/reports"
target_id="${MA_RELEASE_SIDECAR_TARGET_ID:-$(hostname -s 2>/dev/null || hostname)-$(uname -m)}"
provider_output="${MA_RELEASE_SIDECAR_TARGET_PROVIDER_OUTPUT:-$output_dir/release-provider-smoke-$stamp.log}"
report_path="${MA_RELEASE_SIDECAR_TARGET_SMOKE_REPORT:-$report_dir/release-sidecar-target-smoke-$target_id-$stamp.json}"

mkdir -p "$(dirname "$provider_output")" "$(dirname "$report_path")"

echo "release sidecar target smoke running: provider=$provider_output report=$report_path"

set +e
./platform/processing-cli/scripts/release-provider-smoke.sh >"$provider_output" 2>&1
provider_exit=$?
set -e

cat "$provider_output"

set +e
python3 "$ROOT_DIR/platform/e2e/release_sidecar_target_smoke_report.py" \
  --root "$ROOT_DIR" \
  --provider-output "$provider_output" \
  --report "$report_path" \
  --provider-exit-code "$provider_exit"
report_exit=$?
set -e

if ((provider_exit != 0)); then
  echo "release sidecar target smoke failed: preserving release-provider-smoke exit code $provider_exit." >&2
  exit "$provider_exit"
fi
if ((report_exit != 0)); then
  echo "release sidecar target smoke failed: structured report validation failed." >&2
  exit "$report_exit"
fi

echo "release sidecar target smoke passed."
