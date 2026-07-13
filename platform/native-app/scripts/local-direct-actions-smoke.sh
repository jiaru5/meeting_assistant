#!/usr/bin/env bash
set -euo pipefail

component_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
root_dir="$(cd "$component_dir/../.." && pwd)"
cd "$root_dir"

timeout_seconds="${MA_NATIVE_LOCAL_APP_ACTIONS_SMOKE_TIMEOUT_SECONDS:-180}"
report_dir="${MA_NATIVE_LOCAL_APP_ACTIONS_SMOKE_REPORT_DIR:-$component_dir/build/local-direct-actions-smoke}"
report_file="$report_dir/local-direct-actions-smoke-report.json"
snapshot_file="$report_dir/local-direct-actions-ui-tree.txt"
runner_log="$report_dir/run-local-app.log"
export_dir="${MA_NATIVE_LOCAL_APP_ACTIONS_SMOKE_EXPORT_DIR:-$report_dir/export}"
workspace_dir="${MA_NATIVE_LOCAL_APP_ACTIONS_SMOKE_WORKSPACE:-$component_dir/build/local-direct-recording-smoke-direct/workspace}"
session_id="${MA_NATIVE_LOCAL_APP_ACTIONS_SMOKE_SESSION_ID:-session-app-ui-blocked}"
expected_terms="${MA_NATIVE_LOCAL_APP_ACTIONS_SMOKE_EXPECTED_TERMS:-}"
ax_helper="$report_dir/local-app-ax-helper"

usage() {
  cat <<'USAGE'
Usage: platform/native-app/scripts/local-direct-actions-smoke.sh [run-local-app options]

Launch the local-direct Release MeetingAssistantNative.app with an existing
processed workspace/session, press Copy/Export/Delete through macOS
Accessibility AXIdentifier / AXPress controls, and verify system pasteboard,
Save Panel export, delete confirmation, external export retention, and delete
event output.

This smoke consumes an existing processed session. It does not start recording,
does not start processing, does not open System Settings, does not modify TCC or
system permissions, and does not require Developer ID/notarization.
USAGE
}

if [[ "${1:-}" == "--help" ]]; then
  usage
  exit 0
fi

for arg in "$@"; do
  case "$arg" in
    --workspace)
      echo "error: local-direct actions smoke owns --workspace; use MA_NATIVE_LOCAL_APP_ACTIONS_SMOKE_WORKSPACE instead." >&2
      exit 2
      ;;
    --ma-native-transcript-workspace* | --ma-native-transcript-session-id* | --)
      echo "error: local-direct actions smoke owns native transcript app args." >&2
      exit 2
      ;;
  esac
done

mkdir -p "$report_dir" "$export_dir"
swiftc "$component_dir/scripts/local-app-ax.swift" -o "$ax_helper"
export_run_id="${MA_NATIVE_LOCAL_APP_ACTIONS_SMOKE_RUN_ID:-$(date -u +%Y%m%dT%H%M%SZ)-$$}"
export_path="$export_dir/$session_id-$export_run_id.md"
rm -f "$export_path"

collect_pids() {
  /usr/bin/pgrep -x MeetingAssistantNative 2>/dev/null || true
}

pid_is_new() {
  local candidate="$1"
  local existing
  for existing in ${before_pids:-}; do
    if [[ "$candidate" == "$existing" ]]; then
      return 1
    fi
  done
  return 0
}

before_pids="$(collect_pids)"
runner_pid=""
app_pid=""

cleanup() {
  local exit_code=$?
  if [[ -n "$app_pid" ]]; then
    /bin/kill "$app_pid" >/dev/null 2>&1 || true
  fi
  if [[ -n "$runner_pid" ]]; then
    wait "$runner_pid" >/dev/null 2>&1 || true
  fi
  exit "$exit_code"
}
trap cleanup EXIT INT TERM

"$component_dir/scripts/run-local-app.sh" \
  --workspace "$workspace_dir" \
  "$@" \
  -- \
  "--ma-native-transcript-workspace=$workspace_dir" \
  "--ma-native-transcript-session-id=$session_id" >"$runner_log" 2>&1 &
