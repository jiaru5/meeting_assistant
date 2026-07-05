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

release_home="$smoke_tmp/release-home"
release_runtime_path="$release_home/.local/bin/whisper-cli"
release_audio_path="$release_home/.local/share/ai-fixtures/asr/zh-en-tech/mixed-zh-en-tech.wav"
mkdir -p \
  "$release_home/.local/bin" \
  "$release_home/.local/share/ai-models/whisper.cpp/large-v3-turbo" \
  "$release_home/.local/share/ai-fixtures/asr/zh-en-tech"
printf '#!/usr/bin/env sh\nexit 0\n' > "$release_runtime_path"
chmod +x "$release_runtime_path"
printf 'fake model' > "$release_home/.local/share/ai-models/whisper.cpp/large-v3-turbo/ggml-large-v3-turbo-q5_0.bin"
printf 'fake wav' > "$release_audio_path"
release_model_path="$release_home/.local/share/ai-models/whisper.cpp/large-v3-turbo/ggml-large-v3-turbo-q5_0.bin"
release_license_file="$release_model_path.license.txt"
release_provenance_file="$release_model_path.provenance.json"
release_model_hash="$(
  python3 - "$release_model_path" <<'PY'
import hashlib
import sys
from pathlib import Path

path = Path(sys.argv[1])
digest = hashlib.sha256(path.read_bytes()).hexdigest()
print(digest)
PY
)"
set +e
release_smoke_output="$(
  HOME="$release_home" \
    MEETING_ASSISTANT_TRANSCRIPTION_RUNTIME="$release_runtime_path" \
    MEETING_ASSISTANT_TRANSCRIPTION_MODEL="$release_model_path" \
    MEETING_ASSISTANT_WHISPER_SMOKE_AUDIO="$release_audio_path" \
    ./scripts/release-provider-smoke.sh 2>&1
)"
release_smoke_status="$?"
set -e
if [ "$release_smoke_status" -eq 0 ]; then
  echo "processing-cli test failed: release provider smoke accepted missing model sidecar evidence" >&2
  exit 1
fi
case "$release_smoke_output" in
  *"model hash blocker"* ) ;;
  *)
    echo "processing-cli test failed: release provider smoke did not report the model hash blocker" >&2
    echo "$release_smoke_output" >&2
    exit 1
    ;;
esac
case "$release_smoke_output" in
  *"model license blocker"* ) ;;
  *)
    echo "processing-cli test failed: release provider smoke did not report the model license blocker" >&2
    echo "$release_smoke_output" >&2
    exit 1
    ;;
esac
case "$release_smoke_output" in
  *"model provenance blocker"* ) ;;
  *)
    echo "processing-cli test failed: release provider smoke did not report the model provenance blocker" >&2
    echo "$release_smoke_output" >&2
    exit 1
    ;;
esac

printf '%s  %s\n' "$release_model_hash" "$(basename "$release_model_path")" > "$release_model_path.sha256"
printf 'Apache-2.0 compatible local fixture license evidence.\n' > "$release_license_file"
printf '{"source":"local release smoke fixture","model":"large-v3-turbo","sha256":"sha256:%s","license":"Apache-2.0"}\n' "$release_model_hash" > "$release_provenance_file"

set +e
release_hash_mismatch_output="$(
  HOME="$release_home" \
    MEETING_ASSISTANT_TRANSCRIPTION_RUNTIME="$release_runtime_path" \
    MEETING_ASSISTANT_TRANSCRIPTION_MODEL="$release_model_path" \
    MEETING_ASSISTANT_WHISPER_SMOKE_AUDIO="$release_audio_path" \
    MEETING_ASSISTANT_TRANSCRIPTION_MODEL_SHA256="sha256:0000000000000000000000000000000000000000000000000000000000000000" \
    MEETING_ASSISTANT_TRANSCRIPTION_MODEL_LICENSE_FILE="$release_license_file" \
    MEETING_ASSISTANT_TRANSCRIPTION_MODEL_PROVENANCE_FILE="$release_provenance_file" \
    ./scripts/release-provider-smoke.sh 2>&1
)"
release_hash_mismatch_status="$?"
set -e
if [ "$release_hash_mismatch_status" -eq 0 ]; then
  echo "processing-cli test failed: release provider smoke accepted mismatched model sha256 evidence" >&2
  exit 1
fi
case "$release_hash_mismatch_output" in
  *"configured sha256 does not match the selected model"* ) ;;
  *)
    echo "processing-cli test failed: release provider smoke did not report the model sha256 mismatch blocker" >&2
    echo "$release_hash_mismatch_output" >&2
    exit 1
    ;;
esac

