#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT_DIR"

phase="${1:-current}"
case "$phase" in
  current|development|release) ;;
  *)
    echo "usage: $0 [current|development|release]" >&2
    exit 2
    ;;
esac

python3 scripts/harness-runtime.py check --phase "$phase"
