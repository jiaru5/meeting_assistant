# Native App Architecture Test

Component: `native-app`

VS-MA-12 boundary:

1. This component may implement the permission/dependency status surface for VS-MA-12.
2. It consumes the `check_dependencies` command contract through stable JSON only.
3. It may expose SwiftUI status labels and accessibility identifiers for permissions and dependencies.
4. It may expose an injected `Open Privacy Settings` action that opens the macOS Privacy & Security Screen Recording pane through `NSWorkspace.shared.open` from `PermissionDependencyStatusView.swift` only.
5. The privacy settings action must not grant permissions, edit TCC, call `tccutil`, mutate authorization databases, run shell/system commands, use AppleScript or change system settings without the user acting in System Settings.

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
9. Non-XCTest app runtime must default to `NativeRecordingCommandClient` with `MacOSNativeCapturePermissionChecker` and `AppleScreenCaptureKitNativeCaptureAdapter`; Debug/XCTest may default to `FakeRecordingCommandClient`, and only Debug/XCTest-only test hooks may inject controlled recording with `MA_NATIVE_RECORDING_CLIENT=controlled` plus `MA_NATIVE_RECORDING_WORKSPACE` or `MEETING_ASSISTANT_WORKSPACE`. A Debug/XCTest `MA_NATIVE_RECORDING_CLIENT=fake` or controlled hook must not downgrade non-XCTest runtime to fake.
10. It must not invoke processing providers, native-to-processing commands, Apple capture frameworks outside `AppleScreenCaptureKitNativeCaptureAdapter.swift` and microphone authorization checks in `NativeCapturePermissionChecker.swift`, CoreAudio, OBS, BlackHole, FFmpeg auxiliary capture, external model APIs, network APIs, downloads, real pasteboard, real file pickers or direct delete behavior.

Apple ScreenCaptureKit native capture adapter exception:

1. `AppleScreenCaptureKitNativeCaptureAdapter.swift` is the only native-app Swift file allowed to import `ScreenCaptureKit`, use `SCStream`, `SCContentFilter`, `SCShareableContent`, `SCRecordingOutput`, `SCStreamOutput`, `AVAssetWriter` or configure Apple recording output. `NativeCapturePermissionChecker.swift` may import `AVFoundation` only to query/request microphone authorization through `AVCaptureDevice`.
2. The adapter is a VS-MA-14/15 spike implementation of the existing `NativeCaptureAdapter`; it must not add command fields, error codes, exit codes, artifact types, event schema or UI states.
3. The adapter may use a temporary ScreenCaptureKit recording file only as adapter-local input data. `RecordingSessionStore` remains the only component responsible for final `session.json`, managed artifact paths, `sha256:` checksums, symlink/hardlink/path fail-closed checks and command response materialization.
4. Because `SCRecordingOutput` produces one combined recording file, the adapter must register the combined file as existing `screen_video` data. Requested `system_audio` and `microphone_audio` may be materialized only from ScreenCaptureKit `.audio` / `.microphone` sample outputs into adapter-local `.m4a` files; unavailable or failed independent audio outputs must stay degraded/missing/failed with `degradation_reason`. When requested audio exists and AVFoundation can export an audio track from the combined file, the adapter may materialize the existing `mixed_audio` artifact as `available`; failed extraction must stay degraded/missing/failed with `degradation_reason`.
5. If no available combined media file exists at stop, the adapter must fail closed through existing `capture_failed` semantics; it must not invent a successful empty recording.
6. The adapter may expose only code-level identity and capability summary such as `apple_screencapturekit`, supported screen target, combined-file support, independent audio artifact support and mixed-audio extraction attempt support; this is not a command/schema/UI contract.
7. The adapter must not call OBS, BlackHole, FFmpeg auxiliary capture, helper tools, `processing-cli`, processing commands, external APIs, network APIs, automatic downloads, real pasteboard, real file pickers or direct delete behavior.
8. Non-XCTest app runtime may use this adapter as the default recording client. The Debug/XCTest app-bundle real adapter path remains the explicitly opt-in combination `MA_NATIVE_RECORDING_CLIENT=apple_screencapturekit`, `MA_NATIVE_CAPTURE_SMOKE=1`, `MA_NATIVE_APP_REAL_CAPTURE_SMOKE=1` and a writable recording workspace; otherwise XCTest fixtures must fall back to fake.

opt-in real native capture smoke boundary:

