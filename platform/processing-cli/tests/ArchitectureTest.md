# Processing CLI Architecture Test

Component: `processing-cli`

Dependency-check boundary:

1. This component implements the `check_dependencies` command contract.
2. It may define command, dependency-check and adapter boundaries.
3. It must not implement media processing, transcription, speaker labeling, external model calls or dependency downloads in this slice.
4. Missing required dependencies must be reported as `ok: false`, not as a skipped success.
