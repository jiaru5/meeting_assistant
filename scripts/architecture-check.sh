#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT_DIR"

./scripts/project-manifest-check.sh current
python3 scripts/harness-runtime.py run-gate architecture

echo "architecture-check passed."
