#!/usr/bin/env bash
set -euo pipefail

component_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
repo_root="$(cd "$component_dir/../.." && pwd)"
cd "$component_dir"

PYTHONPATH=src REPO_ROOT="$repo_root" python3 - <<'PY'
from __future__ import annotations

import hashlib
import json
import os
import re
import subprocess
import sys
import tempfile
from pathlib import Path

from meeting_assistant_cli.transcription_runtime_config import (
    TRANSCRIPTION_MODEL_ENV,
    TRANSCRIPTION_RUNTIME_ENV,
    TRANSCRIPTION_SMOKE_AUDIO_ENV,
    model_name_suggests_english_only,
    resolve_model_path,
    resolve_runtime_executable,
)


MODEL_SHA256_ENV = "MEETING_ASSISTANT_TRANSCRIPTION_MODEL_SHA256"
MODEL_SHA256_FILE_ENV = "MEETING_ASSISTANT_TRANSCRIPTION_MODEL_SHA256_FILE"
MODEL_LICENSE_FILE_ENV = "MEETING_ASSISTANT_TRANSCRIPTION_MODEL_LICENSE_FILE"
MODEL_PROVENANCE_FILE_ENV = "MEETING_ASSISTANT_TRANSCRIPTION_MODEL_PROVENANCE_FILE"


def normalize_sha256(value: str) -> str | None:
    stripped = value.strip()
    if stripped.startswith("sha256:"):
        stripped = stripped.split(":", 1)[1]
    match = re.search(r"\b([a-fA-F0-9]{64})\b", stripped)
    if match is None:
        return None
    return match.group(1).lower()


def sha256_file(path: Path) -> str:
    digest = hashlib.sha256()
    with path.open("rb") as handle:
        for chunk in iter(lambda: handle.read(1024 * 1024), b""):
            digest.update(chunk)
    return digest.hexdigest()


def read_sha256_sidecar(path: Path, model_path: Path) -> str:
    try:
        text = path.read_text(encoding="utf-8").strip()
    except OSError:
        return ""
    if not text:
        return ""
    lines = [line.strip() for line in text.splitlines() if line.strip()]
    model_names = {model_path.name, str(model_path)}
    for line in lines:
        if any(name in line for name in model_names):
            return line
    if len(lines) == 1:
        return lines[0]
    return ""


def sidecar_from_env_or_candidates(env: dict[str, str], env_name: str, model_path: Path, candidates: tuple[str, ...]) -> Path | None:
    env_value = env.get(env_name, "").strip()
    if env_value:
        return Path(env_value).expanduser()
    for name in candidates:
        candidate = model_path.parent / name
        if candidate.is_file():
            return candidate
    return None


def require_under_any(candidate: Path, roots: list[Path], label: str, blockers: list[str]) -> None:
    resolved_roots = [root.resolve(strict=False) for root in roots]
    for root in resolved_roots:
        try:
            candidate.relative_to(root)
            return
        except ValueError:
            continue
    roots_display = ", ".join(str(root) for root in resolved_roots)
    blockers.append(f"{label} blocker: {candidate} must be under {roots_display}")


def reject_disallowed_roots(candidate: Path, roots: list[Path], label: str, blockers: list[str]) -> None:
    for root in roots:
        resolved_root = root.resolve(strict=False)
        try:
            candidate.relative_to(resolved_root)
        except ValueError:
            continue
        blockers.append(f"{label} blocker: {candidate} must not be under {resolved_root}")