1. `scripts/native-capture-smoke.sh` may run real ScreenCaptureKit capture only when invoked explicitly with `MA_NATIVE_CAPTURE_SMOKE=1`; default `scripts/test.sh`, app-bundle tests and Release app execution must not run it implicitly.
2. The smoke may build a temporary Swift executable that composes only `NativeRecordingCommandClient`, `MacOSNativeCapturePermissionChecker`, `CoreGraphicsScreenRecordingPermissionProbe`, `AVFoundationMicrophonePermissionProbe`, `AppleScreenCaptureKitNativeCaptureAdapter` and `RecordingSessionStore`; the screen recording probe may request Screen Recording access before preserving fail-closed denial, and the microphone probe may request Microphone access only when microphone capture is requested.
3. The smoke may write to `build/native-capture-smoke/` or an explicit `MA_NATIVE_CAPTURE_SMOKE_WORKSPACE`, start a bounded screen recording, stop it, and validate existing `session.json`, `screen_video`, artifact status and `sha256:` checksum fields.
4. The smoke must not add or change command fields, error codes, exit codes, artifact types, event schema, UI states or app-bundle env hooks.
5. Permission denied, unknown permission, missing macOS runtime or missing ScreenCaptureKit output must remain fail-closed evidence and must not be reported as `covered` release readiness.
6. The smoke must not call OBS, BlackHole, FFmpeg auxiliary capture, helper tools, `processing-cli`, processing commands, external APIs, network APIs, automatic downloads, real pasteboard, real file pickers or direct delete behavior.

opt-in real native capture app-bundle smoke boundary:

1. `AppBundleLocatorSmokeTests` may drive the designed native shell Start/Stop buttons against `AppleScreenCaptureKitNativeCaptureAdapter` only when the test process is explicitly launched with `MA_NATIVE_APP_REAL_CAPTURE_SMOKE=1`.
2. The app-bundle smoke may select `MA_NATIVE_RECORDING_CLIENT=apple_screencapturekit` only in Debug/XCTest and only when `MA_NATIVE_CAPTURE_SMOKE=1` plus `MA_NATIVE_RECORDING_WORKSPACE` or `MEETING_ASSISTANT_WORKSPACE` are present; default XCTest fixtures must fall back to `FakeRecordingCommandClient`, while non-XCTest app runtime defaults to the Apple adapter through the production recording client path.
3. The app-bundle smoke must default to screen-only by setting `MA_NATIVE_CAPTURE_SMOKE_SYSTEM_AUDIO=false` and `MA_NATIVE_CAPTURE_SMOKE_MICROPHONE_AUDIO=false`; it may validate only existing `session.json`, `screen_video`, artifact status and `sha256:` checksum fields.
4. The app-bundle smoke must not add command fields, error codes, exit codes, artifact types, event schema, UI states, processing invocation, real pasteboard, real file picker, direct delete, network APIs or automatic downloads.
5. A passing app-bundle real capture smoke remains `partial` evidence and must not be reported as Release readiness, cross-machine TCC/display proof or independent audio proof. Production default Apple adapter selection must be guarded separately by app-root source-contract and architecture checks.
6. When the opt-in smoke fails with `permission_denied`, the runner may print TCC Screen Recording / Screen & System Audio Recording remediation details, but it must preserve the failing exit status and must not convert the run into a skip or pass.

VS-MA-21 opt-in real capture same-chain app-bundle smoke boundary:

1. `AppBundleLocatorSmokeTests` may drive a single launched app-bundle smoke with real ScreenCaptureKit recording, provider-owned processing CLI, transcript review and transcript actions only when the test process is explicitly launched with `MA_NATIVE_APP_REAL_CAPTURE_SAME_CHAIN_SMOKE=1`.
2. This smoke may request system audio through the existing `capture_system_audio` command field so the Apple adapter can materialize an existing `mixed_audio` artifact from the combined recording; it currently keeps microphone audio disabled to avoid expanding same-chain evidence beyond `mixed_audio` extraction.
3. The smoke must use the same workspace/session for Start/Stop, processing, transcript review, copy/export and delete. It must fail if the real capture run does not produce `mixed_audio` as `available`; it must not copy fixture audio into the real capture session.
4. The launched app must still call provider-owned `platform/e2e/ma-cli-local.sh` through `ProcessingCommandProcessRunner` and `TranscriptActionProcessRunner`; the UI test must not call provider commands directly to create transcript, export or delete results.
5. A passing same-chain smoke remains explicit opt-in evidence. It does not prove independent `system_audio`/`microphone_audio` artifacts, all target-machine TCC/display repeatability, true user Save Panel interaction, release distribution bundle, or product-validation release readiness.

VS-MA-16 native processing state consumer boundary:

