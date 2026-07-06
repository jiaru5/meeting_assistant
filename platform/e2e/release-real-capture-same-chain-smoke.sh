#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
cd "$ROOT_DIR"

stamp="$(date -u +%Y%m%dT%H%M%SZ)-$$"
build_dir="$ROOT_DIR/platform/e2e/build/real-capture-same-chain"
workspace="${MA_REAL_CAPTURE_SAME_CHAIN_WORKSPACE:-$build_dir/workspace-$stamp}"
report_dir="${MA_REAL_CAPTURE_SAME_CHAIN_REPORT_DIR:-$build_dir/reports}"
summary_dir="${MA_REAL_CAPTURE_SAME_CHAIN_SUMMARY_DIR:-$build_dir/summaries}"
capture_report_dir="${MA_REAL_CAPTURE_SAME_CHAIN_CAPTURE_REPORT_DIR:-$build_dir/capture-reports}"
report_path="${MA_REAL_CAPTURE_SAME_CHAIN_REPORT:-$report_dir/real-capture-same-chain-report-$stamp.json}"
capture_summary_path="${MA_REAL_CAPTURE_SAME_CHAIN_CAPTURE_SUMMARY:-$summary_dir/native-capture-summary-$stamp.json}"
capture_report_path="${MA_REAL_CAPTURE_SAME_CHAIN_CAPTURE_REPORT:-$capture_report_dir/native-capture-report-$stamp.json}"

mkdir -p "$report_dir" "$summary_dir" "$capture_report_dir" "$(dirname "$workspace")"

export MA_NATIVE_CAPTURE_SMOKE=1
export MA_NATIVE_CAPTURE_RELEASE_SCOPE=1
export MA_NATIVE_CAPTURE_SMOKE_WORKSPACE="$workspace"
export MA_NATIVE_CAPTURE_ARTIFACT_SMOKE_SUMMARY="$capture_summary_path"
export MA_NATIVE_CAPTURE_ARTIFACT_SMOKE_REPORT="$capture_report_path"
export MA_NATIVE_CAPTURE_ARTIFACT_SMOKE_ATTEMPTS="${MA_NATIVE_CAPTURE_ARTIFACT_SMOKE_ATTEMPTS:-1}"
export MA_NATIVE_CAPTURE_SMOKE_DURATION_SECONDS="${MA_NATIVE_CAPTURE_SMOKE_DURATION_SECONDS:-2}"
export MA_NATIVE_CAPTURE_SMOKE_TIMEOUT_SECONDS="${MA_NATIVE_CAPTURE_SMOKE_TIMEOUT_SECONDS:-120}"
export MA_NATIVE_CAPTURE_SMOKE_SYSTEM_AUDIO="${MA_NATIVE_CAPTURE_SMOKE_SYSTEM_AUDIO:-true}"
export MA_NATIVE_CAPTURE_SMOKE_MICROPHONE_AUDIO="${MA_NATIVE_CAPTURE_SMOKE_MICROPHONE_AUDIO:-false}"

echo "real capture same-chain smoke running: workspace=$workspace report=$report_path" >&2
"$ROOT_DIR/platform/e2e/native-capture-artifact-smoke.sh"

PYTHONDONTWRITEBYTECODE=1 \
PYTHONPATH="$ROOT_DIR/platform/processing-cli/src${PYTHONPATH:+:$PYTHONPATH}" \
python3 - "$ROOT_DIR" "$workspace" "$capture_report_path" "$report_path" <<'PY'
from __future__ import annotations

import hashlib
import json
import os
import subprocess
import sys
from pathlib import Path
from typing import Any


class ChainFailure(Exception):
    def __init__(self, message: str, *, step: str, payload: dict[str, Any] | None = None):
        super().__init__(message)
        self.step = step
        self.payload = payload


root = Path(sys.argv[1])
workspace = Path(sys.argv[2])
capture_report_path = Path(sys.argv[3])
report_path = Path(sys.argv[4])
cli = root / "platform/e2e/ma-cli-local.sh"


def write_report(report: dict[str, Any]) -> None:
    report_path.parent.mkdir(parents=True, exist_ok=True)
    report_path.write_text(json.dumps(report, ensure_ascii=False, indent=2, sort_keys=True) + "\n", encoding="utf-8")


def sha256_file(path: Path) -> str:
    digest = hashlib.sha256()
    with path.open("rb") as handle:
        for chunk in iter(lambda: handle.read(1024 * 1024), b""):
            digest.update(chunk)
    return "sha256:" + digest.hexdigest()


def artifact_path(session_dir: Path, artifact: dict[str, Any]) -> Path:
    raw_path = Path(str(artifact["path"]))
    if raw_path.is_absolute():
        return raw_path
    return session_dir / raw_path


def load_session(session_id: str) -> dict[str, Any]:
    session_path = workspace / "sessions" / session_id / "session.json"
    return json.loads(session_path.read_text(encoding="utf-8"))


def artifact_by_type(session: dict[str, Any], artifact_type: str) -> dict[str, Any]:
    for artifact in session.get("artifacts", []):
        if artifact.get("artifact_type") == artifact_type:
            return artifact
    raise ChainFailure(f"Missing {artifact_type} artifact.", step="validate_artifacts")


def run_cli(step: str, args: list[str], *, expected_exit: int = 0) -> dict[str, Any]:
    env = os.environ.copy()
    env["MEETING_ASSISTANT_WORKSPACE"] = str(workspace)
    completed = subprocess.run(
        [str(cli), *args],
        cwd=root,
        env=env,
        text=True,
        capture_output=True,
        check=False,
    )
    lines = [line for line in completed.stdout.splitlines() if line.strip()]
    payload: dict[str, Any] | None = None
    if len(lines) == 1:
        try:
            parsed = json.loads(lines[0])
            if isinstance(parsed, dict):
                payload = parsed
        except json.JSONDecodeError:
            payload = None
    if completed.returncode != expected_exit or payload is None or payload.get("ok") is not True:
        raise ChainFailure(
            f"{step} failed with exit {completed.returncode}.",
            step=step,
            payload={
                "exit_code": completed.returncode,
                "stdout": completed.stdout,
                "stderr": completed.stderr,
                "json": payload,
            },
        )
    return payload


