# Native App Architecture Test

Component: `native-app`

Activation skeleton boundary:

1. This component is a non-business activation skeleton.
2. It may define command, test and architecture boundaries.
3. It must not implement recording, capture, transcription, speaker labeling, external model calls or dependency downloads before project mode.
