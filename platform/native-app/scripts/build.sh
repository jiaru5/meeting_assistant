#!/usr/bin/env bash
set -euo pipefail

component_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$component_dir"

mkdir -p build
printf '%s\n' "native-app activation skeleton build: no business binary is produced." > build/build-report.txt

test -f component.json
test -f README.md

echo "native-app build passed."
