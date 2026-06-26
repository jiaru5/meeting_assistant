#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT_DIR"

python3 -m unittest discover -s scripts/tests -p 'test_*.py'
python3 scripts/agent-eval-check.py

echo "harness-self-test passed."
