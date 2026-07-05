#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT_DIR"

python3 scripts/product-validation-check.py current-phase
./scripts/check.sh
case "${MA_NATIVE_CAPTURE_SMOKE:-0}" in
  1|true|TRUE|yes|YES)
    echo "phase-preflight optional evidence requested: VS-MA-14/15 real native capture artifact smoke will run inside full-stack E2E; this remains partial evidence, not release readiness."
    ;;
esac
./scripts/test-e2e-full-stack.sh
./scripts/review-report.sh --require-evidence

echo "phase-preflight passed."
