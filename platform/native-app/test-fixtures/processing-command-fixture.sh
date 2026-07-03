#!/usr/bin/env sh
set -eu

if [ "$#" -lt 1 ]; then
  printf '%s\n' "missing command" >&2
  exit 2
fi

if [ -z "${MEETING_ASSISTANT_WORKSPACE:-}" ] || [ ! -d "${MEETING_ASSISTANT_WORKSPACE:-}" ]; then
  cat <<JSON
{
  "ok": false,
  "request_id": "native-process-fixture-workspace-missing",
  "command": "$1",
  "code": "invalid_input",
  "message": "Fixture workspace is missing.",
  "details": [],
  "warnings": []
}
JSON
  exit 2
fi

if [ -n "${MA_NATIVE_PROCESSING_FIXTURE_INVOCATIONS:-}" ]; then
  printf '%s\n' "$*" >> "$MA_NATIVE_PROCESSING_FIXTURE_INVOCATIONS"
fi

command="$1"
shift
session_id=""
transcript_id=""

while [ "$#" -gt 0 ]; do
  case "$1" in
    --session-id)
      session_id="${2:-}"
      shift 2
      ;;
    --transcript-id)
      transcript_id="${2:-}"
      shift 2
      ;;
    *)
      shift
      ;;
  esac
done

mode="${MA_NATIVE_PROCESSING_FIXTURE_MODE:-success}"

case "$command" in
  generate_transcript)
    if [ "$mode" = "non-json-stderr" ]; then
      printf '%s\n' "adapter crashed at /Users/jerry/Movies/MeetingAssistant/session with sk-nativefixturevalue and transcript_text customer roadmap" >&2
      exit 5
    fi

    if [ "$mode" = "invalid-json-stdout" ]; then
      printf '%s\n' "not json from /Users/jerry/Movies/MeetingAssistant/session sk-nativefixturevalue"
      exit 5
    fi

    if [ "$mode" = "transcript-failure" ]; then
      cat <<JSON
{
  "ok": false,
  "request_id": "native-process-fixture-transcript-failure",
  "command": "generate_transcript",
  "session_id": "$session_id",
  "code": "processing_failed",
  "message": "Transcript adapter failed from process fixture.",
  "details": {
    "stage": "transcription",
    "exit_code": 5
  },
  "warnings": []
}
JSON
      exit 5
    fi

    cat <<JSON
{
  "ok": true,
  "request_id": "native-process-fixture-transcript",
  "command": "generate_transcript",
  "session_id": "$session_id",
  "transcript_id": "transcript-process-fixture",
  "artifact_id": "artifact-process-transcript",
  "segment_count": 2,
  "warnings": []
}
JSON
    ;;
  generate_speaker_labels)
    if [ "$mode" = "degraded" ]; then
      cat <<JSON
{
  "ok": true,
  "request_id": "native-process-fixture-speakers-degraded",
  "command": "generate_speaker_labels",
  "session_id": "$session_id",
  "transcript_id": "$transcript_id",
  "label_status": "transcript_only",
  "speaker_labels_artifact_id": "artifact-process-speakers",
  "degradation_reason": "speaker labeling runtime unavailable",
  "warnings": []
}
JSON
      exit 0
    fi

    cat <<JSON
{
  "ok": true,
  "request_id": "native-process-fixture-speakers",
  "command": "generate_speaker_labels",
  "session_id": "$session_id",
  "transcript_id": "$transcript_id",
  "label_status": "labeled",
  "speaker_labels_artifact_id": "artifact-process-speakers",
  "warnings": []
}
JSON
    ;;
  *)
    printf '%s\n' "unsupported command: $command" >&2
    exit 2
    ;;
esac
