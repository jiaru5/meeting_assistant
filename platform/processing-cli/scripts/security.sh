#!/usr/bin/env bash
set -euo pipefail

component_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$component_dir"

scan_targets=(src tests scripts component.json README.md ../e2e)
if grep -R -n -E --exclude='security.sh' 'curl |wget |brew install|pip install|npm install|API_KEY|SECRET|TOKEN' "${scan_targets[@]}"; then
  echo "processing-cli security failed: forbidden network, install, or secret marker found." >&2
  exit 1
fi

echo "processing-cli security check passed."
