#!/usr/bin/env python3
from __future__ import annotations

import argparse
import json
import os
import subprocess
import sys
from pathlib import Path
from typing import Any

from meeting_assistant_cli.workspace_contract import (
    ORIGINAL_MEDIA_ARTIFACT_TYPES,
    ContractError,
    artifact_file_path,
    load_session,
    session_directory,
    sha256_file,
    verify_registered_artifacts,
)


TRANSCRIPTION_ENV_NAMES = (
    "MEETING_ASSISTANT_TRANSCRIPTION_RUNTIME",
    "MEETING_ASSISTANT_TRANSCRIPTION_MODEL",
    "MEETING_ASSISTANT_WHISPER_SMOKE_AUDIO",
)
DERIVED_ARTIFACT_TYPES = {"normalized_audio", "transcript_text", "speaker_labels"}
PARTIAL_EVIDENCE_BLOCKERS = [
    "not a release-scope ScreenCaptureKit gate",
    "does not prove independent system_audio or microphone_audio capture artifacts",
    "does not prove cross-machine TCC/display repeatability",
    "does not prove real native-to-processing successful transcript chain",
    "does not prove VS-MA-23 release readiness",
]
RELEASE_SCOPE_RESIDUAL_RISKS = [
    "does not prove independent system_audio or microphone_audio capture artifacts beyond productized missing/degraded registration",
    "does not prove cross-machine TCC/display repeatability beyond this release-scope run",
    "does not prove real native-to-processing successful transcript chain",
    "does not prove VS-MA-23 release readiness",
]
GENERIC_FAILURE_HINTS = [
    "Confirm the Mac is awake, unlocked, and has an active display before rerunning the smoke.",
    "Grant Screen Recording or Screen & System Audio Recording permission to the test runner app, terminal, and Xcode as applicable.",
    "Rerun the opt-in smoke without changing release readiness status; failed native capture evidence remains partial.",
]


class NativeCaptureArtifactReportError(AssertionError):
    pass


def fail(message: str) -> None:
    raise NativeCaptureArtifactReportError(f"native capture artifact e2e: {message}")


def load_single_json(stdout: str, command: str) -> dict[str, Any]:
    lines = [line for line in stdout.splitlines() if line.strip()]
    if len(lines) != 1:
        fail(f"{command} expected one JSON object, got {len(lines)} lines: {stdout!r}")
    payload = json.loads(lines[0])
    if not isinstance(payload, dict):
        fail(f"{command} response must be a JSON object")
    return payload


def require_response(payload: dict[str, Any], command: str, *, ok: bool, code: str | None = None) -> None:
    for key in ("ok", "request_id", "command", "warnings"):
        if key not in payload:
            fail(f"{command} missing response key {key}")
    if payload["command"] != command:
        fail(f"{command} response command drifted to {payload['command']!r}")
    if payload["ok"] is not ok:
        fail(f"{command} expected ok={ok}, got {payload['ok']!r}")
    if not isinstance(payload["warnings"], list):
        fail(f"{command} warnings must be a list")
    if not ok:
        for key in ("code", "message", "details"):
            if key not in payload:
                fail(f"{command} missing failure key {key}")
        if code is not None and payload["code"] != code:
            fail(f"{command} expected code={code}, got {payload['code']!r}")


def artifact_by_type(session: dict[str, Any], artifact_type: str) -> dict[str, Any]:
    matches = [
        artifact
        for artifact in session.get("artifacts", [])
        if isinstance(artifact, dict) and artifact.get("artifact_type") == artifact_type
    ]
    if len(matches) != 1:
        fail(f"expected exactly one {artifact_type} artifact, got {len(matches)}")
    return matches[0]


def assert_managed_relative_path(artifact: dict[str, Any], artifact_type: str) -> str:
    path_text = str(artifact.get("path", ""))
    if not path_text:
        fail(f"{artifact_type} artifact path is empty")
    path = Path(path_text)
    if path.is_absolute():
        fail(f"{artifact_type} artifact path must be relative, got {path_text}")
    if not path_text.startswith("artifacts/") or ".." in path.parts:
        fail(f"{artifact_type} artifact path must stay under artifacts/, got {path_text}")
    return path_text


