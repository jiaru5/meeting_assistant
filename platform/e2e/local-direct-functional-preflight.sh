#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
cd "$ROOT_DIR"

stamp="$(date -u +%Y%m%dT%H%M%SZ)-$$"
build_dir="$ROOT_DIR/platform/e2e/build/local-direct-functional-preflight"
system_name="$(uname -s | tr '[:upper:]' '[:lower:]')"
if [[ "$system_name" == "darwin" ]]; then
  default_target_os="macos"
else
  default_target_os="$system_name"
fi
target_os="${MA_LOCAL_DIRECT_FUNCTIONAL_TARGET_OS:-$default_target_os}"
target_arch="${MA_LOCAL_DIRECT_FUNCTIONAL_TARGET_ARCH:-$(uname -m)}"
target_id="${MA_LOCAL_DIRECT_FUNCTIONAL_TARGET_ID:-$(hostname -s 2>/dev/null || hostname)-$target_os-$target_arch}"
report_dir="$build_dir/reports"
target_smoke_report="${MA_LOCAL_DIRECT_FUNCTIONAL_TARGET_SMOKE_REPORT:-$build_dir/target/release-local-direct-target-smoke-$target_id-$stamp.json}"
target_smoke_output="${MA_LOCAL_DIRECT_FUNCTIONAL_TARGET_SMOKE_OUTPUT:-$build_dir/output/release-local-direct-target-smoke-$target_id-$stamp.log}"
repeatability_report="${MA_LOCAL_DIRECT_FUNCTIONAL_REPEATABILITY_REPORT:-$build_dir/repeatability/release-local-direct-repeatability-report-$target_id-$stamp.json}"
report_path="${MA_LOCAL_DIRECT_FUNCTIONAL_PREFLIGHT_REPORT:-$report_dir/local-direct-functional-preflight-$target_id-$stamp.json}"
source_repository="${MA_LOCAL_DIRECT_FUNCTIONAL_SOURCE_REPOSITORY:-$(git config --get remote.origin.url || true)}"
source_app="${MA_LOCAL_DIRECT_FUNCTIONAL_SOURCE_APP:-$ROOT_DIR/.harness/release-build/native-app/DerivedData/Build/Products/Release/MeetingAssistantNative.app}"
release_bundle_report="${MA_LOCAL_DIRECT_FUNCTIONAL_RELEASE_BUNDLE_REPORT:-$ROOT_DIR/.harness/release-inputs/bundle/release-bundle-report.json}"
build_source="${MA_LOCAL_DIRECT_FUNCTIONAL_BUILD_SOURCE:-1}"

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

mkdir -p "$(dirname "$target_smoke_report")" "$(dirname "$target_smoke_output")" "$(dirname "$repeatability_report")" "$(dirname "$report_path")"

echo "local-direct functional preflight running: target=$target_id report=$report_path"

if is_truthy "$build_source"; then
  ./scripts/release-bundle-create.py \
    --distribution-mode local-direct \
    --builder "${MA_LOCAL_DIRECT_FUNCTIONAL_BUILDER:-local-direct-functional-preflight}" \
    --source-repository "${source_repository:-local/meeting_assistant}" \
    --report "$release_bundle_report"
fi

MA_RELEASE_LOCAL_DIRECT_TARGET_ID="$target_id" \
MA_RELEASE_LOCAL_DIRECT_TARGET_OS="$target_os" \
MA_RELEASE_LOCAL_DIRECT_TARGET_ARCH="$target_arch" \
MA_RELEASE_LOCAL_DIRECT_TARGET_SMOKE_REPORT="$target_smoke_report" \
MA_RELEASE_LOCAL_DIRECT_TARGET_SMOKE_OUTPUT="$target_smoke_output" \
./platform/e2e/release-local-direct-target-smoke.sh "$@"

MA_RELEASE_LOCAL_DIRECT_TARGET_SMOKE_REPORTS="$target_smoke_report" \
MA_RELEASE_LOCAL_DIRECT_EXPECTED_TARGETS="$target_id" \
MA_RELEASE_LOCAL_DIRECT_REPEATABILITY_REPORT="$repeatability_report" \
MA_RELEASE_LOCAL_DIRECT_BUILDER="${MA_LOCAL_DIRECT_FUNCTIONAL_BUILDER:-local-direct-functional-preflight}" \
MA_RELEASE_LOCAL_DIRECT_SOURCE_REPOSITORY="${source_repository:-local/meeting_assistant}" \
./platform/e2e/release-local-direct-repeatability-report.sh

python3 "$ROOT_DIR/platform/e2e/local_direct_functional_preflight_report.py" \
  --root "$ROOT_DIR" \
  --target-smoke-report "$target_smoke_report" \
  --repeatability-report "$repeatability_report" \
  --source-app "$source_app" \
  --release-bundle-report "$release_bundle_report" \
  --report "$report_path"

echo "local-direct functional preflight passed."
