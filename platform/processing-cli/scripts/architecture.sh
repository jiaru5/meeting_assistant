#!/usr/bin/env bash
set -euo pipefail

component_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$component_dir"

test -f tests/ArchitectureTest.md
grep -q "Component: \`processing-cli\`" tests/ArchitectureTest.md
grep -q "implements the \`check_dependencies\` command contract" tests/ArchitectureTest.md
grep -q "implements the workspace artifact contract kernel" tests/ArchitectureTest.md
grep -q "implements the \`import_media\` command contract" tests/ArchitectureTest.md
grep -q "must not implement media processing" tests/ArchitectureTest.md
grep -q "must not transcode" tests/ArchitectureTest.md

echo "processing-cli architecture check passed."
