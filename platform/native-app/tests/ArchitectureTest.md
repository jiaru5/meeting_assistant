# Native App Architecture Test

Component: `native-app`

VS-MA-12 boundary:

1. This component may implement the permission/dependency status surface for VS-MA-12.
2. It consumes the `check_dependencies` command contract through stable JSON only.
3. It may expose SwiftUI status labels and accessibility identifiers for permissions and dependencies.

VS-MA-13 fake recording boundary:

1. This component may express `start_native_recording` and `stop_recording` through a Swift protocol, deterministic fake client, view model state machine and SwiftUI control.
2. The fake recording boundary exists only for UI/state verification and must not call a real helper, CLI, capture API or processing internals.
3. It may expose stable recording accessibility identifiers for status, start, stop, error and saved-summary regions.
4. It must not implement real capture, ScreenCaptureKit, AVCapture, audio capture, transcription, speaker labeling, external model calls, public normalize audio commands or dependency downloads.

VS-MA-16 native processing state consumer boundary:

1. This component may express `generate_transcript` and `generate_speaker_labels` through Swift command request/response models, a production `Process` runner, deterministic fake client, processing state view model and SwiftUI status view.
2. The production runner may call only public command names and frozen flags from `06-api-contracts.md`, and must parse stdout JSON as the only product contract source.
3. The native processing consumer may validate frozen response fields and display idle, blocked, generating transcript, generating speaker labels, completed, degraded and failed states.
4. It may expose stable `ma.processing.*` accessibility identifiers for heading, status, start, retry, transcript status, speaker-label status, success, error, degradation and warnings.
5. It must not read `processing-cli` provider internals, add command fields, add `--format`, mutate artifacts directly, implement real capture, call external GPT/Qwen/API, automatically download dependencies, use real pasteboard, show a real file picker or delete files directly.

VS-MA-17 read-only transcript review boundary:

1. This component may implement a read-only transcript review consumer for deterministic UI/state verification.
2. It may consume only frozen `transcript.json` fields `id`, `session_id`, `source_artifact_id`, `status`, `segments`, `segment_id`, `start_ms`, `end_ms`, `text` and optional `speaker_label`.
3. It may consume only frozen `speaker_labels.json` fields `session_id`, `labels` and `segment_mapping`.
4. Transcript-only speaker label degradation reason may appear only as fixture/read-model input state, not as a new artifact schema.
5. It may expose stable `ma.transcript.*` accessibility identifiers for heading, summary, segment row, timestamp, text, anonymous speaker label, degradation, empty and missing states.
6. The read-only workspace transcript loading boundary may read `sessions/<session_id>/session.json`, find `transcript_text` and optional `speaker_labels` artifacts, validate artifact path/checksum safety, and project them into `TranscriptReviewInput`.
7. It must not implement transcription generation, speaker generation, processing commands, real capture, external providers, network calls, downloads or helper runtime invocation.

VS-MA-18/VS-MA-19 deterministic transcript action consumer boundary:

1. This component may express copy/export/delete through Swift protocols, command request/response models, deterministic fake command client, injected clipboard writer, injected export destination selector, view model state and SwiftUI action controls.
2. Copy may use the frozen `export_transcript` contract with `session_id`, `export_type=plain_text` and no `target_path`, and may update only an injected clipboard after a successful response with `content`.
3. Export may use the frozen `export_transcript` contract with `session_id`, `export_type=markdown` and an injected deterministic `target_path`; cancel or no destination must not call the command.
4. Delete may use the frozen `delete_session` contract with `session_id`, optional `workspace_dir` and `confirm=true`; cancel must not call the command.
5. It may expose stable `ma.transcriptAction.*` accessibility identifiers for copy/export/delete buttons, status, success, failure, delete prompt, confirm and cancel.
6. It must not call processing-cli/provider internals, real helpers, network APIs, external GPT/Qwen/API, the real pasteboard, real file pickers or delete files directly.
