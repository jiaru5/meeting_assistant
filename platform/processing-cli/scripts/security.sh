#!/usr/bin/env bash
set -euo pipefail

component_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$component_dir"

if grep -R -n -E 'curl |wget |brew install|pip install|npm install|API_KEY|SECRET|TOKEN' src tests component.json README.md; then
  echo "processing-cli security failed: forbidden network, install, or secret marker found." >&2
  exit 1
fi

echo "processing-cli security check passed."
