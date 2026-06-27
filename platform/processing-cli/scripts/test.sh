#!/usr/bin/env bash
set -euo pipefail

component_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$component_dir"

PYTHONPATH=src python3 -m unittest discover -s tests

python3 - <<'PY'
import json
from pathlib import Path

metadata = json.loads(Path("component.json").read_text(encoding="utf-8"))
if metadata.get("business_behavior") != "dependency_check_artifact_contract_import_media_audio_normalization_transcript_fake":
    raise SystemExit("processing-cli test failed: dependency_check_artifact_contract_import_media_audio_normalization_transcript_fake behavior is missing")
implemented_contracts = set(metadata.get("implemented_contracts", []))
required_contracts = {
    "check_dependencies",
    "workspace_artifact_contract",
    "import_media",
    "audio_source_selection",
    "normalized_audio_stage",
    "generate_transcript",
    "transcription_fake_adapter",
}
if not required_contracts.issubset(implemented_contracts):
    raise SystemExit("processing-cli test failed: implemented contracts are incomplete")
if metadata.get("allowed_before_project_mode") is not False:
    raise SystemExit("processing-cli test failed: project behavior cannot be allowed before project mode")
required_forbidden = {
    "production_grade_transcoding",
    "real_transcription_runtime",
    "speaker_labeling",
    "external_model_api",
    "automatic_downloads",
}
forbidden = set(metadata.get("forbidden_capabilities", []))
if required_forbidden - forbidden:
    raise SystemExit("processing-cli test failed: forbidden capability list is incomplete")
if implemented_contracts & required_forbidden:
    raise SystemExit("processing-cli test failed: forbidden capabilities cannot be implemented contracts")

architecture = Path("tests/ArchitectureTest.md").read_text(encoding="utf-8")
required_phrases = (
    "Component: `processing-cli`",
    "implements the `check_dependencies` command contract",
    "implements the workspace artifact contract kernel",
    "implements the `import_media` command contract",
    "implements the internal normalized audio stage",
    "must not expose `normalize_audio` as a public command",
    "implements the `generate_transcript` command contract with a deterministic fake transcription adapter",
    "must not implement production-grade media transcoding, a real transcription runtime",
    "must not implement production-grade media transcoding",
    "Missing required dependencies must be reported as `ok: false`",
)
missing = [phrase for phrase in required_phrases if phrase not in architecture]
if missing:
    raise SystemExit(f"processing-cli test failed: missing architecture phrases {missing}")
PY

PYTHONPATH=src python3 - <<'PY'
import argparse

from meeting_assistant_cli.cli import build_parser

parser = build_parser()
subparsers = [action for action in parser._actions if isinstance(action, argparse._SubParsersAction)]
if len(subparsers) != 1:
    raise SystemExit("processing-cli test failed: CLI parser must define exactly one subparser group")
commands = set(subparsers[0].choices)
expected = {"check_dependencies", "import_media", "generate_transcript"}
if commands != expected:
    raise SystemExit(f"processing-cli test failed: public CLI commands drifted: {sorted(commands)}")
PY

echo "processing-cli tests passed."
