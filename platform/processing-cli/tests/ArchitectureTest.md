# Processing CLI Architecture Test

Component: `processing-cli`

Processing CLI boundary:

1. This component implements the `check_dependencies` command contract.
2. This component implements the workspace artifact contract kernel for `session.json`, artifact registry, checksum verification, path boundaries and session locks.
3. This component implements the `import_media` command contract for explicit local file import into a new `imported_media` session.
4. `import_media` may copy supported local media files into session `artifacts/` and register them as `mixed_audio` or `screen_video`.
5. It may define command, dependency-check, workspace and adapter boundaries.
6. It must not implement media processing, transcription, speaker labeling, external model calls or dependency downloads in this slice.
7. `import_media` must not transcode, normalize audio, generate transcript artifacts or generate speaker label artifacts.
8. Missing required dependencies must be reported as `ok: false`, not as a skipped success.