runner_pid=$!

deadline=$((SECONDS + timeout_seconds))
while [[ $SECONDS -lt $deadline ]]; do
  current_pids="$(collect_pids)"
  for pid in $current_pids; do
    if pid_is_new "$pid"; then
      app_pid="$pid"
      break
    fi
  done
  if [[ -n "$app_pid" ]]; then
    break
  fi
  if ! kill -0 "$runner_pid" >/dev/null 2>&1; then
    echo "local-direct actions smoke failed: run-local-app exited before the app became visible." >&2
    cat "$runner_log" >&2 || true
    exit 1
  fi
  sleep 0.5
done

if [[ -z "$app_pid" ]]; then
  echo "local-direct actions smoke failed: timed out waiting for MeetingAssistantNative process." >&2
  cat "$runner_log" >&2 || true
  exit 1
fi

python3 - "$report_file" "$snapshot_file" "$runner_log" "$app_pid" "$workspace_dir" "$session_id" "$timeout_seconds" "$export_dir" "$export_path" "$expected_terms" "$ax_helper" <<'PY'
import json
import plistlib
import re
import subprocess
import sys
import time
from pathlib import Path
from typing import Any, Optional, Tuple

report_path = Path(sys.argv[1])
snapshot_path = Path(sys.argv[2])
runner_log_path = Path(sys.argv[3])
app_pid = int(sys.argv[4])
workspace_dir = Path(sys.argv[5])
session_id = sys.argv[6]
timeout_seconds = int(sys.argv[7])
export_dir = Path(sys.argv[8])
export_path = Path(sys.argv[9])
actual_export_path = export_path
expected_terms_raw = sys.argv[10].strip()
AX_HELPER = Path(sys.argv[11])

last_snapshot = ""
checked_markers: list[str] = []
pressed_controls: list[str] = []
blocker_type = "none"
blocker_detail = ""
clipboard_excerpt = ""
delete_event_path = ""


class SmokeFailure(Exception):
    def __init__(self, kind: str, detail: str) -> None:
        super().__init__(detail)
        self.kind = kind
        self.detail = detail


def run_osascript(script: str, args: list[str], timeout: int) -> str:
    try:
        completed = subprocess.run(
            ["/usr/bin/osascript", "-", *args],
            input=script,
            text=True,
            stdout=subprocess.PIPE,
            stderr=subprocess.PIPE,
            timeout=timeout,
            check=False,
        )
    except subprocess.TimeoutExpired as exc:
        raise SmokeFailure("accessibility_timeout", f"osascript timed out after {timeout}s") from exc
    if completed.returncode != 0:
        raise SmokeFailure(
            "accessibility_error",
            (completed.stderr or completed.stdout or "osascript failed").strip(),
        )
    return completed.stdout


def run_ax_helper(command: str, args: list[str], timeout: int) -> str:
    if not AX_HELPER.is_file():
        raise SmokeFailure("accessibility_error", f"missing AX helper: {AX_HELPER}")
    try:
        completed = subprocess.run(
            [str(AX_HELPER), command, str(timeout), str(app_pid), *args],
            text=True,
            stdout=subprocess.PIPE,
            stderr=subprocess.PIPE,
            timeout=timeout + 30,
            check=False,
        )
    except subprocess.TimeoutExpired as exc:
        raise SmokeFailure("accessibility_timeout", f"AX helper timed out after {timeout}s") from exc
    if completed.returncode != 0:
        raise SmokeFailure(
            "accessibility_error",
            (completed.stderr or completed.stdout or "AX helper failed").strip(),
        )
    return completed.stdout


def snapshot(timeout: int = 120) -> str:
    global last_snapshot
    text = run_ax_helper("snapshot", [], timeout)
    last_snapshot = text
    snapshot_path.write_text(text, encoding="utf-8")
    return text


def classify_snapshot(text: str) -> Tuple[Optional[str], Optional[str]]:
    lowered = text.lower()
    if "transcript is missing" in lowered or "transcript actions are unavailable" in lowered:
        return "transcript_missing", "transcript actions are unavailable"
    if "artifact_missing" in lowered:
        return "artifact_missing", "required transcript action artifact is missing"
    if "path_conflict" in lowered:
        return "path_conflict", "transcript action path conflict"
    if "permission_denied" in lowered:
        return "permission_denied", "transcript action permission denied"
    if "internal_error" in lowered:
        return "internal_error", "transcript action internal error"
    return None, None