def artifact_report_entry(
    session_dir: Path,
    artifact: dict[str, Any],
    artifact_type: str,
    *,
    require_file: bool,
) -> dict[str, Any]:
    path_text = assert_managed_relative_path(artifact, artifact_type)
    status = str(artifact.get("capture_status"))
    entry: dict[str, Any] = {
        "artifact_type": artifact_type,
        "capture_status": status,
        "path": path_text,
        "path_managed_relative": True,
        "has_checksum": bool(artifact.get("checksum")),
        "has_degradation_reason": bool(artifact.get("degradation_reason")),
    }
    if require_file:
        artifact_path = artifact_file_path(session_dir, artifact)
        entry["file_exists"] = artifact_path.is_file()
        entry["file_bytes"] = artifact_path.stat().st_size if artifact_path.is_file() else 0
        entry["checksum_verified"] = sha256_file(artifact_path) == artifact.get("checksum") if artifact_path.is_file() else False
    else:
        entry["file_exists"] = False
        entry["file_bytes"] = 0
        entry["checksum_verified"] = None
    return entry


def assert_unavailable_audio_artifact(
    session_dir: Path,
    session: dict[str, Any],
    artifact_type: str,
    expected_status: str,
) -> dict[str, Any]:
    artifact = artifact_by_type(session, artifact_type)
    if artifact.get("capture_status") != expected_status:
        fail(f"{artifact_type} expected {expected_status}, got {artifact.get('capture_status')!r}")
    if artifact.get("checksum"):
        fail(f"{artifact_type} {expected_status} artifact must not include checksum")
    if not artifact.get("degradation_reason"):
        fail(f"{artifact_type} {expected_status} artifact must include degradation_reason")
    return artifact_report_entry(session_dir, artifact, artifact_type, require_file=False)


def assert_original_artifact_contract(
    session_dir: Path,
    session: dict[str, Any],
    summary: dict[str, Any],
) -> dict[str, dict[str, Any]]:
    expected_types = set(ORIGINAL_MEDIA_ARTIFACT_TYPES)
    actual_types = {
        str(artifact.get("artifact_type"))
        for artifact in session.get("artifacts", [])
        if isinstance(artifact, dict) and artifact.get("artifact_type") in expected_types
    }
    if actual_types != expected_types:
        fail(f"original artifact types mismatch: expected {sorted(expected_types)}, got {sorted(actual_types)}")

    verify_registered_artifacts(session_dir, expected_types)

    artifacts: dict[str, dict[str, Any]] = {}
    screen = artifact_by_type(session, "screen_video")
    if screen.get("capture_status") != "available":
        fail(f"screen_video must be available, got {screen.get('capture_status')!r}")
    screen_path = artifact_file_path(session_dir, screen)
    if not screen_path.is_file():
        fail(f"screen_video file is missing at {screen_path}")
    if screen_path.stat().st_size <= 0:
        fail("screen_video file must be non-empty")
    checksum = screen.get("checksum")
    if not isinstance(checksum, str) or not checksum.startswith("sha256:"):
        fail("screen_video checksum must be a sha256 value")
    if sha256_file(screen_path) != checksum:
        fail("screen_video checksum does not match file bytes")
    if summary.get("screen_video_checksum") != checksum:
        fail("ScreenCaptureKit summary checksum differs from processing contract checksum")
    if summary.get("screen_video_bytes") is not None and summary.get("screen_video_bytes") != screen_path.stat().st_size:
        fail("ScreenCaptureKit summary screen_video_bytes differs from file size")
    summary_screen_path = summary.get("screen_video_path")
    if summary_screen_path and Path(str(summary_screen_path)).resolve(strict=False) != screen_path.resolve(strict=False):
        fail("ScreenCaptureKit summary screen_video_path differs from registered artifact path")
    artifacts["screen_video"] = artifact_report_entry(session_dir, screen, "screen_video", require_file=True)

    expected_status = {
        "system_audio": "degraded" if summary.get("capture_system_audio") else "missing",
        "microphone_audio": "degraded" if summary.get("capture_microphone_audio") else "missing",
    }
    for artifact_type, status in expected_status.items():
        artifacts[artifact_type] = assert_unavailable_audio_artifact(session_dir, session, artifact_type, status)

    audio_requested = bool(summary.get("capture_system_audio") or summary.get("capture_microphone_audio"))
    mixed_audio = artifact_by_type(session, "mixed_audio")
    if audio_requested and mixed_audio.get("capture_status") == "available":
        mixed_path = artifact_file_path(session_dir, mixed_audio)
        if not mixed_path.is_file():
            fail(f"mixed_audio file is missing at {mixed_path}")
        if mixed_path.stat().st_size <= 0:
            fail("mixed_audio file must be non-empty")
        checksum = mixed_audio.get("checksum")
        if not isinstance(checksum, str) or not checksum.startswith("sha256:"):
            fail("mixed_audio available artifact must include a sha256 value")
        if sha256_file(mixed_path) != checksum:
            fail("mixed_audio checksum does not match file bytes")
        artifacts["mixed_audio"] = artifact_report_entry(session_dir, mixed_audio, "mixed_audio", require_file=True)
    else:
        mixed_expected_status = "degraded" if audio_requested else "missing"
        artifacts["mixed_audio"] = assert_unavailable_audio_artifact(
            session_dir,
            session,
            "mixed_audio",
            mixed_expected_status,
        )
    return artifacts


