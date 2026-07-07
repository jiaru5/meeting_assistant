#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
cd "$ROOT_DIR"

stamp="$(date -u +%Y%m%dT%H%M%SZ)-$$"
build_dir="$ROOT_DIR/platform/e2e/build/release-local-direct-target-smoke"
same_chain_root="$build_dir/same-chain"
output_dir="$build_dir/output"
report_dir="$build_dir/reports"
target_os="${MA_RELEASE_LOCAL_DIRECT_TARGET_OS:-$(uname -s | tr '[:upper:]' '[:lower:]')}"
target_arch="${MA_RELEASE_LOCAL_DIRECT_TARGET_ARCH:-$(uname -m)}"
target_id="${MA_RELEASE_LOCAL_DIRECT_TARGET_ID:-$(hostname -s 2>/dev/null || hostname)-$target_os-$target_arch}"
same_chain_output="${MA_RELEASE_LOCAL_DIRECT_TARGET_SMOKE_OUTPUT:-$output_dir/local-direct-same-chain-$stamp.log}"
report_path="${MA_RELEASE_LOCAL_DIRECT_TARGET_SMOKE_REPORT:-$report_dir/release-local-direct-target-smoke-$target_id-$stamp.json}"
same_chain_report="$same_chain_root/$stamp/local-direct-same-chain-smoke-report.json"

mkdir -p "$(dirname "$same_chain_output")" "$(dirname "$report_path")"

echo "release local-direct target smoke running: same_chain=$same_chain_output report=$report_path"

set +e
MA_NATIVE_LOCAL_APP_SAME_CHAIN_SMOKE_RUN_ID="$stamp" \
MA_NATIVE_LOCAL_APP_SAME_CHAIN_SMOKE_REPORT_ROOT="$same_chain_root" \
./platform/native-app/scripts/local-direct-same-chain-smoke.sh "$@" >"$same_chain_output" 2>&1
same_chain_exit=$?
set -e

cat "$same_chain_output"

set +e
python3 "$ROOT_DIR/platform/e2e/release_local_direct_target_smoke_report.py" \
  --root "$ROOT_DIR" \
  --same-chain-report "$same_chain_report" \
  --report "$report_path" \
  --smoke-exit-code "$same_chain_exit" \
  --target-id "$target_id" \
  --target-os "$target_os" \
  --architecture "$target_arch"
report_exit=$?
set -e

if ((same_chain_exit != 0)); then
  echo "release local-direct target smoke failed: preserving local-direct-same-chain-smoke exit code $same_chain_exit." >&2
  exit "$same_chain_exit"
fi
if ((report_exit != 0)); then
  echo "release local-direct target smoke failed: structured report validation failed." >&2
  exit "$report_exit"
fi

echo "release local-direct target smoke passed."
