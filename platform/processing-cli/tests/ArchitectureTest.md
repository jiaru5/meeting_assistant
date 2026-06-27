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
8. It may define command, dependency-check, workspace and adapter boundaries.
9. It must not implement production-grade media transcoding, transcription, speaker labeling, external model calls or dependency downloads in this slice.
10. `import_media` must not transcode, normalize audio, generate transcript artifacts or generate speaker label artifacts.
11. Missing required dependencies must be reported as `ok: false`, not as a skipped success.