release_outside_runtime_path="$smoke_tmp/outside-whisper-cli"
printf '#!/usr/bin/env sh\nexit 0\n' > "$release_outside_runtime_path"
chmod +x "$release_outside_runtime_path"
set +e
release_outside_runtime_output="$(
  HOME="$release_home" \
    MEETING_ASSISTANT_TRANSCRIPTION_RUNTIME="$release_outside_runtime_path" \
    MEETING_ASSISTANT_TRANSCRIPTION_MODEL="$release_model_path" \
    MEETING_ASSISTANT_WHISPER_SMOKE_AUDIO="$release_audio_path" \
    MEETING_ASSISTANT_TRANSCRIPTION_MODEL_SHA256="sha256:$release_model_hash" \
    MEETING_ASSISTANT_TRANSCRIPTION_MODEL_LICENSE_FILE="$release_license_file" \
    MEETING_ASSISTANT_TRANSCRIPTION_MODEL_PROVENANCE_FILE="$release_provenance_file" \
    ./scripts/release-provider-smoke.sh 2>&1
)"
release_outside_runtime_status="$?"
set -e
if [ "$release_outside_runtime_status" -eq 0 ]; then
  echo "processing-cli test failed: release provider smoke accepted a runtime outside the allowed .local roots" >&2
  exit 1
fi
case "$release_outside_runtime_output" in
  *"runtime path blocker"* ) ;;
  *)
    echo "processing-cli test failed: release provider smoke did not report the runtime root blocker" >&2
    echo "$release_outside_runtime_output" >&2
    exit 1
    ;;
esac

release_outside_model_path="$smoke_tmp/ggml-large-v3-turbo-q5_0.bin"
printf 'fake model outside allowed root' > "$release_outside_model_path"
release_outside_model_hash="$(
  python3 - "$release_outside_model_path" <<'PY'
import hashlib
import sys
from pathlib import Path

path = Path(sys.argv[1])
digest = hashlib.sha256(path.read_bytes()).hexdigest()
print(digest)
PY
)"
set +e
release_outside_model_output="$(
  HOME="$release_home" \
    MEETING_ASSISTANT_TRANSCRIPTION_RUNTIME="$release_runtime_path" \
    MEETING_ASSISTANT_TRANSCRIPTION_MODEL="$release_outside_model_path" \
    MEETING_ASSISTANT_WHISPER_SMOKE_AUDIO="$release_audio_path" \
    MEETING_ASSISTANT_TRANSCRIPTION_MODEL_SHA256="sha256:$release_outside_model_hash" \
    MEETING_ASSISTANT_TRANSCRIPTION_MODEL_LICENSE_FILE="$release_license_file" \
    MEETING_ASSISTANT_TRANSCRIPTION_MODEL_PROVENANCE_FILE="$release_provenance_file" \
    ./scripts/release-provider-smoke.sh 2>&1
)"
release_outside_model_status="$?"
set -e
if [ "$release_outside_model_status" -eq 0 ]; then
  echo "processing-cli test failed: release provider smoke accepted a model outside the allowed .local root" >&2
  exit 1
fi
case "$release_outside_model_output" in
  *"model path blocker"* ) ;;
  *)
    echo "processing-cli test failed: release provider smoke did not report the model root blocker" >&2
    echo "$release_outside_model_output" >&2
    exit 1
    ;;
esac

release_english_only_model_path="$release_home/.local/share/ai-models/whisper.cpp/large-v3-turbo/ggml-large-v3-turbo.en.bin"
printf 'fake english only model' > "$release_english_only_model_path"
release_english_only_model_hash="$(
  python3 - "$release_english_only_model_path" <<'PY'
import hashlib
import sys
from pathlib import Path

path = Path(sys.argv[1])
digest = hashlib.sha256(path.read_bytes()).hexdigest()
print(digest)
PY
)"
set +e
release_english_only_model_output="$(
  HOME="$release_home" \
    MEETING_ASSISTANT_TRANSCRIPTION_RUNTIME="$release_runtime_path" \
    MEETING_ASSISTANT_TRANSCRIPTION_MODEL="$release_english_only_model_path" \
    MEETING_ASSISTANT_WHISPER_SMOKE_AUDIO="$release_audio_path" \
    MEETING_ASSISTANT_TRANSCRIPTION_MODEL_SHA256="sha256:$release_english_only_model_hash" \
    MEETING_ASSISTANT_TRANSCRIPTION_MODEL_LICENSE_FILE="$release_license_file" \
    MEETING_ASSISTANT_TRANSCRIPTION_MODEL_PROVENANCE_FILE="$release_provenance_file" \
    ./scripts/release-provider-smoke.sh 2>&1
)"
release_english_only_model_status="$?"
set -e
if [ "$release_english_only_model_status" -eq 0 ]; then
  echo "processing-cli test failed: release provider smoke accepted an English-only model" >&2
  exit 1
fi
case "$release_english_only_model_output" in
  *"English-only .en model"* ) ;;
  *)
    echo "processing-cli test failed: release provider smoke did not report the English-only model blocker" >&2
    echo "$release_english_only_model_output" >&2
    exit 1
    ;;