1. This component may express `generate_transcript` and `generate_speaker_labels` through Swift command request/response models, a production `Process` runner, deterministic fake client, processing state view model and SwiftUI status view.
2. The production runner may call only public command names and frozen flags from `06-api-contracts.md`, and must parse stdout JSON as the only product contract source.
3. The native processing consumer may validate frozen response fields and display idle, blocked, generating transcript, generating speaker labels, completed, degraded and failed states.
4. It may expose stable `ma.processing.*` accessibility identifiers for heading, status, start, retry, transcript status, speaker-label status, success, error, degradation and warnings.
5. Non-XCTest app runtime must default to `ProcessingCommandProcessRunner`; Debug/XCTest may default to `ProcessingCommandFakeClient`, and the `MA_NATIVE_PROCESSING_CLIENT=process` test hook may inject `ProcessingCommandProcessRunner` with `MEETING_ASSISTANT_CLI_PATH` and `MEETING_ASSISTANT_WORKSPACE` for app-bundle smoke evidence. A Debug/XCTest `MA_NATIVE_PROCESSING_CLIENT=fake` hook must not downgrade non-XCTest runtime to fake.
6. The app-bundle process-runner smoke may use the native-owned `test-fixtures/processing-command-fixture.sh` for controlled success, transcript-only degradation and structured failure cases. A separate explicit real-processing smoke may point `MEETING_ASSISTANT_CLI_PATH` at the provider-owned `platform/e2e/ma-cli-local.sh` wrapper; it must not replace provider behavior with native-owned JSON fixtures.
7. It must not read `processing-cli` provider internals, add command fields, add `--format`, mutate artifacts directly, implement real capture, call external GPT/Qwen/API, automatically download dependencies, use real pasteboard, show a real file picker or delete files directly.

VS-MA-21 opt-in native hardening bridge smoke boundary:

1. `MA_NATIVE_VSMA21_HARDENING_BRIDGE_SMOKE=1` may run a Swift Testing-only bridge smoke against the native-owned `test-fixtures/processing-command-fixture.sh` in `path-conflict-then-success` mode.
2. The smoke may verify `ProcessingStateViewModel` retry behavior, `ProcessingCommandProcessRunner` stdout JSON consumption, `path_conflict` display, generated transcript/speaker-label artifact registration and original `mixed_audio` checksum preservation.
3. This smoke is not app-bundle UI evidence, not real ScreenCaptureKit concurrency evidence, not a release bundle proof and not release readiness. The app-bundle XCUITest remains the evidence path for launched `.app` UI behavior when macOS Automation Mode is available.

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
6. `TranscriptActionProcessRunner` is the only action file allowed to use `Process`/`Pipe`; it may call only public frozen `export_transcript` and `delete_session` flags, must not add `--format`, and must parse stdout JSON as the only product contract source.
7. `TranscriptActionOSClients.swift` is the only action file allowed to use AppKit OS effects; it may implement only `TranscriptClipboardWriting` through `NSPasteboard` and `TranscriptExportDestinationSelecting` through `NSSavePanel`, and must not call command processes, network APIs, provider internals, `NSOpenPanel` or direct delete/file mutation APIs.
8. The view model may construct neither real clipboard nor save-panel implementations; the app root injects system action OS clients only outside XCTest, while XCTest keeps deterministic memory clipboard and static destination selector.
9. Non-XCTest app runtime must default to `TranscriptActionProcessRunner`; Debug/XCTest may default to `TranscriptActionFakeCommandClient`, and the `MA_NATIVE_TRANSCRIPT_ACTION_CLIENT=process` test hook may inject `TranscriptActionProcessRunner` with `MEETING_ASSISTANT_CLI_PATH` and `MEETING_ASSISTANT_WORKSPACE` for app-bundle smoke evidence. A Debug/XCTest `MA_NATIVE_TRANSCRIPT_ACTION_CLIENT=fake` hook must not downgrade non-XCTest runtime to fake.
10. The app-bundle process-runner smoke may use only the native-owned `test-fixtures/transcript-action-command-fixture.sh`, which emits frozen action stdout JSON for controlled copy/export/delete success and safe bridge failure cases.
11. It must not call processing-cli/provider internals, real helpers, network APIs, external GPT/Qwen/API, or delete files directly.

VS-MA-19A designed native shell boundary:

