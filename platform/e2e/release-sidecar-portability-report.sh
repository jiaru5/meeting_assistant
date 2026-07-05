#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
cd "$ROOT_DIR"

stamp="$(date -u +%Y%m%dT%H%M%SZ)-$$"
report_path="${MA_RELEASE_SIDECAR_REPORT:-$ROOT_DIR/.harness/release-inputs/supply-chain/release-sidecar-report.json}"
builder="${MA_RELEASE_SIDECAR_BUILDER:-local-release-rehearsal}"
source_repository="${MA_RELEASE_SIDECAR_SOURCE_REPOSITORY:-$(git config --get remote.origin.url || true)}"

mkdir -p "$(dirname "$report_path")"

echo "release sidecar portability report running: report=$report_path"

python3 "$ROOT_DIR/platform/e2e/release_sidecar_portability_report.py" \
  --root "$ROOT_DIR" \
  --target-smoke-reports "${MA_RELEASE_SIDECAR_TARGET_SMOKE_REPORTS:-}" \
  --expected-targets "${MA_RELEASE_SIDECAR_EXPECTED_TARGETS:-}" \
  --report "$report_path" \
  --builder "$builder" \
  --source-repository "$source_repository"