esac

release_outside_audio_path="$smoke_tmp/mixed-zh-en-tech.wav"
printf 'fake wav outside allowed root' > "$release_outside_audio_path"
set +e
release_outside_audio_output="$(
  HOME="$release_home" \
    MEETING_ASSISTANT_TRANSCRIPTION_RUNTIME="$release_runtime_path" \
    MEETING_ASSISTANT_TRANSCRIPTION_MODEL="$release_model_path" \
    MEETING_ASSISTANT_WHISPER_SMOKE_AUDIO="$release_outside_audio_path" \
    MEETING_ASSISTANT_TRANSCRIPTION_MODEL_SHA256="sha256:$release_model_hash" \
    MEETING_ASSISTANT_TRANSCRIPTION_MODEL_LICENSE_FILE="$release_license_file" \
    MEETING_ASSISTANT_TRANSCRIPTION_MODEL_PROVENANCE_FILE="$release_provenance_file" \
    ./scripts/release-provider-smoke.sh 2>&1
)"
release_outside_audio_status="$?"
set -e
if [ "$release_outside_audio_status" -eq 0 ]; then
  echo "processing-cli test failed: release provider smoke accepted an audio fixture outside the allowed .local root" >&2
  exit 1
fi
case "$release_outside_audio_output" in
  *"audio fixture path blocker"* ) ;;
  *)
    echo "processing-cli test failed: release provider smoke did not report the audio root blocker" >&2
    echo "$release_outside_audio_output" >&2
    exit 1
    ;;
esac

release_invalid_provenance_file="$release_model_path.invalid-provenance.json"
printf '{not-json\n' > "$release_invalid_provenance_file"
set +e
release_invalid_provenance_output="$(
  HOME="$release_home" \
    MEETING_ASSISTANT_TRANSCRIPTION_RUNTIME="$release_runtime_path" \
    MEETING_ASSISTANT_TRANSCRIPTION_MODEL="$release_model_path" \
    MEETING_ASSISTANT_WHISPER_SMOKE_AUDIO="$release_audio_path" \
    MEETING_ASSISTANT_TRANSCRIPTION_MODEL_SHA256="sha256:$release_model_hash" \
    MEETING_ASSISTANT_TRANSCRIPTION_MODEL_LICENSE_FILE="$release_license_file" \
    MEETING_ASSISTANT_TRANSCRIPTION_MODEL_PROVENANCE_FILE="$release_invalid_provenance_file" \
    ./scripts/release-provider-smoke.sh 2>&1
)"
release_invalid_provenance_status="$?"
set -e
if [ "$release_invalid_provenance_status" -eq 0 ]; then
  echo "processing-cli test failed: release provider smoke accepted invalid provenance JSON" >&2
  exit 1
fi
case "$release_invalid_provenance_output" in
  *"JSON sidecar cannot be parsed"* ) ;;
  *)
    echo "processing-cli test failed: release provider smoke did not report the invalid provenance JSON blocker" >&2
    echo "$release_invalid_provenance_output" >&2
    exit 1
    ;;
esac

release_outside_provenance_file="$smoke_tmp/outside-provenance.json"
printf '{"source":"outside fixture","model":"large-v3-turbo"}\n' > "$release_outside_provenance_file"
set +e
release_outside_provenance_output="$(
  HOME="$release_home" \
    MEETING_ASSISTANT_TRANSCRIPTION_RUNTIME="$release_runtime_path" \
    MEETING_ASSISTANT_TRANSCRIPTION_MODEL="$release_model_path" \
    MEETING_ASSISTANT_WHISPER_SMOKE_AUDIO="$release_audio_path" \
    MEETING_ASSISTANT_TRANSCRIPTION_MODEL_SHA256="sha256:$release_model_hash" \
    MEETING_ASSISTANT_TRANSCRIPTION_MODEL_LICENSE_FILE="$release_license_file" \
    MEETING_ASSISTANT_TRANSCRIPTION_MODEL_PROVENANCE_FILE="$release_outside_provenance_file" \
    ./scripts/release-provider-smoke.sh 2>&1
)"
release_outside_provenance_status="$?"
set -e
if [ "$release_outside_provenance_status" -eq 0 ]; then
  echo "processing-cli test failed: release provider smoke accepted provenance outside model root" >&2
  exit 1
fi
case "$release_outside_provenance_output" in
  *"model provenance sidecar blocker"* ) ;;
  *)
    echo "processing-cli test failed: release provider smoke did not report the provenance root blocker" >&2
    echo "$release_outside_provenance_output" >&2
    exit 1
    ;;
esac

./scripts/smoke-whisper-cpp.sh

../e2e/smoke-test.sh

../e2e/capture-processing-smoke.sh

echo "processing-cli tests passed."