1. This component may implement a designed native shell around the existing permission/dependency, recording, artifact, processing, transcript review and transcript action surfaces.
2. `DesignedNativeShellViewModel` may project navigation state, status summaries, required artifact rows and processing step labels from existing view model states; it must not add command fields, artifact types, event schema, error codes, exit codes or business states.
3. `DesignedNativeShellView` may expose stable `ma.shell.*` and `ma.sessionArtifact.*` accessibility identifiers, a navigation model and visual state hierarchy while preserving existing `ma.permissionDependency.*`, `ma.recording.*`, `ma.processing.*`, `ma.transcript.*` and `ma.transcriptAction.*` locators.
4. The shell must keep primary controls wired to the existing command/helper/adapter clients: `check_dependencies`, `start_native_recording`, `stop_recording`, processing command bridge, `export_transcript` and `delete_session`; it must not create UI-only mock success.
5. Debug/XCTest fixtures and fake hooks remain isolated behind existing `MA_NATIVE_*` test hooks. Non-XCTest defaults must use the approved production command clients for recording, processing and transcript actions unless later product/spec changes approve otherwise. Production copy/export OS clients may be injected through `TranscriptActionOSClients.swift`.
6. The shell must not implement uncontrolled capture, processing provider internals, transcription, speaker labeling, network APIs, automatic downloads or direct delete behavior.

VS-MA-20 opt-in native app-bundle MVP full-stack smoke boundary:

1. `AppBundleLocatorSmokeTests` may run a single app-bundle smoke only when the test process is explicitly launched with `MA_NATIVE_APP_MVP_FULL_STACK_SMOKE=1`.
2. The smoke may compose existing Debug/XCTest-only hooks for controlled native recording, provider-owned processing/action CLI routing through `platform/e2e/ma-cli-local.sh`, deterministic clipboard/export destination and read-only workspace transcript loading.
3. The controlled recording hook may set `MA_NATIVE_RECORDING_CONTROLLED_MIXED_AUDIO=1` only for this test path so the same recorded session has an existing `mixed_audio` artifact that the frozen processing command contract can consume.
4. The smoke must drive the designed shell Start/Stop recording, Start Processing, transcript review, copy/export and delete confirmation controls through stable accessibility identifiers; it must not mutate session metadata by hand to fake a processed state.
5. The smoke must remain opt-in from `platform/e2e/full-stack-smoke.sh` through `MA_NATIVE_APP_MVP_FULL_STACK_SMOKE=1`; default full-stack and component test gates must not require macOS UI automation.
6. A passing smoke remains partial evidence unless the relevant `PV-MA-*` rows explicitly become `covered`; it does not prove real ScreenCaptureKit output, true user Save Panel interaction, release distribution bundle, or product-validation release readiness.

VS-MA-22 opt-in real runtime app-bundle smoke boundary:

1. `AppBundleLocatorSmokeTests` may run a single app-bundle smoke with the real `whisper.cpp` runtime only when the test process is explicitly launched with `MA_NATIVE_APP_REAL_RUNTIME_SMOKE=1`.
2. The smoke may set `MA_NATIVE_PROCESSING_RUNTIME=whisper_cpp` and `MA_NATIVE_PROCESSING_LANGUAGE=zh` in Debug/XCTest for a native-recording workspace fixture whose `mixed_audio` is copied from `MEETING_ASSISTANT_WHISPER_SMOKE_AUDIO`.
3. The launched app must still call provider-owned `platform/e2e/ma-cli-local.sh` through `ProcessingCommandProcessRunner`; the UI test must not call `meeting_assistant_cli` directly to create the transcript.
4. Production/default app runtime may pass an explicitly configured `MA_NATIVE_PROCESSING_RUNTIME` / `MA_NATIVE_PROCESSING_LANGUAGE` to the provider command runner for local direct use, but it must not enable XCTest-only fixture hooks and must not download, copy or package models or audio fixtures.
5. A passing real runtime app-bundle smoke remains partial evidence for native-to-provider runtime integration; it does not prove real ScreenCaptureKit output, true user Save Panel interaction, release distribution bundle, all developer machines, or product-validation release readiness.

VS-MA-23 opt-in local functional real capture + real runtime app-bundle smoke boundary:

1. `AppBundleLocatorSmokeTests` may run the combined local functional smoke only when the test process is explicitly launched with `MA_NATIVE_APP_REAL_CAPTURE_REAL_RUNTIME_SAME_CHAIN_SMOKE=1`.
2. The smoke may play the configured mixed-language WAV through `/usr/bin/afplay` while the launched app records with ScreenCaptureKit system audio enabled; it must not copy fixture audio into the real capture session or mutate `session.json` directly.
3. The launched app must use the same workspace/session for real Start/Stop, `mixed_audio` registration, provider-owned `platform/e2e/ma-cli-local.sh` processing with `whisper_cpp`, transcript review, copy/export and delete.
4. The smoke must require host-provided `MEETING_ASSISTANT_TRANSCRIPTION_RUNTIME`, `MEETING_ASSISTANT_TRANSCRIPTION_MODEL`, `MEETING_ASSISTANT_WHISPER_SMOKE_AUDIO` and a usable local audio output path; it must not package or auto-download runtime/model/audio assets.
5. A passing combined smoke is local direct-run functional evidence only. It does not prove Developer ID signing, notarization, App Store distribution, all target-machine TCC/display repeatability, real user Save Panel interaction or final product-validation release readiness.

