#!/usr/bin/env bash
set -euo pipefail

component_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$component_dir"

test -f tests/ArchitectureTest.md
grep -q "Component: \`native-app\`" tests/ArchitectureTest.md
grep -q "non-business project skeleton" tests/ArchitectureTest.md

echo "native-app architecture check passed."
