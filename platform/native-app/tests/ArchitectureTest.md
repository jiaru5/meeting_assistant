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
4. It must not implement uncontrolled real capture, non-approved capture framework files, AVCapture, audio capture frameworks outside the named Apple adapter exception, transcription, speaker labeling, external model calls, public normalize audio commands or dependency downloads.

VS-MA-14/VS-MA-15 controlled native capture artifact registration boundary:

1. This component may implement a controlled native capture adapter and `RecordingCommandClient` implementation for deterministic native capture artifact registration.
2. The controlled adapter may only use frozen `start_native_recording` and `stop_recording` semantics and must not add command fields, artifact types, event schema, error codes, exit codes or UI states.
3. `NativeCapturePermissionChecker` must fail closed when screen recording or requested microphone permission is denied or unknown, using the existing `permission_denied` error code.
4. `RecordingSessionStore` may create `sessions/<session_id>/session.json`, write managed artifact files under `artifacts/`, compute `sha256:` checksums and validate path traversal, symlink and hardlink boundaries.
5. Stop artifact registration must register `screen_video`, `system_audio`, `microphone_audio` and `mixed_audio` as `available`, `degraded`, `missing` or `failed`; unavailable artifacts must include `degradation_reason`.
6. At least one available media artifact may return `ok=true status=recorded`; no available media must return `ok=false code=capture_failed` and persist session `status=failed`.
7. Repeated stop must return the existing final artifact registry without duplicating entries or re-running the adapter.
8. It may expose additive recording artifact locators under `ma.recording.artifact.<artifact_type>.status` and `.degradation`, while preserving existing `ma.recording.*` locators and phase/status strings.
9. The app bundle must default to `FakeRecordingCommandClient`; only the Debug/XCTest-only test hook `MA_NATIVE_RECORDING_CLIENT=controlled` may inject `NativeRecordingCommandClient` with `MA_NATIVE_RECORDING_WORKSPACE` or `MEETING_ASSISTANT_WORKSPACE`; Release builds must ignore this env hook and fall back to fake.
10. It must not invoke processing providers, native-to-processing commands, Apple capture frameworks outside `AppleScreenCaptureKitNativeCaptureAdapter.swift`, CoreAudio, OBS, BlackHole, FFmpeg auxiliary capture, external model APIs, network APIs, downloads, real pasteboard, real file pickers or direct delete behavior.

Apple ScreenCaptureKit native capture adapter exception:

1. `AppleScreenCaptureKitNativeCaptureAdapter.swift` is the only native-app Swift file allowed to import `ScreenCaptureKit` and `AVFoundation`, use `SCStream`, `SCContentFilter`, `SCShareableContent`, `SCRecordingOutput` or configure Apple recording output.
2. The adapter is a VS-MA-14/15 spike implementation of the existing `NativeCaptureAdapter`; it must not add command fields, error codes, exit codes, artifact types, event schema or UI states.
3. The adapter may use a temporary ScreenCaptureKit recording file only as adapter-local input data. `RecordingSessionStore` remains the only component responsible for final `session.json`, managed artifact paths, `sha256:` checksums, symlink/hardlink/path fail-closed checks and command response materialization.
4. Because `SCRecordingOutput` produces one combined recording file, the adapter must register the combined file as existing `screen_video` data and express unproven `system_audio`, `microphone_audio` and `mixed_audio` as existing artifact results with `degraded`, `missing` or `failed` plus `degradation_reason`.
5. If no available combined media file exists at stop, the adapter must fail closed through existing `capture_failed` semantics; it must not invent a successful empty recording.
6. The adapter may expose only code-level identity and capability summary such as `apple_screencapturekit`, supported screen target, combined-file support and no separate audio artifacts; this is not a command/schema/UI contract.
7. The adapter must not call OBS, BlackHole, FFmpeg auxiliary capture, helper tools, `processing-cli`, processing commands, external APIs, network APIs, automatic downloads, real pasteboard, real file pickers or direct delete behavior.
8. The app bundle must not enable this real adapter from a Release env hook. Existing Debug/XCTest-only hooks remain limited to `MA_NATIVE_RECORDING_CLIENT=controlled` and `MA_NATIVE_PROCESSING_CLIENT=process`.

VS-MA-16 native processing state consumer boundary:

1. This component may express `generate_transcript` and `generate_speaker_labels` through Swift command request/response models, a production `Process` runner, deterministic fake client, processing state view model and SwiftUI status view.
2. The production runner may call only public command names and frozen flags from `06-api-contracts.md`, and must parse stdout JSON as the only product contract source.
3. The native processing consumer may validate frozen response fields and display idle, blocked, generating transcript, generating speaker labels, completed, degraded and failed states.
4. It may expose stable `ma.processing.*` accessibility identifiers for heading, status, start, retry, transcript status, speaker-label status, success, error, degradation and warnings.
5. The app bundle must default to `ProcessingCommandFakeClient`; only the Debug/XCTest-only test hook `MA_NATIVE_PROCESSING_CLIENT=process` may inject `ProcessingCommandProcessRunner` with `MEETING_ASSISTANT_CLI_PATH` and `MEETING_ASSISTANT_WORKSPACE`; Release builds must ignore this env hook and fall back to fake.
6. The app-bundle process-runner smoke may use only the native-owned `test-fixtures/processing-command-fixture.sh`, which emits frozen CMD-MA-005/006 stdout JSON for controlled success, transcript-only degradation and structured failure cases.
7. It must not read `processing-cli` provider internals, add command fields, add `--format`, mutate artifacts directly, implement real capture, call external GPT/Qwen/API, automatically download dependencies, use real pasteboard, show a real file picker or delete files directly.

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