def run_generate_transcript_fail_closed(
    workspace: Path,
    session_id: str,
    *,
    root: Path,
    python: str,
) -> dict[str, Any]:
    env = os.environ.copy()
    for env_name in TRANSCRIPTION_ENV_NAMES:
        env.pop(env_name, None)
    env["MEETING_ASSISTANT_WORKSPACE"] = str(workspace)
    pythonpath = [str(root / "platform/processing-cli/src")]
    if env.get("PYTHONPATH"):
        pythonpath.append(env["PYTHONPATH"])
    env["PYTHONPATH"] = os.pathsep.join(pythonpath)

    completed = subprocess.run(
        [python, "-m", "meeting_assistant_cli", "generate_transcript", "--session-id", session_id],
        cwd=root,
        env=env,
        text=True,
        capture_output=True,
        check=False,
    )
    if completed.returncode != 3:
        fail(
            "generate_transcript should fail closed with artifact_missing when real capture produced no usable audio; "
            f"exit={completed.returncode} stdout={completed.stdout!r} stderr={completed.stderr!r}"
        )
    if "Traceback" in completed.stdout or "Traceback" in completed.stderr:
        fail("generate_transcript failure must not leak a traceback")
    payload = load_single_json(completed.stdout, "generate_transcript")
    require_response(payload, "generate_transcript", ok=False, code="artifact_missing")
    return {
        "command": "generate_transcript",
        "exit_code": completed.returncode,
        "ok": False,
        "code": payload["code"],
        "fail_closed": True,
    }


def assert_no_derived_artifact_pollution(session: dict[str, Any]) -> bool:
    actual = {
        str(artifact.get("artifact_type"))
        for artifact in session.get("artifacts", [])
        if isinstance(artifact, dict) and artifact.get("artifact_type") in DERIVED_ARTIFACT_TYPES
    }
    if actual:
        fail(f"fail-closed processing path must not register derived artifacts, got {sorted(actual)}")
    return False


def build_report(
    summary_path: Path,
    *,
    report_path: Path | None = None,
    root: Path | None = None,
    python: str | None = None,
    release_scope: bool = False,
) -> dict[str, Any]:
    root = (root or Path.cwd()).resolve()
    python = python or sys.executable
    summary = json.loads(summary_path.read_text(encoding="utf-8"))
    if not isinstance(summary, dict):
        fail("native capture summary must be a JSON object")
    if summary.get("ok") is not True:
        fail(f"native capture summary did not pass: {summary}")

    workspace = Path(str(summary["workspace"]))
    session_id = str(summary["session_id"])
    session_dir = session_directory(workspace, session_id)
    session = load_session(session_dir)

    if session.get("id") != session_id:
        fail("session id drifted between native summary and session.json")
    if session.get("source_type") != "native_recording":
        fail("session source_type must be native_recording")
    if session.get("status") != "recorded":
        fail("session status must be recorded before processing consumption")
    if not session.get("ended_at"):
        fail("recorded native session must include ended_at")

    artifacts = assert_original_artifact_contract(session_dir, session, summary)
    mixed_audio_available = artifacts["mixed_audio"]["capture_status"] == "available"
    if mixed_audio_available:
        processing = {
            "command": "generate_transcript",
            "skipped": True,
            "reason": "mixed_audio was available in this native capture run; no-audio artifact_missing processing path is not applicable.",
            "fail_closed": None,
        }
    else:
        processing = run_generate_transcript_fail_closed(workspace, session_id, root=root, python=python)
    derived_pollution = assert_no_derived_artifact_pollution(load_session(session_dir))

    release_gate = "release-scope-native-capture" if release_scope else "partial-evidence-only"
    release_blockers = RELEASE_SCOPE_RESIDUAL_RISKS if release_scope else PARTIAL_EVIDENCE_BLOCKERS
    report: dict[str, Any] = {
        "report_schema": 1,
        "component": "platform/e2e/native-capture-artifact-smoke",
        "scope": "validation-only",
        "release_gate": release_gate,
        "release_scope_native_capture": release_scope,
        "vs_ma": ["VS-MA-14", "VS-MA-15"],
        "pv": ["PV-MA-002", "PV-MA-003"],
        "summary_path": str(summary_path),
        "workspace": str(workspace),
        "session_id": session_id,
        "source_type": session["source_type"],
        "session_status": session["status"],
        "recorded_ended_at": True,
        "adapter": summary.get("adapter"),
        "capture_system_audio": bool(summary.get("capture_system_audio")),
        "capture_microphone_audio": bool(summary.get("capture_microphone_audio")),
        "artifacts": artifacts,
        "processing_contract": processing | {
            "derived_artifact_pollution": derived_pollution,
        },
        "not_release_readiness": True,
        "release_blockers": release_blockers,
        "findings": [],
    }
    if report_path is not None:
        report_path.parent.mkdir(parents=True, exist_ok=True)
        report_path.write_text(json.dumps(report, ensure_ascii=False, indent=2, sort_keys=True) + "\n", encoding="utf-8")
    return report


