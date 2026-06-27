#!/usr/bin/env bash
set -euo pipefail

component_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$component_dir"

test -f tests/ArchitectureTest.md
grep -q "Component: \`processing-cli\`" tests/ArchitectureTest.md
grep -q "implements the \`check_dependencies\` command contract" tests/ArchitectureTest.md
grep -q "implements the workspace artifact contract kernel" tests/ArchitectureTest.md
grep -q "implements the \`import_media\` command contract" tests/ArchitectureTest.md
grep -q "implements the internal normalized audio stage" tests/ArchitectureTest.md
grep -q "must not expose \`normalize_audio\` as a public command" tests/ArchitectureTest.md
grep -q "implements the \`generate_transcript\` command contract with a deterministic fake transcription adapter and a minimal \`whisper.cpp\` runtime adapter" tests/ArchitectureTest.md
grep -q "must not implement production-grade media transcoding, production-grade transcription quality gates" tests/ArchitectureTest.md

PYTHONPATH=src python3 - <<'PY'
import argparse

from meeting_assistant_cli.cli import build_parser

parser = build_parser()
subparsers = [action for action in parser._actions if isinstance(action, argparse._SubParsersAction)]
if len(subparsers) != 1:
    raise SystemExit("processing-cli architecture check failed: CLI parser must define exactly one subparser group")
commands = set(subparsers[0].choices)
expected = {"check_dependencies", "import_media", "generate_transcript"}
if commands != expected:
    raise SystemExit(f"processing-cli architecture check failed: public CLI commands drifted: {sorted(commands)}")
PY

echo "processing-cli architecture check passed."
