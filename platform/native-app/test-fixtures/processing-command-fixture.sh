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

checksum_file() {
  shasum -a 256 "$1" | awk '{print $1}'
}

workspace_session_root() {
  printf '%s/sessions/%s' "$MEETING_ASSISTANT_WORKSPACE" "$session_id"
}

write_workspace_session() {
  session_root="$(workspace_session_root)"
  artifacts_dir="$session_root/artifacts"
  transcript_file="$artifacts_dir/transcript.json"
  speaker_file="$artifacts_dir/speaker_labels.json"
  transcript_checksum="$(checksum_file "$transcript_file")"

  if [ -f "$speaker_file" ]; then
    speaker_checksum="$(checksum_file "$speaker_file")"
    speaker_artifact_status="${1:-available}"
    speaker_degradation="${2:-}"
    if [ "$speaker_artifact_status" = "degraded" ]; then
      cat > "$session_root/session.json" <<JSON
{
  "id": "$session_id",
  "title": "Native process bridge workspace fixture",
  "source_type": "native_recording",
  "status": "transcribed",
  "started_at": "2026-07-03T00:00:00Z",
  "workspace_dir": "$session_root",
  "created_at": "2026-07-03T00:00:00Z",
  "updated_at": "2026-07-03T00:00:00Z",
  "artifacts": [
    {
      "id": "artifact-process-transcript",
      "session_id": "$session_id",
      "artifact_type": "transcript_text",
      "path": "artifacts/transcript.json",
      "format": "json",
      "capture_status": "available",
      "checksum": "sha256:$transcript_checksum",
      "created_at": "2026-07-03T00:00:00Z"
    },
    {
      "id": "artifact-process-speakers",
      "session_id": "$session_id",
      "artifact_type": "speaker_labels",
      "path": "artifacts/speaker_labels.json",
      "format": "json",
      "capture_status": "degraded",
      "degradation_reason": "$speaker_degradation",
      "checksum": "sha256:$speaker_checksum",
      "created_at": "2026-07-03T00:00:00Z"
    }
  ]
}
JSON
      return
    fi

    cat > "$session_root/session.json" <<JSON
{
  "id": "$session_id",
  "title": "Native process bridge workspace fixture",
  "source_type": "native_recording",
  "status": "transcribed",
  "started_at": "2026-07-03T00:00:00Z",
  "workspace_dir": "$session_root",
  "created_at": "2026-07-03T00:00:00Z",
  "updated_at": "2026-07-03T00:00:00Z",
  "artifacts": [
    {
      "id": "artifact-process-transcript",
      "session_id": "$session_id",
      "artifact_type": "transcript_text",
      "path": "artifacts/transcript.json",
      "format": "json",
      "capture_status": "available",
      "checksum": "sha256:$transcript_checksum",
      "created_at": "2026-07-03T00:00:00Z"
    },
    {
      "id": "artifact-process-speakers",
      "session_id": "$session_id",
      "artifact_type": "speaker_labels",
      "path": "artifacts/speaker_labels.json",
      "format": "json",
      "capture_status": "available",
      "checksum": "sha256:$speaker_checksum",
      "created_at": "2026-07-03T00:00:00Z"
    }
  ]
}
JSON
    return
  fi

  cat > "$session_root/session.json" <<JSON
{
  "id": "$session_id",
  "title": "Native process bridge workspace fixture",
  "source_type": "native_recording",
  "status": "processing",
  "started_at": "2026-07-03T00:00:00Z",
  "workspace_dir": "$session_root",
  "created_at": "2026-07-03T00:00:00Z",
  "updated_at": "2026-07-03T00:00:00Z",
  "artifacts": [
    {
      "id": "artifact-process-transcript",
      "session_id": "$session_id",
      "artifact_type": "transcript_text",
      "path": "artifacts/transcript.json",
      "format": "json",
      "capture_status": "available",
      "checksum": "sha256:$transcript_checksum",
      "created_at": "2026-07-03T00:00:00Z"
    }
  ]
}
JSON
}

write_workspace_transcript() {
  session_root="$(workspace_session_root)"
  artifacts_dir="$session_root/artifacts"
  mkdir -p "$artifacts_dir"
  cat > "$artifacts_dir/transcript.json" <<JSON
{
  "id": "transcript-process-fixture",
  "session_id": "$session_id",
  "source_artifact_id": "artifact-normalized-process",
  "status": "succeeded",
  "segments": [
    {
      "segment_id": "seg-process-1",
      "start_ms": 1000,
      "end_ms": 3000,
      "text": "Native process bridge wrote transcript artifact."
    }
  ],
  "created_at": "2026-07-03T00:00:00Z"
}
JSON
  write_workspace_session
}

write_workspace_speaker_labels() {
  speaker_artifact_status="$1"
  degradation_reason="${2:-}"
  session_root="$(workspace_session_root)"
  artifacts_dir="$session_root/artifacts"
  mkdir -p "$artifacts_dir"

  if [ "$speaker_artifact_status" = "degraded" ]; then
    cat > "$artifacts_dir/speaker_labels.json" <<JSON
{
  "session_id": "$session_id",
  "labels": [],
  "segment_mapping": [],
  "created_at": "2026-07-03T00:00:00Z"
}
JSON
    write_workspace_session "degraded" "$degradation_reason"
    return
  fi

  cat > "$artifacts_dir/speaker_labels.json" <<JSON
{
  "session_id": "$session_id",
  "labels": [
    {
      "label": "SPEAKER_01",
      "session_id": "$session_id",
      "is_verified_identity": false
    }
  ],
  "segment_mapping": [
    {
      "segment_id": "seg-process-1",
      "label": "SPEAKER_01"
    }
  ],
  "created_at": "2026-07-03T00:00:00Z"
}
JSON
  write_workspace_session "available"
}

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

    if [ "$mode" = "workspace-success" ] || [ "$mode" = "workspace-degraded" ]; then
      write_workspace_transcript
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
    if [ "$mode" = "degraded" ] || [ "$mode" = "workspace-degraded" ]; then
      if [ "$mode" = "workspace-degraded" ]; then
        write_workspace_speaker_labels "degraded" "speaker labeling runtime unavailable"
      fi
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

    if [ "$mode" = "workspace-success" ]; then
      write_workspace_speaker_labels "available"
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
