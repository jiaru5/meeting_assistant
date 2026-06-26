#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT_DIR"

./scripts/harness-self-test.sh
python3 scripts/harness-runtime.py run-gate test

echo "test passed."
