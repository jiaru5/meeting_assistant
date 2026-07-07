#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
cd "$ROOT_DIR"

report_path="${MA_RELEASE_LOCAL_DIRECT_REPEATABILITY_REPORT:-$ROOT_DIR/.harness/release-inputs/local-direct/release-local-direct-repeatability-report.json}"
builder="${MA_RELEASE_LOCAL_DIRECT_BUILDER:-local-direct-release-rehearsal}"
source_repository="${MA_RELEASE_LOCAL_DIRECT_SOURCE_REPOSITORY:-$(git config --get remote.origin.url || true)}"

mkdir -p "$(dirname "$report_path")"

echo "release local-direct repeatability report running: report=$report_path"

python3 "$ROOT_DIR/platform/e2e/release_local_direct_repeatability_report.py" \
  --root "$ROOT_DIR" \
  --target-smoke-reports "${MA_RELEASE_LOCAL_DIRECT_TARGET_SMOKE_REPORTS:-}" \
  --expected-targets "${MA_RELEASE_LOCAL_DIRECT_EXPECTED_TARGETS:-}" \
  --report "$report_path" \
  --builder "$builder" \
  --source-repository "$source_repository"