def wait_for_marker(marker: str, timeout: int) -> str:
    deadline = time.monotonic() + timeout
    while time.monotonic() < deadline:
        try:
            text = snapshot(timeout=120)
        except SmokeFailure as exc:
            if exc.kind in {"accessibility_error", "accessibility_timeout"}:
                time.sleep(0.5)
                continue
            raise
        if marker in text:
            checked_markers.append(marker)
            return text
        kind, detail = classify_snapshot(text)
        if kind:
            raise SmokeFailure(kind, detail or marker)
        time.sleep(0.5)
    raise SmokeFailure("ui_timeout", f"timed out waiting for marker: {marker}")


def buttons_enabled(text: str, identifiers: list[str]) -> bool:
    for identifier in identifiers:
        if f"identifier={identifier} enabled=true" not in text:
            return False
    return True


def wait_for_actions_ready(timeout: int) -> str:
    deadline = time.monotonic() + timeout
    identifiers = [
        "ma.transcriptAction.copyButton",
        "ma.transcriptAction.exportButton",
        "ma.transcriptAction.deleteButton",
    ]
    while time.monotonic() < deadline:
        try:
            text = snapshot(timeout=120)
        except SmokeFailure as exc:
            if exc.kind in {"accessibility_error", "accessibility_timeout"}:
                time.sleep(0.5)
                continue
            raise
        if "Transcript actions are ready." in text or buttons_enabled(text, identifiers):
            checked_markers.append("Transcript actions are ready or action controls enabled.")
            return text
        kind, detail = classify_snapshot(text)
        if kind:
            raise SmokeFailure(kind, detail or "actions ready")
        time.sleep(0.5)
    raise SmokeFailure("ui_timeout", "timed out waiting for transcript action controls")


def wait_for_pasteboard(transcript: str, timeout: int) -> str:
    deadline = time.monotonic() + timeout
    last_content = ""
    while time.monotonic() < deadline:
        last_content = read_pasteboard()
        try:
            validate_action_content(last_content, transcript, "system pasteboard")
            checked_markers.append("Copy complete.")
            return last_content
        except SmokeFailure:
            time.sleep(0.5)
    raise SmokeFailure("clipboard_mismatch", "system pasteboard does not contain transcript content")


def exported_path_from_snapshot(text: str) -> Optional[Path]:
    marker = "value=Exported markdown transcript to "
    for line in text.splitlines():
        if marker not in line:
            continue
        raw_path = line.split(marker, 1)[1].strip()
        if raw_path.endswith("."):
            raw_path = raw_path[:-1]
        if raw_path:
            return Path(raw_path)
    return None


def wait_for_export(transcript: str, timeout: int) -> str:
    global actual_export_path
    deadline = time.monotonic() + timeout
    while time.monotonic() < deadline:
        text = snapshot(timeout=120)
        if "Export complete." not in text:
            time.sleep(0.5)
            continue
        observed_export_path = exported_path_from_snapshot(text)
        if observed_export_path is None:
            time.sleep(0.5)
            continue
        actual_export_path = observed_export_path
        if actual_export_path.is_file():
            content = actual_export_path.read_text(encoding="utf-8", errors="replace")
            validate_action_content(content, transcript, "exported markdown")
            checked_markers.append("Export complete.")
            return content
        time.sleep(0.5)
    raise SmokeFailure("export_missing", f"expected export file is missing after Save Panel export: {actual_export_path}")


def wait_for_delete(timeout: int) -> tuple[str, str]:
    deadline = time.monotonic() + timeout
    while time.monotonic() < deadline:
        if not session_root().exists():
            event_path, event = find_delete_event()
            checked_markers.append("Delete complete.")
            return event_path, event
        time.sleep(0.5)
    raise SmokeFailure("delete_failed", f"session root still exists after delete: {session_root()}")


