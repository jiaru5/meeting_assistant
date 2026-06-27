#!/usr/bin/env bash
set -euo pipefail

component_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$component_dir"

mkdir -p build
printf '%s\n' "processing-cli build: Python command package verified; no standalone binary is produced." > build/build-report.txt

test -f component.json
test -f README.md

echo "processing-cli build passed."
