#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT_DIR"

phase="${1:-current}"
case "$phase" in
  current|release) ;;
  *)
    echo "usage: $0 [current|release]" >&2
    exit 2
    ;;
esac

python3 scripts/action-pin-check.py
./scripts/project-manifest-check.sh "$phase"
python3 scripts/harness-runtime.py run-gate sbom

echo "supply-chain-check passed: phase=$phase."
