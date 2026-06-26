#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT_DIR"

while IFS= read -r script; do
  bash -n "$script"
done < <(find scripts -maxdepth 1 -type f -name "*.sh" | sort)

python3 -m py_compile scripts/*.py scripts/tests/*.py
python3 scripts/harness-runtime.py run-gate lint

echo "lint passed."
