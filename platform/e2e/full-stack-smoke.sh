#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
cd "$ROOT_DIR"

run_stage() {
  local stage="$1"
  local marker="$2"
  local command_path="$3"
  local output
  local exit_code

  echo "full-stack e2e smoke stage starting: $stage"
  set +e
  output="$("$command_path" 2>&1)"
  exit_code=$?
  set -e
  printf '%s\n' "$output"

  if ((exit_code != 0)); then
    echo "full-stack e2e smoke failed: stage=$stage exit_code=$exit_code expected_marker=$marker" >&2
    case "$output" in
      *"$marker"*) echo "full-stack e2e smoke diagnostic: marker was present despite non-zero exit." >&2 ;;
      *) echo "full-stack e2e smoke diagnostic: missing marker=$marker" >&2 ;;
    esac
    exit "$exit_code"
  fi

  case "$output" in
    *"$marker"*) ;;
    *)
      echo "full-stack e2e smoke failed: stage=$stage exit_code=0 missing marker=$marker" >&2
      exit 1
      ;;
  esac
  echo "full-stack e2e smoke stage passed: $stage"
}

run_stage "processing local smoke" "p2-c processing local e2e smoke passed." "./platform/e2e/smoke-test.sh"
run_stage "capture-style processing smoke" "capture-style processing e2e smoke passed." "./platform/e2e/capture-processing-smoke.sh"
case "${MA_NATIVE_CAPTURE_SMOKE:-0}" in
  1|true|TRUE|yes|YES)
    run_stage "real native capture artifact smoke" "real native capture artifact e2e smoke passed." "./platform/e2e/native-capture-artifact-smoke.sh"
    ;;
  *)
    echo "full-stack e2e smoke optional stage skipped: set MA_NATIVE_CAPTURE_SMOKE=1 to include real native capture artifact smoke."
    ;;
esac
run_stage "native transcript bridge and designed shell smoke" "designed native shell bridge smoke passed." "./platform/e2e/native-transcript-bridge-smoke.sh"

echo "VS-MA-20 provider/e2e attribution [non-contract]: import processing chain remains in scope."
echo "VS-MA-20 provider/e2e attribution [non-contract]: native_recording-style provider chain remains in scope."
echo "VS-MA-20 provider/e2e attribution [non-contract]: real native capture artifact stage is opt-in via MA_NATIVE_CAPTURE_SMOKE=1 and remains partial evidence."
echo "VS-MA-20 provider/e2e attribution [non-contract]: native read bridge checksum remains in scope."
echo "VS-MA-20 provider/e2e attribution [non-contract]: designed native shell app-root and ma.shell locator bridge remain in scope."
echo "VS-MA-20 provider/e2e attribution [non-contract]: no-auto-pull precondition remains in scope."
echo "VS-MA-20 provider/e2e attribution [non-contract]: real native capture, app-bundle UI launch, and release bundle are not proven by this provider smoke."
echo "VS-MA-23 provider/e2e release readiness [non-contract]: processing local command chain passed."
echo "VS-MA-23 provider/e2e release readiness [non-contract]: capture-style provider artifact and failure-redaction chain passed."
echo "VS-MA-23 provider/e2e release readiness [non-contract]: native read bridge and designed shell app-root smoke passed."
echo "VS-MA-23 provider/e2e release readiness [non-contract]: product-validation release blockers remain authoritative until Main PM closes PV partial rows."

echo "full-stack e2e smoke passed."
