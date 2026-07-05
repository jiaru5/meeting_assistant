#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
cd "$ROOT_DIR"

stamp="$(date -u +%Y%m%dT%H%M%SZ)-$$"
build_dir="$ROOT_DIR/platform/e2e/build/security-supply-chain"
output_dir="$build_dir/output"
report_dir="$build_dir/reports"
security_output="${MA_SECURITY_SUPPLY_CHAIN_SECURITY_OUTPUT:-$output_dir/security-check-$stamp.log}"
supply_chain_output="${MA_SECURITY_SUPPLY_CHAIN_SUPPLY_OUTPUT:-$output_dir/supply-chain-check-$stamp.log}"
provider_output="${MA_SECURITY_SUPPLY_CHAIN_PROVIDER_OUTPUT:-$output_dir/release-provider-smoke-$stamp.log}"
report_path="${MA_SECURITY_SUPPLY_CHAIN_REPORT:-$report_dir/security-supply-chain-report-$stamp.json}"

mkdir -p "$(dirname "$security_output")" "$(dirname "$supply_chain_output")" "$(dirname "$provider_output")" "$(dirname "$report_path")"

echo "security supply-chain smoke running: security=$security_output supply_chain=$supply_chain_output provider=$provider_output report=$report_path"

set +e
./scripts/security-check.sh >"$security_output" 2>&1
security_exit=$?
./scripts/supply-chain-check.sh current >"$supply_chain_output" 2>&1
supply_chain_exit=$?
./platform/processing-cli/scripts/release-provider-smoke.sh >"$provider_output" 2>&1
provider_exit=$?
set -e

cat "$security_output"
cat "$supply_chain_output"
cat "$provider_output"

set +e
python3 "$ROOT_DIR/platform/e2e/release_security_supply_chain_report.py" \
  --root "$ROOT_DIR" \
  --security-output "$security_output" \
  --supply-chain-output "$supply_chain_output" \
  --provider-output "$provider_output" \
  --report "$report_path" \
  --security-exit-code "$security_exit" \
  --supply-chain-exit-code "$supply_chain_exit" \
  --provider-exit-code "$provider_exit" \
  --release-scope
report_exit=$?
set -e

if ((security_exit != 0)); then
  echo "release security supply-chain smoke failed: preserving security-check exit code $security_exit." >&2
  exit "$security_exit"
fi
if ((supply_chain_exit != 0)); then
  echo "release security supply-chain smoke failed: preserving supply-chain-check exit code $supply_chain_exit." >&2
  exit "$supply_chain_exit"
fi
if ((provider_exit != 0)); then
  echo "release security supply-chain smoke failed: preserving release-provider-smoke exit code $provider_exit." >&2
  exit "$provider_exit"
fi
if ((report_exit != 0)); then
  echo "release security supply-chain smoke failed: structured report validation failed." >&2
  exit "$report_exit"
fi

echo "release security supply-chain smoke passed."
