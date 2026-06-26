# Processing CLI Architecture Test

Component: `processing-cli`

Activation skeleton boundary:

1. This component is a non-business activation skeleton.
2. It may define command, dependency-check and adapter boundaries.
3. It must not implement media processing, transcription, speaker labeling, external model calls or dependency downloads before project mode.