def check_model_sha256(env: dict[str, str], model_path: Path, model_root: Path, blockers: list[str], messages: list[str]) -> None:
    expected_source = "env"
    expected = env.get(MODEL_SHA256_ENV, "").strip()
    sidecar_path: Path | None = None
    if not expected:
        sidecar_path = sidecar_from_env_or_candidates(
            env,
            MODEL_SHA256_FILE_ENV,
            model_path,
            (
                f"{model_path.name}.sha256",
                f"{model_path.name}.sha256.txt",
                f"{model_path.name}.sha256sum",
                "SHA256SUMS",
            ),
        )
        if sidecar_path is not None:
            expected_source = str(sidecar_path)
            expected = read_sha256_sidecar(sidecar_path, model_path)
    if not expected:
        blockers.append(
            "model hash blocker: provide "
            f"{MODEL_SHA256_ENV}, {MODEL_SHA256_FILE_ENV}, or a local model sha256 sidecar"
        )
        return
    if sidecar_path is not None:
        require_under_any(sidecar_path.resolve(strict=False), [model_root], "model hash sidecar", blockers)
    expected_hash = normalize_sha256(expected)
    if expected_hash is None:
        blockers.append("model hash blocker: expected sha256 must be 64 hex characters or sha256:<hex>")
        return
    actual_hash = sha256_file(model_path)
    if actual_hash != expected_hash:
        blockers.append(
            "model hash blocker: configured sha256 does not match the selected model "
            f"(expected sha256:{expected_hash}, actual sha256:{actual_hash})"
        )
        return
    messages.append(
        "VS-MA-23 provider release smoke [non-contract]: model sha256 evidence verified "
        f"from {expected_source}: sha256:{actual_hash}"
    )


def check_model_sidecar(
    env: dict[str, str],
    model_path: Path,
    model_root: Path,
    env_name: str,
    label: str,
    blockers: list[str],
    messages: list[str],
    *,
    candidates: tuple[str, ...],
    validate_json: bool = False,
) -> None:
    sidecar_path = sidecar_from_env_or_candidates(env, env_name, model_path, candidates)
    if sidecar_path is None:
        blockers.append(f"model {label} blocker: provide {env_name} or a local model {label} sidecar")
        return
    sidecar_resolved = sidecar_path.resolve(strict=False)
    require_under_any(sidecar_resolved, [model_root], f"model {label} sidecar", blockers)
    if not sidecar_path.is_file() or sidecar_path.stat().st_size == 0:
        blockers.append(f"model {label} blocker: sidecar is missing or empty at {sidecar_resolved}")
        return
    if validate_json and sidecar_resolved.suffix.lower() == ".json":
        try:
            payload = json.loads(sidecar_path.read_text(encoding="utf-8"))
        except (OSError, json.JSONDecodeError) as exc:
            blockers.append(f"model {label} blocker: JSON sidecar cannot be parsed ({exc.__class__.__name__})")
            return
        source_keys = {"source", "repository", "model", "model_family", "commit", "tag", "sha256", "license"}
        if not isinstance(payload, dict) or not (set(payload) & source_keys):
            blockers.append(
                "model provenance blocker: JSON sidecar must identify source, model, commit, tag, sha256, or license"
            )
            return
    messages.append(f"VS-MA-23 provider release smoke [non-contract]: model {label} sidecar accepted: {sidecar_resolved}")