def wait_for_delete_prompt(timeout: int) -> str:
    deadline = time.monotonic() + timeout
    while time.monotonic() < deadline:
        try:
            text = snapshot(timeout=120)
        except SmokeFailure as exc:
            if exc.kind in {"accessibility_error", "accessibility_timeout"}:
                time.sleep(0.5)
                continue
            raise
        if "External exports are retained." in text or "identifier=ma.transcriptAction.deleteConfirmButton enabled=true" in text:
            checked_markers.append("Delete confirmation is visible.")
            return text
        time.sleep(0.5)
    raise SmokeFailure("ui_timeout", "timed out waiting for delete confirmation")


def press(identifier: str) -> None:
    run_ax_helper("press", [identifier], 30)
    pressed_controls.append(identifier)


def press_with_retry(identifier: str, timeout: int) -> None:
    deadline = time.monotonic() + timeout
    last_error: Optional[SmokeFailure] = None
    while time.monotonic() < deadline:
        try:
            press(identifier)
            return
        except SmokeFailure as exc:
            last_error = exc
            if exc.kind not in {"accessibility_error", "accessibility_timeout"}:
                raise
            time.sleep(0.5)
    if last_error:
        raise last_error
    raise SmokeFailure("ui_timeout", f"timed out pressing {identifier}")


def confirm_save_panel() -> None:
    wait_for_marker("identifier=save-panel", 30)
    wait_for_marker("identifier=saveAsNameTextField", 30)
    run_ax_helper("set-value", ["saveAsNameTextField", export_path.name], 30)
    wait_for_marker(f"value={export_path.name}", 30)
    wait_for_marker("identifier=OKButton enabled=true", 30)
    press_with_retry("OKButton", 30)


def runner_configuration() -> dict[str, str]:
    config: dict[str, str] = {}
    if runner_log_path.is_file():
        for line in runner_log_path.read_text(encoding="utf-8", errors="replace").splitlines():
            stripped = line.strip()
            if ": " in stripped:
                key, value = stripped.split(": ", 1)
                normalized = key.lower().replace(" ", "_")
                if normalized in {
                    "app",
                    "cli",
                    "workspace",
                    "launch_mode",
                    "capture_system_audio",
                    "capture_microphone_audio",
                    "processing_runtime",
                    "transcription_runtime",
                    "transcription_model",
                }:
                    config[normalized] = value
    return config


def app_identity(config: dict[str, str]) -> dict[str, Any]:
    identity: dict[str, Any] = {}
    app_path = config.get("app", "")
    if not app_path:
        return identity
    app = Path(app_path)
    identity["path"] = str(app)
    plist_path = app / "Contents" / "Info.plist"
    if plist_path.is_file():
        with plist_path.open("rb") as handle:
            plist = plistlib.load(handle)
        for key in ("CFBundleIdentifier", "CFBundleName", "CFBundleShortVersionString"):
            identity[key] = plist.get(key, "")
    completed = subprocess.run(
        ["/usr/bin/codesign", "-dv", "--verbose=4", str(app)],
        text=True,
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
        check=False,
    )
    if completed.returncode == 0:
        fields: dict[str, str] = {}
        for line in (completed.stderr or completed.stdout).splitlines():
            if "=" in line:
                key, value = line.split("=", 1)
                key = key.strip()
                if key in {"Identifier", "Format", "Signature", "TeamIdentifier", "CDHash"}:
                    fields[key] = value.strip()
        identity["codesign"] = fields
    return identity


def session_root() -> Path:
    return workspace_dir / "sessions" / session_id


def load_json(path: Path) -> Any:
    try:
        return json.loads(path.read_text(encoding="utf-8"))
    except FileNotFoundError as exc:
        raise SmokeFailure("artifact_missing", f"missing JSON file: {path}") from exc
    except json.JSONDecodeError as exc:
        raise SmokeFailure("artifact_invalid", f"invalid JSON file: {path}") from exc