VS-MA-23 local-direct app run boundary:

1. `scripts/run-local-app.sh` may build or reuse the local-direct Release `MeetingAssistantNative.app` and launch it through fresh LaunchServices `open -n -W -F` so the app behaves like a normal local GUI app instead of a headless executable diagnostic while bypassing stale macOS window restoration state.
2. The launcher must require user-provided `MEETING_ASSISTANT_TRANSCRIPTION_RUNTIME` and `MEETING_ASSISTANT_TRANSCRIPTION_MODEL` by default, set `MEETING_ASSISTANT_CLI_PATH` to the provider-owned `platform/e2e/ma-cli-local.sh` bridge when not already configured, and pass `MA_NATIVE_PROCESSING_RUNTIME=whisper_cpp` / `MA_NATIVE_PROCESSING_LANGUAGE=zh` through a scoped `launchctl setenv` / cleanup wrapper without downloading, copying or packaging runtime/model/audio assets.
3. Non-XCTest app runtime must use `ProcessingCLIDependencyCheckRunner` for the Preflight panel; XCTest and app-bundle fixture paths may keep `StaticDependencyCheckRunner` so deterministic UI smoke remains isolated.
4. The designed shell must propagate preflight readiness changes to `RecordingControlViewModel` and `ProcessingStateViewModel`, so a successful real `check_dependencies` run can enable the same app session's Start Recording and Start Processing controls.
5. Non-XCTest app runtime may auto-refresh Preflight once on first shell appearance using the same workspace URL passed to recording, so the local-direct app can surface missing runtime/model/permission state before the user triggers recording or processing.
6. The app root must use an AppKit-owned main `NSWindow` with `NSHostingController(rootView:)`, frame autosave name `meeting-assistant-main`, and `window.makeKeyAndOrderFront(nil)` on launch/reopen, so stale macOS window restoration state or suppressed SwiftUI automatic launch policy cannot leave local-direct runs with a live process and no primary window.
7. `MA_NATIVE_LOCAL_APP_LAUNCH_MODE=direct` is allowed only as a low-level executable diagnostic; the default local-direct user path must remain LaunchServices `open`.
8. This launcher is local functional evidence only. It does not prove XCUITest Automation Mode, Developer ID signing, notarization, App Store distribution, all target-machine repeatability, real user Save Panel interaction or final product-validation release readiness.
9. `scripts/local-direct-smoke.sh` may wrap `run-local-app.sh`, read the launched Release app's visible UI through macOS Accessibility/System Events, and verify the designed shell, Preflight, Recording and Processing controls are present. It must also verify the action controls expose stable `AXIdentifier` values and expected enabled states for `ma.recording.startButton`, `ma.recording.stopButton`, `ma.processing.startButton` and `ma.processing.retryButton` without clicking recording controls.
10. The local-direct smoke must not open System Settings, request or modify macOS permissions, call `CGRequestScreenCaptureAccess`, call `AVCaptureDevice.requestAccess`, change TCC, require Developer ID/notarization, or claim release readiness.

VS-MA-22 opt-in real runtime native bridge smoke boundary:

1. `ProcessingStateViewModelTests` may exercise `ProcessingCommandProcessRunner` with the real `whisper.cpp` runtime only when `MA_NATIVE_REAL_RUNTIME_BRIDGE_SMOKE=1` is explicitly set.
2. The smoke must use a native-recording workspace fixture whose `mixed_audio` is copied from `MEETING_ASSISTANT_WHISPER_SMOKE_AUDIO`, pass `runtime=whisper_cpp` and `language=zh` through the public command contract, and read the resulting transcript through `TranscriptReviewWorkspaceLoader`.
3. `platform/native-app/scripts/test.sh` must require `MEETING_ASSISTANT_TRANSCRIPTION_RUNTIME`, `MEETING_ASSISTANT_TRANSCRIPTION_MODEL`, and `MEETING_ASSISTANT_WHISPER_SMOKE_AUDIO` before enabling this smoke; it must not infer, download, copy, or package runtime/model/audio assets.
4. A passing native bridge smoke is not app-bundle evidence and remains partial evidence; it does not prove launched `.app` UI automation, real ScreenCaptureKit output, true user Save Panel interaction, release distribution bundle, all developer machines, or product-validation release readiness.
