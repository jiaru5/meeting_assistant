#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT_DIR"

python3 scripts/product-validation-check.py current-phase
./scripts/check.sh
./scripts/test-e2e-full-stack.sh
./scripts/review-report.sh --require-evidence

echo "phase-preflight passed."