def artifact_path(artifact: dict[str, Any]) -> Path:
    raw_path = artifact.get("path")
    if not isinstance(raw_path, str) or not raw_path:
        raise SmokeFailure("artifact_missing", f"{artifact.get('artifact_type', '<unknown>')} artifact path is missing")
    path = Path(raw_path)
    if not path.is_absolute():
        path = session_root() / path
    resolved = path.resolve(strict=False)
    resolved_root = session_root().resolve(strict=False)
    if not (resolved == resolved_root or resolved_root in resolved.parents):
        raise SmokeFailure("path_conflict", f"artifact path escapes the session root: {raw_path}")
    return resolved


def session_artifacts() -> list[dict[str, Any]]:
    data = load_json(session_root() / "session.json")
    artifacts = data.get("artifacts")
    if not isinstance(artifacts, list):
        raise SmokeFailure("artifact_invalid", "session artifacts must be a list")
    return [artifact for artifact in artifacts if isinstance(artifact, dict)]


def artifact_by_type(artifact_type: str) -> dict[str, Any]:
    for artifact in session_artifacts():
        if artifact.get("artifact_type") == artifact_type:
            return artifact
    raise SmokeFailure("artifact_missing", f"{artifact_type} artifact is missing from session.json")


def transcript_text() -> str:
    transcript_artifact = artifact_by_type("transcript_text")
    transcript = load_json(artifact_path(transcript_artifact))
    segments = transcript.get("segments")
    if not isinstance(segments, list) or not segments:
        raise SmokeFailure("artifact_invalid", "transcript.json must contain at least one segment")
    text = " ".join(
        str(segment.get("text", ""))
        for segment in segments
        if isinstance(segment, dict)
    ).strip()
    if not text:
        raise SmokeFailure("artifact_invalid", "transcript text is empty")
    return text


def expected_content_markers(transcript: str) -> list[str]:
    explicit_terms = [
        term.strip()
        for term in expected_terms_raw.split(",")
        if term.strip()
    ]
    if explicit_terms:
        return explicit_terms
    candidates = [
        token.strip("[]().,，。:：;；")
        for token in re.split(r"\s+", transcript)
        if len(token.strip("[]().,，。:：;；")) >= 4
    ]
    return candidates[:3]


def validate_action_content(content: str, transcript: str, label: str) -> None:
    lower_content = content.lower()
    markers = expected_content_markers(transcript)
    if not markers:
        if transcript[:40] not in content:
            raise SmokeFailure("content_mismatch", f"{label} does not contain transcript content")
        return
    missing = [marker for marker in markers if marker.lower() not in lower_content]
    if missing:
        raise SmokeFailure("content_mismatch", f"{label} is missing transcript markers: {', '.join(missing)}")


def validate_processed_input() -> str:
    root = session_root()
    if not root.is_dir():
        raise SmokeFailure("workspace_missing", f"session root does not exist: {root}")
    for artifact_type in ("transcript_text", "speaker_labels"):
        artifact = artifact_by_type(artifact_type)
        if artifact.get("capture_status") not in {"available", "degraded"}:
            raise SmokeFailure("artifact_missing", f"{artifact_type} artifact is not available or degraded")
        if not artifact_path(artifact).is_file():
            raise SmokeFailure("artifact_missing", f"{artifact_type} file is missing")
    text = transcript_text()
    expected_terms = [
        term.strip()
        for term in expected_terms_raw.split(",")
        if term.strip()
    ]
    lower_text = text.lower()
    missing_terms = [term for term in expected_terms if term.lower() not in lower_text]
    if missing_terms:
        raise SmokeFailure("artifact_invalid", f"missing expected transcript terms: {', '.join(missing_terms)}")
    return text


def read_pasteboard() -> str:
    completed = subprocess.run(
        ["/usr/bin/pbpaste"],
        text=True,
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
        check=False,
    )
    if completed.returncode != 0:
        raise SmokeFailure("clipboard_unavailable", (completed.stderr or "pbpaste failed").strip())
    return completed.stdout


def workspace_files() -> list[str]:
    if not workspace_dir.exists():
        return []
    return sorted(
        str(path.relative_to(workspace_dir))
        for path in workspace_dir.rglob("*")
        if path.is_file()
    )


