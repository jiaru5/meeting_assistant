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
grep -q "implements the \`generate_speaker_labels\` command contract with transcript-only fallback and an injectable local adapter boundary" tests/ArchitectureTest.md
grep -q "implements the \`export_transcript\` command contract for \`plain_text\`, \`markdown\` and \`json\`" tests/ArchitectureTest.md
grep -q "implements the \`delete_session\` command contract for confirmed deletion" tests/ArchitectureTest.md
grep -q "must not implement production-grade media transcoding, production-grade transcription quality gates" tests/ArchitectureTest.md

PYTHONPATH=src python3 - <<'PY'
import argparse
import ast
from pathlib import Path

from meeting_assistant_cli.cli import build_parser
from meeting_assistant_cli.transcription_runtime_config import SUPPORTED_TRANSCRIPTION_RUNTIME

parser = build_parser()
subparsers = [action for action in parser._actions if isinstance(action, argparse._SubParsersAction)]
if len(subparsers) != 1:
    raise SystemExit("processing-cli architecture check failed: CLI parser must define exactly one subparser group")
commands = set(subparsers[0].choices)
expected = {
    "check_dependencies",
    "import_media",
    "generate_transcript",
    "generate_speaker_labels",
    "export_transcript",
    "delete_session",
}
if commands != expected:
    raise SystemExit(f"processing-cli architecture check failed: public CLI commands drifted: {sorted(commands)}")
if "normalize_audio" in commands:
    raise SystemExit("processing-cli architecture check failed: normalize_audio must remain an internal stage")
if SUPPORTED_TRANSCRIPTION_RUNTIME != "whisper_cpp":
    raise SystemExit("processing-cli architecture check failed: supported runtime drifted")

forbidden_import_roots = {"ftplib", "http", "requests", "socket", "smtplib", "urllib"}
for path in Path("src").rglob("*.py"):
    tree = ast.parse(path.read_text(encoding="utf-8"), filename=str(path))
    for node in ast.walk(tree):
        if isinstance(node, ast.Import):
            imported = {alias.name.split(".", 1)[0] for alias in node.names}
        elif isinstance(node, ast.ImportFrom) and node.module:
            imported = {node.module.split(".", 1)[0]}
        else:
            continue
        blocked = imported & forbidden_import_roots
        if blocked:
            raise SystemExit(
                f"processing-cli architecture check failed: network import {sorted(blocked)} in {path}"
            )
PY

echo "processing-cli architecture release evidence passed."
echo "processing-cli architecture check passed."