def _response_summary(response: Any) -> dict[str, Any] | None:
    if not isinstance(response, dict):
        return None
    return {
        "ok": response.get("ok"),
        "command": response.get("command"),
        "code": response.get("code"),
        "message": response.get("message"),
        "session_id": response.get("session_id"),
        "status": response.get("status"),
    }


def failure_diagnostics(summary: dict[str, Any]) -> tuple[dict[str, bool], list[str]]:
    failure_stage = str(summary.get("failure_stage") or "unknown")
    message = str(summary.get("message") or "")
    start_response = summary.get("start_response") if isinstance(summary.get("start_response"), dict) else {}
    stop_response = summary.get("stop_response") if isinstance(summary.get("stop_response"), dict) else {}
    start_code = str(start_response.get("code") or "")
    stop_code = str(stop_response.get("code") or "")
    validation_errors = summary.get("validation_errors") if isinstance(summary.get("validation_errors"), list) else []
    validation_text = " ".join(str(item) for item in validation_errors)
    haystack = " ".join([failure_stage, message, start_code, stop_code, validation_text]).lower()

    diagnostics = {
        "permission_or_tcc_likely": any(
            token in haystack
            for token in (
                "permission_denied",
                "permission",
                "screen recording",
                "screen & system audio",
                "microphone",
                "tcc",
            )
        ),
        "display_or_target_likely": any(
            token in haystack
            for token in ("display", "screen_video", "no display", "window", "target", "shareable content")
        ),
        "runtime_or_os_likely": failure_stage == "runtime" or "macos" in haystack or "screencapturekit" in haystack,
        "timeout_likely": failure_stage == "timeout" or "timed out" in haystack,
        "artifact_validation_likely": failure_stage == "validation" or bool(validation_errors),
    }

    hints = list(GENERIC_FAILURE_HINTS)
    if diagnostics["runtime_or_os_likely"]:
        hints.append("Verify the host macOS version supports ScreenCaptureKit recording output.")
    if diagnostics["timeout_likely"]:
        hints.append("Increase MA_NATIVE_CAPTURE_SMOKE_TIMEOUT_SECONDS only after confirming the runner is not blocked by a system permission prompt.")
    if diagnostics["display_or_target_likely"]:
        hints.append("Confirm a capturable display or target is available; display sleep or remote/headless sessions can produce missing screen_video evidence.")
    if diagnostics["artifact_validation_likely"]:
        hints.append("Inspect the copied native capture summary and workspace session.json before rerunning; validation failures are not release-ready evidence.")
    return diagnostics, hints