def find_delete_event() -> tuple[str, str]:
    for path in sorted(workspace_dir.rglob("*")):
        if not path.is_file():
            continue
        try:
            content = path.read_text(encoding="utf-8", errors="replace")
        except OSError:
            continue
        if "meeting_session.deleted.v1" in content and session_id in content:
            return str(path), content
    raise SmokeFailure("delete_event_missing", "delete event was not written")


def write_report(passed: bool, transcript_excerpt: str = "") -> None:
    config = runner_configuration()
    launch_mode = config.get("launch_mode", "")
    report = {
        "report_schema": 1,
        "release_gate": "local-direct-actions-smoke",
        "passed": passed,
        "blocker_type": blocker_type,
        "blocker_detail": blocker_detail,
        "app_pid": app_pid,
        "workspace": str(workspace_dir),
        "session_id": session_id,
        "runner_configuration": config,
        "app_identity": app_identity(config),
        "ui_tree": str(snapshot_path),
        "runner_log": str(runner_log_path),
        "checked_markers": checked_markers,
        "pressed_controls": pressed_controls,
        "requested_export_path": str(export_path),
        "actual_export_path": str(actual_export_path),
        "export_path": str(actual_export_path),
        "export_exists": actual_export_path.is_file(),
        "session_root_exists_after_delete": session_root().exists(),
        "delete_event_path": delete_event_path,
        "clipboard_excerpt": clipboard_excerpt,
        "transcript_excerpt": transcript_excerpt[:240],
        "workspace_files": workspace_files()[:120],
        "workspace_precondition": (
            "Requires an existing processed session from local-direct-processing-smoke or an equivalent "
            "native recording plus processing workspace."
        ),
        "actions_boundary": "Uses app UI actions with process-backed transcript commands, system pasteboard, and NSSavePanel.",
        "starts_recording": False,
        "starts_processing": False,
        "uses_system_pasteboard": True,
        "uses_save_panel": True,
        "opens_system_settings": False,
        "modifies_tcc_or_system_settings": False,
        "may_request_macos_permissions": False,
        "launch_attribution_boundary": (
            "direct launch is executable diagnostic evidence only; the default local user path remains LaunchServices open."
            if launch_mode == "direct"
            else "LaunchServices open is the default local user path."
        ),
        "requires_developer_id_or_notarization": False,
        "not_release_readiness": True,
    }
    report_path.write_text(json.dumps(report, ensure_ascii=False, indent=2) + "\n", encoding="utf-8")


try:
    transcript = validate_processed_input()

    press_with_retry(f"ma.meetings.row.{session_id}", timeout_seconds)
    wait_for_actions_ready(timeout_seconds)
    subprocess.run(["/usr/bin/pbcopy"], input="", text=True, check=False)
    press_with_retry("ma.transcriptAction.copyButton", timeout_seconds)
    pasted = wait_for_pasteboard(transcript, min(timeout_seconds, 60))
    clipboard_excerpt = pasted[:240]

    press_with_retry("ma.transcriptAction.exportButton", timeout_seconds)
    confirm_save_panel()
    wait_for_export(transcript, min(timeout_seconds, 90))

    press_with_retry("ma.transcriptAction.deleteButton", timeout_seconds)
    wait_for_delete_prompt(min(timeout_seconds, 60))
    press_with_retry("ma.transcriptAction.deleteConfirmButton", timeout_seconds)
    found_event_path, delete_event = wait_for_delete(min(timeout_seconds, 60))
    if not actual_export_path.is_file():
        raise SmokeFailure("external_export_missing", "external export was not retained after delete")
    delete_event_path = found_event_path
    if transcript[:40] in delete_event:
        raise SmokeFailure("delete_event_leak", "delete event leaked transcript content")

    write_report(True, transcript_excerpt=transcript)
except SmokeFailure as exc:
    blocker_type = exc.kind
    blocker_detail = exc.detail
    try:
        snapshot(timeout=15)
    except SmokeFailure:
        pass
    write_report(False)
    print(f"local-direct actions smoke failed: {blocker_type}: {blocker_detail}", file=sys.stderr)
    print(f"report: {report_path}", file=sys.stderr)
    sys.exit(1)

print("local-direct actions smoke passed.")
print(f"report: {report_path}")
PY
