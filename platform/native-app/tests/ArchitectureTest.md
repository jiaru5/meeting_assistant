# Native App Architecture Test

Component: `native-app`

VS-MA-12 boundary:

1. This component may implement the permission/dependency status surface for VS-MA-12.
2. It consumes the `check_dependencies` command contract through stable JSON only.
3. It may expose SwiftUI status labels and accessibility identifiers for permissions and dependencies.
4. It must not implement recording, start/stop recording, fake capture adapter, capture, transcription, speaker labeling, external model calls, public normalize audio commands or dependency downloads in VS-MA-12.