def check_real_dependency_json(env: dict[str, str], blockers: list[str], messages: list[str]) -> None:
    with tempfile.TemporaryDirectory(prefix="meeting-assistant-release-deps-") as tmp:
        workspace = Path(tmp) / "workspace"
        completed = subprocess.run(
            [
                sys.executable,
                "-m",
                "meeting_assistant_cli",
                "check_dependencies",
                "--workspace-dir",
                str(workspace),
                "--format",
                "json",
            ],
            cwd=Path.cwd(),
            env=env,
            text=True,
            capture_output=True,
            check=False,
        )
    if completed.returncode != 0:
        blockers.append(
            "check_dependencies real env blocker: expected exit 0, got "
            f"{completed.returncode}; stderr={completed.stderr.strip()!r}"
        )
        return
    lines = [line for line in completed.stdout.splitlines() if line.strip()]
    if len(lines) != 1:
        blockers.append(
            "check_dependencies real env blocker: expected exactly one JSON stdout line, "
            f"got {len(lines)}"
        )
        return
    try:
        payload = json.loads(lines[0])
    except json.JSONDecodeError as exc:
        blockers.append(f"check_dependencies real env blocker: stdout is not JSON ({exc.__class__.__name__})")
        return
    if not isinstance(payload, dict) or payload.get("ok") is not True or payload.get("command") != "check_dependencies":
        blockers.append("check_dependencies real env blocker: response must be ok=true for check_dependencies")
        return
    checks_payload = payload.get("checks")
    if not isinstance(checks_payload, list):
        blockers.append("check_dependencies real env blocker: checks must be a list")
        return
    checks = {
        str(item.get("id")): item
        for item in checks_payload
        if isinstance(item, dict) and item.get("id")
    }
    required_status = {
        "transcription.runtime": "available",
        "transcription.model": "available",
        "transcription.model.multilingual": "reported",
        "transcription.hardware": "supported",
        "dependency_downloads.automatic": "not_attempted",
        "dependency_sources.allowed": "reported",
        "workspace.writable": "creatable",
    }
    for check_id, status in required_status.items():
        item = checks.get(check_id)
        if item is None:
            blockers.append(f"check_dependencies real env blocker: missing check {check_id}")
            continue
        if item.get("status") != status or item.get("ok") is not True:
            blockers.append(
                "check_dependencies real env blocker: "
                f"{check_id} expected status={status} ok=true, got {item!r}"
            )
    warnings = payload.get("warnings")
    if not isinstance(warnings, list):
        blockers.append("check_dependencies real env blocker: warnings must be a list")
    messages.append(
        "VS-MA-23 provider release smoke [non-contract]: real check_dependencies JSON accepted "
        "for runtime/model/hardware/no-auto-download."
    )


env = dict(os.environ)
blockers: list[str] = []
messages: list[str] = []
missing_env = [
    name
    for name in (
        TRANSCRIPTION_RUNTIME_ENV,
        TRANSCRIPTION_MODEL_ENV,
        TRANSCRIPTION_SMOKE_AUDIO_ENV,
    )
    if not env.get(name, "").strip()
]
if missing_env:
    blockers.append(
        "required env missing: "
        + ", ".join(missing_env)
        + "; configure explicit local runtime, multilingual model, and mixed-language audio fixture"
    )

home = Path.home().resolve(strict=False)
local_root = home / ".local"
model_root = local_root / "share" / "ai-models" / "whisper.cpp"
audio_root = local_root / "share" / "ai-fixtures" / "asr" / "zh-en-tech"
runtime_roots = [local_root / "bin", local_root / "opt" / "whisper.cpp"]
disallowed_roots = [
    Path(os.environ["REPO_ROOT"]).resolve(strict=False),
    home / "Downloads",
    home / "Desktop",
    home / "Library" / "Caches",
]

runtime_path = resolve_runtime_executable(env) if TRANSCRIPTION_RUNTIME_ENV not in missing_env else None
model_path = resolve_model_path(env) if TRANSCRIPTION_MODEL_ENV not in missing_env else None
audio_path = Path(env[TRANSCRIPTION_SMOKE_AUDIO_ENV]).expanduser() if TRANSCRIPTION_SMOKE_AUDIO_ENV not in missing_env else None

if not missing_env:
    check_real_dependency_json(env, blockers, messages)

if TRANSCRIPTION_RUNTIME_ENV not in missing_env:
    runtime_value = env.get(TRANSCRIPTION_RUNTIME_ENV, "").strip()
    if runtime_path is None:
        blockers.append(
            f"runtime blocker: {TRANSCRIPTION_RUNTIME_ENV}={runtime_value!r} is missing, not executable, or not resolvable on PATH"
        )
    else:
        runtime_resolved = Path(runtime_path).expanduser().resolve(strict=False)
        require_under_any(runtime_resolved, runtime_roots, "runtime path", blockers)
        reject_disallowed_roots(runtime_resolved, disallowed_roots, "runtime path", blockers)
        messages.append(f"VS-MA-23 provider release smoke [non-contract]: runtime .local path accepted: {runtime_resolved}")

