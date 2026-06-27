# Processing CLI Architecture Test

Component: `processing-cli`

Processing CLI boundary:

1. This component implements the `check_dependencies` command contract.
2. This component implements the workspace artifact contract kernel for `session.json`, artifact registry, checksum verification, path boundaries and session locks.
3. This component implements the `import_media` command contract for explicit local file import into a new `imported_media` session.
4. `import_media` may copy supported local media files into session `artifacts/` and register them as `mixed_audio` or `screen_video`.
5. This component implements the internal normalized audio stage for source selection, `normalized_audio.wav` generation and artifact registration.
6. The normalized audio stage must prefer `mixed_audio`; when `mixed_audio` is missing it may use an explicitly selected available `system_audio` or `microphone_audio`; it must not overwrite original audio artifacts.
7. It must not expose `normalize_audio` as a public command unless `docs/product-spec/06-api-contracts.md` is updated first.
8. This component implements the `generate_transcript` command contract with a deterministic fake transcription adapter and a minimal `whisper.cpp` runtime adapter.
9. The `whisper.cpp` adapter may invoke a user-provided local runtime and multilingual model when explicitly requested with `runtime=whisper_cpp`.
10. `generate_transcript` may create `artifacts/transcript.json` and register a `transcript_text` artifact, but it must not overwrite original media artifacts or existing valid transcript artifacts.
11. It may define command, dependency-check, workspace and adapter boundaries.
12. This component implements the `generate_speaker_labels` command contract with transcript-only fallback and an injectable local adapter boundary.
13. `generate_speaker_labels` may create `artifacts/speaker_labels.json` and register a `speaker_labels` artifact; labels must remain anonymous and `is_verified_identity` must remain `false`.
14. This component implements the `export_transcript` command contract for `plain_text`, `markdown` and `json` content or explicit local target files.
15. `export_transcript` must not call external model APIs, read external account credentials, upload transcript/audio/video, or modify transcript/media artifacts.
16. This component implements the `delete_session` command contract for confirmed deletion of the current workspace session directory.
17. `delete_session` must not follow symlinks outside the session root and must retain workspace-external export files.
18. It must not implement production-grade media transcoding, production-grade transcription quality gates, production-grade speaker labeling, external speaker labeling runtimes, external model calls or dependency downloads in this slice.
19. `import_media` must not transcode, normalize audio, generate transcript artifacts or generate speaker label artifacts.
20. Missing required dependencies must be reported as `ok: false`, not as a skipped success.
