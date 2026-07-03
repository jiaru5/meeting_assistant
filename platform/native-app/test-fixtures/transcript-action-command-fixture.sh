#!/usr/bin/env sh
set -eu

if [ "$#" -lt 1 ]; then
  printf '%s\n' "missing command" >&2
  exit 2
fi

command="$1"
shift

if [ -n "${MA_NATIVE_TRANSCRIPT_ACTION_FIXTURE_INVOCATIONS:-}" ]; then
  printf '%s\n' "$command $*" >> "$MA_NATIVE_TRANSCRIPT_ACTION_FIXTURE_INVOCATIONS"
fi

if [ "${MA_NATIVE_TRANSCRIPT_ACTION_FIXTURE_MODE:-success}" = "non-json-stderr" ]; then
  printf '%s\n' "action adapter crashed at /Users/jerry/Movies/MeetingAssistant/session with sk-nativefixturevalue and customer roadmap" >&2
  exit 5
fi

session_id=""
export_type=""
target_path=""
workspace_dir="${MEETING_ASSISTANT_WORKSPACE:-}"
confirm=""

while [ "$#" -gt 0 ]; do
  case "$1" in
    --session-id)
      session_id="${2:-}"
      shift 2
      ;;
    --export-type)
      export_type="${2:-}"
      shift 2
      ;;
    --target-path)
      target_path="${2:-}"
      shift 2
      ;;
    --workspace-dir)
      workspace_dir="${2:-}"
      shift 2
      ;;
    --confirm)
      confirm="${2:-}"
      shift 2
      ;;
    *)
      shift
      ;;
  esac
done

json_failure() {
  failure_command="$1"
  failure_code="$2"
  failure_message="$3"
  failure_exit_code="$4"
  cat <<JSON
{
  "ok": false,
  "request_id": "native-action-fixture-failure",
  "command": "$failure_command",
  "session_id": "$session_id",
  "code": "$failure_code",
  "message": "$failure_message",
  "details": [],
  "warnings": []
}
JSON
  exit "$failure_exit_code"
}

if [ -z "$session_id" ]; then
  json_failure "$command" "invalid_input" "Fixture session id is missing." 2
fi

case "$session_id" in
  */*|*..*) json_failure "$command" "path_conflict" "Fixture session id escaped the workspace." 3 ;;
esac

if [ -z "$workspace_dir" ] || [ ! -d "$workspace_dir" ]; then
  json_failure "$command" "invalid_input" "Fixture workspace is missing." 2
fi

session_root="$workspace_dir/sessions/$session_id"
retained_export_path="${MA_NATIVE_TRANSCRIPT_ACTION_RETAINED_EXPORT:-$workspace_dir/exports/$session_id.md}"

case "$command" in
  export_transcript)
    if [ ! -f "$session_root/artifacts/transcript.json" ]; then
      json_failure "export_transcript" "artifact_missing" "Transcript artifact is missing." 3
    fi

    case "$export_type" in
      plain_text)
        cat <<JSON
{
  "ok": true,
  "request_id": "native-action-fixture-copy",
  "command": "export_transcript",
  "session_id": "$session_id",
  "export_type": "plain_text",
  "export_package_id": "export-package-action-fixture",
  "content": "Native action process fixture transcript content.",
  "warnings": []
}
JSON
        ;;
      markdown)
        if [ -z "$target_path" ]; then
          json_failure "export_transcript" "invalid_input" "Fixture export target is missing." 2
        fi
        mkdir -p "$(dirname "$target_path")"
        cat > "$target_path" <<MD
# Native action process fixture

Native action process fixture transcript content.
MD
        cat <<JSON
{
  "ok": true,
  "request_id": "native-action-fixture-export",
  "command": "export_transcript",
  "session_id": "$session_id",
  "export_type": "markdown",
  "export_package_id": "export-package-action-fixture",
  "target_path": "$target_path",
  "warnings": []
}
JSON
        ;;
      *)
        json_failure "export_transcript" "invalid_input" "Fixture export type is unsupported." 2
        ;;
    esac
    ;;
  delete_session)
    if [ "$confirm" != "true" ]; then
      json_failure "delete_session" "invalid_input" "Delete confirmation is required." 2
    fi
    case "$session_root" in
      "$workspace_dir"/sessions/"$session_id") ;;
      *) json_failure "delete_session" "path_conflict" "Session path escaped the workspace." 3 ;;
    esac
    if [ ! -d "$session_root" ]; then
      json_failure "delete_session" "not_found" "Session was not found." 3
    fi
    rm -rf "$session_root"
    cat <<JSON
{
  "ok": true,
  "request_id": "native-action-fixture-delete",
  "command": "delete_session",
  "session_id": "$session_id",
  "deleted": true,
  "deleted_items": [
    "artifacts/transcript.json",
    "artifacts/speaker_labels.json",
    "session.json"
  ],
  "retained_external_exports": [
    "$retained_export_path"
  ],
  "warnings": []
}
JSON
    ;;
  *)
    json_failure "$command" "invalid_input" "Fixture command is unsupported." 2
    ;;
esac