if TRANSCRIPTION_MODEL_ENV not in missing_env:
    model_value = env.get(TRANSCRIPTION_MODEL_ENV, "").strip()
    if model_path is None:
        blockers.append(f"model blocker: {TRANSCRIPTION_MODEL_ENV}={model_value!r} is missing or not readable")
    else:
        model_resolved = Path(model_path).expanduser().resolve(strict=False)
        require_under_any(model_resolved, [model_root], "model path", blockers)
        reject_disallowed_roots(model_resolved, disallowed_roots, "model path", blockers)
        if model_name_suggests_english_only(str(model_resolved)):
            blockers.append("model blocker: English-only .en model cannot provide release-scope mixed-language evidence")
        if "large-v3" not in str(model_resolved).lower():
            blockers.append("model blocker: model path must identify large-v3 or large-v3-turbo multilingual evidence")
        check_model_sha256(env, model_resolved, model_root, blockers, messages)
        check_model_sidecar(
            env,
            model_resolved,
            model_root,
            MODEL_LICENSE_FILE_ENV,
            "license",
            blockers,
            messages,
            candidates=(
                f"{model_resolved.name}.license",
                f"{model_resolved.name}.license.txt",
                f"{model_resolved.name}.LICENSE",
                "LICENSE",
                "LICENSE.txt",
            ),
        )
        check_model_sidecar(
            env,
            model_resolved,
            model_root,
            MODEL_PROVENANCE_FILE_ENV,
            "provenance",
            blockers,
            messages,
            candidates=(
                f"{model_resolved.name}.provenance.json",
                f"{model_resolved.name}.provenance",
                f"{model_resolved.name}.provenance.txt",
                "PROVENANCE.json",
                "provenance.json",
                "PROVENANCE.txt",
            ),
            validate_json=True,
        )
        messages.append(
            f"VS-MA-23 provider release smoke [non-contract]: model .local large-v3 evidence path accepted: {model_resolved}"
        )

if TRANSCRIPTION_SMOKE_AUDIO_ENV not in missing_env:
    assert audio_path is not None
    audio_resolved = audio_path.resolve(strict=False)
    if not audio_path.is_file():
        blockers.append(f"audio fixture blocker: {TRANSCRIPTION_SMOKE_AUDIO_ENV} must point to a readable WAV fixture")
    if audio_resolved.suffix.lower() != ".wav":
        blockers.append("audio fixture blocker: release smoke fixture must be a .wav file")
    require_under_any(audio_resolved, [audio_root], "audio fixture path", blockers)
    reject_disallowed_roots(audio_resolved, disallowed_roots, "audio fixture path", blockers)
    messages.append(f"VS-MA-23 provider release smoke [non-contract]: mixed-language fixture .local path accepted: {audio_resolved}")

if blockers:
    print("release provider smoke failed: provider release blockers:", file=sys.stderr)
    for blocker in blockers:
        print(f"- {blocker}", file=sys.stderr)
    raise SystemExit(1)

messages.append(
    "VS-MA-23 provider release smoke [non-contract]: sidecar evidence is local-machine evidence only and does not prove all developer machines."
)
for message in messages:
    print(message)
PY

set +e
smoke_output="$(MEETING_ASSISTANT_REQUIRE_WHISPER_CPP_SMOKE=1 ./scripts/smoke-whisper-cpp.sh 2>&1)"
smoke_status="$?"
set -e
printf '%s\n' "$smoke_output"
if [ "$smoke_status" -ne 0 ]; then
  exit "$smoke_status"
fi
case "$smoke_output" in
  *"whisper.cpp smoke passed."*) ;;
  *)
    echo "release provider smoke failed: required whisper.cpp smoke marker was missing." >&2
    exit 1
    ;;
esac

echo "VS-MA-23 provider release smoke [non-contract]: required whisper.cpp runtime smoke passed."
echo "VS-MA-23 provider release smoke [non-contract]: no-auto-download/no-auto-upload boundary remains unchanged."
echo "release provider smoke passed."
