#!/usr/bin/env bash
set -euo pipefail

component_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$component_dir"

scan_targets=(src tests scripts component.json README.md ../e2e)
if grep -R -n -E --exclude='security.sh' --exclude-dir=build 'curl |wget |brew install|pip install|npm install|API_KEY|SECRET|TOKEN' "${scan_targets[@]}"; then
  echo "processing-cli security failed: forbidden network, install, or secret marker found." >&2
  exit 1
fi

PYTHONPATH=src python3 - <<'PY'
from __future__ import annotations

import ast
import os
import stat
import tempfile
from pathlib import Path

from meeting_assistant_cli.dependency_check import run_dependency_check
from meeting_assistant_cli.sanitization import (
    sanitize_provider_failure_details,
    sanitize_provider_failure_message,
)

src_root = Path("src")
forbidden_import_roots = {"ftplib", "http", "requests", "socket", "smtplib", "urllib"}
for path in src_root.rglob("*.py"):
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
                f"processing-cli security failed: forbidden network import {sorted(blocked)} in {path}"
            )

provider_message = "provider leaked /Users/example/model.bin token=abcd1234 private transcript"
sanitized_message = sanitize_provider_failure_message(provider_message, fallback="Provider processing failed.")
if "provider leaked" in sanitized_message or "/Users/example" in sanitized_message or "abcd1234" in sanitized_message:
    raise SystemExit("processing-cli security failed: provider failure message redaction drifted")

sanitized_details = sanitize_provider_failure_details(
    {
        "runtime": "ProjectApolloRoadmap",
        "language": "secretcodename",
        "path": "/Users/example/private/model.bin",
        "artifact_id": "artifact-normalized_audio",
        "nested": {"token": "abcd1234"},
    }
)
if sanitized_details.get("runtime") != "<redacted>" or sanitized_details.get("language") != "<redacted>":
    raise SystemExit("processing-cli security failed: unsafe provider primitive details were not redacted")
if "path" in sanitized_details or "nested" in sanitized_details:
    raise SystemExit("processing-cli security failed: provider path or nested details escaped allowlist")
if sanitized_details.get("artifact_id") != "artifact-normalized_audio":
    raise SystemExit("processing-cli security failed: safe provider artifact id was not preserved")


def write_fake_executable(directory: Path, name: str) -> str:
    path = directory / name
    path.write_text("#!/usr/bin/env sh\nexit 0\n", encoding="utf-8")
    path.chmod(path.stat().st_mode | stat.S_IXUSR)
    return str(path)


with tempfile.TemporaryDirectory(prefix="meeting-assistant-security-") as tmp:
    root = Path(tmp)
    bin_dir = root / "bin"
    workspace = root / "workspace"
    bin_dir.mkdir()
    write_fake_executable(bin_dir, "swift")
    write_fake_executable(bin_dir, "ffmpeg")
    write_fake_executable(bin_dir, "whisper-local")
    model_path = bin_dir / "ggml-large-v3-turbo-q5_0.bin"
    model_path.write_bytes(b"fake multilingual model")
    env = {
        "PATH": str(bin_dir),
        "MEETING_ASSISTANT_OS_NAME": "Darwin",
        "MEETING_ASSISTANT_MACOS_VERSION": "26.5.1",
        "MEETING_ASSISTANT_CPU_ARCH": "arm64",
        "MEETING_ASSISTANT_CHIP_NAME": "Apple M4",
        "MEETING_ASSISTANT_MEMORY_BYTES": str(16 * 1024 * 1024 * 1024),
        "MEETING_ASSISTANT_TRANSCRIPTION_RUNTIME": "whisper-local",
        "MEETING_ASSISTANT_TRANSCRIPTION_MODEL": str(model_path),
        "MEETING_ASSISTANT_SCREEN_RECORDING_PERMISSION": "unknown",
        "MEETING_ASSISTANT_MICROPHONE_PERMISSION": "granted",
    }
    response = run_dependency_check(workspace, env)
    checks = {item["id"]: item for item in response["checks"]}
    automatic_downloads = checks.get("dependency_downloads.automatic", {})
    if automatic_downloads.get("status") != "not_attempted" or automatic_downloads.get("ok") is not True:
        raise SystemExit("processing-cli security failed: dependency check no-auto-download proof drifted")
    if checks["transcription.runtime"]["details"]["path"] != str(bin_dir / "whisper-local"):
        raise SystemExit("processing-cli security failed: runtime path did not stay in explicit fake env")
    if checks["transcription.model"]["details"]["path"] != str(model_path):
        raise SystemExit("processing-cli security failed: model path did not stay in explicit fake env")

print("processing-cli security release evidence passed.")
PY

echo "processing-cli security check passed."
