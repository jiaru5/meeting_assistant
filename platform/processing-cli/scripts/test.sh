#!/usr/bin/env bash
set -euo pipefail

component_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$component_dir"

PYTHONPATH=src python3 -m unittest discover -s tests

python3 - <<'PY'
import json
from pathlib import Path

metadata = json.loads(Path("component.json").read_text(encoding="utf-8"))
expected_behavior = "dependency_check_artifact_contract_import_media_audio_normalization_transcript_whisper_cpp_speaker_fallback_export_delete"
if metadata.get("business_behavior") != expected_behavior:
    raise SystemExit(f"processing-cli test failed: {expected_behavior} behavior is missing")
implemented_contracts = set(metadata.get("implemented_contracts", []))
required_contracts = {
    "check_dependencies",
    "workspace_artifact_contract",
    "import_media",
    "audio_source_selection",
    "normalized_audio_stage",
    "generate_transcript",
    "transcription_fake_adapter",
    "transcription_whisper_cpp_adapter",
    "generate_speaker_labels",
    "speaker_labeling_transcript_only_fallback",
    "speaker_labeling_adapter_boundary",
    "export_transcript",
    "delete_session",
}
if not required_contracts.issubset(implemented_contracts):
    raise SystemExit("processing-cli test failed: implemented contracts are incomplete")
if metadata.get("allowed_before_project_mode") is not False:
    raise SystemExit("processing-cli test failed: project behavior cannot be allowed before project mode")
required_forbidden = {
    "production_grade_transcoding",
    "production_grade_transcription_quality",
    "production_grade_speaker_labeling",
    "external_speaker_labeling_runtime",
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
    "implements the `generate_transcript` command contract with a deterministic fake transcription adapter and a minimal `whisper.cpp` runtime adapter",
    "implements the `generate_speaker_labels` command contract with transcript-only fallback and an injectable local adapter boundary",
    "implements the `export_transcript` command contract for `plain_text`, `markdown` and `json`",
    "implements the `delete_session` command contract for confirmed deletion",
    "must not implement production-grade media transcoding, production-grade transcription quality gates",
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
expected = {
    "check_dependencies",
    "import_media",
    "generate_transcript",
    "generate_speaker_labels",
    "export_transcript",
    "delete_session",
}
if commands != expected:
    raise SystemExit(f"processing-cli test failed: public CLI commands drifted: {sorted(commands)}")
PY

smoke_tmp="$(mktemp -d)"
cleanup_smoke_tmp() {
  rm -rf "$smoke_tmp"
}
trap cleanup_smoke_tmp EXIT
printf '#!/usr/bin/env sh\nexit 0\n' > "$smoke_tmp/whisper-cli"
chmod +x "$smoke_tmp/whisper-cli"
printf 'fake model' > "$smoke_tmp/ggml-base.bin"
printf 'fake wav' > "$smoke_tmp/mixed-zh-en-tech.wav"
set +e
smoke_output="$(
  MEETING_ASSISTANT_TRANSCRIPTION_RUNTIME="$smoke_tmp/whisper-cli" \
    MEETING_ASSISTANT_TRANSCRIPTION_MODEL="$smoke_tmp/ggml-base.bin" \
    MEETING_ASSISTANT_WHISPER_SMOKE_AUDIO="$smoke_tmp/mixed-zh-en-tech.wav" \
    MEETING_ASSISTANT_REQUIRE_WHISPER_CPP_SMOKE=1 \
    ./scripts/smoke-whisper-cpp.sh 2>&1
)"
smoke_status="$?"
set -e
if [ "$smoke_status" -eq 0 ]; then
  echo "processing-cli test failed: whisper smoke accepted a non-recommended model" >&2
  exit 1
fi
case "$smoke_output" in
  *"requires a large-v3"*) ;;
  *)
    echo "processing-cli test failed: whisper smoke did not explain the recommended model requirement" >&2
    echo "$smoke_output" >&2
    exit 1
    ;;
esac

./scripts/smoke-whisper-cpp.sh

echo "processing-cli tests passed."