base_report: dict[str, Any] = {
    "report_schema": 1,
    "component": "platform/e2e/release-real-capture-same-chain-smoke",
    "release_gate": "release-scope-real-capture-same-chain",
    "not_release_readiness": True,
    "workspace": str(workspace),
    "capture_report": str(capture_report_path),
    "report": str(report_path),
    "native_ui_same_chain_proven": False,
}

try:
    capture_report = json.loads(capture_report_path.read_text(encoding="utf-8"))
    session_id = str(capture_report.get("session_id") or "")
    if not session_id:
        raise ChainFailure("Native capture report did not include session_id.", step="capture_report")
    session_dir = workspace / "sessions" / session_id
    recorded_session = load_session(session_id)
    mixed_audio = artifact_by_type(recorded_session, "mixed_audio")
    if mixed_audio.get("capture_status") != "available":
        raise ChainFailure("Native capture did not produce available mixed_audio.", step="validate_mixed_audio")
    mixed_audio_path = artifact_path(session_dir, mixed_audio)
    original_mixed_audio_checksum = sha256_file(mixed_audio_path)
    if mixed_audio.get("checksum") != original_mixed_audio_checksum:
        raise ChainFailure("Native mixed_audio checksum did not match session metadata.", step="validate_mixed_audio")

    transcript_response = run_cli(
        "generate_transcript",
        ["generate_transcript", "--session-id", session_id, "--language", "zh"],
    )
    transcript_id = str(transcript_response.get("transcript_id") or "")
    if not transcript_id:
        raise ChainFailure("generate_transcript did not return transcript_id.", step="generate_transcript")

    speaker_response = run_cli(
        "generate_speaker_labels",
        [
            "generate_speaker_labels",
            "--session-id",
            session_id,
            "--transcript-id",
            transcript_id,
            "--allow-transcript-only-fallback",
            "true",
        ],
    )

    export_dir = workspace / "exports"
    export_dir.mkdir(parents=True, exist_ok=True)
    export_path = export_dir / f"{session_id}.md"
    export_response = run_cli(
        "export_transcript",
        [
            "export_transcript",
            "--session-id",
            session_id,
            "--export-type",
            "markdown",
            "--target-path",
            str(export_path),
        ],
    )
    export_text = export_path.read_text(encoding="utf-8")
    if "Fake transcript generated from local audio." not in export_text:
        raise ChainFailure("Export did not include generated transcript text.", step="export_transcript")

    processed_session = load_session(session_id)
    processed_artifact_types = {artifact.get("artifact_type") for artifact in processed_session.get("artifacts", [])}
    expected_artifacts = {"screen_video", "mixed_audio", "normalized_audio", "transcript_text", "speaker_labels"}
    missing_artifacts = sorted(expected_artifacts - processed_artifact_types)
    if missing_artifacts:
        raise ChainFailure(
            f"Processed session is missing artifacts: {', '.join(missing_artifacts)}.",
            step="validate_processed_artifacts",
        )
    if sha256_file(mixed_audio_path) != original_mixed_audio_checksum:
        raise ChainFailure("Processing changed the original mixed_audio checksum.", step="validate_checksum_preservation")

    delete_response = run_cli("delete_session", ["delete_session", "--session-id", session_id, "--confirm", "true"])
    if session_dir.exists():
        raise ChainFailure("delete_session did not remove the session directory.", step="delete_session")
    if not export_path.is_file():
        raise ChainFailure("delete_session did not retain the external export.", step="delete_session")

    report = {
        **base_report,
        "passed": True,
        "session_id": session_id,
        "capture_mixed_audio_status": mixed_audio.get("capture_status"),
        "mixed_audio_checksum": original_mixed_audio_checksum,
        "transcript_id": transcript_id,
        "speaker_label_status": speaker_response.get("label_status"),
        "export_path": str(export_path),
        "deleted_session": bool(delete_response.get("deleted")),
        "retained_external_exports": delete_response.get("retained_external_exports", []),
        "processed_artifacts": sorted(processed_artifact_types),
        "native_capture_to_processing_same_chain_proven": True,
        "residual_blockers": [
            "App-bundle native UI same-chain still requires MA_NATIVE_APP_REAL_CAPTURE_SAME_CHAIN_SMOKE=1 test-app-bundle evidence.",
            "Release bundle, signing, notarization and all-target sidecar portability remain VS-MA-23 inputs.",
        ],
    }
    write_report(report)
    print(f"real capture same-chain evidence report: {report_path}")
    print("VS-MA-21 real capture same-chain marker [non-contract]: native ScreenCaptureKit mixed_audio entered processing, transcript, export and delete.")
except ChainFailure as exc:
    report = {
        **base_report,
        "passed": False,
        "failure_stage": exc.step,
        "message": str(exc),
        "failure_payload": exc.payload,
    }
    write_report(report)
    print(f"real capture same-chain evidence report: {report_path}", file=sys.stderr)
    raise SystemExit(1)
except Exception as exc:
    report = {
        **base_report,
        "passed": False,
        "failure_stage": "unexpected",
        "message": str(exc),
    }
    write_report(report)
    print(f"real capture same-chain evidence report: {report_path}", file=sys.stderr)
    raise
PY

echo "release real capture same-chain smoke passed."
