#!/usr/bin/env bash
set -euo pipefail

component_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$component_dir"

test -f tests/ArchitectureTest.md
grep -q "Component: \`processing-cli\`" tests/ArchitectureTest.md
grep -q "non-business activation skeleton" tests/ArchitectureTest.md

echo "processing-cli architecture check passed."