def build_failure_report(
    summary_path: Path,
    *,
    report_path: Path | None = None,
    native_exit_code: int | None = None,
    attempts: int | None = None,
    display_wake_seconds: int | None = None,
    display_wake_settle_seconds: int | None = None,
    release_scope: bool = False,
) -> dict[str, Any]:
    summary = json.loads(summary_path.read_text(encoding="utf-8"))
    if not isinstance(summary, dict):
        fail("native capture failure summary must be a JSON object")
    if summary.get("ok") is True:
        fail("native capture failure report requires a failed summary")

    diagnostics, remediation_hints = failure_diagnostics(summary)
    release_gate = "release-scope-native-capture" if release_scope else "partial-evidence-only"
    release_blockers = RELEASE_SCOPE_RESIDUAL_RISKS if release_scope else PARTIAL_EVIDENCE_BLOCKERS
    finding = (
        "native capture smoke did not pass; release-scope evidence remains unavailable"
        if release_scope
        else "native capture smoke did not pass; evidence remains partial"
    )
    report: dict[str, Any] = {
        "report_schema": 1,
        "component": "platform/e2e/native-capture-artifact-smoke",
        "scope": "validation-only",
        "release_gate": release_gate,
        "release_scope_native_capture": release_scope,
        "vs_ma": ["VS-MA-14", "VS-MA-15"],
        "pv": ["PV-MA-002", "PV-MA-003"],
        "summary_path": str(summary_path),
        "native_smoke_ok": False,
        "native_exit_code": native_exit_code,
        "native_attempts": attempts,
        "workspace": summary.get("workspace"),
        "session_id": summary.get("session_id"),
        "adapter": summary.get("adapter"),
        "failure_stage": summary.get("failure_stage") or "unknown",
        "message": summary.get("message"),
        "capture_system_audio": bool(summary.get("capture_system_audio")),
        "capture_microphone_audio": bool(summary.get("capture_microphone_audio")),
        "start_response": _response_summary(summary.get("start_response")),
        "stop_response": _response_summary(summary.get("stop_response")),
        "validation_errors": summary.get("validation_errors") if isinstance(summary.get("validation_errors"), list) else [],
        "notes": summary.get("notes") if isinstance(summary.get("notes"), list) else [],
        "display_wake_guard": {
            "seconds": display_wake_seconds,
            "settle_seconds": display_wake_settle_seconds,
        },
        "diagnostics": diagnostics,
        "remediation_hints": remediation_hints,
        "not_release_readiness": True,
        "release_blockers": release_blockers,
        "findings": [finding],
    }
    if report_path is not None:
        report_path.parent.mkdir(parents=True, exist_ok=True)
        report_path.write_text(json.dumps(report, ensure_ascii=False, indent=2, sort_keys=True) + "\n", encoding="utf-8")
    return report


def main(argv: list[str] | None = None) -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("--summary", default=os.environ.get("MA_NATIVE_CAPTURE_ARTIFACT_SUMMARY"))
    parser.add_argument("--report", default=os.environ.get("MA_NATIVE_CAPTURE_ARTIFACT_REPORT"))
    parser.add_argument("--failure-report", action="store_true")
    parser.add_argument("--native-exit-code", type=int)
    parser.add_argument("--attempts", type=int)
    parser.add_argument("--display-wake-seconds", type=int)
    parser.add_argument("--display-wake-settle-seconds", type=int)
    parser.add_argument("--release-scope", action="store_true")
    args = parser.parse_args(argv)
    if not args.summary:
        print("native capture artifact report failed: --summary is required", file=sys.stderr)
        return 2

    try:
        if args.failure_report:
            report = build_failure_report(
                Path(args.summary),
                report_path=Path(args.report) if args.report else None,
                native_exit_code=args.native_exit_code,
                attempts=args.attempts,
                display_wake_seconds=args.display_wake_seconds,
                display_wake_settle_seconds=args.display_wake_settle_seconds,
                release_scope=args.release_scope,
            )
        else:
            report = build_report(
                Path(args.summary),
                report_path=Path(args.report) if args.report else None,
                root=Path.cwd(),
                python=sys.executable,
                release_scope=args.release_scope,
            )
    except (ContractError, NativeCaptureArtifactReportError, OSError, json.JSONDecodeError) as exc:
        print(f"native capture artifact report failed: {exc}", file=sys.stderr)
        return 1

    if args.report:
        print(f"native capture artifact evidence report: {args.report}", file=sys.stderr)
    if args.failure_report:
        print(
            "VS-MA-14/15 real native capture artifact failure report marker [non-contract]: "
            f"failure_stage={report['failure_stage']} release_gate={report['release_gate']}."
        )
        return 0
    print(
        "VS-MA-14/15 real native capture artifact e2e marker [non-contract]: "
        "processing workspace contract consumed native session and original artifact availability was verified."
    )
    print(
        "VS-MA-14/15 real native capture artifact report marker [non-contract]: "
        f"report_schema={report['report_schema']} release_gate={report['release_gate']}."
    )
    if args.release_scope:
        print("VS-MA-14/15 release-scope native capture artifact gate passed.")
    print("real native capture artifact e2e smoke passed.")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
